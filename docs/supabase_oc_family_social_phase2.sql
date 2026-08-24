-- Anime Arena OC Family Social System - Phase 2: OC Lore & Personality
-- Run manually in the Supabase SQL Editor after:
--   1. docs/supabase_oc_family_social_phase1.sql
--   2. the current player_characters and OC type migrations
--
-- Lore is social metadata attached to the persistent OC. It is intentionally
-- excluded from match snapshots and all competitive match-state functions.

alter table public.player_characters
  add column if not exists lore text;

alter table public.player_characters
  drop constraint if exists player_characters_lore_length_check;

alter table public.player_characters
  add constraint player_characters_lore_length_check
  check (lore is null or char_length(lore) <= 1000);

create or replace function public.update_player_character_lore(
  p_player_character_id uuid,
  p_lore text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_lore text := nullif(btrim(coalesce(p_lore, '')), '');
  updated_character public.player_characters%rowtype;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  if normalized_lore is not null and char_length(normalized_lore) > 1000 then
    raise exception using errcode = '22001', message = 'OC lore cannot exceed 1000 characters.';
  end if;

  update public.player_characters pc
  set lore = normalized_lore
  where pc.id = p_player_character_id
    and pc.owner_id = caller_id
  returning pc.* into updated_character;

  if not found then
    raise exception using errcode = '42501', message = 'OC not found or not owned by you.';
  end if;

  return jsonb_build_object(
    'characterId', updated_character.id,
    'lore', updated_character.lore,
    'updatedAt', updated_character.updated_at
  );
end;
$$;

-- Replace the Phase 1 public-profile function without widening its profile or
-- OC exposure. The only Phase 2 addition to each public family member is lore.
create or replace function public.get_public_player_profile(p_player_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  public_profile jsonb;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;

  with ranked_players as (
    select
      p.id,
      row_number() over (
        order by
          p.wins::numeric / nullif(p.wins + p.losses, 0) desc,
          p.wins desc,
          (p.wins + p.losses) desc,
          p.username asc,
          p.id asc
      ) as leaderboard_rank
    from public.profiles p
    where p.is_guest = false
      and (p.wins + p.losses) > 0
  ),
  family_members as (
    select
      row_number() over (order by pc.created_at asc, pc.id asc) as family_slot,
      pc.id,
      pc.name,
      pc.image_url,
      pc.verse_id,
      v.name as verse_name,
      v.slug as verse_slug,
      pc.oc_type,
      pc.starting_overall,
      pc.overall,
      pc.overall_cap,
      pc.power_score,
      pc.power_score_cap,
      pc.lore
    from public.player_characters pc
    join public.verses v on v.id = pc.verse_id
    where pc.owner_id = p_player_id
      and pc.active = true
      and pc.equipped = true
      and pc.retired_at is null
    order by pc.created_at asc, pc.id asc
    limit 3
  )
  select jsonb_build_object(
    'playerId', p.id,
    'displayName', p.username,
    'avatarUrl', p.avatar_url,
    'wins', p.wins,
    'losses', p.losses,
    'winRate', case
      when p.wins + p.losses = 0 then 0
      else round((p.wins::numeric * 100) / (p.wins + p.losses), 1)
    end,
    'rank', rp.leaderboard_rank,
    'joinedAt', p.created_at,
    'ocFamily', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'characterId', fm.id,
            'slot', fm.family_slot,
            'name', fm.name,
            'imageUrl', fm.image_url,
            'verseId', fm.verse_id,
            'verseName', fm.verse_name,
            'verseSlug', fm.verse_slug,
            'ocType', fm.oc_type,
            'startingOverall', fm.starting_overall,
            'overall', fm.overall,
            'overallCap', fm.overall_cap,
            'powerScore', fm.power_score,
            'powerScoreCap', fm.power_score_cap,
            'growth', fm.overall - fm.starting_overall,
            'lore', fm.lore
          )
          order by fm.family_slot
        )
        from family_members fm
      ),
      '[]'::jsonb
    )
  )
  into public_profile
  from public.profiles p
  left join ranked_players rp on rp.id = p.id
  where p.id = p_player_id
    and p.is_guest = false
    and p.is_system_player = false;

  return public_profile;
end;
$$;

-- Direct player_characters UPDATE access remains revoked. Only the dedicated,
-- ownership-checked lore function is executable by browser clients.
revoke all on function public.update_player_character_lore(uuid, text) from public;
revoke all on function public.update_player_character_lore(uuid, text) from anon;
revoke all on function public.update_player_character_lore(uuid, text) from authenticated;
grant execute on function public.update_player_character_lore(uuid, text) to authenticated;

revoke all on function public.get_public_player_profile(uuid) from public;
revoke all on function public.get_public_player_profile(uuid) from anon;
revoke all on function public.get_public_player_profile(uuid) from authenticated;
grant execute on function public.get_public_player_profile(uuid) to authenticated;

notify pgrst, 'reload schema';
