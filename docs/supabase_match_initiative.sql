-- Run after supabase_online_draft.sql. Safe to rerun.
alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches add constraint matches_status_check
  check (status in ('waiting', 'initiative', 'draft', 'battle', 'completed', 'cancelled'));

alter table public.matches
  add column if not exists initiative_player_id uuid references public.profiles(id) on delete restrict,
  -- Legacy field retained so the RPS migration can clean old unresolved coin matches.
  add column if not exists initiative_result text check (initiative_result in ('heads', 'tails')),
  add column if not exists initiative_resolved_at timestamptz,
  add column if not exists initiative_round integer not null default 1 check (initiative_round >= 1),
  add column if not exists initiative_state text not null default 'choosing' check (initiative_state in ('choosing', 'revealed'));

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'matches_initiative_player_check' and conrelid = 'public.matches'::regclass) then
    alter table public.matches add constraint matches_initiative_player_check
      check (initiative_player_id is null or initiative_player_id in (player_one_id, player_two_id));
  end if;
end $$;

create or replace function public.find_or_create_match()
returns table (result_status text, match_id uuid)
language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  existing_match_id uuid;
  opponent_id uuid;
  created_match_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.profiles where id = caller_id) then raise exception 'Player profile required'; end if;
  perform pg_advisory_xact_lock(hashtext('anime_arena_matchmaking'));

  select id into existing_match_id from public.matches
  where caller_id in (player_one_id, player_two_id) and status not in ('completed', 'cancelled')
  order by created_at desc limit 1;
  if existing_match_id is not null then
    return query select 'existing_match'::text, existing_match_id;
    return;
  end if;

  select queue.player_id into opponent_id from public.matchmaking_queue as queue
  where queue.status = 'waiting' and queue.matched_match_id is null and queue.player_id <> caller_id
    and not exists (select 1 from public.matches active_match
      where queue.player_id in (active_match.player_one_id, active_match.player_two_id)
        and active_match.status not in ('completed', 'cancelled'))
  order by queue.joined_at asc limit 1 for update skip locked;

  if opponent_id is null then
    insert into public.matchmaking_queue (player_id, status, joined_at, matched_match_id)
    values (caller_id, 'waiting', now(), null)
    on conflict (player_id) do update set status = 'waiting',
      joined_at = case when public.matchmaking_queue.status = 'waiting' then public.matchmaking_queue.joined_at else now() end,
      matched_match_id = null;
    return query select 'waiting'::text, null::uuid;
    return;
  end if;

  insert into public.matches (player_one_id, player_two_id, status)
  values (opponent_id, caller_id, 'initiative') returning id into created_match_id;
  update public.matchmaking_queue set status = 'matched', matched_match_id = created_match_id where player_id = opponent_id;
  insert into public.matchmaking_queue (player_id, status, joined_at, matched_match_id)
  values (caller_id, 'matched', now(), created_match_id)
  on conflict (player_id) do update set status = 'matched', matched_match_id = created_match_id;
  return query select 'matched'::text, created_match_id;
end;
$$;

create or replace function public.initialize_match_initiative(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'initiative' then return; end if;
  if match_row.initiative_round is null or match_row.initiative_state is null then
    update public.matches set initiative_round = 1, initiative_state = 'choosing',
      initiative_player_id = null, priority_player_id = null, tie_priority_player_id = null,
      action_version = action_version + 1, updated_at = now() where id = p_match_id;
  end if;
end;
$$;

-- Replace the draft initializer so initiative is mandatory and its winner owns
-- Round 1 priority. Later rounds still use advance_online_draft unchanged.
create or replace function public.initialize_match_draft(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  active_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status in ('draft', 'battle', 'completed') then return; end if;
  if match_row.status <> 'initiative' or match_row.initiative_player_id is null then raise exception 'Initiative must be resolved first'; end if;

  select count(*) into active_count from public.characters where active = true;
  if active_count < 10 then raise exception 'At least 10 active fighters are required to start an online draft'; end if;
  insert into public.match_players (match_id, player_id, player_number, balance) values
    (p_match_id, match_row.player_one_id, 1, 20), (p_match_id, match_row.player_two_id, 2, 20)
  on conflict (match_id, player_id) do nothing;
  insert into public.match_characters (match_id, character_id, draft_position)
  select p_match_id, selected.id, row_number() over ()::integer
  from (select id from public.characters where active = true order by random() limit 10) selected
  on conflict do nothing;
  if (select count(*) from public.match_characters where match_id = p_match_id) <> 10 then raise exception 'Unable to create a complete unique draft pool'; end if;

  update public.matches set status = 'draft', current_draft_position = 1, draft_state = 'decision',
    current_bid = null, current_bidder_id = null, priority_player_id = match_row.initiative_player_id,
    tie_priority_player_id = case when match_row.initiative_player_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end,
    action_version = action_version + 1, updated_at = now()
  where id = p_match_id;
end;
$$;

revoke all on function public.initialize_match_initiative(uuid) from public;
grant execute on function public.initialize_match_initiative(uuid) to authenticated;
revoke all on function public.find_or_create_match() from public;
grant execute on function public.find_or_create_match() to authenticated;
revoke all on function public.initialize_match_draft(uuid) from public;
grant execute on function public.initialize_match_draft(uuid) to authenticated;
notify pgrst, 'reload schema';
