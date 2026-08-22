-- Anime Arena OC Progression (Phase 2)
-- Run after docs/supabase_oc_foundation.sql.
-- Local battles are currently client-simulated. This migration makes reward
-- issuance and spending transactional/idempotent, but stronger anti-farming
-- and authoritative battle replay remain required before production.

create table if not exists public.local_progression_matches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'active' check (status in ('active', 'completed')),
  player_score integer check (player_score between 0 and 3),
  opponent_score integer check (opponent_score between 0 and 3),
  round_count integer check (round_count between 1 and 5),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (
    (status = 'active' and player_score is null and opponent_score is null and round_count is null and completed_at is null) or
    (status = 'completed' and player_score is not null and opponent_score is not null and round_count is not null and completed_at is not null)
  )
);

create unique index if not exists local_progression_matches_one_active_owner_idx
  on public.local_progression_matches (owner_id) where status = 'active';
create index if not exists local_progression_matches_owner_created_idx
  on public.local_progression_matches (owner_id, created_at desc);

create table if not exists public.oc_progression_rewards (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  source_match_id uuid not null references public.local_progression_matches(id) on delete restrict,
  points integer not null check (points > 0),
  claimed_character_id uuid references public.player_characters(id) on delete restrict,
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint oc_progression_rewards_source_unique unique (source_match_id),
  constraint oc_progression_rewards_claim_check check (
    (claimed_character_id is null and claimed_at is null) or
    (claimed_character_id is not null and claimed_at is not null)
  )
);

create index if not exists oc_progression_rewards_owner_unclaimed_idx
  on public.oc_progression_rewards (owner_id, created_at)
  where claimed_at is null;

create table if not exists public.oc_progression_transactions (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete restrict,
  owner_id uuid not null references public.profiles(id) on delete restrict,
  transaction_type text not null check (transaction_type in ('match_reward', 'overall_upgrade', 'power_upgrade')),
  points_delta integer not null,
  overall_delta integer not null default 0,
  power_delta integer not null default 0,
  source_match_id uuid references public.local_progression_matches(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (points_delta <> 0 or overall_delta <> 0 or power_delta <> 0)
);

create index if not exists oc_progression_transactions_character_created_idx
  on public.oc_progression_transactions (character_id, created_at desc);
create index if not exists oc_progression_transactions_owner_created_idx
  on public.oc_progression_transactions (owner_id, created_at desc);

alter table public.local_progression_matches enable row level security;
alter table public.oc_progression_rewards enable row level security;
alter table public.oc_progression_transactions enable row level security;

drop policy if exists "Owners read local progression matches" on public.local_progression_matches;
create policy "Owners read local progression matches" on public.local_progression_matches
  for select to authenticated using ((select auth.uid()) = owner_id);
drop policy if exists "Owners read OC progression rewards" on public.oc_progression_rewards;
create policy "Owners read OC progression rewards" on public.oc_progression_rewards
  for select to authenticated using ((select auth.uid()) = owner_id);
drop policy if exists "Owners read OC progression transactions" on public.oc_progression_transactions;
create policy "Owners read OC progression transactions" on public.oc_progression_transactions
  for select to authenticated using ((select auth.uid()) = owner_id);

create or replace function public.get_oc_overall_upgrade_cost(p_current_overall integer)
returns integer
language sql
immutable
strict
set search_path = ''
as $$
  select case
    when p_current_overall between 50 and 69 then 1
    when p_current_overall between 70 and 79 then 2
    when p_current_overall between 80 and 89 then 3
    when p_current_overall >= 90 then 4
    else null
  end;
$$;

create or replace function public.start_local_progression_match()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  session_id uuid;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  perform 1 from public.profiles where id = caller_id for update;
  if not found then raise exception using errcode = '23503', message = 'Player profile not found.'; end if;

  select id into session_id from public.local_progression_matches
  where owner_id = caller_id and status = 'active'
  order by created_at desc limit 1 for update;
  if session_id is not null then return session_id; end if;

  insert into public.local_progression_matches (owner_id)
  values (caller_id) returning id into session_id;
  return session_id;
end;
$$;

create or replace function public.complete_local_progression_match(
  p_match_id uuid,
  p_player_score integer,
  p_opponent_score integer,
  p_round_count integer
)
returns table (result_status text, reward_id uuid, points integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  match_row public.local_progression_matches%rowtype;
  existing_reward public.oc_progression_rewards%rowtype;
  created_reward_id uuid;
  reward_points constant integer := 3;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  select * into match_row from public.local_progression_matches
  where id = p_match_id and owner_id = caller_id for update;
  if not found then raise exception using errcode = '42501', message = 'Local progression match not found.'; end if;

  if match_row.status = 'completed' then
    select * into existing_reward from public.oc_progression_rewards where source_match_id = match_row.id;
    return query select 'already_completed'::text, existing_reward.id, existing_reward.points;
    return;
  end if;

  if p_player_score not between 0 and 3 or p_opponent_score not between 0 and 3 or p_round_count not between 1 and 5
    or p_player_score + p_opponent_score > p_round_count
    or (greatest(p_player_score, p_opponent_score) < 3 and p_round_count < 5) then
    raise exception using errcode = '22023', message = 'Invalid completed local match result.';
  end if;

  update public.local_progression_matches set
    status = 'completed', player_score = p_player_score, opponent_score = p_opponent_score,
    round_count = p_round_count, completed_at = now()
  where id = match_row.id;

  if p_player_score > p_opponent_score then
    insert into public.oc_progression_rewards (owner_id, source_match_id, points)
    values (caller_id, match_row.id, reward_points)
    on conflict (source_match_id) do nothing
    returning id into created_reward_id;
    if created_reward_id is null then
      select id into created_reward_id from public.oc_progression_rewards where source_match_id = match_row.id;
    end if;
    return query select 'reward_created'::text, created_reward_id, reward_points;
  else
    return query select 'completed_no_reward'::text, null::uuid, 0;
  end if;
end;
$$;

create or replace function public.claim_oc_progression_reward(p_reward_id uuid, p_character_id uuid)
returns public.player_characters
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  reward_row public.oc_progression_rewards%rowtype;
  character_row public.player_characters%rowtype;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  select * into reward_row from public.oc_progression_rewards
  where id = p_reward_id and owner_id = caller_id for update;
  if not found then raise exception using errcode = '42501', message = 'Progression reward not found or not owned by you.'; end if;
  if reward_row.claimed_at is not null then raise exception using errcode = '23514', message = 'Progression reward has already been claimed.'; end if;

  select * into character_row from public.player_characters
  where id = p_character_id and owner_id = caller_id for update;
  if not found then raise exception using errcode = '42501', message = 'OC not found or not owned by you.'; end if;
  if not character_row.active or character_row.retired_at is not null then
    raise exception using errcode = '22023', message = 'Progression can only be assigned to an active OC.';
  end if;

  update public.player_characters set progression_points = progression_points + reward_row.points
  where id = character_row.id returning * into character_row;
  update public.oc_progression_rewards set claimed_character_id = character_row.id, claimed_at = now()
  where id = reward_row.id;
  insert into public.oc_progression_transactions
    (character_id, owner_id, transaction_type, points_delta, source_match_id)
  values (character_row.id, caller_id, 'match_reward', reward_row.points, reward_row.source_match_id);
  return character_row;
end;
$$;

create or replace function public.upgrade_player_character_overall(p_character_id uuid)
returns public.player_characters
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  character_row public.player_characters%rowtype;
  upgrade_cost integer;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  select * into character_row from public.player_characters
  where id = p_character_id and owner_id = caller_id for update;
  if not found then raise exception using errcode = '42501', message = 'OC not found or not owned by you.'; end if;
  if not character_row.active or character_row.retired_at is not null then raise exception using errcode = '22023', message = 'Only active OCs can be developed.'; end if;
  if character_row.overall >= character_row.overall_cap then raise exception using errcode = '23514', message = 'OVR is already at its cap.'; end if;
  upgrade_cost := public.get_oc_overall_upgrade_cost(character_row.overall);
  if character_row.progression_points < upgrade_cost then raise exception using errcode = '23514', message = 'Not enough progression points for this OVR upgrade.'; end if;

  update public.player_characters set overall = overall + 1, progression_points = progression_points - upgrade_cost
  where id = character_row.id returning * into character_row;
  insert into public.oc_progression_transactions
    (character_id, owner_id, transaction_type, points_delta, overall_delta)
  values (character_row.id, caller_id, 'overall_upgrade', -upgrade_cost, 1);
  return character_row;
end;
$$;

create or replace function public.upgrade_player_character_power(p_character_id uuid)
returns public.player_characters
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  character_row public.player_characters%rowtype;
  power_gain integer;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  select * into character_row from public.player_characters
  where id = p_character_id and owner_id = caller_id for update;
  if not found then raise exception using errcode = '42501', message = 'OC not found or not owned by you.'; end if;
  if not character_row.active or character_row.retired_at is not null then raise exception using errcode = '22023', message = 'Only active OCs can be developed.'; end if;
  if character_row.power_score >= character_row.power_score_cap then raise exception using errcode = '23514', message = 'Battle Power is already at its cap.'; end if;
  if character_row.progression_points < 1 then raise exception using errcode = '23514', message = 'Not enough progression points for this Power upgrade.'; end if;
  power_gain := least(50, character_row.power_score_cap - character_row.power_score);

  update public.player_characters set power_score = power_score + power_gain, progression_points = progression_points - 1
  where id = character_row.id returning * into character_row;
  insert into public.oc_progression_transactions
    (character_id, owner_id, transaction_type, points_delta, power_delta)
  values (character_row.id, caller_id, 'power_upgrade', -1, power_gain);
  return character_row;
end;
$$;

revoke all on public.local_progression_matches, public.oc_progression_rewards, public.oc_progression_transactions from public, anon, authenticated;
grant select on public.local_progression_matches, public.oc_progression_rewards, public.oc_progression_transactions to authenticated;

revoke all on function public.get_oc_overall_upgrade_cost(integer) from public;
revoke all on function public.start_local_progression_match() from public;
revoke all on function public.complete_local_progression_match(uuid, integer, integer, integer) from public;
revoke all on function public.claim_oc_progression_reward(uuid, uuid) from public;
revoke all on function public.upgrade_player_character_overall(uuid) from public;
revoke all on function public.upgrade_player_character_power(uuid) from public;
grant execute on function public.get_oc_overall_upgrade_cost(integer) to authenticated;
grant execute on function public.start_local_progression_match() to authenticated;
grant execute on function public.complete_local_progression_match(uuid, integer, integer, integer) to authenticated;
grant execute on function public.claim_oc_progression_reward(uuid, uuid) to authenticated;
grant execute on function public.upgrade_player_character_overall(uuid) to authenticated;
grant execute on function public.upgrade_player_character_power(uuid) to authenticated;

notify pgrst, 'reload schema';
