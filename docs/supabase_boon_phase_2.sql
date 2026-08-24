-- Anime Arena Boon System - Phase 2: definitions, private inventory, and equip management.
-- Run after docs/supabase_boon_phase_1.sql.
-- This migration does not spend BP, roll Boons, snapshot a loadout into a match,
-- or apply any gameplay effect.

-- 1. Data-driven catalogue. Keys/effect/target identifiers are structured data,
-- never executable code. Numeric values remain balance-configurable seed data.
create table if not exists public.boon_definitions (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  description text not null,
  rarity text not null,
  effect_type text not null,
  effect_value integer,
  target_rule text not null,
  active boolean not null default true,
  roll_weight integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint boon_definitions_key_format check (key = btrim(key) and key ~ '^[a-z][a-z0-9_]{1,49}$'),
  constraint boon_definitions_name_check check (name = btrim(name) and char_length(name) between 2 and 80),
  constraint boon_definitions_description_check check (description = btrim(description) and char_length(description) between 2 and 500),
  constraint boon_definitions_rarity_check check (rarity in ('common', 'rare', 'epic', 'legendary')),
  constraint boon_definitions_effect_type_format check (effect_type = btrim(effect_type) and effect_type ~ '^[a-z][a-z0-9_]{1,49}$'),
  constraint boon_definitions_effect_value_check check (effect_value is null or effect_value > 0),
  constraint boon_definitions_target_rule_format check (target_rule = btrim(target_rule) and target_rule ~ '^[a-z][a-z0-9_]{1,79}$'),
  constraint boon_definitions_roll_weight_check check (roll_weight > 0)
);

create or replace function public.set_boon_definition_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists set_boon_definition_updated_at on public.boon_definitions;
create trigger set_boon_definition_updated_at
  before update on public.boon_definitions
  for each row execute function public.set_boon_definition_updated_at();

insert into public.boon_definitions
  (key, name, description, rarity, effect_type, effect_value, target_rule, active, roll_weight)
values
  ('ascendant', 'Ascendant', 'Selected OC gains +3 temporary OVR for the match.', 'legendary', 'oc_overall', 3, 'selected_oc', true, 1),
  ('oc_power_surge', 'OC Power Surge', 'Selected OC gains +500 temporary Global Power for the match.', 'epic', 'oc_power', 500, 'selected_oc', true, 1),
  ('lucky_draft', 'Lucky Draft', 'One random drafted canon fighter gains +2 temporary OVR.', 'rare', 'random_drafted_overall', 2, 'random_drafted_canon', true, 1),
  ('chosen_one', 'Chosen One', 'One random drafted canon fighter gains +3 temporary OVR.', 'epic', 'random_drafted_overall', 3, 'random_drafted_canon', true, 1),
  ('underdog', 'Underdog', 'Your lowest-OVR drafted canon fighter gains +3 temporary OVR.', 'rare', 'lowest_drafted_overall', 3, 'lowest_drafted_canon', true, 1),
  ('elite_training', 'Elite Training', 'Your highest-OVR drafted canon fighter gains +1 temporary OVR.', 'common', 'highest_drafted_overall', 1, 'highest_drafted_canon', true, 1),
  ('resonance', 'Resonance', 'Eligible same-verse canon fighters gain +250 temporary Global Power.', 'rare', 'same_verse_power', 250, 'same_verse_as_selected_oc', true, 1),
  ('balanced_formation', 'Balanced Formation', 'Your three lowest-OVR drafted canon fighters gain +1 temporary OVR.', 'rare', 'multi_lowest_overall', 1, 'three_lowest_drafted', true, 1),
  ('wild_card', 'Wild Card', 'One random eligible fighter gains a random +1 to +4 temporary OVR.', 'epic', 'random_overall', 4, 'random_eligible_fighter', true, 1),
  ('unity', 'Unity', 'Fighters from one eligible team verse gain +300 temporary Global Power.', 'rare', 'verse_power', 300, 'random_team_verse', true, 1)
on conflict (key) do update set
  name = excluded.name,
  description = excluded.description,
  rarity = excluded.rarity,
  effect_type = excluded.effect_type,
  effect_value = excluded.effect_value,
  target_rule = excluded.target_rule,
  active = excluded.active,
  roll_weight = excluded.roll_weight,
  updated_at = now();

-- 2. Private player inventory. A player cannot own duplicate definitions.
create table if not exists public.player_boons (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  boon_definition_id uuid not null references public.boon_definitions(id) on delete restrict,
  equipped boolean not null default false,
  created_at timestamptz not null default now(),
  constraint player_boons_owner_definition_unique unique (owner_id, boon_definition_id)
);

create unique index if not exists player_boons_one_equipped_per_owner_idx
  on public.player_boons (owner_id)
  where equipped = true;

create index if not exists player_boons_definition_id_idx
  on public.player_boons (boon_definition_id);

-- Serialize every acquisition per owner and enforce the hard two-item limit at
-- the table boundary. This protects future server-side acquisition functions,
-- the manual test seed, and concurrent inserts without exposing a client grant.
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
    where d.id = new.boon_definition_id and d.active = true
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

drop trigger if exists enforce_player_boon_inventory_limit on public.player_boons;
create trigger enforce_player_boon_inventory_limit
  before insert or update of owner_id, boon_definition_id on public.player_boons
  for each row execute function public.enforce_player_boon_inventory_limit();

-- 3. Narrow RLS. Definitions are non-secret, but the normal UI reads them via
-- a safe active-only RPC. Inventories are private and all mutations use RPCs.
alter table public.boon_definitions enable row level security;
alter table public.player_boons enable row level security;

drop policy if exists "Authenticated users can read active Boon definitions" on public.boon_definitions;
create policy "Authenticated users can read active Boon definitions"
  on public.boon_definitions for select to authenticated
  using (active = true);

drop policy if exists "Owners can read their Boon inventory" on public.player_boons;
create policy "Owners can read their Boon inventory"
  on public.player_boons for select to authenticated
  using (owner_id = (select auth.uid()));

-- 4. Active catalogue response. No inventory or economy data is included.
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
  where d.active = true;
$$;

-- 5. Owner dashboard response. This is the only inventory read used by the UI
-- and reuses profiles.boon_points from Phase 1 as the single balance source.
create or replace function public.get_my_boons()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  profile_row public.profiles%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  select * into profile_row from public.profiles where id = caller_id;
  if not found then
    raise exception using errcode = '23503', message = 'Player profile not found.';
  end if;

  return jsonb_build_object(
    'eligible', not profile_row.is_guest and not profile_row.is_system_player,
    'boonPoints', case when profile_row.is_guest or profile_row.is_system_player then 0 else profile_row.boon_points end,
    'inventoryCount', case when profile_row.is_guest or profile_row.is_system_player then 0 else (select count(*) from public.player_boons pb where pb.owner_id = caller_id) end,
    'inventoryCapacity', 2,
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

-- 6. Atomic equip swap. The profile lock serializes equipment changes with
-- future acquisition flows. Only an active definition owned by the caller can
-- become equipped.
create or replace function public.equip_boon(p_player_boon_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  target_id uuid;
  profile_is_guest boolean;
  profile_is_system boolean;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select p.is_guest, p.is_system_player
    into profile_is_guest, profile_is_system
  from public.profiles p where p.id = caller_id for update;
  if not found then raise exception using errcode = '23503', message = 'Player profile not found.'; end if;
  if profile_is_guest then raise exception using errcode = '42501', message = 'Sign in to manage a Boon loadout.'; end if;
  if profile_is_system then raise exception using errcode = '42501', message = 'System profiles cannot equip Boons.'; end if;

  select pb.id into target_id
  from public.player_boons pb
  join public.boon_definitions d on d.id = pb.boon_definition_id
  where pb.id = p_player_boon_id
    and pb.owner_id = caller_id
    and d.active = true
  for update of pb;

  if not found then
    raise exception using errcode = '42501', message = 'Boon not found, not owned, or unavailable.';
  end if;

  update public.player_boons set equipped = false
  where owner_id = caller_id and equipped = true and id <> target_id;
  update public.player_boons set equipped = true
  where id = target_id and owner_id = caller_id;

  return public.get_my_boons();
end;
$$;

create or replace function public.unequip_boon()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  profile_is_guest boolean;
  profile_is_system boolean;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  select p.is_guest, p.is_system_player
    into profile_is_guest, profile_is_system
  from public.profiles p where p.id = caller_id for update;
  if not found then raise exception using errcode = '23503', message = 'Player profile not found.'; end if;
  if profile_is_guest then raise exception using errcode = '42501', message = 'Sign in to manage a Boon loadout.'; end if;
  if profile_is_system then raise exception using errcode = '42501', message = 'System profiles cannot equip Boons.'; end if;

  update public.player_boons set equipped = false
  where owner_id = caller_id and equipped = true;
  return public.get_my_boons();
end;
$$;

-- 7. Browser privileges. There is intentionally no authenticated INSERT,
-- UPDATE, DELETE, or arbitrary grant function for player_boons.
revoke all on table public.boon_definitions from anon, authenticated;
revoke all on table public.player_boons from anon, authenticated;

revoke all on function public.set_boon_definition_updated_at() from public, anon, authenticated;
revoke all on function public.enforce_player_boon_inventory_limit() from public, anon, authenticated;
revoke all on function public.get_boon_catalogue() from public, anon;
revoke all on function public.get_my_boons() from public, anon;
revoke all on function public.equip_boon(uuid) from public, anon;
revoke all on function public.unequip_boon() from public, anon;

grant execute on function public.get_boon_catalogue() to authenticated;
grant execute on function public.get_my_boons() to authenticated;
grant execute on function public.equip_boon(uuid) to authenticated;
grant execute on function public.unequip_boon() to authenticated;

notify pgrst, 'reload schema';
