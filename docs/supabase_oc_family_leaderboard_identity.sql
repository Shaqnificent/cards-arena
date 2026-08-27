-- OC Family leaderboard identity projection.
-- Run after docs/supabase_oc_family_social_phase3.sql and the latest
-- profile-identity / OC leaderboard migration.

create or replace function public.get_oc_family_leaderboard(
  p_sort text default 'overall', p_limit integer default 100, p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception using errcode='42501', message='Authentication required.'; end if;
  if p_sort not in ('overall','power','growth') then raise exception using errcode='22023', message='Invalid OC family sort.'; end if;
  if p_limit not between 1 and 100 or p_offset < 0 then raise exception using errcode='22023', message='Invalid pagination.'; end if;

  with eligible as (
    select
      pc.owner_id,
      p.username,
      p.avatar_url,
      p.avatar_mode,
      p.avatar_bg_color,
      p.avatar_text_color,
      coalesce(nullif(btrim(f.name), ''), p.username || '''s OC Family') as family_name,
      f.logo_url as family_logo_path,
      f.updated_at as family_updated_at,
      count(*)::integer family_size,
      avg(pc.overall)::numeric avg_overall,
      avg(pc.power_score)::numeric avg_power_score,
      sum(pc.overall-pc.starting_overall)::bigint total_growth,
      jsonb_agg(jsonb_build_object(
        'id',pc.id,'name',pc.name,'verseId',pc.verse_id,'verseName',v.name,
        'startingOverall',pc.starting_overall,'overall',pc.overall,
        'powerScore',pc.power_score,'growth',pc.overall-pc.starting_overall
      ) order by pc.overall desc,pc.id) family
    from public.player_characters pc
    join public.profiles p on p.id=pc.owner_id
    join public.verses v on v.id=pc.verse_id
    left join public.oc_families f on f.owner_id=pc.owner_id
    where pc.active=true and pc.equipped=true and pc.retired_at is null
      and p.is_guest=false and p.is_system_player=false
    group by
      pc.owner_id,p.username,p.avatar_url,p.avatar_mode,p.avatar_bg_color,p.avatar_text_color,
      f.name,f.logo_url,f.updated_at
    having count(*)=3
  ), ranked as (
    select row_number() over (order by
      case when p_sort='overall' then avg_overall end desc nulls last,
      case when p_sort='overall' then avg_power_score end desc nulls last,
      case when p_sort='power' then avg_power_score end desc nulls last,
      case when p_sort='power' then avg_overall end desc nulls last,
      case when p_sort='growth' then total_growth end desc nulls last,
      case when p_sort='growth' then avg_overall end desc nulls last,
      case when p_sort='growth' then avg_power_score end desc nulls last,
      owner_id asc) as rank, *
    from eligible
  ), page as (
    select * from ranked order by rank limit p_limit offset p_offset
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank',rank,
    'ownerId',owner_id,
    'username',username,
    'avatarUrl',avatar_url,
    'avatarMode',avatar_mode,
    'avatarBgColor',avatar_bg_color,
    'avatarTextColor',avatar_text_color,
    'familyName',family_name,
    'familyLogoPath',family_logo_path,
    'familyUpdatedAt',family_updated_at,
    'familySize',family_size,
    'avgOverall',avg_overall,
    'avgPowerScore',avg_power_score,
    'totalGrowth',total_growth,
    'family',family
  ) order by rank),'[]'::jsonb) into result from page;
  return result;
end;
$$;

revoke all on function public.get_oc_family_leaderboard(text,integer,integer)
  from public, anon, authenticated;
grant execute on function public.get_oc_family_leaderboard(text,integer,integer)
  to authenticated;

notify pgrst, 'reload schema';
