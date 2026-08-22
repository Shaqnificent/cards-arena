-- Run this file in the Supabase SQL Editor after supabase_profiles.sql.
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  player_one_id uuid not null references public.profiles(id) on delete restrict,
  player_two_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'waiting'
    check (status in ('waiting', 'draft', 'battle', 'completed', 'cancelled')),
  player_one_score integer not null default 0 check (player_one_score >= 0),
  player_two_score integer not null default 0 check (player_two_score >= 0),
  winner_id uuid references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  check (player_one_id <> player_two_id),
  check (winner_id is null or winner_id in (player_one_id, player_two_id))
);

create table public.matchmaking_queue (
  player_id uuid primary key references public.profiles(id) on delete cascade,
  status text not null default 'waiting' check (status in ('waiting', 'matched', 'cancelled')),
  joined_at timestamptz not null default now(),
  matched_match_id uuid references public.matches(id) on delete set null,
  check ((status = 'matched' and matched_match_id is not null) or status <> 'matched')
);

create index matchmaking_queue_waiting_idx
  on public.matchmaking_queue (status, joined_at)
  where status = 'waiting';
create index matches_player_one_status_idx on public.matches (player_one_id, status);
create index matches_player_two_status_idx on public.matches (player_two_id, status);

alter table public.matchmaking_queue enable row level security;
alter table public.matches enable row level security;

create policy "Players can read their own queue entry"
  on public.matchmaking_queue for select to authenticated
  using ((select auth.uid()) = player_id);

create policy "Participants can read their matches"
  on public.matches for select to authenticated
  using ((select auth.uid()) in (player_one_id, player_two_id));

grant select on public.matchmaking_queue, public.matches to authenticated;
revoke insert, update, delete on public.matchmaking_queue from authenticated;
revoke insert, update, delete on public.matches from authenticated;

create or replace function public.find_or_create_match()
returns table (result_status text, match_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  existing_match_id uuid;
  opponent_id uuid;
  created_match_id uuid;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (select 1 from public.profiles where id = caller_id) then
    raise exception 'Player profile required';
  end if;

  -- One narrow transaction lock serializes queue pairing and prevents a waiting
  -- player from being claimed by two simultaneous callers.
  perform pg_advisory_xact_lock(hashtext('anime_arena_matchmaking'));

  select id into existing_match_id
  from public.matches
  where caller_id in (player_one_id, player_two_id)
    and status not in ('completed', 'cancelled')
  order by created_at desc
  limit 1;

  if existing_match_id is not null then
    return query select 'existing_match'::text, existing_match_id;
    return;
  end if;

  select queue.player_id into opponent_id
  from public.matchmaking_queue as queue
  where queue.status = 'waiting'
    and queue.matched_match_id is null
    and queue.player_id <> caller_id
    and not exists (
      select 1 from public.matches as active_match
      where queue.player_id in (active_match.player_one_id, active_match.player_two_id)
        and active_match.status not in ('completed', 'cancelled')
    )
  order by queue.joined_at asc
  limit 1
  for update skip locked;

  if opponent_id is null then
    insert into public.matchmaking_queue (player_id, status, joined_at, matched_match_id)
    values (caller_id, 'waiting', now(), null)
    on conflict (player_id) do update set
      status = 'waiting',
      joined_at = case
        when public.matchmaking_queue.status = 'waiting' then public.matchmaking_queue.joined_at
        else now()
      end,
      matched_match_id = null;

    return query select 'waiting'::text, null::uuid;
    return;
  end if;

  insert into public.matches (player_one_id, player_two_id, status)
  values (opponent_id, caller_id, 'waiting')
  returning id into created_match_id;

  update public.matchmaking_queue
  set status = 'matched', matched_match_id = created_match_id
  where player_id = opponent_id;

  insert into public.matchmaking_queue (player_id, status, joined_at, matched_match_id)
  values (caller_id, 'matched', now(), created_match_id)
  on conflict (player_id) do update set
    status = 'matched', matched_match_id = created_match_id;

  return query select 'matched'::text, created_match_id;
end;
$$;

create or replace function public.cancel_matchmaking()
returns table (result_status text, match_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  existing_match_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  perform pg_advisory_xact_lock(hashtext('anime_arena_matchmaking'));

  select id into existing_match_id
  from public.matches
  where caller_id in (player_one_id, player_two_id)
    and status not in ('completed', 'cancelled')
  order by created_at desc
  limit 1;

  if existing_match_id is not null then
    return query select 'matched'::text, existing_match_id;
    return;
  end if;

  delete from public.matchmaking_queue
  where player_id = caller_id and status = 'waiting';

  return query select 'cancelled'::text, null::uuid;
end;
$$;

revoke all on function public.find_or_create_match() from public;
revoke all on function public.cancel_matchmaking() from public;
grant execute on function public.find_or_create_match() to authenticated;
grant execute on function public.cancel_matchmaking() to authenticated;

-- Ask PostgREST to expose the newly created RPCs immediately.
notify pgrst, 'reload schema';

-- Add only this narrow table to Realtime so waiting clients receive match IDs.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'matchmaking_queue'
  ) then
    alter publication supabase_realtime add table public.matchmaking_queue;
  end if;
end $$;

-- OPTIONAL DEVELOPMENT CLEANUP (run manually only when no test is active):
-- delete from public.matchmaking_queue;
-- delete from public.matches where status in ('waiting', 'draft', 'battle', 'cancelled');
