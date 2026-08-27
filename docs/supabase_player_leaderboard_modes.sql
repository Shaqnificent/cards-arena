-- Anime Arena: combined player leaderboard modes.
-- Run after docs/supabase_direct_challenges.sql.
-- This is display-only: it does not change ranked profile counters, BP,
-- progression, or Boon rewards.

begin;

create or replace function public.get_player_leaderboard(
  p_mode text default 'all',
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_mode text := lower(btrim(coalesce(p_mode, '')));
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if normalized_mode not in ('all', 'ranked', 'challenges') then
    raise exception using errcode = '22023', message = 'Invalid leaderboard mode';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using errcode = '22023', message = 'Leaderboard limit must be between 1 and 100';
  end if;

  return coalesce((
    with challenge_participants as (
      select m.player_one_id as player_id, m.winner_id
      from public.matches m
      where m.match_source = 'direct_challenge'
        and m.status = 'completed'
        and m.completed_at is not null
        and m.winner_id is not null

      union all

      select m.player_two_id as player_id, m.winner_id
      from public.matches m
      where m.match_source = 'direct_challenge'
        and m.status = 'completed'
        and m.completed_at is not null
        and m.winner_id is not null
    ),
    challenge_totals as (
      select
        cp.player_id,
        count(*) filter (where cp.winner_id = cp.player_id)::integer as wins,
        count(*) filter (where cp.winner_id <> cp.player_id)::integer as losses
      from challenge_participants cp
      group by cp.player_id
    ),
    mode_totals as (
      select
        p.id,
        p.username,
        p.avatar_url,
        p.avatar_mode,
        p.avatar_bg_color,
        p.avatar_text_color,
        p.is_system_player,
        case normalized_mode
          when 'ranked' then p.wins
          when 'challenges' then coalesce(ct.wins, 0)
          else p.wins + coalesce(ct.wins, 0)
        end::integer as wins,
        case normalized_mode
          when 'ranked' then p.losses
          when 'challenges' then coalesce(ct.losses, 0)
          else p.losses + coalesce(ct.losses, 0)
        end::integer as losses
      from public.profiles p
      left join challenge_totals ct on ct.player_id = p.id
      where p.is_guest = false
    ),
    eligible as (
      select mt.*, (mt.wins + mt.losses)::integer as games_played
      from mode_totals mt
      where mt.wins + mt.losses > 0
    ),
    ranked as (
      select
        e.*,
        row_number() over (
          order by
            e.wins::numeric / nullif(e.games_played, 0) desc,
            e.wins desc,
            e.games_played desc,
            e.username asc,
            e.id asc
        )::integer as result_rank
      from eligible e
    ),
    limited as (
      select *
      from ranked
      order by result_rank
      limit p_limit
    )
    select jsonb_agg(
      jsonb_build_object(
        'id', l.id,
        'username', l.username,
        'avatarUrl', l.avatar_url,
        'avatarMode', l.avatar_mode,
        'avatarBgColor', l.avatar_bg_color,
        'avatarTextColor', l.avatar_text_color,
        'wins', l.wins,
        'losses', l.losses,
        'gamesPlayed', l.games_played,
        'winRate', round((l.wins::numeric * 100) / l.games_played, 1),
        'rank', l.result_rank,
        'isSystemPlayer', l.is_system_player
      )
      order by l.result_rank
    )
    from limited l
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_player_leaderboard(text, integer)
from public, anon, authenticated;
grant execute on function public.get_player_leaderboard(text, integer)
to authenticated;

notify pgrst, 'reload schema';

commit;
