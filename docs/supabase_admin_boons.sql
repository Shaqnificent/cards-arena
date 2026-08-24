-- Anime Arena Administrator-only Boons.
-- Run after docs/supabase_boon_phase_5.sql and the current Administrator migration.
-- New matches only: historical and already-created match snapshots are untouched.

-- 1. Explicit availability and structured multi-stat values. effect_value stays
-- intact for every existing Boon and remains the primary value used by Phase 5.
alter table public.boon_definitions
  add column if not exists system_only boolean not null default false,
  add column if not exists overall_effect_value integer,
  add column if not exists power_effect_value integer;

alter table public.boon_definitions
  drop constraint if exists boon_definitions_overall_effect_value_check,
  drop constraint if exists boon_definitions_power_effect_value_check;
alter table public.boon_definitions
  add constraint boon_definitions_overall_effect_value_check
    check (overall_effect_value is null or overall_effect_value > 0),
  add constraint boon_definitions_power_effect_value_check
    check (power_effect_value is null or power_effect_value > 0);

-- Match rows retain both structured values independently of future balancing.
alter table public.match_boon_snapshots
  add column if not exists boon_system_only_snapshot boolean not null default false,
  add column if not exists boon_overall_effect_value_snapshot integer,
  add column if not exists boon_power_effect_value_snapshot integer;

alter table public.match_boon_resolutions
  add column if not exists requested_overall_value integer,
  add column if not exists requested_power_value integer;

-- 2. The controlled system pool. roll_weight remains valid for the legacy
-- table constraint but is never consulted by the player roll RPC.
insert into public.boon_definitions (
  key, name, description, rarity, effect_type, effect_value, target_rule,
  active, roll_weight, system_only, overall_effect_value, power_effect_value
)
values
  (
    'admin_sovereign_ascension',
    'Sovereign Ascension',
    'The Administrator''s selected OC ascends beyond its normal limits, gaining +4 OVR for this match.',
    'legendary',
    'oc_overall',
    4,
    'selected_oc',
    true,
    1,
    true,
    4,
    null
  ),
  (
    'admin_apex_overdrive',
    'Apex Overdrive',
    'The Administrator''s selected OC enters overdrive, gaining +2 OVR and +1,000 Global Power for this match.',
    'legendary',
    'oc_overall',
    2,
    'selected_oc',
    true,
    1,
    true,
    2,
    1000
  )
on conflict (key) do update set
  name = excluded.name,
  description = excluded.description,
  rarity = excluded.rarity,
  effect_type = excluded.effect_type,
  effect_value = excluded.effect_value,
  target_rule = excluded.target_rule,
  active = excluded.active,
  roll_weight = excluded.roll_weight,
  system_only = excluded.system_only,
  overall_effect_value = excluded.overall_effect_value,
  power_effect_value = excluded.power_effect_value,
  updated_at = now();

-- 3. Defense in depth: authenticated catalogue reads and all acquisition paths
-- exclude system definitions. Direct table mutation remains revoked.
drop policy if exists "Authenticated users can read active Boon definitions"
  on public.boon_definitions;
create policy "Authenticated users can read active Boon definitions"
  on public.boon_definitions for select to authenticated
  using (active = true and system_only = false);

create or replace function public.get_boon_catalogue()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id,
    'key', d.key,
    'name', d.name,
    'description', d.description,
    'rarity', d.rarity,
    'effectType', d.effect_type,
    'effectValue', d.effect_value,
    'targetRule', d.target_rule
  ) order by
    case d.rarity when 'legendary' then 1 when 'epic' then 2 when 'rare' then 3 else 4 end,
    d.name), '[]'::jsonb)
  from public.boon_definitions d
  where d.active = true and d.system_only = false;
$$;

create or replace function public.enforce_player_boon_inventory_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  owned_count integer;
  profile_is_guest boolean;
  profile_is_system boolean;
begin
  select p.is_guest, p.is_system_player
    into profile_is_guest, profile_is_system
  from public.profiles p
  where p.id = new.owner_id
  for update;

  if not found then
    raise exception using errcode = '23503', message = 'Player profile not found.';
  end if;
  if profile_is_guest then
    raise exception using errcode = '42501', message = 'Guests cannot own Boons.';
  end if;
  if profile_is_system then
    raise exception using errcode = '42501', message = 'System profiles cannot own Boons.';
  end if;
  if not exists (
    select 1 from public.boon_definitions d
    where d.id = new.boon_definition_id
      and d.active = true
      and d.system_only = false
  ) then
    raise exception using errcode = '22023', message = 'This Boon is unavailable.';
  end if;

  select count(*) into owned_count
  from public.player_boons pb
  where pb.owner_id = new.owner_id
    and (tg_op = 'INSERT' or pb.id <> new.id);

  if owned_count >= 2 then
    raise exception using errcode = '23514', message = 'Boon inventory is full. A player may own at most 2 Boons.';
  end if;
  return new;
end;
$$;

-- Preserve the Phase 3 dashboard contract while excluding system definitions
-- from availability calculations and all returned player inventory data.
create or replace function public.get_my_boons()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  profile_row public.profiles%rowtype;
  roll_cost bigint := public.get_boon_roll_cost();
  pending_roll jsonb;
  has_eligible_definition boolean := false;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  select * into profile_row from public.profiles p where p.id = caller_id;
  if not found then
    raise exception using errcode = '23503', message = 'Player profile not found.';
  end if;

  if not profile_row.is_guest and not profile_row.is_system_player then
    select jsonb_build_object(
      'id', br.id,
      'cost', br.cost,
      'status', br.status,
      'createdAt', br.created_at,
      'definition', jsonb_build_object(
        'id', d.id, 'key', d.key, 'name', d.name,
        'description', d.description, 'rarity', d.rarity,
        'effectType', d.effect_type, 'effectValue', d.effect_value,
        'targetRule', d.target_rule
      )
    ) into pending_roll
    from public.boon_rolls br
    join public.boon_definitions d on d.id = br.boon_definition_id
      and d.system_only = false
    where br.owner_id = caller_id and br.status = 'pending'
    order by br.created_at
    limit 1;

    select exists (
      select 1 from public.boon_definitions d
      where d.active = true and d.system_only = false
        and not exists (
          select 1 from public.player_boons pb
          where pb.owner_id = caller_id and pb.boon_definition_id = d.id
        )
    ) into has_eligible_definition;
  end if;

  return jsonb_build_object(
    'eligible', not profile_row.is_guest and not profile_row.is_system_player,
    'boonPoints', case when profile_row.is_guest or profile_row.is_system_player then 0 else profile_row.boon_points end,
    'rollCost', roll_cost,
    'canRoll', not profile_row.is_guest
      and not profile_row.is_system_player
      and profile_row.boon_points >= roll_cost
      and pending_roll is null
      and has_eligible_definition,
    'inventoryCount', case when profile_row.is_guest or profile_row.is_system_player then 0 else (
      select count(*) from public.player_boons pb
      join public.boon_definitions d on d.id = pb.boon_definition_id
      where pb.owner_id = caller_id and d.system_only = false
    ) end,
    'inventoryCapacity', 2,
    'pendingRoll', pending_roll,
    'boons', case when profile_row.is_guest or profile_row.is_system_player then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pb.id,
        'equipped', pb.equipped,
        'acquiredAt', pb.created_at,
        'definition', jsonb_build_object(
          'id', d.id, 'key', d.key, 'name', d.name,
          'description', d.description, 'rarity', d.rarity,
          'effectType', d.effect_type, 'effectValue', d.effect_value,
          'targetRule', d.target_rule
        )
      ) order by pb.equipped desc, pb.created_at, d.name)
      from public.player_boons pb
      join public.boon_definitions d on d.id = pb.boon_definition_id
        and d.system_only = false
      where pb.owner_id = caller_id
    ), '[]'::jsonb) end
  );
end;
$$;

-- Canonical Phase 3 weighted roll with only the two eligibility predicates
-- extended to exclude system-only definitions.
create or replace function public.roll_boon()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  profile_row public.profiles%rowtype;
  roll_cost bigint := public.get_boon_roll_cost();
  total_weight bigint;
  roll_target double precision;
  rolled_definition public.boon_definitions%rowtype;
  roll_row public.boon_rolls%rowtype;
  inventory_count integer;
  next_balance bigint;
  result_status text;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select * into profile_row
  from public.profiles p
  where p.id = caller_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'Player profile not found.';
  end if;
  if profile_row.is_guest then
    raise exception using errcode = '42501', message = 'Sign in to roll Boons.';
  end if;
  if profile_row.is_system_player then
    raise exception using errcode = '42501', message = 'System profiles cannot roll Boons.';
  end if;
  if exists (
    select 1 from public.boon_rolls br
    where br.owner_id = caller_id and br.status = 'pending'
  ) then
    raise exception using errcode = '55000', message = 'Resolve your current Boon roll first.';
  end if;
  if profile_row.boon_points < roll_cost then
    raise exception using errcode = '22003', message = 'Not enough Boon Points.';
  end if;

  select sum(d.roll_weight::bigint) into total_weight
  from public.boon_definitions d
  where d.active = true and d.system_only = false
    and not exists (
      select 1 from public.player_boons pb
      where pb.owner_id = caller_id and pb.boon_definition_id = d.id
    );
  if coalesce(total_weight, 0) <= 0 then
    raise exception using errcode = 'P0001', message = 'No new Boons are currently available.';
  end if;

  roll_target := random() * total_weight;
  select d.* into rolled_definition
  from public.boon_definitions d
  join (
    select eligible.id,
      sum(eligible.roll_weight::bigint) over (order by eligible.id) as cumulative_weight
    from public.boon_definitions eligible
    where eligible.active = true and eligible.system_only = false
      and not exists (
        select 1 from public.player_boons pb
        where pb.owner_id = caller_id and pb.boon_definition_id = eligible.id
      )
  ) weighted on weighted.id = d.id
  where weighted.cumulative_weight > roll_target
  order by weighted.cumulative_weight
  limit 1;
  if not found then
    raise exception using errcode = 'P0001', message = 'Unable to select a Boon result.';
  end if;

  update public.profiles p
  set boon_points = p.boon_points - roll_cost
  where p.id = caller_id
  returning p.boon_points into next_balance;

  select count(*) into inventory_count
  from public.player_boons pb
  where pb.owner_id = caller_id;

  if inventory_count < 2 then
    insert into public.boon_rolls
      (owner_id, boon_definition_id, cost, status, resolved_at)
    values (caller_id, rolled_definition.id, roll_cost, 'kept', now())
    returning * into roll_row;
    insert into public.player_boons (owner_id, boon_definition_id, equipped)
    values (caller_id, rolled_definition.id, false);
    result_status := 'added';
  else
    insert into public.boon_rolls (owner_id, boon_definition_id, cost, status)
    values (caller_id, rolled_definition.id, roll_cost, 'pending')
    returning * into roll_row;
    result_status := 'pending';
  end if;

  return jsonb_build_object(
    'status', result_status,
    'boonPoints', next_balance,
    'roll', jsonb_build_object(
      'id', roll_row.id,
      'cost', roll_row.cost,
      'status', roll_row.status,
      'createdAt', roll_row.created_at,
      'definition', jsonb_build_object(
        'id', rolled_definition.id, 'key', rolled_definition.key,
        'name', rolled_definition.name,
        'description', rolled_definition.description,
        'rarity', rolled_definition.rarity,
        'effectType', rolled_definition.effect_type,
        'effectValue', rolled_definition.effect_value,
        'targetRule', rolled_definition.target_rule
      )
    ),
    'dashboard', public.get_my_boons()
  );
end;
$$;

-- 4. Snapshot selection. Humans retain their equipped player Boon. The system
-- profile draws one of the two active system Boons uniformly at match creation.
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
      'systemOnly', true
    ) into result
    from public.boon_definitions d
    where d.active = true and d.system_only = true
      and d.key in ('admin_sovereign_ascension', 'admin_apex_overdrive')
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
    'systemOnly', false
  ) into result
  from public.player_boons pb
  join public.boon_definitions d on d.id = pb.boon_definition_id
  where pb.owner_id = p_player_id
    and pb.equipped = true
    and d.active = true
    and d.system_only = false
  order by pb.created_at
  limit 1;
  return result;
end;
$$;

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

  insert into public.match_boon_snapshots (
    match_id, player_id, player_boon_id_snapshot, boon_definition_id_snapshot,
    boon_key_snapshot, boon_name_snapshot, boon_description_snapshot,
    boon_rarity_snapshot, boon_effect_type_snapshot, boon_effect_value_snapshot,
    boon_target_rule_snapshot, boon_system_only_snapshot,
    boon_overall_effect_value_snapshot, boon_power_effect_value_snapshot
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
    (player_one_snapshot ->> 'powerEffectValue')::integer
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
    (player_two_snapshot ->> 'powerEffectValue')::integer
  )
  on conflict (match_id, player_id) do nothing;
  return new;
end;
$$;

-- 5. Apply the structured secondary Power component after the normal Phase 5
-- resolver establishes OC eligibility and applies the primary OVR component.
create or replace function public.apply_match_boon_secondary_stats_internal(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  snapshot_row public.match_boon_snapshots%rowtype;
  affected_count integer;
begin
  for snapshot_row in
    select s.* from public.match_boon_snapshots s
    where s.match_id = p_match_id and s.boon_system_only_snapshot = true
  loop
    affected_count := 0;

    if coalesce(snapshot_row.boon_power_effect_value_snapshot, 0) > 0 then
      update public.match_boon_fighter_stats fs set
        boon_targeted = true,
        boon_power_bonus = least(
          snapshot_row.boon_power_effect_value_snapshot,
          greatest(0, 12000 - fs.base_power_score - fs.preparation_power_bonus)
        ),
        final_power_score = least(
          12000,
          fs.base_power_score + fs.preparation_power_bonus
            + snapshot_row.boon_power_effect_value_snapshot
        )
      where fs.match_id = p_match_id
        and fs.player_id = snapshot_row.player_id
        and fs.fighter_type = 'oc'
        and fs.eligible_for_battle;
      get diagnostics affected_count = row_count;
    end if;

    update public.match_boon_resolutions r set
      requested_overall_value = coalesce(
        snapshot_row.boon_overall_effect_value_snapshot,
        snapshot_row.boon_effect_value_snapshot
      ),
      requested_power_value = snapshot_row.boon_power_effect_value_snapshot,
      metadata = r.metadata || jsonb_build_object(
        'systemOnly', true,
        'overallRequested', coalesce(
          snapshot_row.boon_overall_effect_value_snapshot,
          snapshot_row.boon_effect_value_snapshot
        ),
        'powerRequested', coalesce(snapshot_row.boon_power_effect_value_snapshot, 0),
        'secondaryTargetCount', affected_count
      )
    where r.match_id = p_match_id and r.player_id = snapshot_row.player_id;
  end loop;
end;
$$;

-- Preserve the Phase 5 lifecycle trigger and add the structured second stat in
-- the same transaction, before the match becomes visible as battle-ready.
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

-- 6. Browser permissions. System definitions remain server-owned; no player
-- inventory rows are created for Administrator.
revoke all on table public.boon_definitions from public, anon, authenticated;
revoke all on table public.player_boons from public, anon, authenticated;
revoke all on table public.boon_rolls from public, anon, authenticated;
revoke all on table public.match_boon_snapshots from public, anon, authenticated;
revoke all on table public.match_boon_resolutions from public, anon, authenticated;

revoke all on function public.get_boon_catalogue() from public, anon, authenticated;
revoke all on function public.get_my_boons() from public, anon, authenticated;
revoke all on function public.roll_boon() from public, anon, authenticated;
revoke all on function public.enforce_player_boon_inventory_limit() from public, anon, authenticated;
revoke all on function public.build_player_boon_snapshot_internal(uuid) from public, anon, authenticated;
revoke all on function public.capture_match_boon_snapshots() from public, anon, authenticated;
revoke all on function public.apply_match_boon_secondary_stats_internal(uuid) from public, anon, authenticated;
revoke all on function public.apply_match_boon_effects_before_battle() from public, anon, authenticated;

grant execute on function public.get_boon_catalogue() to authenticated;
grant execute on function public.get_my_boons() to authenticated;
grant execute on function public.roll_boon() to authenticated;

notify pgrst, 'reload schema';
