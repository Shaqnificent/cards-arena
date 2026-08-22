-- Anime Arena OC Foundation (Phase 1)
-- Run this file in the Supabase SQL Editor after profiles and verses exist.
-- Normal player removal is retirement, not deletion. Production anti-reroll
-- controls (cooldowns or creation resources) remain required in a later phase.

create table if not exists public.player_characters (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  verse_id uuid not null references public.verses(id) on delete restrict,
  name text not null,
  image_url text,
  starting_overall integer not null,
  overall integer not null,
  overall_cap integer not null,
  starting_power_score integer not null,
  power_score integer not null,
  power_score_cap integer not null,
  progression_points integer not null default 0,
  equipped boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz,
  constraint player_characters_name_check check (name = btrim(name) and char_length(name) between 2 and 50),
  constraint player_characters_starting_overall_check check (starting_overall between 50 and 60),
  constraint player_characters_overall_cap_check check (overall_cap between 92 and 95),
  constraint player_characters_overall_check check (overall >= starting_overall and overall <= overall_cap),
  constraint player_characters_starting_power_check check (starting_power_score = 5000),
  constraint player_characters_power_cap_check check (power_score_cap between 8500 and 10000),
  constraint player_characters_power_check check (power_score >= starting_power_score and power_score <= power_score_cap),
  constraint player_characters_points_check check (progression_points >= 0),
  constraint player_characters_potential_caps_check check (
    (starting_overall between 50 and 52 and overall_cap = 92 and power_score_cap = 10000) or
    (starting_overall between 53 and 55 and overall_cap = 93 and power_score_cap = 9500) or
    (starting_overall between 56 and 58 and overall_cap = 94 and power_score_cap = 9000) or
    (starting_overall between 59 and 60 and overall_cap = 95 and power_score_cap = 8500)
  ),
  constraint player_characters_retirement_check check (
    (active and retired_at is null) or (not active and not equipped and retired_at is not null)
  )
);

create index if not exists player_characters_owner_active_idx
  on public.player_characters (owner_id, active);
create index if not exists player_characters_owner_equipped_idx
  on public.player_characters (owner_id, equipped)
  where active = true;
create index if not exists player_characters_verse_id_idx
  on public.player_characters (verse_id);

create or replace function public.set_player_character_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists set_player_character_updated_at on public.player_characters;
create trigger set_player_character_updated_at
  before update on public.player_characters
  for each row execute function public.set_player_character_updated_at();

alter table public.player_characters enable row level security;

drop policy if exists "Owners can read their OCs" on public.player_characters;
create policy "Owners can read their OCs"
  on public.player_characters for select to authenticated
  using ((select auth.uid()) = owner_id);

create or replace function public.create_player_character(p_name text, p_verse_id uuid)
returns public.player_characters
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_name text := btrim(p_name);
  band_roll double precision;
  rolled_overall integer;
  derived_overall_cap integer;
  derived_power_cap integer;
  created_character public.player_characters%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if not exists (select 1 from public.profiles where id = caller_id) then
    raise exception using errcode = '23503', message = 'Player profile not found.';
  end if;
  if normalized_name is null or char_length(normalized_name) not between 2 and 50 then
    raise exception using errcode = '22023', message = 'OC name must be between 2 and 50 characters.';
  end if;
  if not exists (select 1 from public.verses where id = p_verse_id and active = true) then
    raise exception using errcode = '22023', message = 'Select an active verse.';
  end if;

  band_roll := random();
  if band_roll < 0.20 then
    rolled_overall := 50 + floor(random() * 3)::integer;
    derived_overall_cap := 92;
    derived_power_cap := 10000;
  elsif band_roll < 0.60 then
    rolled_overall := 53 + floor(random() * 3)::integer;
    derived_overall_cap := 93;
    derived_power_cap := 9500;
  elsif band_roll < 0.90 then
    rolled_overall := 56 + floor(random() * 3)::integer;
    derived_overall_cap := 94;
    derived_power_cap := 9000;
  else
    rolled_overall := 59 + floor(random() * 2)::integer;
    derived_overall_cap := 95;
    derived_power_cap := 8500;
  end if;

  insert into public.player_characters (
    owner_id, verse_id, name, starting_overall, overall, overall_cap,
    starting_power_score, power_score, power_score_cap, progression_points
  ) values (
    caller_id, p_verse_id, normalized_name, rolled_overall, rolled_overall, derived_overall_cap,
    5000, 5000, derived_power_cap, 0
  ) returning * into created_character;

  return created_character;
end;
$$;

create or replace function public.set_player_character_equipped(p_character_id uuid, p_equipped boolean)
returns public.player_characters
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  target_character public.player_characters%rowtype;
  equipped_count integer;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  -- Serialize loadout changes per owner so simultaneous equips cannot exceed three.
  perform 1 from public.profiles where id = caller_id for update;
  select * into target_character
  from public.player_characters
  where id = p_character_id and owner_id = caller_id
  for update;

  if not found then
    raise exception using errcode = '42501', message = 'OC not found or not owned by you.';
  end if;
  if not target_character.active or target_character.retired_at is not null then
    raise exception using errcode = '22023', message = 'Retired OCs cannot be equipped.';
  end if;

  if p_equipped and not target_character.equipped then
    select count(*) into equipped_count
    from public.player_characters
    where owner_id = caller_id and active = true and equipped = true;
    if equipped_count >= 3 then
      raise exception using errcode = '23514', message = 'Your OC Family already has 3 fighters. Unequip one before adding another.';
    end if;
  end if;

  update public.player_characters
  set equipped = p_equipped
  where id = target_character.id
  returning * into target_character;
  return target_character;
end;
$$;

create or replace function public.retire_player_character(p_character_id uuid)
returns public.player_characters
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  retired_character public.player_characters%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  update public.player_characters
  set active = false, equipped = false, retired_at = now()
  where id = p_character_id and owner_id = caller_id and active = true
  returning * into retired_character;

  if not found then
    raise exception using errcode = '42501', message = 'Active OC not found or not owned by you.';
  end if;
  return retired_character;
end;
$$;

revoke all on public.player_characters from public, anon, authenticated;
grant select on public.player_characters to authenticated;

revoke all on function public.create_player_character(text, uuid) from public;
revoke all on function public.set_player_character_equipped(uuid, boolean) from public;
revoke all on function public.retire_player_character(uuid) from public;
grant execute on function public.create_player_character(text, uuid) to authenticated;
grant execute on function public.set_player_character_equipped(uuid, boolean) to authenticated;
grant execute on function public.retire_player_character(uuid) to authenticated;

notify pgrst, 'reload schema';
