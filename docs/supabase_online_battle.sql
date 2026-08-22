-- Run after supabase_online_draft.sql.
-- Server-authoritative online battle. Unresolved selections are deliberately
-- inaccessible to browser clients; get_online_battle_state exposes only a
-- caller-safe projection.

alter table public.matches
  add column if not exists current_battle_round integer check (current_battle_round between 1 and 5),
  add column if not exists battle_state text check (battle_state in ('selecting', 'revealed', 'complete'));

alter table public.match_characters
  add column if not exists used_in_battle boolean not null default false;

create table if not exists public.match_rounds (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  round_number integer not null check (round_number between 1 and 5),
  player_one_match_character_id uuid not null references public.match_characters(id) on delete restrict,
  player_two_match_character_id uuid not null references public.match_characters(id) on delete restrict,
  winner_player_id uuid references public.profiles(id) on delete restrict,
  resolved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (match_id, round_number)
);

create table if not exists public.battle_selections (
  match_id uuid not null references public.matches(id) on delete cascade,
  round_number integer not null check (round_number between 1 and 5),
  player_id uuid not null references public.profiles(id) on delete restrict,
  match_character_id uuid not null references public.match_characters(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (match_id, round_number, player_id),
  unique (match_id, round_number, match_character_id)
);

create index if not exists match_rounds_match_idx on public.match_rounds (match_id, round_number);
alter table public.match_rounds enable row level security;
alter table public.battle_selections enable row level security;

drop policy if exists "Participants can read resolved match rounds" on public.match_rounds;
create policy "Participants can read resolved match rounds"
  on public.match_rounds for select to authenticated
  using (exists (
    select 1 from public.matches m
    where m.id = match_rounds.match_id and auth.uid() in (m.player_one_id, m.player_two_id)
  ));

grant select on public.match_rounds to authenticated;
revoke insert, update, delete on public.match_rounds from authenticated;
revoke all on public.battle_selections from anon, authenticated;

create or replace function public.initialize_online_battle(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  player_one_count integer;
  player_two_count integer;
  assigned_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status = 'completed' then return; end if;
  if match_row.status <> 'battle' then raise exception 'Battle is not available'; end if;

  select count(*) filter (where owner_player_id = match_row.player_one_id),
         count(*) filter (where owner_player_id = match_row.player_two_id),
         count(*) filter (where owner_player_id is not null)
  into player_one_count, player_two_count, assigned_count
  from public.match_characters where match_id = p_match_id;
  if player_one_count <> 5 or player_two_count <> 5 or assigned_count <> 10 then
    raise exception 'Both complete five-fighter teams are required';
  end if;

  if match_row.current_battle_round is null then
    update public.matches set current_battle_round = 1, battle_state = 'selecting',
      player_one_score = 0, player_two_score = 0, action_version = action_version + 1, updated_at = now()
    where id = p_match_id;
  end if;
end;
$$;

create or replace function public.submit_battle_selection(p_match_id uuid, p_match_character_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  selected_row public.match_characters%rowtype;
  one_selection uuid;
  two_selection uuid;
  one_overall integer;
  two_overall integer;
  one_power integer;
  two_power integer;
  round_winner uuid;
  next_one_score integer;
  next_two_score integer;
  final_winner uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'battle' or match_row.battle_state <> 'selecting' or match_row.current_battle_round is null then raise exception 'Selections are not open'; end if;

  select * into selected_row from public.match_characters
  where id = p_match_character_id and match_id = p_match_id for update;
  if not found or selected_row.owner_player_id <> caller_id then raise exception 'Fighter does not belong to this player'; end if;
  if selected_row.used_in_battle then raise exception 'Fighter has already been used'; end if;

  insert into public.battle_selections (match_id, round_number, player_id, match_character_id)
  values (p_match_id, match_row.current_battle_round, caller_id, p_match_character_id);

  -- Incrementing the public match version provides a safe Realtime notification
  -- without publishing the private selected fighter ID.
  update public.matches set action_version = action_version + 1, updated_at = now() where id = p_match_id;

  select match_character_id into one_selection from public.battle_selections
    where match_id = p_match_id and round_number = match_row.current_battle_round and player_id = match_row.player_one_id;
  select match_character_id into two_selection from public.battle_selections
    where match_id = p_match_id and round_number = match_row.current_battle_round and player_id = match_row.player_two_id;
  if one_selection is null or two_selection is null then return; end if;

  select c.overall, c.power_score into one_overall, one_power
    from public.match_characters mc join public.characters c on c.id = mc.character_id where mc.id = one_selection;
  select c.overall, c.power_score into two_overall, two_power
    from public.match_characters mc join public.characters c on c.id = mc.character_id where mc.id = two_selection;
  round_winner := case
    when one_overall > two_overall then match_row.player_one_id
    when two_overall > one_overall then match_row.player_two_id
    when one_power > two_power then match_row.player_one_id
    when two_power > one_power then match_row.player_two_id
    else null
  end;
  next_one_score := match_row.player_one_score + case when round_winner = match_row.player_one_id then 1 else 0 end;
  next_two_score := match_row.player_two_score + case when round_winner = match_row.player_two_id then 1 else 0 end;

  update public.match_characters set used_in_battle = true where id in (one_selection, two_selection);
  insert into public.match_rounds (match_id, round_number, player_one_match_character_id, player_two_match_character_id, winner_player_id)
  values (p_match_id, match_row.current_battle_round, one_selection, two_selection, round_winner);
  delete from public.battle_selections where match_id = p_match_id and round_number = match_row.current_battle_round;

  if next_one_score >= 3 or next_two_score >= 3 or match_row.current_battle_round = 5 then
    final_winner := case when next_one_score > next_two_score then match_row.player_one_id when next_two_score > next_one_score then match_row.player_two_id else null end;
    update public.matches set status = 'completed', battle_state = 'complete', player_one_score = next_one_score,
      player_two_score = next_two_score, winner_id = final_winner, completed_at = now(),
      action_version = action_version + 1, updated_at = now() where id = p_match_id and status = 'battle';
    if final_winner is not null then
      update public.profiles set wins = wins + 1 where id = final_winner;
      update public.profiles set losses = losses + 1
        where id = case when final_winner = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
    end if;
  else
    update public.matches set battle_state = 'revealed', player_one_score = next_one_score,
      player_two_score = next_two_score, action_version = action_version + 1, updated_at = now() where id = p_match_id;
  end if;
end;
$$;

create or replace function public.advance_battle_round(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status = 'completed' then return; end if;
  if match_row.status <> 'battle' or match_row.battle_state <> 'revealed' then raise exception 'Round cannot be advanced'; end if;
  if match_row.current_battle_round >= 5 then raise exception 'Maximum round reached'; end if;
  update public.matches set current_battle_round = current_battle_round + 1, battle_state = 'selecting',
    action_version = action_version + 1, updated_at = now() where id = p_match_id;
end;
$$;

create or replace function public.get_online_battle_state(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype; opponent_id uuid; result jsonb;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status not in ('battle', 'completed') then raise exception 'Battle is not available'; end if;
  opponent_id := case when caller_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;

  select jsonb_build_object(
    'matchId', match_row.id, 'status', match_row.status, 'roundNumber', match_row.current_battle_round,
    'battleState', match_row.battle_state, 'yourPlayerId', caller_id, 'opponentPlayerId', opponent_id,
    'yourScore', case when caller_id = match_row.player_one_id then match_row.player_one_score else match_row.player_two_score end,
    'opponentScore', case when caller_id = match_row.player_one_id then match_row.player_two_score else match_row.player_one_score end,
    'matchWinnerId', match_row.winner_id,
    'yourProfile', (select to_jsonb(p) from public.profiles p where p.id = caller_id),
    'opponentProfile', (select to_jsonb(p) from public.profiles p where p.id = opponent_id),
    'yourTeam', coalesce((select jsonb_agg(jsonb_build_object('id', mc.id, 'used', mc.used_in_battle,
      'character', to_jsonb(c) || jsonb_build_object('verses', (select to_jsonb(v) from public.verses v where v.id = c.verse_id))) order by mc.draft_position)
      from public.match_characters mc join public.characters c on c.id = mc.character_id where mc.match_id = p_match_id and mc.owner_player_id = caller_id), '[]'::jsonb),
    'opponentTeam', coalesce((select jsonb_agg(jsonb_build_object('id', mc.id, 'used', mc.used_in_battle,
      'character', to_jsonb(c) || jsonb_build_object('verses', (select to_jsonb(v) from public.verses v where v.id = c.verse_id))) order by mc.draft_position)
      from public.match_characters mc join public.characters c on c.id = mc.character_id where mc.match_id = p_match_id and mc.owner_player_id = opponent_id), '[]'::jsonb),
    'yourSelectionId', (select bs.match_character_id from public.battle_selections bs where bs.match_id = p_match_id and bs.round_number = match_row.current_battle_round and bs.player_id = caller_id),
    'opponentLocked', exists(select 1 from public.battle_selections bs where bs.match_id = p_match_id and bs.round_number = match_row.current_battle_round and bs.player_id = opponent_id),
    'latestRound', (select jsonb_build_object('roundNumber', r.round_number, 'yourFighterId', case when caller_id = match_row.player_one_id then r.player_one_match_character_id else r.player_two_match_character_id end,
      'opponentFighterId', case when caller_id = match_row.player_one_id then r.player_two_match_character_id else r.player_one_match_character_id end, 'winnerPlayerId', r.winner_player_id)
      from public.match_rounds r where r.match_id = p_match_id order by r.round_number desc limit 1)
  ) into result;
  return result;
end;
$$;

revoke all on function public.initialize_online_battle(uuid) from public;
revoke all on function public.submit_battle_selection(uuid, uuid) from public;
revoke all on function public.advance_battle_round(uuid) from public;
revoke all on function public.get_online_battle_state(uuid) from public;
grant execute on function public.initialize_online_battle(uuid) to authenticated;
grant execute on function public.submit_battle_selection(uuid, uuid) to authenticated;
grant execute on function public.advance_battle_round(uuid) to authenticated;
grant execute on function public.get_online_battle_state(uuid) to authenticated;

notify pgrst, 'reload schema';
