-- Anime Arena OC Family Social System - Phase 1: public player profiles
-- Run manually in the Supabase SQL Editor after:
--   1. profiles + the Administrator profile migration
--   2. verses
--   3. player_characters + OC type migrations
--
-- Phase 1 intentionally does not add oc_families or OC lore. The current
-- active/equipped/non-retired loadout remains the single OC Family source.

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
    -- This is the existing player leaderboard ordering: win rate, wins,
    -- games played, username, then the stable profile UUID tiebreaker.
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
      pc.power_score_cap
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
            'growth', fm.overall - fm.starting_overall
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

  -- Guests, the Administrator/system profile, missing profiles, and unavailable
  -- targets share the same non-disclosing response.
  return public_profile;
end;
$$;

revoke all on function public.get_public_player_profile(uuid) from public;
revoke all on function public.get_public_player_profile(uuid) from anon;
revoke all on function public.get_public_player_profile(uuid) from authenticated;
grant execute on function public.get_public_player_profile(uuid) to authenticated;

notify pgrst, 'reload schema';
