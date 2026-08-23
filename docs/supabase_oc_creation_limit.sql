-- Anime Arena OC active-collection limit
-- Run after docs/supabase_oc_types_and_sacrifice.sql.
-- Retired OCs remain persisted but do not consume one of the five active slots.

create or replace function public.create_player_character(
  p_name text,
  p_verse_id bigint,
  p_oc_type text
)
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
  active_character_count integer;
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
  if p_oc_type not in ('champion', 'sacrificial') then
    raise exception using errcode = '22023', message = 'Choose Champion or Sacrificial.';
  end if;
  if not exists (select 1 from public.verses where id = p_verse_id and active = true) then
    raise exception using errcode = '22023', message = 'Select an active verse.';
  end if;

  -- Lock the owner's profile row before counting. Every creation for this owner
  -- must acquire the same lock, preventing simultaneous requests from both
  -- observing four active characters and inserting a sixth.
  perform 1 from public.profiles where id = caller_id for update;
  select count(*) into active_character_count
  from public.player_characters
  where owner_id = caller_id and active = true;

  if active_character_count >= 5 then
    raise exception using
      errcode = '22023',
      message = 'Your OC collection already has 5 active fighters. Retire one before creating another.';
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
    starting_power_score, power_score, power_score_cap, progression_points,
    oc_type, type_selected_at
  ) values (
    caller_id, p_verse_id, normalized_name, rolled_overall, rolled_overall,
    derived_overall_cap, 5000, 5000, derived_power_cap, 0, p_oc_type, now()
  )
  returning * into created_character;

  return created_character;
end;
$$;

revoke all on function public.create_player_character(text, bigint, text) from public;
revoke all on function public.create_player_character(text, bigint, text) from anon;
grant execute on function public.create_player_character(text, bigint, text) to authenticated;

notify pgrst, 'reload schema';
