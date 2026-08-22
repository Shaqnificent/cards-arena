-- Anime Arena OC Leaderboards (Phase 6)
-- Persistent OC data only; no private match-state tables are queried.

create index if not exists player_characters_active_overall_rank_idx
  on public.player_characters (overall desc, power_score desc, id)
  where active = true and retired_at is null;
create index if not exists player_characters_active_power_rank_idx
  on public.player_characters (power_score desc, overall desc, id)
  where active = true and retired_at is null;

create or replace function public.get_oc_individual_leaderboard(
  p_sort text default 'overall', p_limit integer default 100, p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception using errcode='42501', message='Authentication required.'; end if;
  if p_sort not in ('overall','power','growth') then raise exception using errcode='22023', message='Invalid OC leaderboard sort.'; end if;
  if p_limit not between 1 and 100 or p_offset < 0 then raise exception using errcode='22023', message='Invalid pagination.'; end if;
  with ranked as (
    select row_number() over (order by
      case when p_sort='overall' then pc.overall end desc nulls last,
      case when p_sort='overall' then pc.power_score end desc nulls last,
      case when p_sort='power' then pc.power_score end desc nulls last,
      case when p_sort='power' then pc.overall end desc nulls last,
      case when p_sort='growth' then pc.overall-pc.starting_overall end desc nulls last,
      case when p_sort='growth' then pc.overall end desc nulls last,
      case when p_sort='growth' then pc.power_score end desc nulls last,
      pc.created_at asc, pc.id asc) as rank,
      pc.id, pc.name, pc.image_url, pc.starting_overall, pc.overall, pc.overall_cap,
      pc.power_score, pc.power_score_cap, pc.overall-pc.starting_overall as growth,
      pc.owner_id, p.username, p.avatar_url, pc.verse_id, v.name as verse_name
    from public.player_characters pc join public.profiles p on p.id=pc.owner_id
      join public.verses v on v.id=pc.verse_id
    where pc.active=true and pc.retired_at is null and p.is_guest=false
  ), page as (select * from ranked order by rank limit p_limit offset p_offset)
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank',rank,'id',id,'name',name,'imageUrl',image_url,'ownerId',owner_id,'ownerUsername',username,
    'ownerAvatarUrl',avatar_url,'verseId',verse_id,'verseName',verse_name,'startingOverall',starting_overall,
    'overall',overall,'overallCap',overall_cap,'powerScore',power_score,'powerScoreCap',power_score_cap,'growth',growth
  ) order by rank),'[]'::jsonb) into result from page;
  return result;
end;
$$;

create or replace function public.get_oc_family_leaderboard(
  p_sort text default 'overall', p_limit integer default 100, p_offset integer default 0
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception using errcode='42501', message='Authentication required.'; end if;
  if p_sort not in ('overall','power','growth') then raise exception using errcode='22023', message='Invalid OC family sort.'; end if;
  if p_limit not between 1 and 100 or p_offset < 0 then raise exception using errcode='22023', message='Invalid pagination.'; end if;
  with eligible as (
    select pc.owner_id, p.username, p.avatar_url, count(*)::integer family_size,
      avg(pc.overall)::numeric avg_overall, avg(pc.power_score)::numeric avg_power_score,
      sum(pc.overall-pc.starting_overall)::bigint total_growth,
      jsonb_agg(jsonb_build_object('id',pc.id,'name',pc.name,'verseId',pc.verse_id,'verseName',v.name,
        'startingOverall',pc.starting_overall,'overall',pc.overall,'powerScore',pc.power_score,
        'growth',pc.overall-pc.starting_overall) order by pc.overall desc,pc.id) family
    from public.player_characters pc join public.profiles p on p.id=pc.owner_id
      join public.verses v on v.id=pc.verse_id
    where pc.active=true and pc.equipped=true and pc.retired_at is null and p.is_guest=false
    group by pc.owner_id,p.username,p.avatar_url having count(*)=3
  ), ranked as (
    select row_number() over (order by
      case when p_sort='overall' then avg_overall end desc nulls last,
      case when p_sort='overall' then avg_power_score end desc nulls last,
      case when p_sort='power' then avg_power_score end desc nulls last,
      case when p_sort='power' then avg_overall end desc nulls last,
      case when p_sort='growth' then total_growth end desc nulls last,
      case when p_sort='growth' then avg_overall end desc nulls last,
      case when p_sort='growth' then avg_power_score end desc nulls last,
      owner_id asc) as rank, * from eligible
  ), page as (select * from ranked order by rank limit p_limit offset p_offset)
  select coalesce(jsonb_agg(jsonb_build_object('rank',rank,'ownerId',owner_id,'username',username,
    'avatarUrl',avatar_url,'familySize',family_size,'avgOverall',avg_overall,'avgPowerScore',avg_power_score,
    'totalGrowth',total_growth,'family',family) order by rank),'[]'::jsonb) into result from page;
  return result;
end;
$$;

revoke all on function public.get_oc_individual_leaderboard(text,integer,integer) from public;
revoke all on function public.get_oc_family_leaderboard(text,integer,integer) from public;
grant execute on function public.get_oc_individual_leaderboard(text,integer,integer) to authenticated;
grant execute on function public.get_oc_family_leaderboard(text,integer,integer) to authenticated;
notify pgrst,'reload schema';
