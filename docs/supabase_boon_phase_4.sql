-- Anime Arena Boon System - Phase 4: ranked snapshot, locking, and reveal.
-- Run after docs/supabase_boon_phase_3.sql and the current matchmaking/RPS/
-- Administrator migrations. This migration stores and reveals definition
-- snapshots only. It does not modify any fighter OVR or Power value.

-- 1. Private queue commitment. Authenticated users can already read only their
-- own queue row through RLS, so this JSON never exposes an opponent's Boon.
alter table public.matchmaking_queue
  add column if not exists boon_snapshot jsonb,
  add column if not exists boon_snapshot_locked_at timestamptz;

-- 2. Immutable per-match/per-player definition snapshot. Snapshot identifiers
-- deliberately have no FK to live inventory/definition rows: replacement,
-- deactivation, or rebalancing must not change or invalidate an active match.
create table if not exists public.match_boon_snapshots (
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete restrict,
  player_boon_id_snapshot uuid,
  boon_definition_id_snapshot uuid,
  boon_key_snapshot text,
  boon_name_snapshot text,
  boon_description_snapshot text,
  boon_rarity_snapshot text,
  boon_effect_type_snapshot text,
  boon_effect_value_snapshot integer,
  boon_target_rule_snapshot text,
  snapshotted_at timestamptz not null default now(),
  primary key (match_id, player_id),
  constraint match_boon_snapshots_rarity_check check (
    boon_rarity_snapshot is null
    or boon_rarity_snapshot in ('common', 'rare', 'epic', 'legendary', 'mythic')
  ),
  constraint match_boon_snapshots_complete_definition_check check (
    (boon_definition_id_snapshot is null
      and player_boon_id_snapshot is null
      and boon_key_snapshot is null
      and boon_name_snapshot is null
      and boon_description_snapshot is null
      and boon_rarity_snapshot is null
      and boon_effect_type_snapshot is null
      and boon_effect_value_snapshot is null
      and boon_target_rule_snapshot is null)
    or
    (boon_definition_id_snapshot is not null
      and boon_key_snapshot is not null
      and boon_name_snapshot is not null
      and boon_description_snapshot is not null
      and boon_rarity_snapshot is not null
      and boon_effect_type_snapshot is not null
      and boon_target_rule_snapshot is not null)
  )
);

create index if not exists match_boon_snapshots_player_match_idx
  on public.match_boon_snapshots (player_id, match_id);

alter table public.match_boon_snapshots enable row level security;
revoke all on table public.match_boon_snapshots from public, anon, authenticated;

-- 3. Internal builder. Guests and the Administrator intentionally receive a
-- NULL/no-Boon snapshot without acquiring inventory or BP.
create or replace function public.build_player_boon_snapshot_internal(p_player_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  profile_is_guest boolean;
  profile_is_system boolean;
  result jsonb;
begin
  select p.is_guest, p.is_system_player
    into profile_is_guest, profile_is_system
  from public.profiles p
  where p.id = p_player_id;

  if not found or profile_is_guest or profile_is_system then
    return null;
  end if;

  select jsonb_build_object(
    'playerBoonId', pb.id,
    'definitionId', d.id,
    'key', d.key,
    'name', d.name,
    'description', d.description,
    'rarity', d.rarity,
    'effectType', d.effect_type,
    'effectValue', d.effect_value,
    'targetRule', d.target_rule
  ) into result
  from public.player_boons pb
  join public.boon_definitions d on d.id = pb.boon_definition_id
  where pb.owner_id = p_player_id
    and pb.equipped = true
  order by pb.created_at
  limit 1;

  return result;
end;
$$;

-- 4. Lock a fresh future-match snapshot only when a queue row first becomes
-- waiting. Repeated calls while already waiting preserve the original choice.
create or replace function public.lock_matchmaking_boon_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'waiting' then
      new.boon_snapshot := public.build_player_boon_snapshot_internal(new.player_id);
      new.boon_snapshot_locked_at := now();
    end if;
    return new;
  end if;

  if new.status = 'waiting' and old.status is distinct from 'waiting' then
    new.boon_snapshot := public.build_player_boon_snapshot_internal(new.player_id);
    new.boon_snapshot_locked_at := now();
  elsif new.status = 'waiting' and old.status = 'waiting' then
    new.boon_snapshot := old.boon_snapshot;
    new.boon_snapshot_locked_at := old.boon_snapshot_locked_at;
  end if;

  return new;
end;
$$;

drop trigger if exists lock_matchmaking_boon_snapshot on public.matchmaking_queue;
create trigger lock_matchmaking_boon_snapshot
  before insert or update of status on public.matchmaking_queue
  for each row execute function public.lock_matchmaking_boon_snapshot();

-- 5. Insert one row for each match side. Waiting participants use their locked
-- queue JSON. A player matched immediately is snapshotted at match insertion,
-- before the transaction returns opponent information. Historical matches are
-- intentionally not backfilled.
create or replace function public.capture_match_boon_snapshots()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  player_one_snapshot jsonb;
  player_two_snapshot jsonb;
  queue_snapshot_found boolean;
begin
  select q.boon_snapshot, true
    into player_one_snapshot, queue_snapshot_found
  from public.matchmaking_queue q
  where q.player_id = new.player_one_id
    and q.status = 'waiting'
    and q.boon_snapshot_locked_at is not null;
  if coalesce(queue_snapshot_found, false) = false then
    player_one_snapshot := public.build_player_boon_snapshot_internal(new.player_one_id);
  end if;

  queue_snapshot_found := false;
  select q.boon_snapshot, true
    into player_two_snapshot, queue_snapshot_found
  from public.matchmaking_queue q
  where q.player_id = new.player_two_id
    and q.status = 'waiting'
    and q.boon_snapshot_locked_at is not null;
  if coalesce(queue_snapshot_found, false) = false then
    player_two_snapshot := public.build_player_boon_snapshot_internal(new.player_two_id);
  end if;

  insert into public.match_boon_snapshots (
    match_id, player_id, player_boon_id_snapshot, boon_definition_id_snapshot,
    boon_key_snapshot, boon_name_snapshot, boon_description_snapshot,
    boon_rarity_snapshot, boon_effect_type_snapshot, boon_effect_value_snapshot,
    boon_target_rule_snapshot
  ) values
  (
    new.id,
    new.player_one_id,
    (player_one_snapshot ->> 'playerBoonId')::uuid,
    (player_one_snapshot ->> 'definitionId')::uuid,
    player_one_snapshot ->> 'key',
    player_one_snapshot ->> 'name',
    player_one_snapshot ->> 'description',
    player_one_snapshot ->> 'rarity',
    player_one_snapshot ->> 'effectType',
    (player_one_snapshot ->> 'effectValue')::integer,
    player_one_snapshot ->> 'targetRule'
  ),
  (
    new.id,
    new.player_two_id,
    (player_two_snapshot ->> 'playerBoonId')::uuid,
    (player_two_snapshot ->> 'definitionId')::uuid,
    player_two_snapshot ->> 'key',
    player_two_snapshot ->> 'name',
    player_two_snapshot ->> 'description',
    player_two_snapshot ->> 'rarity',
    player_two_snapshot ->> 'effectType',
    (player_two_snapshot ->> 'effectValue')::integer,
    player_two_snapshot ->> 'targetRule'
  )
  on conflict (match_id, player_id) do nothing;

  return new;
end;
$$;

drop trigger if exists capture_match_boon_snapshots on public.matches;
create trigger capture_match_boon_snapshots
  after insert on public.matches
  for each row execute function public.capture_match_boon_snapshots();

-- 6. Private owner-only active match snapshot for Loadout/Boons management UI.
create or replace function public.get_my_active_match_boon()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  snapshot_row public.match_boon_snapshots%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select * into match_row
  from public.matches m
  where caller_id in (m.player_one_id, m.player_two_id)
    and m.status not in ('completed', 'cancelled')
  order by m.created_at desc
  limit 1;

  if not found then return null; end if;

  select * into snapshot_row
  from public.match_boon_snapshots s
  where s.match_id = match_row.id and s.player_id = caller_id;

  return jsonb_build_object(
    'matchId', match_row.id,
    'status', match_row.status,
    'boon', case when snapshot_row.boon_definition_id_snapshot is null then null else jsonb_build_object(
      'definitionId', snapshot_row.boon_definition_id_snapshot,
      'key', snapshot_row.boon_key_snapshot,
      'name', snapshot_row.boon_name_snapshot,
      'description', snapshot_row.boon_description_snapshot,
      'rarity', snapshot_row.boon_rarity_snapshot,
      'effectType', snapshot_row.boon_effect_type_snapshot,
      'effectValue', snapshot_row.boon_effect_value_snapshot,
      'targetRule', snapshot_row.boon_target_rule_snapshot
    ) end
  );
end;
$$;

-- 7. Perspective-safe initiative state. Boons reveal when the match is in the
-- competitive initiative phase or later. The response never joins OC option,
-- selection, preparation, sacrifice, draft-target, or battle-selection state.
-- Profile objects are also deliberately restricted to fields used by match UI.
create or replace function public.get_match_initiative_state(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  opponent_id uuid;
  resolved public.match_initiative_rounds%rowtype;
  own_snapshot public.match_boon_snapshots%rowtype;
  opponent_snapshot public.match_boon_snapshots%rowtype;
  opponent_boon_revealed boolean;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;

  select * into match_row
  from public.matches
  where id = p_match_id;

  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception 'Match unavailable';
  end if;

  opponent_id := case
    when caller_id = match_row.player_one_id then match_row.player_two_id
    else match_row.player_one_id
  end;

  if match_row.initiative_state = 'revealed' then
    select * into resolved
    from public.match_initiative_rounds
    where match_id = p_match_id
      and initiative_round = match_row.initiative_round;
  end if;

  select * into own_snapshot
  from public.match_boon_snapshots s
  where s.match_id = p_match_id and s.player_id = caller_id;

  opponent_boon_revealed := match_row.status in (
    'initiative', 'oc_selection', 'draft', 'oc_preparation', 'battle', 'completed'
  );

  if opponent_boon_revealed then
    select * into opponent_snapshot
    from public.match_boon_snapshots s
    where s.match_id = p_match_id and s.player_id = opponent_id;
  end if;

  return jsonb_build_object(
    'matchId', match_row.id,
    'status', match_row.status,
    'initiativeRound', match_row.initiative_round,
    'initiativeState', match_row.initiative_state,
    'yourPlayerId', caller_id,
    'opponentPlayerId', opponent_id,
    'yourProfile', (select jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'avatar_url', p.avatar_url,
      'is_system_player', p.is_system_player
    ) from public.profiles p where p.id = caller_id),
    'opponentProfile', (select jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'avatar_url', p.avatar_url,
      'is_system_player', p.is_system_player
    ) from public.profiles p where p.id = opponent_id),
    'yourBoon', case when own_snapshot.boon_definition_id_snapshot is null then null else jsonb_build_object(
      'definitionId', own_snapshot.boon_definition_id_snapshot,
      'key', own_snapshot.boon_key_snapshot,
      'name', own_snapshot.boon_name_snapshot,
      'description', own_snapshot.boon_description_snapshot,
      'rarity', own_snapshot.boon_rarity_snapshot,
      'effectType', own_snapshot.boon_effect_type_snapshot,
      'effectValue', own_snapshot.boon_effect_value_snapshot,
      'targetRule', own_snapshot.boon_target_rule_snapshot
    ) end,
    'opponentBoonRevealed', opponent_boon_revealed,
    'opponentBoon', case when not opponent_boon_revealed
      or opponent_snapshot.boon_definition_id_snapshot is null then null else jsonb_build_object(
      'definitionId', opponent_snapshot.boon_definition_id_snapshot,
      'key', opponent_snapshot.boon_key_snapshot,
      'name', opponent_snapshot.boon_name_snapshot,
      'description', opponent_snapshot.boon_description_snapshot,
      'rarity', opponent_snapshot.boon_rarity_snapshot,
      'effectType', opponent_snapshot.boon_effect_type_snapshot,
      'effectValue', opponent_snapshot.boon_effect_value_snapshot,
      'targetRule', opponent_snapshot.boon_target_rule_snapshot
    ) end,
    'yourChoice', case when match_row.initiative_state = 'revealed' then
      case when caller_id = match_row.player_one_id then resolved.player_one_choice else resolved.player_two_choice end
      else (select c.choice from public.match_initiative_choices c
        where c.match_id = p_match_id
          and c.initiative_round = match_row.initiative_round
          and c.player_id = caller_id)
    end,
    'opponentLocked', case when match_row.initiative_state = 'revealed' then true else exists(
      select 1 from public.match_initiative_choices c
      where c.match_id = p_match_id
        and c.initiative_round = match_row.initiative_round
        and c.player_id = opponent_id
    ) end,
    'opponentChoice', case when match_row.initiative_state = 'revealed' then
      case when caller_id = match_row.player_one_id then resolved.player_two_choice else resolved.player_one_choice end
      else null
    end,
    'winnerPlayerId', case when match_row.initiative_state = 'revealed' then resolved.winner_player_id else null end,
    'isDraw', match_row.initiative_state = 'revealed' and resolved.winner_player_id is null
  );
end;
$$;

-- 8. Grants. Snapshot tables and trigger helpers remain inaccessible to browser
-- roles. Only the two narrow perspective/owner RPCs are executable.
revoke all on function public.build_player_boon_snapshot_internal(uuid) from public, anon, authenticated;
revoke all on function public.lock_matchmaking_boon_snapshot() from public, anon, authenticated;
revoke all on function public.capture_match_boon_snapshots() from public, anon, authenticated;
revoke all on function public.get_my_active_match_boon() from public, anon, authenticated;
revoke all on function public.get_match_initiative_state(uuid) from public, anon, authenticated;

grant execute on function public.get_my_active_match_boon() to authenticated;
grant execute on function public.get_match_initiative_state(uuid) to authenticated;

notify pgrst, 'reload schema';
