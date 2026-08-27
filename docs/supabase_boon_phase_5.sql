-- Anime Arena Boon System - Phase 5: authoritative temporary match effects.
-- Run after docs/supabase_boon_phase_4.sql and the current OC type/preparation,
-- online battle, Administrator, and docs/supabase_boon_phase_1.sql migrations.
-- This migration never updates public.characters or public.player_characters.

-- 1. Match-level exactly-once marker. Existing battle/completed matches remain
-- NULL and are deliberately not retroactively resolved.
alter table public.matches
  add column if not exists boon_effects_resolved_at timestamptz;

-- 2. One private resolution record per match side. The definition identifiers
-- are snapshots rather than live foreign keys, preserving Phase 4 rebalance
-- isolation. Random values and selected verses are stored once here.
create table if not exists public.match_boon_resolutions (
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete restrict,
  boon_definition_id_snapshot uuid,
  boon_key_snapshot text,
  effect_type_snapshot text,
  requested_effect_value integer,
  status text not null,
  resolved_random_value integer,
  resolved_verse_id bigint,
  metadata jsonb not null default '{}'::jsonb,
  resolved_at timestamptz not null default now(),
  primary key (match_id, player_id),
  constraint match_boon_resolutions_status_check check (
    status in ('applied', 'no_eligible_target', 'no_boon')
  ),
  constraint match_boon_resolutions_value_check check (
    requested_effect_value is null or requested_effect_value >= 0
  ),
  constraint match_boon_resolutions_random_value_check check (
    resolved_random_value is null or resolved_random_value between 1 and 99
  )
);

create index if not exists match_boon_resolutions_player_idx
  on public.match_boon_resolutions (player_id, match_id);

-- 3. Private base/preparation/Boon/final breakdown for every fighter on the
-- player's finalized roster. Keeping this out of match_characters prevents a
-- normal browser SELECT from revealing hidden opponent targets or OC context.
create table if not exists public.match_boon_fighter_stats (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null,
  player_id uuid not null,
  fighter_type text not null,
  match_character_id uuid references public.match_characters(id) on delete cascade,
  player_character_id uuid references public.player_characters(id) on delete restrict,
  verse_id_snapshot bigint not null,
  roster_order integer not null,
  eligible_for_battle boolean not null,
  boon_targeted boolean not null default false,
  base_overall integer not null,
  preparation_overall_bonus integer not null default 0,
  boon_overall_bonus integer not null default 0,
  final_overall integer not null,
  base_power_score integer not null,
  preparation_power_bonus integer not null default 0,
  boon_power_bonus integer not null default 0,
  final_power_score integer not null,
  created_at timestamptz not null default now(),
  foreign key (match_id, player_id)
    references public.match_boon_resolutions(match_id, player_id) on delete cascade,
  constraint match_boon_fighter_stats_source_check check (
    (fighter_type = 'canon' and match_character_id is not null and player_character_id is null)
    or
    (fighter_type = 'oc' and match_character_id is null and player_character_id is not null)
  ),
  constraint match_boon_fighter_stats_overall_check check (
    base_overall between 1 and 99
    and preparation_overall_bonus >= 0
    and boon_overall_bonus >= 0
    and final_overall between 1 and 99
  ),
  constraint match_boon_fighter_stats_power_check check (
    base_power_score >= 0
    and preparation_power_bonus >= 0
    and boon_power_bonus >= 0
    and final_power_score between 0 and 12000
  )
);

create unique index if not exists match_boon_fighter_stats_canon_unique
  on public.match_boon_fighter_stats (match_id, player_id, match_character_id)
  where fighter_type = 'canon';
create unique index if not exists match_boon_fighter_stats_oc_unique
  on public.match_boon_fighter_stats (match_id, player_id, player_character_id)
  where fighter_type = 'oc';
create index if not exists match_boon_fighter_stats_roster_idx
  on public.match_boon_fighter_stats (match_id, player_id, roster_order);

alter table public.match_boon_resolutions enable row level security;
alter table public.match_boon_fighter_stats enable row level security;
revoke all on table public.match_boon_resolutions from public, anon, authenticated;
revoke all on table public.match_boon_fighter_stats from public, anon, authenticated;

-- Never publish private target/final-stat rows directly. Realtime continues to
-- notify through the match row; clients refetch a perspective-safe RPC.
do $$
begin
  if exists (
    select 1
    from pg_publication_tables pt
    join pg_publication p on p.pubname = pt.pubname
    where pt.pubname = 'supabase_realtime'
      and pt.schemaname = 'public'
      and pt.tablename = 'match_boon_resolutions'
      and not p.puballtables
  ) then
    execute 'alter publication supabase_realtime drop table public.match_boon_resolutions';
  end if;
  if exists (
    select 1
    from pg_publication_tables pt
    join pg_publication p on p.pubname = pt.pubname
    where pt.pubname = 'supabase_realtime'
      and pt.schemaname = 'public'
      and pt.tablename = 'match_boon_fighter_stats'
      and not p.puballtables
  ) then
    execute 'alter publication supabase_realtime drop table public.match_boon_fighter_stats';
  end if;
end
$$;

-- 4. Persist round-level breakdowns so resolved rounds remain independently
-- auditable even if future match-state presentation changes.
alter table public.match_rounds
  add column if not exists player_one_base_overall integer,
  add column if not exists player_one_preparation_overall_bonus integer,
  add column if not exists player_one_boon_overall_bonus integer,
  add column if not exists player_one_base_power_score integer,
  add column if not exists player_one_preparation_power_bonus integer,
  add column if not exists player_one_boon_power_bonus integer,
  add column if not exists player_two_base_overall integer,
  add column if not exists player_two_preparation_overall_bonus integer,
  add column if not exists player_two_boon_overall_bonus integer,
  add column if not exists player_two_base_power_score integer,
  add column if not exists player_two_preparation_power_bonus integer,
  add column if not exists player_two_boon_power_bonus integer;

-- 5. Central private resolver. It is called only by the protected
-- oc_preparation -> battle transition trigger. All randomness and targets are
-- derived here from match-local snapshots and stored in the same transaction.
create or replace function public.resolve_match_boon_effects_internal(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  match_row public.matches%rowtype;
  current_player uuid;
  snapshot_row public.match_boon_snapshots%rowtype;
  requested_value integer;
  target_id uuid;
  target_count integer;
  selected_verse bigint;
  random_value integer;
  unsupported_effect boolean;
begin
  select * into match_row
  from public.matches m
  where m.id = p_match_id;

  if not found then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'oc_preparation' then
    raise exception 'Boon effects require completed OC preparation';
  end if;
  if match_row.boon_effects_resolved_at is not null then return; end if;
  if (select count(*) from public.match_oc_preparations p where p.match_id = p_match_id) <> 2 then
    raise exception 'Both OC preparations are required before Boon resolution';
  end if;
  if exists (select 1 from public.match_boon_resolutions r where r.match_id = p_match_id) then
    raise exception 'Incomplete Boon resolution state already exists';
  end if;

  foreach current_player in array array[match_row.player_one_id, match_row.player_two_id]
  loop
    select * into snapshot_row
    from public.match_boon_snapshots s
    where s.match_id = p_match_id and s.player_id = current_player;

    insert into public.match_boon_resolutions (
      match_id, player_id, boon_definition_id_snapshot, boon_key_snapshot,
      effect_type_snapshot, requested_effect_value, status
    ) values (
      p_match_id,
      current_player,
      snapshot_row.boon_definition_id_snapshot,
      snapshot_row.boon_key_snapshot,
      snapshot_row.boon_effect_type_snapshot,
      snapshot_row.boon_effect_value_snapshot,
      case when snapshot_row.boon_definition_id_snapshot is null then 'no_boon' else 'no_eligible_target' end
    );

    -- Canon base values come from immutable draft snapshots. Existing
    -- Sacrificial Power transfer is the preparation layer and is already
    -- capped at 12,000 by match_oc_power_boosts.
    insert into public.match_boon_fighter_stats (
      match_id, player_id, fighter_type, match_character_id,
      verse_id_snapshot, roster_order, eligible_for_battle, boon_targeted,
      base_overall, preparation_overall_bonus, boon_overall_bonus, final_overall,
      base_power_score, preparation_power_bonus, boon_power_bonus, final_power_score
    )
    select
      p_match_id,
      current_player,
      'canon',
      mc.id,
      mc.verse_id_snapshot,
      mc.draft_position,
      not exists (
        select 1 from public.match_oc_preparations p
        where p.match_id = p_match_id
          and p.player_id = current_player
          and p.sacrificed_match_character_id = mc.id
      ),
      false,
      mc.overall_snapshot::integer,
      0,
      0,
      mc.overall_snapshot::integer,
      mc.power_score_snapshot::integer,
      coalesce(boost.effective_bonus, 0),
      0,
      least(12000, coalesce(boost.match_power_score, mc.power_score_snapshot)::integer)
    from public.match_characters mc
    left join public.match_oc_power_boosts boost
      on boost.match_id = mc.match_id and boost.match_character_id = mc.id
    where mc.match_id = p_match_id and mc.owner_player_id = current_player;

    -- Every selected OC can use Reserve under the current rules. Join the
    -- private selection snapshot so the no-OC `decision = none` preparation
    -- row is not mistaken for a fighter and the match verse remains
    -- authoritative even for matches created before preparation hardening.
    insert into public.match_boon_fighter_stats (
      match_id, player_id, fighter_type, player_character_id,
      verse_id_snapshot, roster_order, eligible_for_battle, boon_targeted,
      base_overall, preparation_overall_bonus, boon_overall_bonus, final_overall,
      base_power_score, preparation_power_bonus, boon_power_bonus, final_power_score
    )
    select
      p_match_id,
      current_player,
      'oc',
      oc_selection.player_character_id,
      oc_selection.verse_id,
      1000,
      prep.decision in ('reserve', 'absorb') and not coalesce(prep.oc_sacrificed, false),
      false,
      oc_selection.base_overall,
      greatest(0, coalesce(prep.match_overall, oc_selection.base_overall) - oc_selection.base_overall),
      0,
      coalesce(prep.match_overall, oc_selection.base_overall),
      oc_selection.base_power_score,
      0,
      0,
      least(12000, oc_selection.base_power_score)
    from public.match_oc_preparations prep
    join public.match_oc_selections oc_selection
      on oc_selection.match_id = prep.match_id
      and oc_selection.player_id = prep.player_id
      and oc_selection.player_character_id = prep.player_character_id
    where prep.match_id = p_match_id
      and prep.player_id = current_player
      and prep.decision <> 'none';

    if snapshot_row.boon_definition_id_snapshot is null then
      continue;
    end if;

    requested_value := greatest(coalesce(snapshot_row.boon_effect_value_snapshot, 0), 0);
    target_count := 0;
    target_id := null;
    selected_verse := null;
    random_value := null;
    unsupported_effect := false;

    if requested_value = 0 then
      null;

    elsif snapshot_row.boon_effect_type_snapshot = 'oc_overall' then
      select fs.id into target_id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = current_player
        and fs.fighter_type = 'oc' and fs.eligible_for_battle
      limit 1;
      if target_id is not null then
        update public.match_boon_fighter_stats fs set
          boon_targeted = true,
          boon_overall_bonus = least(requested_value, greatest(0, 99 - fs.base_overall - fs.preparation_overall_bonus)),
          final_overall = least(99, fs.base_overall + fs.preparation_overall_bonus + requested_value)
        where fs.id = target_id;
        target_count := 1;
      end if;

    elsif snapshot_row.boon_effect_type_snapshot = 'oc_power' then
      select fs.id into target_id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = current_player
        and fs.fighter_type = 'oc' and fs.eligible_for_battle
      limit 1;
      if target_id is not null then
        update public.match_boon_fighter_stats fs set
          boon_targeted = true,
          boon_power_bonus = least(requested_value, greatest(0, 12000 - fs.base_power_score - fs.preparation_power_bonus)),
          final_power_score = least(12000, fs.base_power_score + fs.preparation_power_bonus + requested_value)
        where fs.id = target_id;
        target_count := 1;
      end if;

    elsif snapshot_row.boon_effect_type_snapshot = 'random_drafted_overall' then
      select fs.id into target_id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = current_player
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
      order by random()
      limit 1;
      if target_id is not null then
        update public.match_boon_fighter_stats fs set
          boon_targeted = true,
          boon_overall_bonus = least(requested_value, greatest(0, 99 - fs.base_overall - fs.preparation_overall_bonus)),
          final_overall = least(99, fs.base_overall + fs.preparation_overall_bonus + requested_value)
        where fs.id = target_id;
        target_count := 1;
      end if;

    elsif snapshot_row.boon_effect_type_snapshot = 'lowest_drafted_overall' then
      select fs.id into target_id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = current_player
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and fs.base_overall = (
          select min(candidate.base_overall)
          from public.match_boon_fighter_stats candidate
          where candidate.match_id = p_match_id and candidate.player_id = current_player
            and candidate.fighter_type = 'canon' and candidate.eligible_for_battle
        )
      order by random()
      limit 1;
      if target_id is not null then
        update public.match_boon_fighter_stats fs set
          boon_targeted = true,
          boon_overall_bonus = least(requested_value, greatest(0, 99 - fs.base_overall - fs.preparation_overall_bonus)),
          final_overall = least(99, fs.base_overall + fs.preparation_overall_bonus + requested_value)
        where fs.id = target_id;
        target_count := 1;
      end if;

    elsif snapshot_row.boon_effect_type_snapshot = 'highest_drafted_overall' then
      select fs.id into target_id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = current_player
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and fs.base_overall = (
          select max(candidate.base_overall)
          from public.match_boon_fighter_stats candidate
          where candidate.match_id = p_match_id and candidate.player_id = current_player
            and candidate.fighter_type = 'canon' and candidate.eligible_for_battle
        )
      order by random()
      limit 1;
      if target_id is not null then
        update public.match_boon_fighter_stats fs set
          boon_targeted = true,
          boon_overall_bonus = least(requested_value, greatest(0, 99 - fs.base_overall - fs.preparation_overall_bonus)),
          final_overall = least(99, fs.base_overall + fs.preparation_overall_bonus + requested_value)
        where fs.id = target_id;
        target_count := 1;
      end if;

    elsif snapshot_row.boon_effect_type_snapshot = 'multi_lowest_overall' then
      update public.match_boon_fighter_stats fs set
        boon_targeted = true,
        boon_overall_bonus = least(requested_value, greatest(0, 99 - fs.base_overall - fs.preparation_overall_bonus)),
        final_overall = least(99, fs.base_overall + fs.preparation_overall_bonus + requested_value)
      where fs.id in (
        select candidate.id
        from public.match_boon_fighter_stats candidate
        where candidate.match_id = p_match_id and candidate.player_id = current_player
          and candidate.fighter_type = 'canon' and candidate.eligible_for_battle
        order by candidate.base_overall, random()
        limit 3
      );
      get diagnostics target_count = row_count;

    elsif snapshot_row.boon_effect_type_snapshot = 'same_verse_power' then
      select oc_selection.verse_id into selected_verse
      from public.match_oc_selections oc_selection
      where oc_selection.match_id = p_match_id
        and oc_selection.player_id = current_player
        and oc_selection.player_character_id is not null;
      update public.match_boon_fighter_stats fs set
        boon_targeted = true,
        boon_power_bonus = least(requested_value, greatest(0, 12000 - fs.base_power_score - fs.preparation_power_bonus)),
        final_power_score = least(12000, fs.base_power_score + fs.preparation_power_bonus + requested_value)
      where fs.match_id = p_match_id and fs.player_id = current_player
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and fs.verse_id_snapshot = selected_verse;
      get diagnostics target_count = row_count;

    elsif snapshot_row.boon_effect_type_snapshot = 'random_overall' then
      select fs.id into target_id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = current_player
        and fs.eligible_for_battle
      order by random()
      limit 1;
      if target_id is not null then
        random_value := 1 + floor(random() * requested_value)::integer;
        update public.match_boon_fighter_stats fs set
          boon_targeted = true,
          boon_overall_bonus = least(random_value, greatest(0, 99 - fs.base_overall - fs.preparation_overall_bonus)),
          final_overall = least(99, fs.base_overall + fs.preparation_overall_bonus + random_value)
        where fs.id = target_id;
        target_count := 1;
      end if;

    elsif snapshot_row.boon_effect_type_snapshot = 'verse_power' then
      select candidate.verse_id_snapshot into selected_verse
      from (
        select distinct fs.verse_id_snapshot
        from public.match_boon_fighter_stats fs
        where fs.match_id = p_match_id and fs.player_id = current_player
          and fs.fighter_type = 'canon' and fs.eligible_for_battle
      ) candidate
      order by random()
      limit 1;
      update public.match_boon_fighter_stats fs set
        boon_targeted = true,
        boon_power_bonus = least(requested_value, greatest(0, 12000 - fs.base_power_score - fs.preparation_power_bonus)),
        final_power_score = least(12000, fs.base_power_score + fs.preparation_power_bonus + requested_value)
      where fs.match_id = p_match_id and fs.player_id = current_player
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and fs.verse_id_snapshot = selected_verse;
      get diagnostics target_count = row_count;

    else
      unsupported_effect := true;
    end if;

    update public.match_boon_resolutions r set
      status = case when target_count > 0 then 'applied' else 'no_eligible_target' end,
      resolved_random_value = random_value,
      resolved_verse_id = selected_verse,
      metadata = jsonb_build_object(
        'targetCount', target_count,
        'overallCap', 99,
        'powerCap', 12000,
        'reason', case
          when unsupported_effect then 'unsupported_effect_type'
          when target_count = 0 then 'no_eligible_target'
          else 'applied'
        end
      )
    where r.match_id = p_match_id and r.player_id = current_player;
  end loop;
end;
$$;

-- 6. Integrate atomically at the existing OC Preparation -> Battle boundary.
-- The canonical preparation and Administrator functions remain unchanged.
create or replace function public.apply_match_boon_effects_before_battle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'oc_preparation' and new.status = 'battle'
    and old.boon_effects_resolved_at is null then
    perform public.resolve_match_boon_effects_internal(new.id);
    new.boon_effects_resolved_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists apply_match_boon_effects_before_battle on public.matches;
create trigger apply_match_boon_effects_before_battle
  before update of status on public.matches
  for each row execute function public.apply_match_boon_effects_before_battle();

-- 7. Persisted round breakdown. Existing historical rows remain NULL in these
-- optional audit columns; no history is reinterpreted.
create or replace function public.submit_battle_selection(
  p_match_id uuid,
  p_selection_type text,
  p_fighter_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  selected_canon public.match_characters%rowtype;
  selected_oc public.match_oc_preparations%rowtype;
  one_selection public.battle_selections%rowtype;
  two_selection public.battle_selections%rowtype;
  one_name text; two_name text;
  one_base_overall bigint; two_base_overall bigint;
  one_preparation_overall_bonus bigint; two_preparation_overall_bonus bigint;
  one_boon_overall_bonus bigint; two_boon_overall_bonus bigint;
  one_overall bigint; two_overall bigint;
  one_base_power bigint; two_base_power bigint;
  one_preparation_power_bonus bigint; two_preparation_power_bonus bigint;
  one_boon_power_bonus bigint; two_boon_power_bonus bigint;
  one_power bigint; two_power bigint;
  round_winner uuid;
  next_one_score integer; next_two_score integer; final_winner uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception 'Match unavailable';
  end if;
  if match_row.status <> 'battle' or match_row.battle_state <> 'selecting'
    or match_row.current_battle_round is null then
    raise exception 'Selections are not open';
  end if;

  if p_selection_type = 'canon' then
    select * into selected_canon
    from public.match_characters
    where id = p_fighter_id and match_id = p_match_id
    for update;
    if not found or selected_canon.owner_player_id <> caller_id then
      raise exception 'Fighter does not belong to this player';
    end if;
    if selected_canon.used_in_battle then raise exception 'Fighter has already been used'; end if;
    if exists (
      select 1 from public.match_oc_preparations p
      where p.match_id = p_match_id and p.player_id = caller_id
        and p.sacrificed_match_character_id = selected_canon.id
    ) then raise exception 'Absorbed fighters cannot be used in battle'; end if;
    insert into public.battle_selections (
      match_id, round_number, player_id, selection_type, match_character_id
    ) values (
      p_match_id, match_row.current_battle_round, caller_id, 'canon', selected_canon.id
    );
  elsif p_selection_type = 'oc' then
    select * into selected_oc
    from public.match_oc_preparations
    where match_id = p_match_id and player_id = caller_id
      and player_character_id = p_fighter_id
    for update;
    if not found then raise exception 'OC reserve does not belong to this player or match'; end if;
    if selected_oc.decision not in ('reserve', 'absorb') then
      raise exception 'OC preparation does not allow reserve battle use';
    end if;
    if selected_oc.decision = 'absorb' and selected_oc.oc_type <> 'champion' then
      raise exception 'Only Champion OCs can absorb a fighter';
    end if;
    if selected_oc.oc_sacrificed then raise exception 'Sacrificed OCs cannot enter battle'; end if;
    if selected_oc.match_overall is null or selected_oc.base_power_score is null then
      raise exception 'OC match stats are unavailable';
    end if;
    if selected_oc.used_in_battle then raise exception 'OC has already been used'; end if;
    insert into public.battle_selections (
      match_id, round_number, player_id, selection_type, player_character_id
    ) values (
      p_match_id, match_row.current_battle_round, caller_id, 'oc', selected_oc.player_character_id
    );
  else
    raise exception 'Invalid fighter selection type';
  end if;

  update public.matches set action_version = action_version + 1, updated_at = now()
  where id = p_match_id;
  select * into one_selection from public.battle_selections
  where match_id = p_match_id and round_number = match_row.current_battle_round
    and player_id = match_row.player_one_id;
  select * into two_selection from public.battle_selections
  where match_id = p_match_id and round_number = match_row.current_battle_round
    and player_id = match_row.player_two_id;
  if one_selection.player_id is null or two_selection.player_id is null then return; end if;

  if one_selection.selection_type = 'canon' then
    select
      c.name,
      coalesce(fs.base_overall, mc.overall_snapshot)::bigint,
      coalesce(fs.preparation_overall_bonus, 0)::bigint,
      coalesce(fs.boon_overall_bonus, 0)::bigint,
      coalesce(fs.final_overall, mc.overall_snapshot)::bigint,
      coalesce(fs.base_power_score, mc.power_score_snapshot)::bigint,
      coalesce(fs.preparation_power_bonus, boost.effective_bonus, 0)::bigint,
      coalesce(fs.boon_power_bonus, 0)::bigint,
      coalesce(fs.final_power_score, boost.match_power_score, mc.power_score_snapshot)::bigint
    into one_name, one_base_overall, one_preparation_overall_bonus,
      one_boon_overall_bonus, one_overall, one_base_power,
      one_preparation_power_bonus, one_boon_power_bonus, one_power
    from public.match_characters mc
    join public.characters c on c.id = mc.character_id
    left join public.match_oc_power_boosts boost
      on boost.match_id = mc.match_id and boost.match_character_id = mc.id
    left join public.match_boon_fighter_stats fs
      on fs.match_id = mc.match_id and fs.player_id = match_row.player_one_id
        and fs.match_character_id = mc.id
    where mc.id = one_selection.match_character_id;
  else
    select
      o.name_snapshot,
      coalesce(fs.base_overall, prep.base_overall)::bigint,
      coalesce(fs.preparation_overall_bonus, greatest(0, prep.match_overall - prep.base_overall))::bigint,
      coalesce(fs.boon_overall_bonus, 0)::bigint,
      coalesce(fs.final_overall, prep.match_overall)::bigint,
      coalesce(fs.base_power_score, prep.base_power_score)::bigint,
      coalesce(fs.preparation_power_bonus, 0)::bigint,
      coalesce(fs.boon_power_bonus, 0)::bigint,
      coalesce(fs.final_power_score, prep.base_power_score)::bigint
    into one_name, one_base_overall, one_preparation_overall_bonus,
      one_boon_overall_bonus, one_overall, one_base_power,
      one_preparation_power_bonus, one_boon_power_bonus, one_power
    from public.match_oc_preparations prep
    join public.match_oc_options o
      on o.match_id = prep.match_id and o.player_id = prep.player_id
        and o.player_character_id = prep.player_character_id
    left join public.match_boon_fighter_stats fs
      on fs.match_id = prep.match_id and fs.player_id = prep.player_id
        and fs.player_character_id = prep.player_character_id
    where prep.match_id = p_match_id and prep.player_id = match_row.player_one_id;
  end if;

  if two_selection.selection_type = 'canon' then
    select
      c.name,
      coalesce(fs.base_overall, mc.overall_snapshot)::bigint,
      coalesce(fs.preparation_overall_bonus, 0)::bigint,
      coalesce(fs.boon_overall_bonus, 0)::bigint,
      coalesce(fs.final_overall, mc.overall_snapshot)::bigint,
      coalesce(fs.base_power_score, mc.power_score_snapshot)::bigint,
      coalesce(fs.preparation_power_bonus, boost.effective_bonus, 0)::bigint,
      coalesce(fs.boon_power_bonus, 0)::bigint,
      coalesce(fs.final_power_score, boost.match_power_score, mc.power_score_snapshot)::bigint
    into two_name, two_base_overall, two_preparation_overall_bonus,
      two_boon_overall_bonus, two_overall, two_base_power,
      two_preparation_power_bonus, two_boon_power_bonus, two_power
    from public.match_characters mc
    join public.characters c on c.id = mc.character_id
    left join public.match_oc_power_boosts boost
      on boost.match_id = mc.match_id and boost.match_character_id = mc.id
    left join public.match_boon_fighter_stats fs
      on fs.match_id = mc.match_id and fs.player_id = match_row.player_two_id
        and fs.match_character_id = mc.id
    where mc.id = two_selection.match_character_id;
  else
    select
      o.name_snapshot,
      coalesce(fs.base_overall, prep.base_overall)::bigint,
      coalesce(fs.preparation_overall_bonus, greatest(0, prep.match_overall - prep.base_overall))::bigint,
      coalesce(fs.boon_overall_bonus, 0)::bigint,
      coalesce(fs.final_overall, prep.match_overall)::bigint,
      coalesce(fs.base_power_score, prep.base_power_score)::bigint,
      coalesce(fs.preparation_power_bonus, 0)::bigint,
      coalesce(fs.boon_power_bonus, 0)::bigint,
      coalesce(fs.final_power_score, prep.base_power_score)::bigint
    into two_name, two_base_overall, two_preparation_overall_bonus,
      two_boon_overall_bonus, two_overall, two_base_power,
      two_preparation_power_bonus, two_boon_power_bonus, two_power
    from public.match_oc_preparations prep
    join public.match_oc_options o
      on o.match_id = prep.match_id and o.player_id = prep.player_id
        and o.player_character_id = prep.player_character_id
    left join public.match_boon_fighter_stats fs
      on fs.match_id = prep.match_id and fs.player_id = prep.player_id
        and fs.player_character_id = prep.player_character_id
    where prep.match_id = p_match_id and prep.player_id = match_row.player_two_id;
  end if;

  round_winner := case
    when one_overall > two_overall then match_row.player_one_id
    when two_overall > one_overall then match_row.player_two_id
    when one_power > two_power then match_row.player_one_id
    when two_power > one_power then match_row.player_two_id
    else null
  end;
  next_one_score := match_row.player_one_score
    + case when round_winner = match_row.player_one_id then 1 else 0 end;
  next_two_score := match_row.player_two_score
    + case when round_winner = match_row.player_two_id then 1 else 0 end;

  if one_selection.selection_type = 'canon' then
    update public.match_characters set used_in_battle = true
    where id = one_selection.match_character_id;
    if one_preparation_power_bonus > 0 then
      update public.match_oc_preparations set revealed_at = coalesce(revealed_at, now())
      where match_id = p_match_id and player_id = match_row.player_one_id
        and oc_type = 'sacrificial' and decision = 'sacrifice';
    end if;
  else
    update public.match_oc_preparations
    set used_in_battle = true,
        used_in_round = match_row.current_battle_round,
        revealed_at = coalesce(revealed_at, now())
    where match_id = p_match_id and player_id = match_row.player_one_id;
  end if;
  if two_selection.selection_type = 'canon' then
    update public.match_characters set used_in_battle = true
    where id = two_selection.match_character_id;
    if two_preparation_power_bonus > 0 then
      update public.match_oc_preparations set revealed_at = coalesce(revealed_at, now())
      where match_id = p_match_id and player_id = match_row.player_two_id
        and oc_type = 'sacrificial' and decision = 'sacrifice';
    end if;
  else
    update public.match_oc_preparations
    set used_in_battle = true,
        used_in_round = match_row.current_battle_round,
        revealed_at = coalesce(revealed_at, now())
    where match_id = p_match_id and player_id = match_row.player_two_id;
  end if;

  insert into public.match_rounds (
    match_id, round_number, winner_player_id,
    player_one_fighter_type, player_one_match_character_id,
    player_one_player_character_id, player_one_name,
    player_one_base_overall, player_one_preparation_overall_bonus,
    player_one_boon_overall_bonus, player_one_overall,
    player_one_base_power_score, player_one_preparation_power_bonus,
    player_one_boon_power_bonus, player_one_power_score,
    player_two_fighter_type, player_two_match_character_id,
    player_two_player_character_id, player_two_name,
    player_two_base_overall, player_two_preparation_overall_bonus,
    player_two_boon_overall_bonus, player_two_overall,
    player_two_base_power_score, player_two_preparation_power_bonus,
    player_two_boon_power_bonus, player_two_power_score
  ) values (
    p_match_id, match_row.current_battle_round, round_winner,
    one_selection.selection_type, one_selection.match_character_id,
    one_selection.player_character_id, one_name,
    one_base_overall, one_preparation_overall_bonus,
    one_boon_overall_bonus, one_overall,
    one_base_power, one_preparation_power_bonus,
    one_boon_power_bonus, one_power,
    two_selection.selection_type, two_selection.match_character_id,
    two_selection.player_character_id, two_name,
    two_base_overall, two_preparation_overall_bonus,
    two_boon_overall_bonus, two_overall,
    two_base_power, two_preparation_power_bonus,
    two_boon_power_bonus, two_power
  );

  delete from public.battle_selections
  where match_id = p_match_id and round_number = match_row.current_battle_round;

  if next_one_score >= 3 or next_two_score >= 3 or match_row.current_battle_round = 5 then
    final_winner := case
      when next_one_score > next_two_score then match_row.player_one_id
      when next_two_score > next_one_score then match_row.player_two_id
      else null
    end;
    update public.matches set
      status = 'completed', battle_state = 'complete',
      player_one_score = next_one_score, player_two_score = next_two_score,
      winner_id = final_winner, completed_at = now(),
      action_version = action_version + 1, updated_at = now()
    where id = p_match_id and status = 'battle';
    if final_winner is not null then
      update public.profiles set wins = wins + 1 where id = final_winner;
      update public.profiles set losses = losses + 1
      where id = case when final_winner = match_row.player_one_id
        then match_row.player_two_id else match_row.player_one_id end;
    end if;
    perform public.grant_ranked_match_boon_rewards(p_match_id);
  else
    update public.matches set
      battle_state = 'revealed',
      player_one_score = next_one_score,
      player_two_score = next_two_score,
      action_version = action_version + 1,
      updated_at = now()
    where id = p_match_id;
  end if;
end;
$$;

create or replace function public.submit_battle_selection(
  p_match_id uuid,
  p_match_character_id uuid
)
returns void
language sql
security definer
set search_path = ''
as $$
  select public.submit_battle_selection(p_match_id, 'canon', p_match_character_id);
$$;

-- 8. Perspective-safe battle projection. Own finalized stats/targets are
-- visible immediately. Opponent adjustments remain hidden until that fighter
-- resolves a round, protecting secret OC and exact-verse context.
create or replace function public.get_online_battle_state(p_match_id uuid)
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
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception 'Match unavailable';
  end if;
  if match_row.status not in ('battle', 'completed') then
    raise exception 'Battle is not available';
  end if;
  opponent_id := case when caller_id = match_row.player_one_id
    then match_row.player_two_id else match_row.player_one_id end;

  return jsonb_build_object(
    'matchId', match_row.id,
    'status', match_row.status,
    'roundNumber', match_row.current_battle_round,
    'battleState', match_row.battle_state,
    'yourPlayerId', caller_id,
    'opponentPlayerId', opponent_id,
    'yourScore', case when caller_id = match_row.player_one_id
      then match_row.player_one_score else match_row.player_two_score end,
    'opponentScore', case when caller_id = match_row.player_one_id
      then match_row.player_two_score else match_row.player_one_score end,
    'matchWinnerId', match_row.winner_id,
    'yourProfile', (select jsonb_build_object(
      'id', p.id, 'username', p.username, 'wins', p.wins, 'losses', p.losses,
      'is_system_player', p.is_system_player
    ) from public.profiles p where p.id = caller_id),
    'opponentProfile', (select jsonb_build_object(
      'id', p.id, 'username', p.username, 'is_system_player', p.is_system_player
    ) from public.profiles p where p.id = opponent_id),
    'yourBoonResolution', (select jsonb_build_object(
      'boonKey', resolution.boon_key_snapshot,
      'status', resolution.status,
      'resolvedValue', resolution.resolved_random_value,
      'resolvedVerseId', resolution.resolved_verse_id,
      'targets', coalesce((select jsonb_agg(jsonb_build_object(
        'fighterType', stats.fighter_type,
        'fighterId', coalesce(stats.match_character_id, stats.player_character_id),
        'overallBonus', stats.boon_overall_bonus,
        'powerBonus', stats.boon_power_bonus
      ) order by stats.roster_order)
      from public.match_boon_fighter_stats stats
      where stats.match_id = p_match_id and stats.player_id = caller_id
        and stats.boon_targeted), '[]'::jsonb)
    ) from public.match_boon_resolutions resolution
      where resolution.match_id = p_match_id and resolution.player_id = caller_id),
    'yourTeam', coalesce((select jsonb_agg(jsonb_build_object(
      'id', mc.id,
      'used', mc.used_in_battle,
      'sacrificed', not coalesce(stats.eligible_for_battle, not exists(
        select 1 from public.match_oc_preparations prep
        where prep.match_id = p_match_id and prep.player_id = caller_id
          and prep.sacrificed_match_character_id = mc.id
      )),
      'empowered', coalesce(stats.preparation_power_bonus, boost.effective_bonus, 0) > 0,
      'baseOverall', coalesce(stats.base_overall, mc.overall_snapshot),
      'preparationOverallBonus', coalesce(stats.preparation_overall_bonus, 0),
      'boonOverallBonus', coalesce(stats.boon_overall_bonus, 0),
      'basePowerScore', coalesce(stats.base_power_score, mc.power_score_snapshot),
      'preparationPowerBonus', coalesce(stats.preparation_power_bonus, boost.effective_bonus, 0),
      'boonPowerBonus', coalesce(stats.boon_power_bonus, 0),
      'matchPowerScore', coalesce(stats.final_power_score, boost.match_power_score, mc.power_score_snapshot),
      'powerBoost', coalesce(stats.preparation_power_bonus, boost.effective_bonus, 0),
      'boonEnhanced', coalesce(stats.boon_overall_bonus, 0) > 0 or coalesce(stats.boon_power_bonus, 0) > 0,
      'character', to_jsonb(c) || jsonb_build_object(
        'overall', coalesce(stats.final_overall, mc.overall_snapshot),
        'power_score', coalesce(stats.final_power_score, boost.match_power_score, mc.power_score_snapshot),
        'verses', (select to_jsonb(v) from public.verses v where v.id = mc.verse_id_snapshot)
      )
    ) order by mc.draft_position)
    from public.match_characters mc
    join public.characters c on c.id = mc.character_id
    left join public.match_oc_power_boosts boost
      on boost.match_id = mc.match_id and boost.match_character_id = mc.id
    left join public.match_boon_fighter_stats stats
      on stats.match_id = mc.match_id and stats.player_id = caller_id
        and stats.match_character_id = mc.id
    where mc.match_id = p_match_id and mc.owner_player_id = caller_id), '[]'::jsonb),
    'opponentTeam', coalesce((select jsonb_agg(jsonb_build_object(
      'id', mc.id,
      'used', mc.used_in_battle,
      'boonEnhanced', mc.used_in_battle and (
        coalesce(stats.boon_overall_bonus, 0) > 0 or coalesce(stats.boon_power_bonus, 0) > 0
      ),
      'baseOverall', mc.overall_snapshot,
      'preparationOverallBonus', case when mc.used_in_battle then coalesce(stats.preparation_overall_bonus, 0) else 0 end,
      'boonOverallBonus', case when mc.used_in_battle then coalesce(stats.boon_overall_bonus, 0) else 0 end,
      'basePowerScore', mc.power_score_snapshot,
      'preparationPowerBonus', case when mc.used_in_battle then coalesce(stats.preparation_power_bonus, 0) else 0 end,
      'boonPowerBonus', case when mc.used_in_battle then coalesce(stats.boon_power_bonus, 0) else 0 end,
      'character', to_jsonb(c) || jsonb_build_object(
        'overall', case when mc.used_in_battle then coalesce(stats.final_overall, mc.overall_snapshot) else mc.overall_snapshot end,
        'power_score', case when mc.used_in_battle then coalesce(stats.final_power_score, mc.power_score_snapshot) else mc.power_score_snapshot end,
        'verses', (select to_jsonb(v) from public.verses v where v.id = mc.verse_id_snapshot)
      )
    ) order by mc.draft_position)
    from public.match_characters mc
    join public.characters c on c.id = mc.character_id
    left join public.match_boon_fighter_stats stats
      on stats.match_id = mc.match_id and stats.player_id = opponent_id
        and stats.match_character_id = mc.id
    where mc.match_id = p_match_id and mc.owner_player_id = opponent_id), '[]'::jsonb),
    'yourOC', (select case
      when prep.player_character_id is null
        or not (prep.decision = 'reserve' or (prep.oc_type = 'champion' and prep.decision = 'absorb'))
      then null else jsonb_build_object(
        'id', prep.player_character_id,
        'name', oc_option.name_snapshot,
        'verseName', oc_option.verse_name_snapshot,
        'overall', coalesce(stats.final_overall, prep.match_overall),
        'powerScore', coalesce(stats.final_power_score, prep.base_power_score),
        'used', prep.used_in_battle,
        'boost', prep.sacrifice_boost,
        'ocType', prep.oc_type,
        'decision', prep.decision,
        'baseOverall', coalesce(stats.base_overall, prep.base_overall),
        'preparationOverallBonus', coalesce(stats.preparation_overall_bonus, greatest(0, prep.match_overall - prep.base_overall)),
        'boonOverallBonus', coalesce(stats.boon_overall_bonus, 0),
        'basePowerScore', coalesce(stats.base_power_score, prep.base_power_score),
        'preparationPowerBonus', coalesce(stats.preparation_power_bonus, 0),
        'boonPowerBonus', coalesce(stats.boon_power_bonus, 0),
        'boonEnhanced', coalesce(stats.boon_overall_bonus, 0) > 0 or coalesce(stats.boon_power_bonus, 0) > 0
      ) end
      from public.match_oc_preparations prep
      left join public.match_oc_options oc_option
        on oc_option.match_id = prep.match_id and oc_option.player_id = prep.player_id
          and oc_option.player_character_id = prep.player_character_id
      left join public.match_boon_fighter_stats stats
        on stats.match_id = prep.match_id and stats.player_id = prep.player_id
          and stats.player_character_id = prep.player_character_id
      where prep.match_id = p_match_id and prep.player_id = caller_id),
    'opponentOC', (select case
      when prep.revealed_at is null
        or not (prep.decision = 'reserve' or (prep.oc_type = 'champion' and prep.decision = 'absorb'))
      then null else jsonb_build_object(
        'id', prep.player_character_id,
        'name', oc_option.name_snapshot,
        'verseName', oc_option.verse_name_snapshot,
        'overall', coalesce(stats.final_overall, prep.match_overall),
        'powerScore', coalesce(stats.final_power_score, prep.base_power_score),
        'used', prep.used_in_battle,
        'boost', prep.sacrifice_boost,
        'ocType', prep.oc_type,
        'decision', prep.decision,
        'sacrificeTier', prep.sacrifice_tier,
        'sacrificeBoost', prep.sacrifice_boost,
        'sacrificedName', (select c.name
          from public.match_characters mc join public.characters c on c.id = mc.character_id
          where mc.id = prep.sacrificed_match_character_id),
        'baseOverall', coalesce(stats.base_overall, prep.base_overall),
        'preparationOverallBonus', coalesce(stats.preparation_overall_bonus, greatest(0, prep.match_overall - prep.base_overall)),
        'boonOverallBonus', coalesce(stats.boon_overall_bonus, 0),
        'basePowerScore', coalesce(stats.base_power_score, prep.base_power_score),
        'preparationPowerBonus', coalesce(stats.preparation_power_bonus, 0),
        'boonPowerBonus', coalesce(stats.boon_power_bonus, 0),
        'boonEnhanced', coalesce(stats.boon_overall_bonus, 0) > 0 or coalesce(stats.boon_power_bonus, 0) > 0
      ) end
      from public.match_oc_preparations prep
      left join public.match_oc_options oc_option
        on oc_option.match_id = prep.match_id and oc_option.player_id = prep.player_id
          and oc_option.player_character_id = prep.player_character_id
      left join public.match_boon_fighter_stats stats
        on stats.match_id = prep.match_id and stats.player_id = prep.player_id
          and stats.player_character_id = prep.player_character_id
      where prep.match_id = p_match_id and prep.player_id = opponent_id),
    'yourSupport', (select case
      when prep.player_character_id is null or prep.oc_type <> 'sacrificial'
        or prep.decision not in ('inactive', 'sacrifice')
      then null else jsonb_build_object(
        'id', prep.player_character_id, 'name', oc_option.name_snapshot,
        'verseName', oc_option.verse_name_snapshot, 'overall', prep.match_overall,
        'powerScore', prep.base_power_score, 'used', true, 'boost', 0,
        'ocType', prep.oc_type, 'decision', prep.decision,
        'recipientCount', prep.recipient_count
      ) end
      from public.match_oc_preparations prep
      left join public.match_oc_options oc_option
        on oc_option.match_id = prep.match_id and oc_option.player_id = prep.player_id
          and oc_option.player_character_id = prep.player_character_id
      where prep.match_id = p_match_id and prep.player_id = caller_id),
    'opponentSupport', (select case
      when prep.revealed_at is null or prep.oc_type <> 'sacrificial'
        or prep.decision not in ('inactive', 'sacrifice')
      then null else jsonb_build_object(
        'id', prep.player_character_id, 'name', oc_option.name_snapshot,
        'verseName', oc_option.verse_name_snapshot, 'overall', prep.match_overall,
        'powerScore', prep.base_power_score, 'used', true, 'boost', 0,
        'ocType', prep.oc_type, 'decision', prep.decision,
        'recipientCount', prep.recipient_count
      ) end
      from public.match_oc_preparations prep
      left join public.match_oc_options oc_option
        on oc_option.match_id = prep.match_id and oc_option.player_id = prep.player_id
          and oc_option.player_character_id = prep.player_character_id
      where prep.match_id = p_match_id and prep.player_id = opponent_id),
    'yourSelection', (select jsonb_build_object(
      'type', selection.selection_type,
      'id', coalesce(selection.match_character_id, selection.player_character_id)
    ) from public.battle_selections selection
      where selection.match_id = p_match_id
        and selection.round_number = match_row.current_battle_round
        and selection.player_id = caller_id),
    'opponentLocked', exists (
      select 1 from public.battle_selections selection
      where selection.match_id = p_match_id
        and selection.round_number = match_row.current_battle_round
        and selection.player_id = opponent_id
    ),
    'latestRound', (select jsonb_build_object(
      'roundNumber', round_row.round_number,
      'yourFighter', case when caller_id = match_row.player_one_id then jsonb_build_object(
        'type', round_row.player_one_fighter_type,
        'id', coalesce(round_row.player_one_match_character_id, round_row.player_one_player_character_id),
        'name', round_row.player_one_name,
        'baseOverall', round_row.player_one_base_overall,
        'preparationOverallBonus', coalesce(round_row.player_one_preparation_overall_bonus, 0),
        'boonOverallBonus', coalesce(round_row.player_one_boon_overall_bonus, 0),
        'overall', round_row.player_one_overall,
        'basePowerScore', round_row.player_one_base_power_score,
        'preparationPowerBonus', coalesce(round_row.player_one_preparation_power_bonus, 0),
        'boonPowerBonus', coalesce(round_row.player_one_boon_power_bonus, 0),
        'powerScore', round_row.player_one_power_score,
        'empowered', coalesce(round_row.player_one_preparation_power_bonus, 0) > 0,
        'powerBoost', coalesce(round_row.player_one_preparation_power_bonus, 0),
        'boonEnhanced', coalesce(round_row.player_one_boon_overall_bonus, 0) > 0
          or coalesce(round_row.player_one_boon_power_bonus, 0) > 0
      ) else jsonb_build_object(
        'type', round_row.player_two_fighter_type,
        'id', coalesce(round_row.player_two_match_character_id, round_row.player_two_player_character_id),
        'name', round_row.player_two_name,
        'baseOverall', round_row.player_two_base_overall,
        'preparationOverallBonus', coalesce(round_row.player_two_preparation_overall_bonus, 0),
        'boonOverallBonus', coalesce(round_row.player_two_boon_overall_bonus, 0),
        'overall', round_row.player_two_overall,
        'basePowerScore', round_row.player_two_base_power_score,
        'preparationPowerBonus', coalesce(round_row.player_two_preparation_power_bonus, 0),
        'boonPowerBonus', coalesce(round_row.player_two_boon_power_bonus, 0),
        'powerScore', round_row.player_two_power_score,
        'empowered', coalesce(round_row.player_two_preparation_power_bonus, 0) > 0,
        'powerBoost', coalesce(round_row.player_two_preparation_power_bonus, 0),
        'boonEnhanced', coalesce(round_row.player_two_boon_overall_bonus, 0) > 0
          or coalesce(round_row.player_two_boon_power_bonus, 0) > 0
      ) end,
      'opponentFighter', case when caller_id = match_row.player_one_id then jsonb_build_object(
        'type', round_row.player_two_fighter_type,
        'id', coalesce(round_row.player_two_match_character_id, round_row.player_two_player_character_id),
        'name', round_row.player_two_name,
        'baseOverall', round_row.player_two_base_overall,
        'preparationOverallBonus', coalesce(round_row.player_two_preparation_overall_bonus, 0),
        'boonOverallBonus', coalesce(round_row.player_two_boon_overall_bonus, 0),
        'overall', round_row.player_two_overall,
        'basePowerScore', round_row.player_two_base_power_score,
        'preparationPowerBonus', coalesce(round_row.player_two_preparation_power_bonus, 0),
        'boonPowerBonus', coalesce(round_row.player_two_boon_power_bonus, 0),
        'powerScore', round_row.player_two_power_score,
        'empowered', coalesce(round_row.player_two_preparation_power_bonus, 0) > 0,
        'powerBoost', coalesce(round_row.player_two_preparation_power_bonus, 0),
        'boonEnhanced', coalesce(round_row.player_two_boon_overall_bonus, 0) > 0
          or coalesce(round_row.player_two_boon_power_bonus, 0) > 0
      ) else jsonb_build_object(
        'type', round_row.player_one_fighter_type,
        'id', coalesce(round_row.player_one_match_character_id, round_row.player_one_player_character_id),
        'name', round_row.player_one_name,
        'baseOverall', round_row.player_one_base_overall,
        'preparationOverallBonus', coalesce(round_row.player_one_preparation_overall_bonus, 0),
        'boonOverallBonus', coalesce(round_row.player_one_boon_overall_bonus, 0),
        'overall', round_row.player_one_overall,
        'basePowerScore', round_row.player_one_base_power_score,
        'preparationPowerBonus', coalesce(round_row.player_one_preparation_power_bonus, 0),
        'boonPowerBonus', coalesce(round_row.player_one_boon_power_bonus, 0),
        'powerScore', round_row.player_one_power_score,
        'empowered', coalesce(round_row.player_one_preparation_power_bonus, 0) > 0,
        'powerBoost', coalesce(round_row.player_one_preparation_power_bonus, 0),
        'boonEnhanced', coalesce(round_row.player_one_boon_overall_bonus, 0) > 0
          or coalesce(round_row.player_one_boon_power_bonus, 0) > 0
      ) end,
      'winnerPlayerId', round_row.winner_player_id
    ) from public.match_rounds round_row
      where round_row.match_id = p_match_id
      order by round_row.round_number desc limit 1)
  );
end;
$$;

-- 9. Browser permissions. Only the canonical selection and perspective RPCs
-- remain executable. Target selection and stat mutation helpers are private.
revoke all on function public.resolve_match_boon_effects_internal(uuid)
  from public, anon, authenticated;
revoke all on function public.apply_match_boon_effects_before_battle()
  from public, anon, authenticated;
revoke all on function public.submit_battle_selection(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.submit_battle_selection(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.get_online_battle_state(uuid)
  from public, anon, authenticated;

grant execute on function public.submit_battle_selection(uuid, text, uuid)
  to authenticated;
grant execute on function public.submit_battle_selection(uuid, uuid)
  to authenticated;
grant execute on function public.get_online_battle_state(uuid)
  to authenticated;

notify pgrst, 'reload schema';
