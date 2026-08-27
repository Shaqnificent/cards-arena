-- Anime Arena: Direct Player Challenges (V1, unranked)
-- Run after the current matchmaking, profile identity, Administrator, and Boon migrations.
-- This migration is intentionally additive: accepted invitations enter the canonical
-- initiative -> OC selection -> draft -> preparation -> battle flow.

begin;

-- 1. Give every match an authoritative source. Existing matches remain normal
-- matchmaking unless they are already registered as Administrator matches.
alter table public.matches
  add column if not exists match_source text not null default 'matchmaking';

alter table public.matches drop constraint if exists matches_match_source_check;
alter table public.matches add constraint matches_match_source_check
  check (match_source in ('matchmaking', 'direct_challenge', 'administrator'));

do $migration$
begin
  if to_regclass('public.administrator_matches') is not null then
    execute $sql$
      update public.matches m
      set match_source = 'administrator'
      from public.administrator_matches a
      where a.match_id = m.id
        and m.match_source <> 'administrator'
    $sql$;
  end if;
end
$migration$;

create or replace function public.mark_administrator_match_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.matches
  set match_source = 'administrator'
  where id = new.match_id;
  return new;
end;
$$;

do $migration$
begin
  if to_regclass('public.administrator_matches') is not null then
    execute 'drop trigger if exists administrator_match_source_sync on public.administrator_matches';
    execute 'create trigger administrator_match_source_sync after insert on public.administrator_matches for each row execute function public.mark_administrator_match_source()';
  end if;
end
$migration$;

-- 2. Invitation lifecycle. Profile and match identifiers are UUID in the current schema.
create table if not exists public.player_challenges (
  id uuid primary key default gen_random_uuid(),
  challenger_id uuid not null references public.profiles(id) on delete cascade,
  challenged_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '60 seconds'),
  responded_at timestamptz,
  match_id uuid references public.matches(id) on delete set null,
  constraint player_challenges_distinct_players check (challenger_id <> challenged_id),
  constraint player_challenges_status_check check (status in ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  constraint player_challenges_expiry_check check (expires_at > created_at),
  constraint player_challenges_acceptance_check check (
    (status = 'accepted' and responded_at is not null and match_id is not null)
    or status <> 'accepted'
  )
);

create index if not exists player_challenges_challenger_idx
  on public.player_challenges (challenger_id, status, expires_at desc);
create index if not exists player_challenges_challenged_idx
  on public.player_challenges (challenged_id, status, expires_at desc);
create index if not exists player_challenges_pending_expiry_idx
  on public.player_challenges (expires_at) where status = 'pending';

-- Database backstop for duplicate and crossed invitations. The RPC's shared
-- advisory lock additionally enforces one active invitation per participant.
create unique index if not exists player_challenges_pending_pair_uidx
  on public.player_challenges (
    least(challenger_id, challenged_id),
    greatest(challenger_id, challenged_id)
  ) where status = 'pending';
create unique index if not exists player_challenges_one_incoming_uidx
  on public.player_challenges (challenged_id) where status = 'pending';

alter table public.player_challenges enable row level security;
drop policy if exists player_challenges_participant_read on public.player_challenges;
create policy player_challenges_participant_read
on public.player_challenges for select
to authenticated
using (auth.uid() = challenger_id or auth.uid() = challenged_id);

revoke all on table public.player_challenges from public, anon, authenticated;
grant select on table public.player_challenges to authenticated;

-- Realtime observes the same participant-only RLS policy. Add only when the
-- publication is not configured FOR ALL TABLES and the relation is not present.
do $migration$
begin
  if exists (
    select 1 from pg_publication p
    where p.pubname = 'supabase_realtime' and not p.puballtables
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'player_challenges'
  ) then
    alter publication supabase_realtime add table public.player_challenges;
  end if;
end
$migration$;

-- 3. Shared helpers. These functions are private and schema-qualified.
create or replace function public.expire_player_challenges()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.player_challenges
  set status = 'expired', responded_at = now()
  where status = 'pending' and expires_at <= now();
$$;

create or replace function public.player_has_active_match(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.matches m
    where p_player_id in (m.player_one_id, m.player_two_id)
      and m.status not in ('completed', 'cancelled')
  );
$$;

create or replace function public.player_is_waiting_for_matchmaking(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.matchmaking_queue q
    -- A historical matched queue row may remain after its match completes; the
    -- active-match check is authoritative for that case. Only a live waiting
    -- row conflicts with a new direct challenge.
    where q.player_id = p_player_id and q.status = 'waiting'
  );
$$;

create or replace function public.player_challenge_summary(p_challenge_id uuid, p_viewer_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', c.id,
    'status', c.status,
    'direction', case when c.challenger_id = p_viewer_id then 'outgoing' else 'incoming' end,
    'challengerId', c.challenger_id,
    'challengedId', c.challenged_id,
    'createdAt', c.created_at,
    'expiresAt', c.expires_at,
    'respondedAt', c.responded_at,
    'matchId', c.match_id,
    'counterpart', jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'avatarUrl', p.avatar_url,
      'avatarMode', coalesce(p.avatar_mode, case when p.avatar_url is null then 'initial' else 'google' end),
      'avatarBgColor', coalesce(p.avatar_bg_color, '#7C3AED'),
      'avatarTextColor', coalesce(p.avatar_text_color, '#FFFFFF')
    )
  )
  from public.player_challenges c
  join public.profiles p on p.id = case
    when c.challenger_id = p_viewer_id then c.challenged_id
    else c.challenger_id
  end
  where c.id = p_challenge_id
    and p_viewer_id in (c.challenger_id, c.challenged_id);
$$;

-- Initial/reconnect read. Opportunistic expiry means no scheduler is required.
create or replace function public.get_my_pending_player_challenge()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  challenge_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  perform public.expire_player_challenges();

  select c.id into challenge_id
  from public.player_challenges c
  where caller_id in (c.challenger_id, c.challenged_id)
    and c.status = 'pending'
    and c.expires_at > now()
  order by c.created_at desc
  limit 1;

  if challenge_id is null then return null; end if;
  return public.player_challenge_summary(challenge_id, caller_id);
end;
$$;

-- 4. Send. The same global lock used by matchmaking serializes challenge
-- creation/acceptance with queue match creation and prevents crossed races.
create or replace function public.send_player_challenge(p_challenged_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  caller_profile public.profiles%rowtype;
  challenged_profile public.profiles%rowtype;
  existing public.player_challenges%rowtype;
  created public.player_challenges%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if p_challenged_id is null or p_challenged_id = caller_id then
    raise exception 'You cannot challenge yourself';
  end if;

  perform pg_advisory_xact_lock(hashtext('anime_arena_matchmaking'));
  perform public.expire_player_challenges();

  select * into caller_profile from public.profiles where id = caller_id for update;
  select * into challenged_profile from public.profiles where id = p_challenged_id for update;
  if caller_profile.id is null or caller_profile.is_guest or caller_profile.is_system_player then
    raise exception 'Your account is not eligible for direct challenges';
  end if;
  if challenged_profile.id is null or challenged_profile.is_guest or challenged_profile.is_system_player then
    raise exception 'This player is not eligible for direct challenges';
  end if;

  if public.player_has_active_match(caller_id)
    or public.player_is_waiting_for_matchmaking(caller_id) then
    raise exception 'Finish or cancel your current match activity first';
  end if;
  if public.player_has_active_match(p_challenged_id)
    or public.player_is_waiting_for_matchmaking(p_challenged_id) then
    raise exception 'Player is currently unavailable';
  end if;

  select * into existing
  from public.player_challenges c
  where c.status = 'pending'
    and caller_id in (c.challenger_id, c.challenged_id)
  order by c.created_at desc limit 1;
  if existing.id is not null then
    if existing.challenger_id = caller_id and existing.challenged_id = p_challenged_id then
      return public.player_challenge_summary(existing.id, caller_id);
    end if;
    raise exception 'You already have a pending challenge';
  end if;

  select * into existing
  from public.player_challenges c
  where c.status = 'pending'
    and p_challenged_id in (c.challenger_id, c.challenged_id)
  order by c.created_at desc limit 1;
  if existing.id is not null then
    raise exception 'Player already has a pending challenge';
  end if;

  insert into public.player_challenges (challenger_id, challenged_id, expires_at)
  values (caller_id, p_challenged_id, now() + interval '60 seconds')
  returning * into created;

  return public.player_challenge_summary(created.id, caller_id);
end;
$$;

-- 5. Accept. The match is created exactly once inside this transaction and
-- starts at the canonical initiative phase. No queue entry or Administrator
-- fallback is involved.
create or replace function public.accept_player_challenge(p_challenge_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  challenge_row public.player_challenges%rowtype;
  challenger_profile public.profiles%rowtype;
  challenged_profile public.profiles%rowtype;
  created_match_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  perform pg_advisory_xact_lock(hashtext('anime_arena_matchmaking'));
  perform public.expire_player_challenges();

  select * into challenge_row
  from public.player_challenges
  where id = p_challenge_id
  for update;

  if challenge_row.id is null or challenge_row.challenged_id <> caller_id then
    raise exception 'Challenge unavailable';
  end if;
  if challenge_row.status = 'accepted' and challenge_row.match_id is not null then
    return jsonb_build_object('status', 'accepted', 'matchId', challenge_row.match_id);
  end if;
  if challenge_row.status <> 'pending' or challenge_row.expires_at <= now() then
    raise exception 'Challenge is no longer active';
  end if;

  select * into challenger_profile from public.profiles where id = challenge_row.challenger_id for update;
  select * into challenged_profile from public.profiles where id = challenge_row.challenged_id for update;

  if challenger_profile.id is null or challenged_profile.id is null
    or challenger_profile.is_guest or challenged_profile.is_guest
    or challenger_profile.is_system_player or challenged_profile.is_system_player
    or public.player_has_active_match(challenge_row.challenger_id)
    or public.player_has_active_match(challenge_row.challenged_id)
    or public.player_is_waiting_for_matchmaking(challenge_row.challenger_id)
    or public.player_is_waiting_for_matchmaking(challenge_row.challenged_id) then
    update public.player_challenges
    set status = 'cancelled', responded_at = now()
    where id = challenge_row.id;
    return jsonb_build_object('status', 'unavailable', 'matchId', null);
  end if;

  insert into public.matches (
    player_one_id, player_two_id, status, started_at, match_source
  ) values (
    challenge_row.challenger_id, challenge_row.challenged_id,
    'initiative', now(), 'direct_challenge'
  ) returning id into created_match_id;

  update public.player_challenges
  set status = 'accepted', responded_at = now(), match_id = created_match_id
  where id = challenge_row.id and status = 'pending';

  return jsonb_build_object('status', 'accepted', 'matchId', created_match_id);
end;
$$;

create or replace function public.decline_player_challenge(p_challenge_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare caller_id uuid := auth.uid(); challenge_row public.player_challenges%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  perform public.expire_player_challenges();
  select * into challenge_row from public.player_challenges where id = p_challenge_id for update;
  if challenge_row.id is null or challenge_row.challenged_id <> caller_id then raise exception 'Challenge unavailable'; end if;
  if challenge_row.status <> 'pending' then raise exception 'Challenge is no longer active'; end if;
  update public.player_challenges set status = 'declined', responded_at = now() where id = challenge_row.id;
  return jsonb_build_object('status', 'declined', 'matchId', null);
end;
$$;

create or replace function public.cancel_player_challenge(p_challenge_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare caller_id uuid := auth.uid(); challenge_row public.player_challenges%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  perform public.expire_player_challenges();
  select * into challenge_row from public.player_challenges where id = p_challenge_id for update;
  if challenge_row.id is null or challenge_row.challenger_id <> caller_id then raise exception 'Challenge unavailable'; end if;
  if challenge_row.status <> 'pending' then raise exception 'Challenge is no longer active'; end if;
  update public.player_challenges set status = 'cancelled', responded_at = now() where id = challenge_row.id;
  return jsonb_build_object('status', 'cancelled', 'matchId', null);
end;
$$;

-- 6. Unranked completion safeguards. The canonical resolver marks a match
-- complete before it updates profile W/L. This transaction-local marker lets a
-- narrow profile trigger preserve ranked statistics and currency for direct
-- challenges. This is also an independent backstop for cached function plans.
create or replace function public.mark_direct_challenge_completion_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.match_source = 'direct_challenge'
    and new.status = 'completed'
    and old.status is distinct from new.status then
    perform set_config('anime_arena.unranked_match_id', new.id::text, true);
  end if;
  return new;
end;
$$;

drop trigger if exists direct_challenge_completion_context on public.matches;
create trigger direct_challenge_completion_context
before update of status on public.matches
for each row execute function public.mark_direct_challenge_completion_context();

create or replace function public.preserve_ranked_profile_stats_for_direct_challenge()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare context_match_id uuid;
begin
  begin
    context_match_id := nullif(current_setting('anime_arena.unranked_match_id', true), '')::uuid;
  exception when invalid_text_representation then
    context_match_id := null;
  end;

  if context_match_id is not null and exists (
    select 1 from public.matches m
    where m.id = context_match_id
      and m.match_source = 'direct_challenge'
      and new.id in (m.player_one_id, m.player_two_id)
  ) then
    new.wins := old.wins;
    new.losses := old.losses;
    new.boon_points := old.boon_points;
  end if;
  return new;
end;
$$;

drop trigger if exists preserve_direct_challenge_ranked_stats on public.profiles;
create trigger preserve_direct_challenge_ranked_stats
before update of wins, losses, boon_points on public.profiles
for each row execute function public.preserve_ranked_profile_stats_for_direct_challenge();

-- A source-aware reward snapshot is always zero, even if an older already-cached
-- battle plan still resolves the renamed canonical reward function by OID.
create or replace function public.zero_direct_challenge_reward_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.match_source = 'direct_challenge'
    and new.boon_rewards_granted_at is not null then
    new.player_one_boon_reward := 0;
    new.player_two_boon_reward := 0;
  end if;
  return new;
end;
$$;

drop trigger if exists zero_direct_challenge_rewards on public.matches;
create trigger zero_direct_challenge_rewards
before update of player_one_boon_reward, player_two_boon_reward, boon_rewards_granted_at
on public.matches
for each row execute function public.zero_direct_challenge_reward_snapshot();

-- Preserve the installed canonical reward implementation under a private name,
-- then keep its public signature as a source-aware router. Reruns do not rename
-- the wrapper again.
do $migration$
begin
  if to_regprocedure('public.grant_ranked_match_boon_rewards_ranked_only(uuid)') is null then
    if to_regprocedure('public.grant_ranked_match_boon_rewards(uuid)') is null then
      raise exception 'Install the current Boon reward migration before Direct Challenges';
    end if;
    alter function public.grant_ranked_match_boon_rewards(uuid)
      rename to grant_ranked_match_boon_rewards_ranked_only;
  end if;
end
$migration$;

create or replace function public.grant_ranked_match_boon_rewards(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare match_row public.matches%rowtype; granted_at_value timestamptz;
begin
  select * into match_row from public.matches where id = p_match_id for update;
  if not found then raise exception 'Match unavailable'; end if;

  if match_row.match_source <> 'direct_challenge' then
    return public.grant_ranked_match_boon_rewards_ranked_only(p_match_id);
  end if;
  if match_row.status <> 'completed' or match_row.completed_at is null then
    raise exception 'Boon Points require a completed match';
  end if;
  if match_row.boon_rewards_granted_at is not null then
    return jsonb_build_object(
      'playerOneReward', coalesce(match_row.player_one_boon_reward, 0),
      'playerTwoReward', coalesce(match_row.player_two_boon_reward, 0),
      'grantedAt', match_row.boon_rewards_granted_at
    );
  end if;

  granted_at_value := now();
  update public.matches
  set player_one_boon_reward = 0,
      player_two_boon_reward = 0,
      boon_rewards_granted_at = granted_at_value
  where id = p_match_id;
  return jsonb_build_object(
    'playerOneReward', 0,
    'playerTwoReward', 0,
    'grantedAt', granted_at_value
  );
end;
$$;

-- 7. RPC permissions. No direct table mutation is granted to browsers.
revoke all on function public.mark_administrator_match_source() from public, anon, authenticated;
revoke all on function public.expire_player_challenges() from public, anon, authenticated;
revoke all on function public.player_has_active_match(uuid) from public, anon, authenticated;
revoke all on function public.player_is_waiting_for_matchmaking(uuid) from public, anon, authenticated;
revoke all on function public.player_challenge_summary(uuid, uuid) from public, anon, authenticated;
revoke all on function public.zero_direct_challenge_reward_snapshot() from public, anon, authenticated;
revoke all on function public.grant_ranked_match_boon_rewards_ranked_only(uuid) from public, anon, authenticated;
revoke all on function public.grant_ranked_match_boon_rewards(uuid) from public, anon, authenticated;
revoke all on function public.get_my_pending_player_challenge() from public, anon;
revoke all on function public.send_player_challenge(uuid) from public, anon;
revoke all on function public.accept_player_challenge(uuid) from public, anon;
revoke all on function public.decline_player_challenge(uuid) from public, anon;
revoke all on function public.cancel_player_challenge(uuid) from public, anon;

grant execute on function public.get_my_pending_player_challenge() to authenticated;
grant execute on function public.send_player_challenge(uuid) to authenticated;
grant execute on function public.accept_player_challenge(uuid) to authenticated;
grant execute on function public.decline_player_challenge(uuid) to authenticated;
grant execute on function public.cancel_player_challenge(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
