-- Anime Arena Boon System - Phase 3: shop, weighted rolling, and replacement.
-- Run after docs/supabase_boon_phase_2.sql.
-- This migration does not snapshot Boons into matches or apply gameplay effects.

-- 1. One durable audit row per paid roll. A pending row is the authoritative
-- unresolved result when the player's two-slot inventory is full.
create table if not exists public.boon_rolls (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  boon_definition_id uuid not null references public.boon_definitions(id) on delete restrict,
  cost bigint not null,
  status text not null,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  constraint boon_rolls_cost_positive check (cost > 0),
  constraint boon_rolls_status_check check (status in ('pending', 'kept', 'discarded')),
  constraint boon_rolls_resolution_check check (
    (status = 'pending' and resolved_at is null)
    or (status in ('kept', 'discarded') and resolved_at is not null)
  )
);

create unique index if not exists boon_rolls_one_pending_per_owner_idx
  on public.boon_rolls (owner_id)
  where status = 'pending';

create index if not exists boon_rolls_owner_created_at_idx
  on public.boon_rolls (owner_id, created_at desc);

create index if not exists boon_rolls_definition_id_idx
  on public.boon_rolls (boon_definition_id);

alter table public.boon_rolls enable row level security;

drop policy if exists "Owners can read their Boon roll history" on public.boon_rolls;
create policy "Owners can read their Boon roll history"
  on public.boon_rolls for select to authenticated
  using (owner_id = (select auth.uid()));

-- 2. Central backend price decision. Player-facing RPCs call this function so
-- the 100 BP cost is defined once rather than repeated across SQL/UI logic.
create or replace function public.get_boon_roll_cost()
returns bigint
language sql
immutable
set search_path = ''
as $$
  select 100::bigint;
$$;

-- Intentional initial weights. With the ten Phase 2 definitions these total
-- to an approximate rarity distribution of 50% common / 30% rare / 15% epic /
-- 5% legendary before owned definitions are excluded.
update public.boon_definitions d
set roll_weight = weights.roll_weight,
    updated_at = now()
from (values
  ('ascendant', 5),
  ('oc_power_surge', 5),
  ('lucky_draft', 6),
  ('chosen_one', 5),
  ('underdog', 6),
  ('elite_training', 50),
  ('resonance', 6),
  ('balanced_formation', 6),
  ('wild_card', 5),
  ('unity', 6)
) as weights(key, roll_weight)
where d.key = weights.key;

-- 3. One coherent private dashboard response: balance, inventory, configured
-- server cost, and the caller's unresolved result (if any).
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

  select * into profile_row
  from public.profiles p
  where p.id = caller_id;

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
        'id', d.id,
        'key', d.key,
        'name', d.name,
        'description', d.description,
        'rarity', d.rarity,
        'effectType', d.effect_type,
        'effectValue', d.effect_value,
        'targetRule', d.target_rule
      )
    ) into pending_roll
    from public.boon_rolls br
    join public.boon_definitions d on d.id = br.boon_definition_id
    where br.owner_id = caller_id and br.status = 'pending'
    order by br.created_at
    limit 1;

    select exists (
      select 1
      from public.boon_definitions d
      where d.active = true
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
      select count(*) from public.player_boons pb where pb.owner_id = caller_id
    ) end,
    'inventoryCapacity', 2,
    'pendingRoll', pending_roll,
    'boons', case when profile_row.is_guest or profile_row.is_system_player then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pb.id,
        'equipped', pb.equipped,
        'acquiredAt', pb.created_at,
        'definition', jsonb_build_object(
          'id', d.id,
          'key', d.key,
          'name', d.name,
          'description', d.description,
          'rarity', d.rarity,
          'effectType', d.effect_type,
          'effectValue', d.effect_value,
          'targetRule', d.target_rule
        )
      ) order by pb.equipped desc, pb.created_at, d.name)
      from public.player_boons pb
      join public.boon_definitions d on d.id = pb.boon_definition_id
      where pb.owner_id = caller_id
    ), '[]'::jsonb) end
  );
end;
$$;

-- 4. Authoritative weighted roll. The caller supplies no owner, price, result,
-- rarity, weight, or random seed. Locking the profile serializes every balance,
-- inventory, equip, and roll mutation for this player.
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
  where d.active = true
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
    where eligible.active = true
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
    values
      (caller_id, rolled_definition.id, roll_cost, 'kept', now())
    returning * into roll_row;

    insert into public.player_boons (owner_id, boon_definition_id, equipped)
    values (caller_id, rolled_definition.id, false);
    result_status := 'added';
  else
    insert into public.boon_rolls
      (owner_id, boon_definition_id, cost, status)
    values
      (caller_id, rolled_definition.id, roll_cost, 'pending')
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
        'id', rolled_definition.id,
        'key', rolled_definition.key,
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

-- 5. Resolve the one paid pending result. Replacement is atomic: deleting an
-- equipped target naturally leaves the slot empty; the new Boon is always
-- inserted unequipped. Discard keeps the old inventory and never refunds BP.
create or replace function public.resolve_boon_roll(
  p_roll_id uuid,
  p_action text,
  p_replace_player_boon_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  profile_row public.profiles%rowtype;
  pending_row public.boon_rolls%rowtype;
  replacement_row public.player_boons%rowtype;
  normalized_action text := lower(btrim(coalesce(p_action, '')));
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
    raise exception using errcode = '42501', message = 'Sign in to resolve Boon rolls.';
  end if;
  if profile_row.is_system_player then
    raise exception using errcode = '42501', message = 'System profiles cannot resolve Boon rolls.';
  end if;
  if normalized_action not in ('replace', 'discard') then
    raise exception using errcode = '22023', message = 'Choose replace or discard.';
  end if;

  select * into pending_row
  from public.boon_rolls br
  where br.id = p_roll_id
    and br.owner_id = caller_id
    and br.status = 'pending'
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Pending Boon roll not found or already resolved.';
  end if;

  if normalized_action = 'discard' then
    update public.boon_rolls br
    set status = 'discarded', resolved_at = now()
    where br.id = pending_row.id and br.owner_id = caller_id and br.status = 'pending';

    return jsonb_build_object(
      'status', 'discarded',
      'dashboard', public.get_my_boons()
    );
  end if;

  if p_replace_player_boon_id is null then
    raise exception using errcode = '22023', message = 'Choose a Boon to replace.';
  end if;

  select * into replacement_row
  from public.player_boons pb
  where pb.id = p_replace_player_boon_id
    and pb.owner_id = caller_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'Replacement Boon not found or not owned.';
  end if;

  if exists (
    select 1 from public.player_boons pb
    where pb.owner_id = caller_id
      and pb.boon_definition_id = pending_row.boon_definition_id
  ) then
    raise exception using errcode = '23505', message = 'That Boon is already owned.';
  end if;

  delete from public.player_boons pb
  where pb.id = replacement_row.id and pb.owner_id = caller_id;

  insert into public.player_boons (owner_id, boon_definition_id, equipped)
  values (caller_id, pending_row.boon_definition_id, false);

  update public.boon_rolls br
  set status = 'kept', resolved_at = now()
  where br.id = pending_row.id and br.owner_id = caller_id and br.status = 'pending';

  return jsonb_build_object(
    'status', 'replaced',
    'dashboard', public.get_my_boons()
  );
end;
$$;

-- 6. Browser security. Roll history and both economy tables remain RPC-only;
-- authenticated clients can call only the narrow owner-derived functions.
revoke all on table public.boon_rolls from public, anon, authenticated;

revoke all on function public.get_boon_roll_cost() from public, anon, authenticated;
revoke all on function public.get_my_boons() from public, anon, authenticated;
revoke all on function public.roll_boon() from public, anon, authenticated;
revoke all on function public.resolve_boon_roll(uuid, text, uuid) from public, anon, authenticated;

grant execute on function public.get_my_boons() to authenticated;
grant execute on function public.roll_boon() to authenticated;
grant execute on function public.resolve_boon_roll(uuid, text, uuid) to authenticated;

notify pgrst, 'reload schema';
