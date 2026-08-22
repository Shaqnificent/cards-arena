-- Run after supabase_profiles.sql, supabase_characters.sql, and supabase_matchmaking.sql.
alter table public.matches
  add column if not exists current_draft_position integer not null default 0 check (current_draft_position between 0 and 10),
  add column if not exists draft_state text not null default 'preparing' check (draft_state in ('preparing', 'decision', 'bidding', 'complete')),
  add column if not exists current_bid integer check (current_bid is null or current_bid >= 0),
  add column if not exists current_bidder_id uuid references public.profiles(id) on delete restrict,
  add column if not exists priority_player_id uuid references public.profiles(id) on delete restrict,
  add column if not exists tie_priority_player_id uuid references public.profiles(id) on delete restrict,
  add column if not exists action_version bigint not null default 0,
  add column if not exists updated_at timestamptz not null default now();

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'matches_draft_actor_check' and conrelid = 'public.matches'::regclass) then
    alter table public.matches add constraint matches_draft_actor_check check (
      (current_bidder_id is null or current_bidder_id in (player_one_id, player_two_id)) and
      (priority_player_id is null or priority_player_id in (player_one_id, player_two_id)) and
      (tie_priority_player_id is null or tie_priority_player_id in (player_one_id, player_two_id))
    );
  end if;
end $$;

create table if not exists public.match_players (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete restrict,
  player_number integer not null check (player_number in (1, 2)),
  balance integer not null default 20 check (balance >= 0),
  created_at timestamptz not null default now(),
  unique (match_id, player_id),
  unique (match_id, player_number)
);

create table if not exists public.match_characters (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  character_id bigint not null references public.characters(id) on delete restrict,
  draft_position integer not null check (draft_position between 1 and 10),
  owner_player_id uuid references public.profiles(id) on delete restrict,
  purchase_price integer check (purchase_price is null or purchase_price >= 0),
  assigned_at timestamptz,
  unique (match_id, draft_position),
  unique (match_id, character_id),
  check (
    (owner_player_id is null and purchase_price is null and assigned_at is null) or
    (owner_player_id is not null and purchase_price is not null and assigned_at is not null)
  )
);

create index if not exists match_players_match_idx on public.match_players (match_id);
create index if not exists match_characters_match_owner_idx on public.match_characters (match_id, owner_player_id);

alter table public.match_players enable row level security;
alter table public.match_characters enable row level security;

drop policy if exists "Participants can read match players" on public.match_players;
create policy "Participants can read match players"
  on public.match_players for select to authenticated
  using (exists (
    select 1 from public.matches
    where matches.id = match_players.match_id
      and (select auth.uid()) in (matches.player_one_id, matches.player_two_id)
  ));

-- During the draft, clients can read assigned cards and the current card only.
-- This avoids revealing future pool positions before they become active.
drop policy if exists "Participants can read revealed match characters" on public.match_characters;
create policy "Participants can read revealed match characters"
  on public.match_characters for select to authenticated
  using (exists (
    select 1 from public.matches
    where matches.id = match_characters.match_id
      and (select auth.uid()) in (matches.player_one_id, matches.player_two_id)
      and (
        match_characters.owner_player_id is not null or
        match_characters.draft_position = matches.current_draft_position or
        matches.status in ('battle', 'completed')
      )
  ));

grant select on public.match_players, public.match_characters to authenticated;
revoke insert, update, delete on public.match_players, public.match_characters from authenticated;

create or replace function public.advance_online_draft(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  match_row public.matches%rowtype;
  player_one_balance integer;
  player_two_balance integer;
  player_one_count integer;
  player_two_count integer;
  assigned_count integer;
  free_player_id uuid;
  next_priority uuid;
  next_tie_priority uuid;
begin
  select * into match_row from public.matches where id = p_match_id for update;
  if not found then raise exception 'Match not found'; end if;

  select count(*) filter (where owner_player_id = match_row.player_one_id),
         count(*) filter (where owner_player_id = match_row.player_two_id)
  into player_one_count, player_two_count
  from public.match_characters where match_id = p_match_id;

  if player_one_count = 5 or player_two_count = 5 then
    free_player_id := case when player_one_count = 5 then match_row.player_two_id else match_row.player_one_id end;
    update public.match_characters
    set owner_player_id = free_player_id, purchase_price = 0, assigned_at = now()
    where match_id = p_match_id and owner_player_id is null;
  end if;

  select count(*) filter (where owner_player_id = match_row.player_one_id),
         count(*) filter (where owner_player_id = match_row.player_two_id),
         count(*) filter (where owner_player_id is not null)
  into player_one_count, player_two_count, assigned_count
  from public.match_characters where match_id = p_match_id;

  if assigned_count = 10 then
    if player_one_count <> 5 or player_two_count <> 5 then raise exception 'Invalid final roster state'; end if;
    update public.matches set status = 'battle', draft_state = 'complete', current_bid = null,
      current_bidder_id = null, priority_player_id = null, current_draft_position = 10,
      action_version = action_version + 1, updated_at = now()
    where id = p_match_id;
    return;
  end if;

  if match_row.current_draft_position >= 10 then raise exception 'Draft pool exhausted'; end if;
  select balance into player_one_balance from public.match_players where match_id = p_match_id and player_number = 1;
  select balance into player_two_balance from public.match_players where match_id = p_match_id and player_number = 2;

  next_tie_priority := match_row.tie_priority_player_id;
  if player_one_balance > player_two_balance then next_priority := match_row.player_one_id;
  elsif player_two_balance > player_one_balance then next_priority := match_row.player_two_id;
  else
    next_priority := match_row.tie_priority_player_id;
    next_tie_priority := case when next_priority = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  end if;

  update public.matches set current_draft_position = current_draft_position + 1,
    draft_state = 'decision', current_bid = null, current_bidder_id = null,
    priority_player_id = next_priority, tie_priority_player_id = next_tie_priority,
    action_version = action_version + 1, updated_at = now()
  where id = p_match_id;
end;
$$;

revoke all on function public.advance_online_draft(uuid) from public;

create or replace function public.initialize_match_draft(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  active_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status in ('draft', 'battle', 'completed') then return; end if;
  if match_row.status <> 'waiting' then raise exception 'Match cannot be initialized'; end if;

  select count(*) into active_count from public.characters where active = true;
  if active_count < 10 then raise exception 'At least 10 active fighters are required to start an online draft'; end if;

  insert into public.match_players (match_id, player_id, player_number, balance) values
    (p_match_id, match_row.player_one_id, 1, 20), (p_match_id, match_row.player_two_id, 2, 20)
  on conflict (match_id, player_id) do nothing;

  insert into public.match_characters (match_id, character_id, draft_position)
  select p_match_id, selected.id, row_number() over ()::integer
  from (select id from public.characters where active = true order by random() limit 10) selected
  on conflict do nothing;

  if (select count(*) from public.match_characters where match_id = p_match_id) <> 10 then
    raise exception 'Unable to create a complete unique draft pool';
  end if;

  update public.matches set status = 'draft', current_draft_position = 1, draft_state = 'decision',
    current_bid = null, current_bidder_id = null, priority_player_id = match_row.player_one_id,
    tie_priority_player_id = match_row.player_two_id, action_version = action_version + 1, updated_at = now()
  where id = p_match_id;
end;
$$;

create or replace function public.draft_bid(p_match_id uuid, p_amount integer)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid(); match_row public.matches%rowtype; caller_balance integer; caller_team_size integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'draft' then raise exception 'Draft is not active'; end if;
  select balance into caller_balance from public.match_players where match_id = p_match_id and player_id = caller_id;
  select count(*) into caller_team_size from public.match_characters where match_id = p_match_id and owner_player_id = caller_id;
  if caller_team_size >= 5 then raise exception 'Roster is complete'; end if;
  if p_amount is null or p_amount < 0 or p_amount > caller_balance then raise exception 'Invalid bid amount'; end if;

  if match_row.draft_state = 'decision' then
    if caller_id <> match_row.priority_player_id then raise exception 'Only the priority player may open bidding'; end if;
  elsif match_row.draft_state = 'bidding' then
    if caller_id = match_row.current_bidder_id then raise exception 'Leading bidder must wait'; end if;
    if p_amount <= match_row.current_bid then raise exception 'Bid must exceed current bid'; end if;
  else raise exception 'Bidding is unavailable';
  end if;

  update public.matches set draft_state = 'bidding', current_bid = p_amount, current_bidder_id = caller_id,
    action_version = action_version + 1, updated_at = now() where id = p_match_id;
end;
$$;

create or replace function public.draft_pass(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid(); match_row public.matches%rowtype; receiver_id uuid; receiver_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'draft' or match_row.draft_state <> 'decision' or caller_id <> match_row.priority_player_id then raise exception 'Pass is unavailable'; end if;
  receiver_id := case when caller_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  select count(*) into receiver_count from public.match_characters where match_id = p_match_id and owner_player_id = receiver_id;
  if receiver_count >= 5 then raise exception 'Opponent roster is complete'; end if;
  update public.match_characters set owner_player_id = receiver_id, purchase_price = 0, assigned_at = now()
  where match_id = p_match_id and draft_position = match_row.current_draft_position and owner_player_id is null;
  if not found then raise exception 'Current character already assigned'; end if;
  perform public.advance_online_draft(p_match_id);
end;
$$;

create or replace function public.draft_fold(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid(); match_row public.matches%rowtype; winner_balance integer; winner_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'draft' or match_row.draft_state <> 'bidding' or match_row.current_bidder_id is null or caller_id = match_row.current_bidder_id then raise exception 'Fold is unavailable'; end if;
  select balance into winner_balance from public.match_players where match_id = p_match_id and player_id = match_row.current_bidder_id;
  select count(*) into winner_count from public.match_characters where match_id = p_match_id and owner_player_id = match_row.current_bidder_id;
  if winner_balance < match_row.current_bid or winner_count >= 5 then raise exception 'Winning assignment is invalid'; end if;
  update public.match_players set balance = balance - match_row.current_bid
  where match_id = p_match_id and player_id = match_row.current_bidder_id;
  update public.match_characters set owner_player_id = match_row.current_bidder_id,
    purchase_price = match_row.current_bid, assigned_at = now()
  where match_id = p_match_id and draft_position = match_row.current_draft_position and owner_player_id is null;
  if not found then raise exception 'Current character already assigned'; end if;
  perform public.advance_online_draft(p_match_id);
end;
$$;

revoke all on function public.initialize_match_draft(uuid) from public;
revoke all on function public.draft_bid(uuid, integer) from public;
revoke all on function public.draft_pass(uuid) from public;
revoke all on function public.draft_fold(uuid) from public;
grant execute on function public.initialize_match_draft(uuid) to authenticated;
grant execute on function public.draft_bid(uuid, integer) to authenticated;
grant execute on function public.draft_pass(uuid) to authenticated;
grant execute on function public.draft_fold(uuid) to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'matches') then
    alter publication supabase_realtime add table public.matches;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'match_players') then
    alter publication supabase_realtime add table public.match_players;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'match_characters') then
    alter publication supabase_realtime add table public.match_characters;
  end if;
end $$;

notify pgrst, 'reload schema';

-- DEVELOPMENT RESET ONLY (does not touch profiles, characters, or verses):
-- delete from public.matchmaking_queue;
-- delete from public.matches where status in ('waiting', 'draft', 'battle', 'cancelled');
