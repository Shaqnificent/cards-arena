-- Run after supabase_match_initiative.sql. Replaces automatic Heads/Tails with
-- private, server-authoritative Rock-Paper-Scissors. Safe to rerun.
alter table public.matches
  add column if not exists initiative_round integer not null default 1 check (initiative_round >= 1),
  add column if not exists initiative_state text not null default 'choosing' check (initiative_state in ('choosing', 'revealed'));

create table if not exists public.match_initiative_choices (
  match_id uuid not null references public.matches(id) on delete cascade,
  initiative_round integer not null check (initiative_round >= 1),
  player_id uuid not null references public.profiles(id) on delete restrict,
  choice text not null check (choice in ('rock', 'paper', 'scissors')),
  created_at timestamptz not null default now(),
  primary key (match_id, initiative_round, player_id)
);
create table if not exists public.match_initiative_rounds (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  initiative_round integer not null check (initiative_round >= 1),
  player_one_choice text not null check (player_one_choice in ('rock', 'paper', 'scissors')),
  player_two_choice text not null check (player_two_choice in ('rock', 'paper', 'scissors')),
  winner_player_id uuid references public.profiles(id) on delete restrict,
  resolved_at timestamptz not null default now(),
  unique (match_id, initiative_round)
);
alter table public.match_initiative_choices enable row level security;
alter table public.match_initiative_rounds enable row level security;
revoke all on public.match_initiative_choices, public.match_initiative_rounds from anon, authenticated;

-- Reset only unfinished legacy coin-flip matches. Drafts already started keep
-- their established priority and are not changed.
update public.matches set initiative_player_id = null, initiative_result = null,
  initiative_resolved_at = null, priority_player_id = null, tie_priority_player_id = null,
  initiative_round = 1, initiative_state = 'choosing'
where status = 'initiative' and initiative_result is not null;

create or replace function public.initialize_match_initiative(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype;
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

create or replace function public.submit_initiative_choice(p_match_id uuid, p_choice text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid(); match_row public.matches%rowtype;
  one_choice text; two_choice text; winner uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'initiative' or match_row.initiative_state <> 'choosing' then raise exception 'Initiative choices are not open'; end if;
  if p_choice is null or p_choice not in ('rock', 'paper', 'scissors') then raise exception 'Invalid initiative choice'; end if;
  insert into public.match_initiative_choices (match_id, initiative_round, player_id, choice)
  values (p_match_id, match_row.initiative_round, caller_id, p_choice);
  update public.matches set action_version = action_version + 1, updated_at = now() where id = p_match_id;

  select choice into one_choice from public.match_initiative_choices
    where match_id = p_match_id and initiative_round = match_row.initiative_round and player_id = match_row.player_one_id;
  select choice into two_choice from public.match_initiative_choices
    where match_id = p_match_id and initiative_round = match_row.initiative_round and player_id = match_row.player_two_id;
  if one_choice is null or two_choice is null then return; end if;
  winner := case
    when one_choice = two_choice then null
    when (one_choice = 'rock' and two_choice = 'scissors') or (one_choice = 'scissors' and two_choice = 'paper') or (one_choice = 'paper' and two_choice = 'rock') then match_row.player_one_id
    else match_row.player_two_id end;
  insert into public.match_initiative_rounds (match_id, initiative_round, player_one_choice, player_two_choice, winner_player_id)
  values (p_match_id, match_row.initiative_round, one_choice, two_choice, winner);
  delete from public.match_initiative_choices where match_id = p_match_id and initiative_round = match_row.initiative_round;
  update public.matches set initiative_state = 'revealed', initiative_player_id = winner,
    initiative_resolved_at = now(), priority_player_id = winner,
    tie_priority_player_id = case when winner = match_row.player_one_id then match_row.player_two_id when winner = match_row.player_two_id then match_row.player_one_id else null end,
    action_version = action_version + 1, updated_at = now() where id = p_match_id;
end;
$$;

create or replace function public.advance_initiative_round(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'initiative' then return; end if;
  if match_row.initiative_state = 'choosing' then return; end if;
  if match_row.initiative_player_id is not null then return; end if;
  update public.matches set initiative_round = initiative_round + 1, initiative_state = 'choosing',
    initiative_resolved_at = null, action_version = action_version + 1, updated_at = now() where id = p_match_id;
end;
$$;

create or replace function public.get_match_initiative_state(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype; opponent_id uuid; resolved public.match_initiative_rounds%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  opponent_id := case when caller_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  if match_row.initiative_state = 'revealed' then
    select * into resolved from public.match_initiative_rounds where match_id = p_match_id and initiative_round = match_row.initiative_round;
  end if;
  return jsonb_build_object(
    'matchId', match_row.id, 'status', match_row.status, 'initiativeRound', match_row.initiative_round,
    'initiativeState', match_row.initiative_state, 'yourPlayerId', caller_id, 'opponentPlayerId', opponent_id,
    'yourProfile', (select jsonb_build_object(
      'id', p.id, 'username', p.username, 'avatar_url', p.avatar_url,
      'is_system_player', p.is_system_player
    ) from public.profiles p where p.id = caller_id),
    'opponentProfile', (select jsonb_build_object(
      'id', p.id, 'username', p.username, 'avatar_url', p.avatar_url,
      'is_system_player', p.is_system_player
    ) from public.profiles p where p.id = opponent_id),
    'yourChoice', case when match_row.initiative_state = 'revealed' then case when caller_id = match_row.player_one_id then resolved.player_one_choice else resolved.player_two_choice end
      else (select c.choice from public.match_initiative_choices c where c.match_id = p_match_id and c.initiative_round = match_row.initiative_round and c.player_id = caller_id) end,
    'opponentLocked', case when match_row.initiative_state = 'revealed' then true else exists(select 1 from public.match_initiative_choices c where c.match_id = p_match_id and c.initiative_round = match_row.initiative_round and c.player_id = opponent_id) end,
    'opponentChoice', case when match_row.initiative_state = 'revealed' then case when caller_id = match_row.player_one_id then resolved.player_two_choice else resolved.player_one_choice end else null end,
    'winnerPlayerId', case when match_row.initiative_state = 'revealed' then resolved.winner_player_id else null end,
    'isDraw', match_row.initiative_state = 'revealed' and resolved.winner_player_id is null
  );
end;
$$;

create or replace function public.initialize_match_draft(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype; active_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status in ('draft', 'battle', 'completed') then return; end if;
  if match_row.status <> 'initiative' or match_row.initiative_state <> 'revealed' or match_row.initiative_player_id is null then raise exception 'Initiative must have a winner first'; end if;
  select count(*) into active_count from public.characters where active = true;
  if active_count < 10 then raise exception 'At least 10 active fighters are required to start an online draft'; end if;
  insert into public.match_players (match_id, player_id, player_number, balance) values
    (p_match_id, match_row.player_one_id, 1, 20), (p_match_id, match_row.player_two_id, 2, 20)
  on conflict (match_id, player_id) do nothing;
  insert into public.match_characters (match_id, character_id, draft_position)
  select p_match_id, selected.id, row_number() over ()::integer
  from (select id from public.characters where active = true order by random() limit 10) selected on conflict do nothing;
  if (select count(*) from public.match_characters where match_id = p_match_id) <> 10 then raise exception 'Unable to create a complete unique draft pool'; end if;
  update public.matches set status = 'draft', current_draft_position = 1, draft_state = 'decision',
    current_bid = null, current_bidder_id = null, priority_player_id = match_row.initiative_player_id,
    tie_priority_player_id = case when match_row.initiative_player_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end,
    action_version = action_version + 1, updated_at = now() where id = p_match_id;
end;
$$;

revoke all on function public.initialize_match_initiative(uuid) from public;
revoke all on function public.submit_initiative_choice(uuid, text) from public;
revoke all on function public.advance_initiative_round(uuid) from public;
revoke all on function public.get_match_initiative_state(uuid) from public;
revoke all on function public.initialize_match_draft(uuid) from public;
grant execute on function public.initialize_match_initiative(uuid) to authenticated;
grant execute on function public.submit_initiative_choice(uuid, text) to authenticated;
grant execute on function public.advance_initiative_round(uuid) to authenticated;
grant execute on function public.get_match_initiative_state(uuid) to authenticated;
grant execute on function public.initialize_match_draft(uuid) to authenticated;
notify pgrst, 'reload schema';
