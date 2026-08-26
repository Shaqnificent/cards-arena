-- Anime Arena Boon Resolver V2
-- Run after boon_catalogue_v2_100.sql, Boon Phases 1-5, and
-- supabase_admin_boons.sql. This migration does not seed or rebalance Boons.

begin;

-- Immutable structured definition snapshot for future matches.
alter table public.match_boon_snapshots
  add column if not exists boon_effect_config_snapshot jsonb;

-- V2 can apply negative temporary modifiers and records richer outcomes.
alter table public.match_boon_resolutions
  add column if not exists requested_overall_value integer,
  add column if not exists requested_power_value integer,
  drop constraint if exists match_boon_resolutions_status_check,
  drop constraint if exists match_boon_resolutions_value_check,
  drop constraint if exists match_boon_resolutions_random_value_check;

alter table public.match_boon_resolutions
  add constraint match_boon_resolutions_status_check check (
    status in (
      'applied', 'no_eligible_target', 'condition_not_met',
      'configuration_error', 'no_boon'
    )
  ),
  add constraint match_boon_resolutions_random_value_check check (
    resolved_random_value is null or resolved_random_value between -12000 and 12000
  );

alter table public.match_boon_fighter_stats
  drop constraint if exists match_boon_fighter_stats_overall_check,
  drop constraint if exists match_boon_fighter_stats_power_check;

alter table public.match_boon_fighter_stats
  add constraint match_boon_fighter_stats_overall_check check (
    base_overall between 1 and 99
    and preparation_overall_bonus >= 0
    and boon_overall_bonus between -98 and 98
    and final_overall between 1 and 99
  ),
  add constraint match_boon_fighter_stats_power_check check (
    base_power_score >= 0
    and preparation_power_bonus >= 0
    and boon_power_bonus between -12000 and 12000
    and final_power_score between 0 and 12000
  );

-- One private row per resolved effect/target. Random choices, reference values,
-- requested deltas, applied deltas, and final values are durable and auditable.
create table if not exists public.match_boon_effect_applications (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null,
  player_id uuid not null,
  effect_index integer not null,
  target_order integer not null,
  fighter_stat_id uuid not null
    references public.match_boon_fighter_stats(id) on delete cascade,
  target_rule_snapshot text not null,
  stat text not null,
  mode text not null,
  condition_status text not null,
  requested_delta integer not null,
  applied_delta integer not null,
  pre_boon_value integer not null,
  value_before_effect integer not null,
  final_value integer not null,
  resolved_random_value integer,
  resolved_verse_id bigint,
  resolved_branch text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (match_id, player_id)
    references public.match_boon_resolutions(match_id, player_id)
    on delete cascade,
  constraint match_boon_effect_applications_stat_check
    check (stat in ('overall', 'power')),
  constraint match_boon_effect_applications_condition_check
    check (condition_status in ('met', 'not_met')),
  constraint match_boon_effect_applications_order_check
    check (effect_index >= 0 and target_order >= 0),
  unique (match_id, player_id, effect_index, fighter_stat_id)
);

create index if not exists match_boon_effect_applications_match_player_idx
  on public.match_boon_effect_applications(match_id, player_id, effect_index);

alter table public.match_boon_effect_applications enable row level security;
revoke all on table public.match_boon_effect_applications
  from public, anon, authenticated;

do $$
begin
  if exists (
    select 1
    from pg_publication_tables pt
    join pg_publication p on p.pubname = pt.pubname
    where pt.pubname = 'supabase_realtime'
      and pt.schemaname = 'public'
      and pt.tablename = 'match_boon_effect_applications'
      and not p.puballtables
  ) then
    execute 'alter publication supabase_realtime drop table public.match_boon_effect_applications';
  end if;
end
$$;

-- Administrator-aware and legacy-safe queue snapshot builder. Existing owned
-- inactive Boons remain snapshot-able when already equipped, but inactive
-- definitions remain excluded from the Shop/roll pool by existing RPCs.
create or replace function public.build_player_boon_snapshot_internal(p_player_id uuid)
returns jsonb
language plpgsql
volatile
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

  if not found or profile_is_guest then return null; end if;

  if profile_is_system then
    select jsonb_build_object(
      'playerBoonId', null,
      'definitionId', d.id,
      'key', d.key,
      'name', d.name,
      'description', d.description,
      'rarity', d.rarity,
      'effectType', d.effect_type,
      'effectValue', d.effect_value,
      'overallEffectValue', d.overall_effect_value,
      'powerEffectValue', d.power_effect_value,
      'targetRule', d.target_rule,
      'effectConfig', d.effect_config,
      'systemOnly', true
    ) into result
    from public.boon_definitions d
    where d.active = true and d.system_only = true
      and d.key in (
        'admin_sovereign_ascension',
        'admin_apex_overdrive',
        'admin_tyrants_verdict'
      )
    order by random()
    limit 1;
    return result;
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
    'overallEffectValue', d.overall_effect_value,
    'powerEffectValue', d.power_effect_value,
    'targetRule', d.target_rule,
    'effectConfig', d.effect_config,
    'systemOnly', false
  ) into result
  from public.player_boons pb
  join public.boon_definitions d on d.id = pb.boon_definition_id
  where pb.owner_id = p_player_id
    and pb.equipped = true
    and d.system_only = false
  order by pb.created_at
  limit 1;
  return result;
end;
$$;

-- Forward declarations keep PostgreSQL function-body validation deterministic;
-- the strict implementations replace these declarations later in this file.
create or replace function public.evaluate_match_boon_condition_v2(
  p_condition jsonb,
  p_match_id uuid,
  p_player_id uuid,
  p_target_ids uuid[] default array[]::uuid[]
)
returns text
language sql
stable
security definer
set search_path = ''
as $$ select 'configuration_error'::text $$;

create or replace function public.resolve_match_boon_targets_v2(
  p_target_rule text,
  p_match_id uuid,
  p_player_id uuid,
  p_condition jsonb default null,
  p_options jsonb default null,
  p_excluded_ids uuid[] default array[]::uuid[]
)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$ select jsonb_build_object('valid', false, 'reason', 'not_initialized') $$;

create or replace function public.calculate_match_boon_effect_v2(
  p_effect jsonb,
  p_match_id uuid,
  p_player_id uuid,
  p_fighter_stat_id uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = ''
as $$ select jsonb_build_object('valid', false, 'reason', 'not_initialized') $$;

-- Central V2 resolver. This replaces (rather than duplicates) the Phase 5
-- resolver and preserves its exactly-once match-transition contract.
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
  config jsonb;
  effect_items jsonb;
  effect_item jsonb;
  root_has_target boolean;
  target_rule text;
  condition_config jsonb;
  target_result jsonb;
  calculation jsonb;
  target_ids uuid[];
  excluded_ids uuid[];
  used_ids uuid[];
  target_id uuid;
  target_row public.match_boon_fighter_stats%rowtype;
  effect_index_value integer;
  target_order_value integer;
  condition_result text;
  requested_delta integer;
  applied_delta integer;
  value_before integer;
  value_after integer;
  configured_cap integer;
  configured_floor integer;
  applied_count integer;
  condition_failure_count integer;
  no_target_count integer;
  configuration_error_count integer;
  requested_overall_total integer;
  requested_power_total integer;
  first_random_value integer;
  first_resolved_verse bigint;
  first_resolved_branch text;
  audit_summary jsonb;
  diagnostic_entries jsonb;
  resolved_groups jsonb;
  group_name text;
  source_group_name text;
  exclude_group_name text;
  grouped_target_id uuid;
  side_already_resolved boolean;
begin
  select * into match_row
  from public.matches m
  where m.id = p_match_id
  for update;

  if not found then raise exception 'Match unavailable'; end if;
  if match_row.boon_effects_resolved_at is not null then return; end if;
  if match_row.status <> 'oc_preparation' then
    raise exception 'Boon effects require completed OC preparation';
  end if;
  if (select count(*) from public.match_oc_preparations prep
      where prep.match_id = p_match_id) <> 2 then
    raise exception 'Both OC preparations are required before Boon resolution';
  end if;
  foreach current_player in array array[match_row.player_one_id, match_row.player_two_id]
  loop
    -- A completed side is immutable. This makes a repeated direct invocation or
    -- a resumed transition reuse the durable result instead of rolling again.
    select coalesce(resolution.metadata ? 'applications', false)
      into side_already_resolved
    from public.match_boon_resolutions resolution
    where resolution.match_id = p_match_id
      and resolution.player_id = current_player;
    if coalesce(side_already_resolved, false) then
      continue;
    end if;

    select * into snapshot_row
    from public.match_boon_snapshots snapshot
    where snapshot.match_id = p_match_id
      and snapshot.player_id = current_player;

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
      case when snapshot_row.boon_definition_id_snapshot is null
        then 'no_boon' else 'no_eligible_target' end
    )
    on conflict (match_id, player_id) do nothing;

    -- Canon stats are immutable draft snapshots plus the already-resolved
    -- Sacrificial preparation transfer. Absorbed fighters remain unavailable.
    insert into public.match_boon_fighter_stats (
      match_id, player_id, fighter_type, match_character_id,
      verse_id_snapshot, roster_order, eligible_for_battle, boon_targeted,
      base_overall, preparation_overall_bonus, boon_overall_bonus, final_overall,
      base_power_score, preparation_power_bonus, boon_power_bonus, final_power_score
    )
    select
      p_match_id, current_player, 'canon', mc.id, mc.verse_id_snapshot,
      mc.draft_position,
      not exists (
        select 1 from public.match_oc_preparations prep
        where prep.match_id = p_match_id and prep.player_id = current_player
          and prep.sacrificed_match_character_id = mc.id
      ),
      false,
      mc.overall_snapshot::integer, 0, 0, mc.overall_snapshot::integer,
      mc.power_score_snapshot::integer, coalesce(boost.effective_bonus, 0), 0,
      least(12000, coalesce(boost.match_power_score, mc.power_score_snapshot)::integer)
    from public.match_characters mc
    left join public.match_oc_power_boosts boost
      on boost.match_id = mc.match_id and boost.match_character_id = mc.id
    where mc.match_id = p_match_id and mc.owner_player_id = current_player
    on conflict do nothing;

    -- Reserve is playable for both OC types. Join the private selection
    -- snapshot so a legitimate no-OC `decision = none` preparation row is
    -- never inserted as a fighter with null identity/verse/stat values.
    insert into public.match_boon_fighter_stats (
      match_id, player_id, fighter_type, player_character_id,
      verse_id_snapshot, roster_order, eligible_for_battle, boon_targeted,
      base_overall, preparation_overall_bonus, boon_overall_bonus, final_overall,
      base_power_score, preparation_power_bonus, boon_power_bonus, final_power_score
    )
    select
      p_match_id, current_player, 'oc', oc_selection.player_character_id,
      oc_selection.verse_id, 1000,
      prep.decision in ('reserve', 'absorb') and not coalesce(prep.oc_sacrificed, false),
      false,
      oc_selection.base_overall,
      greatest(0, coalesce(prep.match_overall, oc_selection.base_overall) - oc_selection.base_overall),
      0, coalesce(prep.match_overall, oc_selection.base_overall),
      oc_selection.base_power_score, 0, 0, least(12000, oc_selection.base_power_score)
    from public.match_oc_preparations prep
    join public.match_oc_selections oc_selection
      on oc_selection.match_id = prep.match_id
      and oc_selection.player_id = prep.player_id
      and oc_selection.player_character_id = prep.player_character_id
    where prep.match_id = p_match_id
      and prep.player_id = current_player
      and prep.decision <> 'none'
    on conflict do nothing;

    if snapshot_row.boon_definition_id_snapshot is null then
      update public.match_boon_resolutions resolution set
        metadata = jsonb_build_object(
          'targetCount', 0,
          'overallCap', 99,
          'powerCap', 12000,
          'resolvedGroups', '{}'::jsonb,
          'applications', '[]'::jsonb
        )
      where resolution.match_id = p_match_id
        and resolution.player_id = current_player;
      continue;
    end if;

    config := snapshot_row.boon_effect_config_snapshot;

    -- A V2 match snapshot without structured config predates this migration.
    -- Do not read today's live definition or guess from classification fields.
    if jsonb_typeof(config) <> 'object'
      and coalesce(snapshot_row.boon_key_snapshot, '') like 'v2\_%' escape '\' then
      update public.match_boon_resolutions resolution set
        status = 'configuration_error',
        metadata = jsonb_build_object(
          'reason', 'missing_v2_effect_config_snapshot',
          'rolloutSafe', true,
          'targetCount', 0,
          'overallCap', 99,
          'powerCap', 12000,
          'resolvedGroups', '{}'::jsonb,
          'applications', '[]'::jsonb
        )
      where resolution.match_id = p_match_id
        and resolution.player_id = current_player;
      continue;
    end if;

    -- Legacy and Administrator Boons intentionally retain Phase 5 behavior.
    if jsonb_typeof(config) <> 'object' then
      config := case snapshot_row.boon_effect_type_snapshot
        when 'oc_overall' then jsonb_build_object(
          'target', 'selected_oc', 'effect', jsonb_build_object(
            'stat', 'overall', 'mode', 'flat',
            'value', greatest(coalesce(snapshot_row.boon_effect_value_snapshot, 0), 0), 'cap', 99))
        when 'oc_power' then jsonb_build_object(
          'target', 'selected_oc', 'effect', jsonb_build_object(
            'stat', 'power', 'mode', 'flat',
            'value', greatest(coalesce(snapshot_row.boon_effect_value_snapshot, 0), 0), 'cap', 12000))
        when 'random_drafted_overall' then jsonb_build_object(
          'target', 'random_drafted_canon', 'effect', jsonb_build_object(
            'stat', 'overall', 'mode', 'flat',
            'value', greatest(coalesce(snapshot_row.boon_effect_value_snapshot, 0), 0), 'cap', 99))
        when 'lowest_drafted_overall' then jsonb_build_object(
          'target', 'lowest_drafted_canon', 'effect', jsonb_build_object(
            'stat', 'overall', 'mode', 'flat',
            'value', greatest(coalesce(snapshot_row.boon_effect_value_snapshot, 0), 0), 'cap', 99))
        when 'highest_drafted_overall' then jsonb_build_object(
          'target', 'highest_drafted_canon', 'effect', jsonb_build_object(
            'stat', 'overall', 'mode', 'flat',
            'value', greatest(coalesce(snapshot_row.boon_effect_value_snapshot, 0), 0), 'cap', 99))
        when 'multi_lowest_overall' then jsonb_build_object(
          'target', 'three_lowest_drafted_canon', 'effect', jsonb_build_object(
            'stat', 'overall', 'mode', 'flat',
            'value', greatest(coalesce(snapshot_row.boon_effect_value_snapshot, 0), 0), 'cap', 99))
        when 'same_verse_power' then jsonb_build_object(
          'target', 'same_verse_canon_as_selected_oc', 'effect', jsonb_build_object(
            'stat', 'power', 'mode', 'flat',
            'value', greatest(coalesce(snapshot_row.boon_effect_value_snapshot, 0), 0), 'cap', 12000))
        when 'random_overall' then jsonb_build_object(
          'target', 'random_eligible_fighter', 'effect', jsonb_build_object(
            'stat', 'overall', 'mode', 'random_range', 'min', 1,
            'max', greatest(coalesce(snapshot_row.boon_effect_value_snapshot, 0), 0),
            'step', 1, 'cap', 99))
        when 'verse_power' then jsonb_build_object(
          'target', 'random_team_verse_canon', 'effect', jsonb_build_object(
            'stat', 'power', 'mode', 'flat',
            'value', greatest(coalesce(snapshot_row.boon_effect_value_snapshot, 0), 0), 'cap', 12000))
        else null end;
    end if;

    if jsonb_typeof(config) <> 'object' then
      update public.match_boon_resolutions resolution set
        status = 'configuration_error',
        metadata = jsonb_build_object(
          'reason', 'unsupported_legacy_effect_type',
          'targetCount', 0,
          'overallCap', 99,
          'powerCap', 12000,
          'resolvedGroups', '{}'::jsonb,
          'applications', '[]'::jsonb
        )
      where resolution.match_id = p_match_id
        and resolution.player_id = current_player;
      continue;
    end if;

    root_has_target := config ? 'target';
    effect_items := '[]'::jsonb;
    if config ? 'effect' and config ? 'effects' then
      effect_items := null;
    elsif jsonb_typeof(config -> 'effect') = 'object' then
      effect_items := jsonb_build_array(
        jsonb_build_object(
          'target', config -> 'target',
          'condition', config -> 'condition',
          'options', config -> 'options'
        ) || (config -> 'effect')
      );
    elsif jsonb_typeof(config -> 'effects') = 'array' then
      if jsonb_array_length(config -> 'effects') = 0 then
        effect_items := null;
      elsif exists (
        select 1
        from jsonb_array_elements(config -> 'effects') as invalid_effects(invalid_effect)
        where jsonb_typeof(invalid_effect) <> 'object'
      ) then
        effect_items := null;
      else
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'target', coalesce(effect_value -> 'target', config -> 'target'),
            'condition', coalesce(effect_value -> 'condition', config -> 'condition'),
            'options', coalesce(effect_value -> 'options', config -> 'options')
          ) || effect_value
          order by effect_ordinality
        ), '[]'::jsonb)
        into effect_items
        from jsonb_array_elements(config -> 'effects')
          with ordinality as effect_list(effect_value, effect_ordinality);
      end if;
    else
      effect_items := null;
    end if;

    if jsonb_typeof(effect_items) <> 'array' then
      update public.match_boon_resolutions resolution set
        status = 'configuration_error',
        metadata = jsonb_build_object(
          'reason', 'invalid_effect_config_shape',
          'targetCount', 0,
          'overallCap', 99,
          'powerCap', 12000,
          'resolvedGroups', '{}'::jsonb,
          'applications', '[]'::jsonb
        )
      where resolution.match_id = p_match_id
        and resolution.player_id = current_player;
      continue;
    end if;

    effect_index_value := 0;
    applied_count := 0;
    condition_failure_count := 0;
    no_target_count := 0;
    configuration_error_count := 0;
    requested_overall_total := 0;
    requested_power_total := 0;
    first_random_value := null;
    first_resolved_verse := null;
    first_resolved_branch := null;
    used_ids := array[]::uuid[];
    diagnostic_entries := '[]'::jsonb;
    resolved_groups := '{}'::jsonb;

    -- Recover any durable partial result before continuing. Normal execution is
    -- atomic, but this also makes repair/retry workflows deterministic.
    select
      count(*),
      coalesce(sum(application.requested_delta)
        filter (where application.stat = 'overall'), 0),
      coalesce(sum(application.requested_delta)
        filter (where application.stat = 'power'), 0),
      (array_agg(application.resolved_random_value order by application.effect_index,
        application.target_order) filter (where application.resolved_random_value is not null))[1],
      (array_agg(application.resolved_verse_id order by application.effect_index,
        application.target_order) filter (where application.resolved_verse_id is not null))[1],
      (array_agg(application.resolved_branch order by application.effect_index,
        application.target_order) filter (where application.resolved_branch is not null))[1],
      coalesce(array_agg(distinct application.fighter_stat_id), array[]::uuid[])
    into applied_count, requested_overall_total, requested_power_total,
      first_random_value, first_resolved_verse, first_resolved_branch, used_ids
    from public.match_boon_effect_applications application
    where application.match_id = p_match_id
      and application.player_id = current_player;

    select coalesce(jsonb_object_agg(grouped.group_key, grouped.fighter_stat_id), '{}'::jsonb)
      into resolved_groups
    from (
      select distinct on (application.metadata ->> 'group')
        application.metadata ->> 'group' as group_key,
        application.fighter_stat_id::text as fighter_stat_id
      from public.match_boon_effect_applications application
      where application.match_id = p_match_id
        and application.player_id = current_player
        and jsonb_typeof(application.metadata -> 'group') = 'string'
        and nullif(btrim(application.metadata ->> 'group'), '') is not null
      order by application.metadata ->> 'group', application.effect_index,
        application.target_order
    ) grouped;

    for effect_item in select value from jsonb_array_elements(effect_items)
    loop
      target_rule := effect_item ->> 'target';
      condition_config := effect_item -> 'condition';
      group_name := case when jsonb_typeof(effect_item -> 'group') = 'string'
        then nullif(btrim(effect_item ->> 'group'), '') else null end;
      source_group_name := case when jsonb_typeof(effect_item -> 'source_group') = 'string'
        then nullif(btrim(effect_item ->> 'source_group'), '') else null end;
      exclude_group_name := case when jsonb_typeof(effect_item -> 'exclude_group') = 'string'
        then nullif(btrim(effect_item ->> 'exclude_group'), '') else null end;
      -- Preserve V2's legacy per-effect de-duplication, except for deterministic
      -- targets that are explicitly meant to be reused across effects.
      excluded_ids := case when not root_has_target and effect_index_value > 0
          and target_rule not in ('selected_oc', 'same_resolved_target')
        then used_ids else array[]::uuid[] end;

      -- Effects already committed to the private audit table are complete and
      -- must never be recalculated or rerolled.
      if exists (
        select 1 from public.match_boon_effect_applications application
        where application.match_id = p_match_id
          and application.player_id = current_player
          and application.effect_index = effect_index_value
      ) then
        effect_index_value := effect_index_value + 1;
        continue;
      end if;

      if target_rule is null or effect_item ->> 'stat' not in ('overall', 'power')
        or effect_item ->> 'mode' is null then
        configuration_error_count := configuration_error_count + 1;
        diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
          'effectIndex', effect_index_value, 'reason', 'invalid_effect_entry'
        ));
        effect_index_value := effect_index_value + 1;
        continue;
      end if;

      if (effect_item ? 'group' and group_name is null)
        or (effect_item ? 'source_group' and source_group_name is null)
        or (effect_item ? 'exclude_group' and exclude_group_name is null)
        or coalesce(length(group_name), 0) > 64
        or coalesce(length(source_group_name), 0) > 64
        or coalesce(length(exclude_group_name), 0) > 64 then
        configuration_error_count := configuration_error_count + 1;
        diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
          'effectIndex', effect_index_value, 'reason', 'invalid_target_group'
        ));
        effect_index_value := effect_index_value + 1;
        continue;
      end if;

      if exclude_group_name is not null then
        if not (resolved_groups ? exclude_group_name) then
          configuration_error_count := configuration_error_count + 1;
          diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
            'effectIndex', effect_index_value, 'reason', 'unresolved_exclude_group',
            'excludeGroup', exclude_group_name
          ));
          effect_index_value := effect_index_value + 1;
          continue;
        end if;
        grouped_target_id := (resolved_groups ->> exclude_group_name)::uuid;
        excluded_ids := array_append(excluded_ids, grouped_target_id);
      end if;

      if group_name is not null and resolved_groups ? group_name then
        configuration_error_count := configuration_error_count + 1;
        diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
          'effectIndex', effect_index_value, 'reason', 'duplicate_target_group',
          'group', group_name
        ));
        effect_index_value := effect_index_value + 1;
        continue;
      end if;

      if target_rule = 'same_resolved_target' then
        if source_group_name is null or not (resolved_groups ? source_group_name) then
          configuration_error_count := configuration_error_count + 1;
          diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
            'effectIndex', effect_index_value, 'reason', 'unresolved_source_group',
            'sourceGroup', source_group_name
          ));
          effect_index_value := effect_index_value + 1;
          continue;
        end if;
        grouped_target_id := (resolved_groups ->> source_group_name)::uuid;
        if not exists (
          select 1 from public.match_boon_fighter_stats fighter_stat
          where fighter_stat.id = grouped_target_id
            and fighter_stat.match_id = p_match_id
            and fighter_stat.player_id = current_player
            and fighter_stat.eligible_for_battle
        ) then
          configuration_error_count := configuration_error_count + 1;
          diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
            'effectIndex', effect_index_value, 'reason', 'invalid_source_group_target',
            'sourceGroup', source_group_name
          ));
          effect_index_value := effect_index_value + 1;
          continue;
        end if;
        target_result := jsonb_build_object(
          'valid', true,
          'targetIds', case when grouped_target_id = any(excluded_ids)
            then '[]'::jsonb else jsonb_build_array(grouped_target_id) end,
          'branch', 'same_resolved_target'
        );
      else
        target_result := public.resolve_match_boon_targets_v2(
          target_rule, p_match_id, current_player, condition_config,
          effect_item -> 'options', excluded_ids
        );
      end if;
      if coalesce((target_result ->> 'valid')::boolean, false) = false then
        configuration_error_count := configuration_error_count + 1;
        diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
          'effectIndex', effect_index_value,
          'reason', coalesce(target_result ->> 'reason', 'target_resolution_error')
        ));
        effect_index_value := effect_index_value + 1;
        continue;
      end if;

      select coalesce(array_agg(target_value::uuid), array[]::uuid[])
        into target_ids
      from jsonb_array_elements_text(target_result -> 'targetIds') target_value;

      if group_name is not null and coalesce(array_length(target_ids, 1), 0) > 1 then
        configuration_error_count := configuration_error_count + 1;
        diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
          'effectIndex', effect_index_value, 'reason', 'ambiguous_group_target',
          'group', group_name
        ));
        effect_index_value := effect_index_value + 1;
        continue;
      end if;

      -- Matching targets are filtered individually, rather than requiring
      -- every drafted fighter to satisfy the predicate.
      if target_rule = 'drafted_canon_matching' then
        select coalesce(array_agg(candidate_id), array[]::uuid[]) into target_ids
        from unnest(target_ids) candidate_id
        where public.evaluate_match_boon_condition_v2(
          condition_config, p_match_id, current_player, array[candidate_id]
        ) = 'met';
      end if;

      condition_result := public.evaluate_match_boon_condition_v2(
        condition_config, p_match_id, current_player, target_ids
      );
      if condition_result = 'configuration_error' then
        configuration_error_count := configuration_error_count + 1;
        diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
          'effectIndex', effect_index_value, 'reason', 'invalid_condition'
        ));
        effect_index_value := effect_index_value + 1;
        continue;
      elsif condition_result <> 'met' then
        condition_failure_count := condition_failure_count + 1;
        diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
          'effectIndex', effect_index_value, 'reason', 'condition_not_met'
        ));
        effect_index_value := effect_index_value + 1;
        continue;
      elsif coalesce(array_length(target_ids, 1), 0) = 0 then
        no_target_count := no_target_count + 1;
        diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
          'effectIndex', effect_index_value, 'reason', 'no_eligible_target'
        ));
        effect_index_value := effect_index_value + 1;
        continue;
      end if;

      if not root_has_target then
        used_ids := used_ids || target_ids;
      end if;
      if first_resolved_verse is null and target_result ->> 'resolvedVerseId' is not null then
        first_resolved_verse := (target_result ->> 'resolvedVerseId')::bigint;
      end if;
      if first_resolved_branch is null and target_result ->> 'branch' is not null then
        first_resolved_branch := target_result ->> 'branch';
      end if;

      target_order_value := 0;
      foreach target_id in array target_ids
      loop
        select * into target_row
        from public.match_boon_fighter_stats fighter_stat
        where fighter_stat.id = target_id
          and fighter_stat.match_id = p_match_id
          and fighter_stat.player_id = current_player
        for update;

        calculation := public.calculate_match_boon_effect_v2(
          effect_item, p_match_id, current_player, target_id
        );
        if coalesce((calculation ->> 'valid')::boolean, false) = false then
          configuration_error_count := configuration_error_count + 1;
          diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
            'effectIndex', effect_index_value,
            'targetOrder', target_order_value,
            'reason', coalesce(calculation ->> 'reason', 'effect_calculation_error')
          ));
          target_order_value := target_order_value + 1;
          continue;
        end if;

        requested_delta := (calculation ->> 'requestedDelta')::integer;
        if first_random_value is null and calculation ->> 'randomValue' is not null then
          first_random_value := (calculation ->> 'randomValue')::integer;
        end if;

        if effect_item ->> 'stat' = 'overall' then
          value_before := target_row.final_overall;
          configured_floor := greatest(1, coalesce((effect_item ->> 'floor')::integer, 1));
          configured_cap := least(99, coalesce((effect_item ->> 'cap')::integer, 99));
          if configured_floor > configured_cap then
            configuration_error_count := configuration_error_count + 1;
            diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
              'effectIndex', effect_index_value,
              'targetOrder', target_order_value,
              'reason', 'overall_floor_exceeds_cap'
            ));
            target_order_value := target_order_value + 1;
            continue;
          end if;
          value_after := greatest(configured_floor,
            least(configured_cap, value_before + requested_delta));
          applied_delta := value_after - value_before;
          update public.match_boon_fighter_stats fighter_stat set
            boon_targeted = true,
            boon_overall_bonus = fighter_stat.boon_overall_bonus + applied_delta,
            final_overall = value_after
          where fighter_stat.id = target_id;
          requested_overall_total := requested_overall_total + requested_delta;
        else
          value_before := target_row.final_power_score;
          configured_floor := greatest(0, coalesce((effect_item ->> 'floor')::integer, 0));
          configured_cap := least(12000, coalesce((effect_item ->> 'cap')::integer, 12000));
          if configured_floor > configured_cap then
            configuration_error_count := configuration_error_count + 1;
            diagnostic_entries := diagnostic_entries || jsonb_build_array(jsonb_build_object(
              'effectIndex', effect_index_value,
              'targetOrder', target_order_value,
              'reason', 'power_floor_exceeds_cap'
            ));
            target_order_value := target_order_value + 1;
            continue;
          end if;
          value_after := greatest(configured_floor,
            least(configured_cap, value_before + requested_delta));
          applied_delta := value_after - value_before;
          update public.match_boon_fighter_stats fighter_stat set
            boon_targeted = true,
            boon_power_bonus = fighter_stat.boon_power_bonus + applied_delta,
            final_power_score = value_after
          where fighter_stat.id = target_id;
          requested_power_total := requested_power_total + requested_delta;
        end if;

        insert into public.match_boon_effect_applications (
          match_id, player_id, effect_index, target_order, fighter_stat_id,
          target_rule_snapshot, stat, mode, condition_status,
          requested_delta, applied_delta, pre_boon_value,
          value_before_effect, final_value, resolved_random_value,
          resolved_verse_id, resolved_branch, metadata
        ) values (
          p_match_id, current_player, effect_index_value, target_order_value,
          target_id, target_rule, effect_item ->> 'stat', effect_item ->> 'mode',
          'met', requested_delta, applied_delta,
          case when effect_item ->> 'stat' = 'overall'
            then target_row.base_overall + target_row.preparation_overall_bonus
            else target_row.base_power_score + target_row.preparation_power_bonus end,
          value_before, value_after,
          (calculation ->> 'randomValue')::integer,
          (target_result ->> 'resolvedVerseId')::bigint,
          target_result ->> 'branch',
          coalesce(calculation -> 'metadata', '{}'::jsonb)
            || jsonb_strip_nulls(jsonb_build_object(
              'boonDefinitionId', snapshot_row.boon_definition_id_snapshot,
              'boonKey', snapshot_row.boon_key_snapshot,
              'effectIndex', effect_index_value,
              'targetId', target_id,
              'group', group_name,
              'sourceGroup', source_group_name,
              'excludeGroup', exclude_group_name,
              'stat', effect_item ->> 'stat',
              'resolvedValue', value_after,
              'random', target_rule like 'random%'
            ))
        );
        applied_count := applied_count + 1;
        target_order_value := target_order_value + 1;
      end loop;
      if group_name is not null and exists (
        select 1 from public.match_boon_effect_applications application
        where application.match_id = p_match_id
          and application.player_id = current_player
          and application.effect_index = effect_index_value
      ) then
        resolved_groups := jsonb_set(
          resolved_groups,
          array[group_name],
          to_jsonb(target_ids[1]::text),
          true
        );
      end if;
      effect_index_value := effect_index_value + 1;
    end loop;

    select coalesce(jsonb_agg(jsonb_build_object(
      'effectIndex', application.effect_index,
      'targetOrder', application.target_order,
      'fighterStatId', application.fighter_stat_id,
      'targetRule', application.target_rule_snapshot,
      'stat', application.stat,
      'mode', application.mode,
      'requestedDelta', application.requested_delta,
      'appliedDelta', application.applied_delta,
      'finalValue', application.final_value,
      'randomValue', application.resolved_random_value,
      'resolvedVerseId', application.resolved_verse_id,
      'resolvedBranch', application.resolved_branch,
      'metadata', application.metadata
    ) order by application.effect_index, application.target_order), '[]'::jsonb)
      into audit_summary
    from public.match_boon_effect_applications application
    where application.match_id = p_match_id
      and application.player_id = current_player;

    update public.match_boon_resolutions resolution set
      status = case
        when configuration_error_count > 0 then 'configuration_error'
        when applied_count > 0 then 'applied'
        when condition_failure_count > 0 then 'condition_not_met'
        else 'no_eligible_target'
      end,
      requested_overall_value = requested_overall_total,
      requested_power_value = requested_power_total,
      resolved_random_value = first_random_value,
      resolved_verse_id = first_resolved_verse,
      metadata = jsonb_build_object(
        'targetCount', applied_count,
        'conditionFailureCount', condition_failure_count,
        'noTargetCount', no_target_count,
        'configurationErrorCount', configuration_error_count,
        'resolvedBranch', first_resolved_branch,
        'overallCap', 99,
        'overallFloor', 1,
        'powerCap', 12000,
        'powerFloor', 0,
        'resolvedGroups', resolved_groups,
        'diagnostics', diagnostic_entries,
        'applications', audit_summary
      )
    where resolution.match_id = p_match_id
      and resolution.player_id = current_player;
  end loop;
end;
$$;

-- Preserve the canonical Phase 5/Admin transition: resolve the primary Boon,
-- apply the Administrator's structured secondary stat, then stamp the marker.
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
    perform public.apply_match_boon_secondary_stats_internal(new.id);
    new.boon_effects_resolved_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists apply_match_boon_effects_before_battle on public.matches;
create trigger apply_match_boon_effects_before_battle
  before update of status on public.matches
  for each row execute function public.apply_match_boon_effects_before_battle();

-- Allowlisted target resolver. It returns private fighter-stat IDs plus any
-- random verse/branch choice. All ranking uses stable pre-Boon match values.
create or replace function public.resolve_match_boon_targets_v2(
  p_target_rule text,
  p_match_id uuid,
  p_player_id uuid,
  p_condition jsonb default null,
  p_options jsonb default null,
  p_excluded_ids uuid[] default array[]::uuid[]
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  target_ids uuid[] := array[]::uuid[];
  selected_verse bigint;
  selected_branch text;
  candidate_count integer;
  condition_type text := coalesce(p_condition ->> 'type', '');
  target_scoped_condition boolean := condition_type in (
    'target_overall_below', 'target_overall_at_least', 'target_overall_equals',
    'target_power_below', 'target_power_at_least'
  );
  option_count integer;
  nested_result jsonb;
begin
  if p_target_rule is null then
    return jsonb_build_object('valid', false, 'reason', 'missing_target');
  end if;

  if p_target_rule = 'selected_oc' then
    select coalesce(array_agg(candidate.id), array[]::uuid[]) into target_ids
    from (
      select fs.id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'oc' and fs.eligible_for_battle
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
      order by fs.roster_order
      limit 1
    ) candidate;

  elsif p_target_rule in ('lowest_drafted_canon', 'second_lowest_drafted_canon', 'median_drafted_canon', 'highest_drafted_canon') then
    select count(*) into candidate_count
    from public.match_boon_fighter_stats fs
    where fs.match_id = p_match_id and fs.player_id = p_player_id
      and fs.fighter_type = 'canon' and fs.eligible_for_battle
      and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])));
    select coalesce(array_agg(candidate.id), array[]::uuid[]) into target_ids
    from (
      select fs.id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
      order by
        case when p_target_rule = 'highest_drafted_canon'
          then -(fs.base_overall + fs.preparation_overall_bonus)
          else fs.base_overall + fs.preparation_overall_bonus end,
        random()
      offset case p_target_rule
        when 'second_lowest_drafted_canon' then 1
        when 'median_drafted_canon' then greatest((candidate_count - 1) / 2, 0)
        else 0 end
      limit 1
    ) candidate;

  elsif p_target_rule in ('two_highest_drafted_canon', 'two_lowest_drafted_canon', 'three_lowest_drafted_canon') then
    select coalesce(array_agg(candidate.id order by candidate.target_order), array[]::uuid[]) into target_ids
    from (
      select fs.id, row_number() over () as target_order
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
      order by
        case when p_target_rule = 'two_highest_drafted_canon'
          then -(fs.base_overall + fs.preparation_overall_bonus)
          else fs.base_overall + fs.preparation_overall_bonus end,
        random()
      limit case when p_target_rule = 'three_lowest_drafted_canon' then 3 else 2 end
    ) candidate;

  elsif p_target_rule in (
    'lowest_power_drafted_canon', 'median_power_drafted_canon',
    'highest_power_drafted_canon'
  ) then
    select count(*) into candidate_count
    from public.match_boon_fighter_stats fs
    where fs.match_id = p_match_id and fs.player_id = p_player_id
      and fs.fighter_type = 'canon' and fs.eligible_for_battle
      and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])));
    select coalesce(array_agg(candidate.id), array[]::uuid[]) into target_ids
    from (
      select fs.id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
      order by
        case when p_target_rule = 'highest_power_drafted_canon'
          then -(fs.base_power_score + fs.preparation_power_bonus)
          else fs.base_power_score + fs.preparation_power_bonus end,
        random()
      offset case when p_target_rule = 'median_power_drafted_canon'
        then greatest((candidate_count - 1) / 2, 0) else 0 end
      limit 1
    ) candidate;

  elsif p_target_rule in ('two_lowest_power_drafted_canon', 'three_lowest_power_drafted_canon') then
    select coalesce(array_agg(candidate.id order by candidate.target_order), array[]::uuid[]) into target_ids
    from (
      select fs.id, row_number() over () as target_order
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
      order by fs.base_power_score + fs.preparation_power_bonus, random()
      limit case when p_target_rule = 'three_lowest_power_drafted_canon' then 3 else 2 end
    ) candidate;

  elsif p_target_rule in ('all_drafted_canon', 'drafted_canon_matching') then
    select coalesce(array_agg(fs.id order by fs.roster_order), array[]::uuid[]) into target_ids
    from public.match_boon_fighter_stats fs
    where fs.match_id = p_match_id and fs.player_id = p_player_id
      and fs.fighter_type = 'canon' and fs.eligible_for_battle
      and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])));

  elsif p_target_rule in (
    'random_drafted_canon', 'random_other_drafted_canon',
    'random_eligible_fighter', 'random_other_eligible_fighter'
  ) then
    select coalesce(array_agg(candidate.id), array[]::uuid[]) into target_ids
    from (
      select fs.id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.eligible_for_battle
        and (p_target_rule in ('random_eligible_fighter', 'random_other_eligible_fighter')
          or fs.fighter_type = 'canon')
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
        and (not target_scoped_condition or public.evaluate_match_boon_condition_v2(
          p_condition, p_match_id, p_player_id, array[fs.id]
        ) = 'met')
      order by random()
      limit 1
    ) candidate;

  elsif p_target_rule = 'two_random_drafted_canon' then
    select coalesce(array_agg(candidate.id), array[]::uuid[]) into target_ids
    from (
      select fs.id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
      order by random()
      limit 2
    ) candidate;

  elsif p_target_rule in ('same_verse_canon', 'same_verse_canon_as_selected_oc') then
    select oc_selection.verse_id into selected_verse
    from public.match_oc_selections oc_selection
    where oc_selection.match_id = p_match_id
      and oc_selection.player_id = p_player_id
      and oc_selection.player_character_id is not null;
    select coalesce(array_agg(fs.id order by fs.roster_order), array[]::uuid[]) into target_ids
    from public.match_boon_fighter_stats fs
    where fs.match_id = p_match_id and fs.player_id = p_player_id
      and fs.fighter_type = 'canon' and fs.eligible_for_battle
      and fs.verse_id_snapshot = selected_verse
      and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])));

  elsif p_target_rule in ('canon_different_verse_from_selected_oc', 'random_canon_different_verse_from_selected_oc') then
    select oc_selection.verse_id into selected_verse
    from public.match_oc_selections oc_selection
    where oc_selection.match_id = p_match_id
      and oc_selection.player_id = p_player_id
      and oc_selection.player_character_id is not null;
    select coalesce(array_agg(candidate.id), array[]::uuid[]) into target_ids
    from (
      select fs.id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and fs.verse_id_snapshot <> selected_verse
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
      order by case when p_target_rule = 'random_canon_different_verse_from_selected_oc'
        then random() else fs.roster_order::double precision end
      limit case when p_target_rule = 'random_canon_different_verse_from_selected_oc'
        then 1 else 2147483647 end
    ) candidate;

  elsif p_target_rule in (
    'lowest_same_verse_canon_as_selected_oc',
    'highest_canon_different_verse_from_selected_oc'
  ) then
    select oc_selection.verse_id into selected_verse
    from public.match_oc_selections oc_selection
    where oc_selection.match_id = p_match_id
      and oc_selection.player_id = p_player_id
      and oc_selection.player_character_id is not null;
    select coalesce(array_agg(candidate.id), array[]::uuid[]) into target_ids
    from (
      select fs.id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and ((p_target_rule = 'lowest_same_verse_canon_as_selected_oc' and fs.verse_id_snapshot = selected_verse)
          or (p_target_rule = 'highest_canon_different_verse_from_selected_oc' and fs.verse_id_snapshot <> selected_verse))
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
      order by case when p_target_rule = 'highest_canon_different_verse_from_selected_oc'
        then -(fs.base_overall + fs.preparation_overall_bonus)
        else fs.base_overall + fs.preparation_overall_bonus end, random()
      limit 1
    ) candidate;

  elsif p_target_rule = 'random_singleton_verse_canon' then
    select groups.verse_id_snapshot into selected_verse
    from (
      select fs.verse_id_snapshot
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
      group by fs.verse_id_snapshot having count(*) = 1
    ) groups order by random() limit 1;
    select coalesce(array_agg(fs.id), array[]::uuid[]) into target_ids
    from public.match_boon_fighter_stats fs
    where fs.match_id = p_match_id and fs.player_id = p_player_id
      and fs.fighter_type = 'canon' and fs.eligible_for_battle
      and fs.verse_id_snapshot = selected_verse
      and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])));

  elsif p_target_rule in ('exactly_two_same_verse_canon', 'random_same_verse_pair_canon') then
    select groups.verse_id_snapshot into selected_verse
    from (
      select fs.verse_id_snapshot
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
      group by fs.verse_id_snapshot
      having (p_target_rule = 'exactly_two_same_verse_canon' and count(*) = 2)
        or (p_target_rule = 'random_same_verse_pair_canon' and count(*) >= 2)
    ) groups order by random() limit 1;
    select coalesce(array_agg(candidate.id), array[]::uuid[]) into target_ids
    from (
      select fs.id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and fs.verse_id_snapshot = selected_verse
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
      order by case when p_target_rule = 'random_same_verse_pair_canon'
        then random() else fs.roster_order::double precision end
      limit 2
    ) candidate;

  elsif p_target_rule in ('most_represented_verse_canon', 'highest_ovr_in_most_represented_verse') then
    select groups.verse_id_snapshot into selected_verse
    from (
      select fs.verse_id_snapshot, count(*) as group_count
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
      group by fs.verse_id_snapshot
    ) groups order by groups.group_count desc, random() limit 1;
    select coalesce(array_agg(candidate.id), array[]::uuid[]) into target_ids
    from (
      select fs.id
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and fs.verse_id_snapshot = selected_verse
        and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])))
      order by case when p_target_rule = 'highest_ovr_in_most_represented_verse'
        then -(fs.base_overall + fs.preparation_overall_bonus)
        else fs.roster_order end, random()
      limit case when p_target_rule = 'highest_ovr_in_most_represented_verse'
        then 1 else 2147483647 end
    ) candidate;

  elsif p_target_rule = 'random_team_verse_canon' then
    select candidate.verse_id_snapshot into selected_verse
    from (
      select distinct fs.verse_id_snapshot
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
    ) candidate
    order by random()
    limit 1;
    select coalesce(array_agg(fs.id order by fs.roster_order), array[]::uuid[]) into target_ids
    from public.match_boon_fighter_stats fs
    where fs.match_id = p_match_id and fs.player_id = p_player_id
      and fs.fighter_type = 'canon' and fs.eligible_for_battle
      and fs.verse_id_snapshot = selected_verse
      and not (fs.id = any(coalesce(p_excluded_ids, array[]::uuid[])));

  elsif p_target_rule = 'random_choice_between' then
    if jsonb_typeof(p_options) <> 'array' then
      return jsonb_build_object('valid', false, 'reason', 'invalid_options');
    end if;
    option_count := jsonb_array_length(p_options);
    if option_count < 1 then return jsonb_build_object('valid', false, 'reason', 'empty_options'); end if;
    selected_branch := p_options ->> floor(random() * option_count)::integer;
    nested_result := public.resolve_match_boon_targets_v2(
      selected_branch, p_match_id, p_player_id, p_condition, null, p_excluded_ids
    );
    return nested_result || jsonb_build_object('branch', selected_branch);

  else
    return jsonb_build_object('valid', false, 'reason', 'unsupported_target_rule');
  end if;

  return jsonb_build_object(
    'valid', true,
    'targetIds', to_jsonb(target_ids),
    'resolvedVerseId', selected_verse,
    'branch', selected_branch
  );
exception when others then
  return jsonb_build_object('valid', false, 'reason', 'target_resolution_error');
end;
$$;

-- Capture the queue commitment. Pre-deployment waiting queue rows may lack the
-- config property; in that narrow rollout case the config is copied once from
-- the referenced definition at match creation and is immutable thereafter.
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
  player_one_config jsonb;
  player_two_config jsonb;
begin
  select q.boon_snapshot, true into player_one_snapshot, queue_snapshot_found
  from public.matchmaking_queue q
  where q.player_id = new.player_one_id and q.status = 'waiting'
    and q.boon_snapshot_locked_at is not null;
  if coalesce(queue_snapshot_found, false) = false then
    player_one_snapshot := public.build_player_boon_snapshot_internal(new.player_one_id);
  end if;

  queue_snapshot_found := false;
  select q.boon_snapshot, true into player_two_snapshot, queue_snapshot_found
  from public.matchmaking_queue q
  where q.player_id = new.player_two_id and q.status = 'waiting'
    and q.boon_snapshot_locked_at is not null;
  if coalesce(queue_snapshot_found, false) = false then
    player_two_snapshot := public.build_player_boon_snapshot_internal(new.player_two_id);
  end if;

  player_one_config := case
    when jsonb_typeof(player_one_snapshot -> 'effectConfig') = 'object'
      then player_one_snapshot -> 'effectConfig'
    else (select d.effect_config from public.boon_definitions d
      where d.id = (player_one_snapshot ->> 'definitionId')::uuid)
  end;
  player_two_config := case
    when jsonb_typeof(player_two_snapshot -> 'effectConfig') = 'object'
      then player_two_snapshot -> 'effectConfig'
    else (select d.effect_config from public.boon_definitions d
      where d.id = (player_two_snapshot ->> 'definitionId')::uuid)
  end;

  insert into public.match_boon_snapshots (
    match_id, player_id, player_boon_id_snapshot, boon_definition_id_snapshot,
    boon_key_snapshot, boon_name_snapshot, boon_description_snapshot,
    boon_rarity_snapshot, boon_effect_type_snapshot, boon_effect_value_snapshot,
    boon_target_rule_snapshot, boon_system_only_snapshot,
    boon_overall_effect_value_snapshot, boon_power_effect_value_snapshot,
    boon_effect_config_snapshot
  ) values
  (
    new.id, new.player_one_id,
    (player_one_snapshot ->> 'playerBoonId')::uuid,
    (player_one_snapshot ->> 'definitionId')::uuid,
    player_one_snapshot ->> 'key', player_one_snapshot ->> 'name',
    player_one_snapshot ->> 'description', player_one_snapshot ->> 'rarity',
    player_one_snapshot ->> 'effectType',
    (player_one_snapshot ->> 'effectValue')::integer,
    player_one_snapshot ->> 'targetRule',
    coalesce((player_one_snapshot ->> 'systemOnly')::boolean, false),
    (player_one_snapshot ->> 'overallEffectValue')::integer,
    (player_one_snapshot ->> 'powerEffectValue')::integer,
    player_one_config
  ),
  (
    new.id, new.player_two_id,
    (player_two_snapshot ->> 'playerBoonId')::uuid,
    (player_two_snapshot ->> 'definitionId')::uuid,
    player_two_snapshot ->> 'key', player_two_snapshot ->> 'name',
    player_two_snapshot ->> 'description', player_two_snapshot ->> 'rarity',
    player_two_snapshot ->> 'effectType',
    (player_two_snapshot ->> 'effectValue')::integer,
    player_two_snapshot ->> 'targetRule',
    coalesce((player_two_snapshot ->> 'systemOnly')::boolean, false),
    (player_two_snapshot ->> 'overallEffectValue')::integer,
    (player_two_snapshot ->> 'powerEffectValue')::integer,
    player_two_config
  )
  on conflict (match_id, player_id) do nothing;
  return new;
end;
$$;

-- Strict condition evaluator. It returns a state rather than raising on bad
-- JSON so one malformed Boon cannot block the match transition.
create or replace function public.evaluate_match_boon_condition_v2(
  p_condition jsonb,
  p_match_id uuid,
  p_player_id uuid,
  p_target_ids uuid[] default array[]::uuid[]
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  condition_type text;
  expected_value numeric;
  expected_count integer;
  child jsonb;
  child_result text;
  comparison_result boolean;
  actual_count integer;
  minimum_value numeric;
  maximum_value numeric;
begin
  if p_condition is null or jsonb_typeof(p_condition) = 'null' then return 'met'; end if;
  if jsonb_typeof(p_condition) <> 'object' then return 'configuration_error'; end if;
  condition_type := p_condition ->> 'type';
  if condition_type is null then return 'configuration_error'; end if;

  if condition_type = 'all' then
    if jsonb_typeof(p_condition -> 'rules') <> 'array' then
      return 'configuration_error';
    end if;
    if jsonb_array_length(p_condition -> 'rules') = 0 then
      return 'configuration_error';
    end if;
    for child in select value from jsonb_array_elements(p_condition -> 'rules')
    loop
      child_result := public.evaluate_match_boon_condition_v2(
        child, p_match_id, p_player_id, p_target_ids
      );
      if child_result = 'configuration_error' then return child_result; end if;
      if child_result <> 'met' then return 'not_met'; end if;
    end loop;
    return 'met';
  end if;

  if condition_type = 'playable_oc' then
    return case when exists (
      select 1 from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'oc' and fs.eligible_for_battle
    ) then 'met' else 'not_met' end;
  end if;

  if condition_type in ('oc_type', 'selected_oc_type') then
    if p_condition ->> 'value' not in ('champion', 'sacrificial') then
      return 'configuration_error';
    end if;
    return case when exists (
      select 1 from public.match_oc_preparations prep
      where prep.match_id = p_match_id and prep.player_id = p_player_id
        and prep.oc_type = p_condition ->> 'value'
    ) then 'met' else 'not_met' end;
  end if;

  if condition_type in (
    'target_overall_below', 'target_overall_at_least', 'target_overall_equals',
    'target_power_below', 'target_power_at_least'
  ) then
    if not (p_condition ? 'value') or coalesce(array_length(p_target_ids, 1), 0) = 0 then
      return case when p_condition ? 'value' then 'not_met' else 'configuration_error' end;
    end if;
    expected_value := (p_condition ->> 'value')::numeric;
    select bool_and(case condition_type
      when 'target_overall_below' then fs.base_overall + fs.preparation_overall_bonus < expected_value
      when 'target_overall_at_least' then fs.base_overall + fs.preparation_overall_bonus >= expected_value
      when 'target_overall_equals' then fs.base_overall + fs.preparation_overall_bonus = expected_value
      when 'target_power_below' then fs.base_power_score + fs.preparation_power_bonus < expected_value
      when 'target_power_at_least' then fs.base_power_score + fs.preparation_power_bonus >= expected_value
      else false end)
      into comparison_result
    from public.match_boon_fighter_stats fs
    where fs.id = any(p_target_ids)
      and fs.match_id = p_match_id and fs.player_id = p_player_id;
    return case when coalesce(comparison_result, false) then 'met' else 'not_met' end;
  end if;

  if condition_type = 'group_size_at_least' then
    if not (p_condition ? 'value') then return 'configuration_error'; end if;
    return case when coalesce(array_length(p_target_ids, 1), 0) >= (p_condition ->> 'value')::integer
      then 'met' else 'not_met' end;
  end if;

  if condition_type in ('unique_verse_count_at_least', 'unique_verse_count_equals') then
    if not (p_condition ? 'value') then return 'configuration_error'; end if;
    select count(distinct fs.verse_id_snapshot) into actual_count
    from public.match_boon_fighter_stats fs
    where fs.match_id = p_match_id and fs.player_id = p_player_id
      and fs.fighter_type = 'canon' and fs.eligible_for_battle;
    if condition_type = 'unique_verse_count_at_least' then
      return case when actual_count >= (p_condition ->> 'value')::integer then 'met' else 'not_met' end;
    end if;
    return case when actual_count = (p_condition ->> 'value')::integer then 'met' else 'not_met' end;
  end if;

  if condition_type in (
    'roster_overall_gap_at_least', 'roster_overall_gap_at_most',
    'roster_power_gap_at_least', 'roster_power_gap_at_most'
  ) then
    if not (p_condition ? 'value') then return 'configuration_error'; end if;
    if condition_type like 'roster_overall%' then
      select min(fs.base_overall + fs.preparation_overall_bonus),
        max(fs.base_overall + fs.preparation_overall_bonus)
        into minimum_value, maximum_value
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle;
    else
      select min(fs.base_power_score + fs.preparation_power_bonus),
        max(fs.base_power_score + fs.preparation_power_bonus)
        into minimum_value, maximum_value
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle;
    end if;
    if minimum_value is null then return 'not_met'; end if;
    if condition_type like '%_at_least' then
      return case when maximum_value - minimum_value >= (p_condition ->> 'value')::numeric then 'met' else 'not_met' end;
    end if;
    return case when maximum_value - minimum_value <= (p_condition ->> 'value')::numeric then 'met' else 'not_met' end;
  end if;

  if condition_type = 'roster_has_no_overall' then
    if not (p_condition ? 'value') then return 'configuration_error'; end if;
    return case when not exists (
      select 1 from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle
        and fs.base_overall + fs.preparation_overall_bonus = (p_condition ->> 'value')::integer
    ) then 'met' else 'not_met' end;
  end if;

  if condition_type = 'roster_count_overall_equals' then
    if not (p_condition ? 'overall') or not (p_condition ? 'count') then
      return 'configuration_error';
    end if;
    select count(*) into actual_count
    from public.match_boon_fighter_stats fs
    where fs.match_id = p_match_id and fs.player_id = p_player_id
      and fs.fighter_type = 'canon' and fs.eligible_for_battle
      and fs.base_overall + fs.preparation_overall_bonus = (p_condition ->> 'overall')::integer;
    return case when actual_count = (p_condition ->> 'count')::integer then 'met' else 'not_met' end;
  end if;

  if condition_type = 'roster_average_overall_below' then
    if not (p_condition ? 'value') then return 'configuration_error'; end if;
    select avg(fs.base_overall + fs.preparation_overall_bonus) into minimum_value
    from public.match_boon_fighter_stats fs
    where fs.match_id = p_match_id and fs.player_id = p_player_id
      and fs.fighter_type = 'canon' and fs.eligible_for_battle;
    return case when minimum_value is not null
      and minimum_value < (p_condition ->> 'value')::numeric then 'met' else 'not_met' end;
  end if;

  return 'configuration_error';
exception when others then
  return 'configuration_error';
end;
$$;

-- Pure effect calculator. It reads only stable base + OC Preparation values;
-- earlier effects from the same Boon never influence targeting or scaling.
create or replace function public.calculate_match_boon_effect_v2(
  p_effect jsonb,
  p_match_id uuid,
  p_player_id uuid,
  p_fighter_stat_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  effect_stat text;
  effect_mode text;
  round_mode text;
  target_overall numeric;
  target_power numeric;
  reference_value numeric;
  highest_value numeric;
  gap_value numeric;
  delta_value numeric;
  tier jsonb;
  matching_tier_count integer := 0;
  random_value integer;
  minimum_random integer;
  maximum_random integer;
  random_step integer;
  random_slots integer;
  metadata_value jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(p_effect) <> 'object' then
    return jsonb_build_object('valid', false, 'reason', 'effect_must_be_object');
  end if;

  effect_stat := p_effect ->> 'stat';
  effect_mode := p_effect ->> 'mode';
  if effect_stat not in ('overall', 'power') then
    return jsonb_build_object('valid', false, 'reason', 'unsupported_stat');
  end if;
  if effect_mode not in (
    'flat', 'percent', 'tiered', 'tiered_by_overall', 'tiered_by_power',
    'gap_steps', 'gap_to_highest', 'gap_percent_to_highest',
    'gap_percent_to_roster_highest_power', 'gap_to_roster_highest',
    'random_range', 'floor_to_value'
  ) then
    return jsonb_build_object('valid', false, 'reason', 'unsupported_mode');
  end if;
  -- Validate common numeric guardrails here so malformed JSON is converted to
  -- a configuration result rather than escaping into the match transaction.
  if p_effect ? 'cap' then perform (p_effect ->> 'cap')::integer; end if;
  if p_effect ? 'floor' then perform (p_effect ->> 'floor')::integer; end if;
  if p_effect ? 'cap_bonus' then perform (p_effect ->> 'cap_bonus')::numeric; end if;
  if p_effect ? 'min_bonus' then perform (p_effect ->> 'min_bonus')::numeric; end if;
  if p_effect ? 'max_bonus' then perform (p_effect ->> 'max_bonus')::numeric; end if;

  select
    fs.base_overall + fs.preparation_overall_bonus,
    fs.base_power_score + fs.preparation_power_bonus
    into target_overall, target_power
  from public.match_boon_fighter_stats fs
  where fs.id = p_fighter_stat_id
    and fs.match_id = p_match_id
    and fs.player_id = p_player_id
    and fs.eligible_for_battle;
  if not found then
    return jsonb_build_object('valid', false, 'reason', 'target_unavailable');
  end if;

  if effect_mode = 'flat' then
    if not (p_effect ? 'value') then
      return jsonb_build_object('valid', false, 'reason', 'missing_value');
    end if;
    delta_value := (p_effect ->> 'value')::numeric;

  elsif effect_mode = 'percent' then
    if effect_stat <> 'power' or not (p_effect ? 'percent') then
      return jsonb_build_object('valid', false, 'reason', 'invalid_percent_effect');
    end if;
    round_mode := coalesce(p_effect ->> 'round', 'floor');
    if round_mode <> 'floor' then
      return jsonb_build_object('valid', false, 'reason', 'unsupported_rounding');
    end if;
    reference_value := target_power;
    delta_value := floor(reference_value * (p_effect ->> 'percent')::numeric / 100);
    metadata_value := jsonb_build_object(
      'referencePower', reference_value,
      'percent', (p_effect ->> 'percent')::numeric
    );

  elsif effect_mode in ('tiered', 'tiered_by_overall', 'tiered_by_power') then
    if jsonb_typeof(p_effect -> 'tiers') <> 'array' then
      return jsonb_build_object('valid', false, 'reason', 'invalid_tiers');
    end if;
    if jsonb_array_length(p_effect -> 'tiers') = 0 then
      return jsonb_build_object('valid', false, 'reason', 'invalid_tiers');
    end if;
    reference_value := case when effect_mode = 'tiered_by_power'
      then target_power else target_overall end;
    for tier in select value from jsonb_array_elements(p_effect -> 'tiers')
    loop
      if jsonb_typeof(tier) <> 'object' or not (tier ? 'value')
        or (not (tier ? 'min') and not (tier ? 'max')) then
        return jsonb_build_object('valid', false, 'reason', 'malformed_tier');
      end if;
      if (not (tier ? 'min') or reference_value >= (tier ->> 'min')::numeric)
        and (not (tier ? 'max') or reference_value <= (tier ->> 'max')::numeric) then
        matching_tier_count := matching_tier_count + 1;
        delta_value := (tier ->> 'value')::numeric;
      end if;
    end loop;
    if matching_tier_count <> 1 then
      return jsonb_build_object(
        'valid', false,
        'reason', case when matching_tier_count = 0 then 'tier_not_found' else 'overlapping_tiers' end
      );
    end if;
    metadata_value := jsonb_build_object('tierReference', reference_value);

  elsif effect_mode = 'gap_steps' then
    if not (p_effect ? 'reference') or not (p_effect ? 'step')
      or not (p_effect ? 'per_step') or (p_effect ->> 'step')::numeric <= 0 then
      return jsonb_build_object('valid', false, 'reason', 'invalid_gap_steps');
    end if;
    reference_value := case coalesce(p_effect ->> 'reference_stat', effect_stat)
      when 'overall' then target_overall
      when 'power' then target_power
      else null end;
    if reference_value is null then
      return jsonb_build_object('valid', false, 'reason', 'invalid_reference_stat');
    end if;
    gap_value := greatest(0, (p_effect ->> 'reference')::numeric - reference_value);
    delta_value := floor(gap_value / (p_effect ->> 'step')::numeric)
      * (p_effect ->> 'per_step')::numeric;
    metadata_value := jsonb_build_object(
      'referenceValue', reference_value,
      'configuredReference', (p_effect ->> 'reference')::numeric,
      'gap', gap_value
    );

  elsif effect_mode in ('gap_to_highest', 'gap_percent_to_highest') then
    round_mode := coalesce(p_effect ->> 'round', 'floor');
    if round_mode <> 'floor' then
      return jsonb_build_object('valid', false, 'reason', 'unsupported_rounding');
    end if;
    if effect_mode = 'gap_to_highest' then
      select max(fs.base_overall + fs.preparation_overall_bonus) into highest_value
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle;
      reference_value := target_overall;
      if not (p_effect ? 'divisor') or (p_effect ->> 'divisor')::numeric <= 0 then
        return jsonb_build_object('valid', false, 'reason', 'invalid_divisor');
      end if;
      delta_value := floor(greatest(0, highest_value - reference_value)
        / (p_effect ->> 'divisor')::numeric);
    else
      select max(fs.base_power_score + fs.preparation_power_bonus) into highest_value
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle;
      reference_value := target_power;
      if not (p_effect ? 'percent') then
        return jsonb_build_object('valid', false, 'reason', 'missing_percent');
      end if;
      delta_value := floor(greatest(0, highest_value - reference_value)
        * (p_effect ->> 'percent')::numeric / 100);
    end if;
    metadata_value := jsonb_build_object(
      'targetReference', reference_value,
      'highestRosterValue', highest_value,
      'gap', greatest(0, highest_value - reference_value)
    );

  elsif effect_mode in ('gap_to_roster_highest', 'gap_percent_to_roster_highest_power') then
    round_mode := coalesce(p_effect ->> 'round', 'floor');
    if round_mode <> 'floor' then
      return jsonb_build_object('valid', false, 'reason', 'unsupported_rounding');
    end if;
    if effect_mode = 'gap_to_roster_highest' then
      select max(fs.base_overall + fs.preparation_overall_bonus) into highest_value
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle;
      reference_value := target_overall;
      if not (p_effect ? 'divisor') or (p_effect ->> 'divisor')::numeric <= 0 then
        return jsonb_build_object('valid', false, 'reason', 'invalid_divisor');
      end if;
      delta_value := floor(greatest(0, highest_value - reference_value)
        / (p_effect ->> 'divisor')::numeric);
    else
      select max(fs.base_power_score + fs.preparation_power_bonus) into highest_value
      from public.match_boon_fighter_stats fs
      where fs.match_id = p_match_id and fs.player_id = p_player_id
        and fs.fighter_type = 'canon' and fs.eligible_for_battle;
      reference_value := target_power;
      if not (p_effect ? 'percent') then
        return jsonb_build_object('valid', false, 'reason', 'missing_percent');
      end if;
      delta_value := floor(greatest(0, highest_value - reference_value)
        * (p_effect ->> 'percent')::numeric / 100);
    end if;
    metadata_value := jsonb_build_object(
      'ocReference', reference_value,
      'highestDraftedCanonValue', highest_value,
      'gap', greatest(0, highest_value - reference_value)
    );

  elsif effect_mode = 'random_range' then
    if not (p_effect ? 'min') or not (p_effect ? 'max') then
      return jsonb_build_object('valid', false, 'reason', 'invalid_random_range');
    end if;
    minimum_random := (p_effect ->> 'min')::integer;
    maximum_random := (p_effect ->> 'max')::integer;
    random_step := coalesce((p_effect ->> 'step')::integer, 1);
    if maximum_random < minimum_random or random_step <= 0 then
      return jsonb_build_object('valid', false, 'reason', 'invalid_random_range');
    end if;
    random_slots := floor((maximum_random - minimum_random)::numeric / random_step)::integer + 1;
    random_value := minimum_random + floor(random() * random_slots)::integer * random_step;
    delta_value := random_value;
    metadata_value := jsonb_build_object(
      'randomMin', minimum_random,
      'randomMax', maximum_random,
      'randomStep', random_step
    );

  elsif effect_mode = 'floor_to_value' then
    if not (p_effect ? 'value') then
      return jsonb_build_object('valid', false, 'reason', 'missing_floor_value');
    end if;
    reference_value := case effect_stat when 'overall' then target_overall else target_power end;
    delta_value := greatest(0, (p_effect ->> 'value')::numeric - reference_value);
    metadata_value := jsonb_build_object(
      'referenceValue', reference_value,
      'floorTarget', (p_effect ->> 'value')::numeric
    );
  end if;

  if highest_value is null and effect_mode like 'gap%highest%' then
    return jsonb_build_object('valid', false, 'reason', 'missing_roster_reference');
  end if;
  if p_effect ? 'min_bonus' then
    delta_value := greatest(delta_value, (p_effect ->> 'min_bonus')::numeric);
  end if;
  if p_effect ? 'max_bonus' then
    delta_value := least(delta_value, (p_effect ->> 'max_bonus')::numeric);
  end if;
  if p_effect ? 'cap_bonus' then
    delta_value := case when delta_value >= 0
      then least(delta_value, (p_effect ->> 'cap_bonus')::numeric)
      else greatest(delta_value, -(p_effect ->> 'cap_bonus')::numeric) end;
  end if;

  return jsonb_build_object(
    'valid', true,
    'requestedDelta', delta_value::integer,
    'randomValue', random_value,
    'metadata', metadata_value || jsonb_build_object(
      'preBoonOverall', target_overall,
      'preBoonPower', target_power
    )
  );
exception when others then
  return jsonb_build_object('valid', false, 'reason', 'effect_calculation_error');
end;
$$;

-- All V2 helpers and audit tables remain private. Browser clients receive only
-- the existing perspective-safe battle-state projection.
revoke all on function public.build_player_boon_snapshot_internal(uuid)
  from public, anon, authenticated;
revoke all on function public.capture_match_boon_snapshots()
  from public, anon, authenticated;
revoke all on function public.evaluate_match_boon_condition_v2(jsonb, uuid, uuid, uuid[])
  from public, anon, authenticated;
revoke all on function public.resolve_match_boon_targets_v2(text, uuid, uuid, jsonb, jsonb, uuid[])
  from public, anon, authenticated;
revoke all on function public.calculate_match_boon_effect_v2(jsonb, uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.resolve_match_boon_effects_internal(uuid)
  from public, anon, authenticated;
revoke all on function public.apply_match_boon_effects_before_battle()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
