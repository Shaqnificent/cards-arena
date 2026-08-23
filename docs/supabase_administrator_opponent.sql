-- Anime Arena persistent Administrator opponent
-- Run after the current matchmaking, RPS, OC selection/type, online draft,
-- OC preparation, battle integration, and leaderboard migrations.
-- Actual project ID types used here:
-- profiles/matches/player_characters/match_characters = uuid
-- characters/verses = bigint

-- 1. Persistent, publicly identifiable system profile.
alter table public.profiles
  add column if not exists is_system_player boolean not null default false;

create unique index if not exists profiles_single_system_player_idx
  on public.profiles ((is_system_player))
  where is_system_player = true;

-- The profile FK requires an auth.users row. This deterministic account has no
-- identity row and an unguessable password, so it cannot be used to sign in.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  is_anonymous
)
values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', 'administrator@anime-arena.invalid',
  crypt(gen_random_uuid()::text, gen_salt('bf')), now(),
  '{"provider":"system","providers":[]}'::jsonb,
  '{"full_name":"Administrator"}'::jsonb,
  now(), now(), '', '', '', '', false
)
on conflict (id) do nothing;

insert into public.profiles (id, username, avatar_url, is_guest, wins, losses, is_system_player)
values ('00000000-0000-4000-8000-000000000001', 'Administrator', null, false, 0, 0, true)
on conflict (id) do update set
  username = 'Administrator',
  is_guest = false,
  is_system_player = true;

create table if not exists public.administrator_config (
  singleton boolean primary key default true check (singleton),
  player_id uuid not null unique references public.profiles(id) on delete restrict,
  match_timeout_seconds integer not null default 12 check (match_timeout_seconds between 5 and 120),
  -- Centralized OC-first strategy tuning. Synergy can swing close choices, but
  -- the reasonable OVR gap prevents it from overruling a major strength loss.
  oc_draft_synergy_bonus integer not null default 3 check (oc_draft_synergy_bonus between 0 and 10),
  oc_same_verse_density_bonus integer not null default 2 check (oc_same_verse_density_bonus between 0 and 10),
  oc_reasonable_ovr_gap integer not null default 4 check (oc_reasonable_ovr_gap between 0 and 15),
  champion_selection_bonus integer not null default 14 check (champion_selection_bonus between 0 and 30),
  sacrificial_recipient_selection_bonus integer not null default 8 check (sacrificial_recipient_selection_bonus between 0 and 30),
  sacrificial_min_power_gain integer not null default 400 check (sacrificial_min_power_gain between 0 and 2000),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.administrator_config
  add column if not exists oc_draft_synergy_bonus integer not null default 3,
  add column if not exists oc_same_verse_density_bonus integer not null default 2,
  add column if not exists oc_reasonable_ovr_gap integer not null default 4,
  add column if not exists champion_selection_bonus integer not null default 14,
  add column if not exists sacrificial_recipient_selection_bonus integer not null default 8,
  add column if not exists sacrificial_min_power_gain integer not null default 400;

alter table public.administrator_config
  drop constraint if exists administrator_config_oc_draft_synergy_bonus_check,
  drop constraint if exists administrator_config_oc_same_verse_density_bonus_check,
  drop constraint if exists administrator_config_oc_reasonable_ovr_gap_check,
  drop constraint if exists administrator_config_champion_selection_bonus_check,
  drop constraint if exists administrator_config_sacrificial_recipient_selection_bonus_check,
  drop constraint if exists administrator_config_sacrificial_min_power_gain_check;
alter table public.administrator_config
  add constraint administrator_config_oc_draft_synergy_bonus_check check (oc_draft_synergy_bonus between 0 and 10),
  add constraint administrator_config_oc_same_verse_density_bonus_check check (oc_same_verse_density_bonus between 0 and 10),
  add constraint administrator_config_oc_reasonable_ovr_gap_check check (oc_reasonable_ovr_gap between 0 and 15),
  add constraint administrator_config_champion_selection_bonus_check check (champion_selection_bonus between 0 and 30),
  add constraint administrator_config_sacrificial_recipient_selection_bonus_check check (sacrificial_recipient_selection_bonus between 0 and 30),
  add constraint administrator_config_sacrificial_min_power_gain_check check (sacrificial_min_power_gain between 0 and 2000);

insert into public.administrator_config (singleton, player_id, match_timeout_seconds, enabled)
values (true, '00000000-0000-4000-8000-000000000001', 12, true)
on conflict (singleton) do update set
  player_id = excluded.player_id,
  match_timeout_seconds = excluded.match_timeout_seconds,
  enabled = true,
  updated_at = now();

create table if not exists public.administrator_matches (
  match_id uuid primary key references public.matches(id) on delete cascade,
  system_player_id uuid not null references public.profiles(id) on delete restrict,
  human_player_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  last_action_at timestamptz,
  last_error text,
  check (system_player_id <> human_player_id)
);

alter table public.administrator_config enable row level security;
alter table public.administrator_matches enable row level security;
revoke all on public.administrator_config, public.administrator_matches from public, anon, authenticated;

-- 2. Seed two real, equipped Administrator OCs in their canonical exact verses.
do $$
declare
  system_id uuid := '00000000-0000-4000-8000-000000000001';
  champion_verse_id bigint;
  sacrificial_verse_id bigint;
begin
  select id into champion_verse_id
  from public.verses
  where active = true
    and (lower(name) = 'naruto' or lower(slug) = 'naruto')
  order by case when lower(slug) = 'naruto' then 0 else 1 end, id
  limit 1;

  select id into sacrificial_verse_id
  from public.verses
  where active = true
    and (lower(name) = 'dragon ball' or lower(slug) = 'dragon-ball')
  order by case when lower(slug) = 'dragon-ball' then 0 else 1 end, id
  limit 1;

  if champion_verse_id is null or sacrificial_verse_id is null then
    raise exception using errcode = '23514',
      message = 'Administrator setup requires active Naruto and Dragon Ball verses.';
  end if;

  -- Only the two seeded OCs belong to the public Administrator family.
  update public.player_characters
  set equipped = false
  where owner_id = system_id and equipped = true
    and id not in (
      '00000000-0000-4000-8000-000000000011',
      '00000000-0000-4000-8000-000000000012'
    );

  insert into public.player_characters (
    id, owner_id, verse_id, name, starting_overall, overall, overall_cap,
    image_url, starting_power_score, power_score, power_score_cap, progression_points,
    equipped, active, retired_at, oc_type, type_selected_at
  ) values (
    '00000000-0000-4000-8000-000000000011', system_id, champion_verse_id,
    'Aegis Prime', 60, 90, 95, '/Admin/aegis-prime.png', 5000, 7200, 8500, 0,
    true, true, null, 'champion', now()
  ) on conflict (id) do update set
    owner_id = excluded.owner_id,
    verse_id = excluded.verse_id,
    name = excluded.name,
    image_url = excluded.image_url,
    starting_overall = excluded.starting_overall,
    overall = excluded.overall,
    overall_cap = excluded.overall_cap,
    starting_power_score = excluded.starting_power_score,
    power_score = excluded.power_score,
    power_score_cap = excluded.power_score_cap,
    progression_points = excluded.progression_points,
    equipped = true,
    active = true,
    retired_at = null,
    oc_type = excluded.oc_type,
    type_selected_at = coalesce(public.player_characters.type_selected_at, excluded.type_selected_at),
    updated_at = now();

  insert into public.player_characters (
    id, owner_id, verse_id, name, starting_overall, overall, overall_cap,
    image_url, starting_power_score, power_score, power_score_cap, progression_points,
    equipped, active, retired_at, oc_type, type_selected_at
  ) values (
    '00000000-0000-4000-8000-000000000012', system_id, sacrificial_verse_id,
    'Nexus Herald', 59, 85, 95, '/Admin/nexus-herald.png', 5000, 6800, 8500, 0,
    true, true, null, 'sacrificial', now()
  ) on conflict (id) do update set
    owner_id = excluded.owner_id,
    verse_id = excluded.verse_id,
    name = excluded.name,
    image_url = excluded.image_url,
    starting_overall = excluded.starting_overall,
    overall = excluded.overall,
    overall_cap = excluded.overall_cap,
    starting_power_score = excluded.starting_power_score,
    power_score = excluded.power_score,
    power_score_cap = excluded.power_score_cap,
    progression_points = excluded.progression_points,
    equipped = true,
    active = true,
    retired_at = null,
    oc_type = excluded.oc_type,
    type_selected_at = coalesce(public.player_characters.type_selected_at, excluded.type_selected_at),
    updated_at = now();

  update public.player_characters
  set equipped = true, active = true, retired_at = null
  where owner_id = system_id
    and id in (
      '00000000-0000-4000-8000-000000000011',
      '00000000-0000-4000-8000-000000000012'
    );
end;
$$;

-- 3. Keep ordinary matchmaking human-first and exclude any accidental system
-- queue row. The existing global advisory lock remains the pairing authority.
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
  if caller_id is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.profiles where id = caller_id and not is_system_player) then
    raise exception 'Player profile required';
  end if;

  perform pg_advisory_xact_lock(hashtext('anime_arena_matchmaking'));

  select m.id into existing_match_id
  from public.matches m
  where caller_id in (m.player_one_id, m.player_two_id)
    and m.status not in ('completed', 'cancelled')
  order by m.created_at desc limit 1;

  if existing_match_id is not null then
    return query select 'existing_match'::text, existing_match_id;
    return;
  end if;

  select q.player_id into opponent_id
  from public.matchmaking_queue q
  join public.profiles p on p.id = q.player_id and not p.is_system_player
  where q.status = 'waiting' and q.matched_match_id is null
    and q.player_id <> caller_id
    and not exists (
      select 1 from public.matches active_match
      where q.player_id in (active_match.player_one_id, active_match.player_two_id)
        and active_match.status not in ('completed', 'cancelled')
    )
  order by q.joined_at asc
  limit 1 for update of q skip locked;

  if opponent_id is null then
    insert into public.matchmaking_queue (player_id, status, joined_at, matched_match_id)
    values (caller_id, 'waiting', now(), null)
    on conflict (player_id) do update set
      status = 'waiting',
      joined_at = case when public.matchmaking_queue.status = 'waiting'
        then public.matchmaking_queue.joined_at else now() end,
      matched_match_id = null;
    return query select 'waiting'::text, null::uuid;
    return;
  end if;

  insert into public.matches (player_one_id, player_two_id, status)
  values (opponent_id, caller_id, 'initiative')
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

-- 4. Internal controller. It reuses the canonical participant RPCs by changing
-- auth.uid() only inside this protected transaction, after resolving the one
-- configured system profile. Browser roles cannot execute this function.
create or replace function public.administrator_take_turn_internal(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  system_id uuid;
  match_row public.matches%rowtype;
  original_sub text := current_setting('request.jwt.claim.sub', true);
  step_number integer;
  selected_id uuid;
  selected_type text;
  selected_verse_id bigint;
  selected_oc_type text;
  selected_oc_overall integer;
  selected_oc_power integer;
  same_verse_count integer;
  boost_value integer;
  champion_gain integer;
  baseline_roster_score integer;
  absorb_score_delta integer;
  total_projected_power_gain integer;
  system_balance integer;
  system_team_size integer;
  remaining_slots integer;
  current_overall integer;
  current_power integer;
  current_verse_id bigint;
  draft_synergy_bonus integer;
  strategic_overall integer;
  best_available_overall integer;
  max_bid integer;
  opening_bid integer;
  strategy_oc_draft_synergy_bonus integer;
  strategy_oc_same_verse_density_bonus integer;
  strategy_oc_reasonable_ovr_gap integer;
  strategy_champion_selection_bonus integer;
  strategy_sacrificial_recipient_selection_bonus integer;
  strategy_sacrificial_min_power_gain integer;
begin
  select c.player_id, c.oc_draft_synergy_bonus,
    c.oc_same_verse_density_bonus, c.oc_reasonable_ovr_gap,
    c.champion_selection_bonus, c.sacrificial_recipient_selection_bonus,
    c.sacrificial_min_power_gain
  into system_id, strategy_oc_draft_synergy_bonus,
    strategy_oc_same_verse_density_bonus, strategy_oc_reasonable_ovr_gap,
    strategy_champion_selection_bonus,
    strategy_sacrificial_recipient_selection_bonus,
    strategy_sacrificial_min_power_gain
  from public.administrator_config c
  where c.singleton = true and c.enabled = true;

  if system_id is null then raise exception 'Administrator configuration is unavailable'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_match_id::text, 9127));
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or system_id not in (match_row.player_one_id, match_row.player_two_id) then return; end if;

  perform set_config('request.jwt.claim.sub', system_id::text, true);

  for step_number in 1..30 loop
    select * into match_row from public.matches where id = p_match_id for update;
    exit when not found or match_row.status in ('completed', 'cancelled');

    if match_row.status = 'initiative' then
      if match_row.initiative_state = 'choosing' and not exists (
        select 1 from public.match_initiative_choices c
        where c.match_id = p_match_id
          and c.initiative_round = match_row.initiative_round
          and c.player_id = system_id
      ) then
        perform public.submit_initiative_choice(
          p_match_id,
          (array['rock', 'paper', 'scissors'])[1 + floor(random() * 3)::integer]
        );
      end if;
      exit;

    elsif match_row.status = 'oc_selection' then
      if not exists (
        select 1 from public.match_oc_selections s
        where s.match_id = p_match_id and s.player_id = system_id
      ) then
        select o.player_character_id into selected_id
        from public.match_oc_options o
        where o.match_id = p_match_id and o.player_id = system_id
        order by random() limit 1;

        if selected_id is null then
          raise exception 'Administrator has no snapshotted OC option';
        end if;
        perform public.submit_match_oc_selection(p_match_id, selected_id);
        continue;
      end if;
      exit;

    elsif match_row.status = 'draft' then
      select mp.balance into system_balance
      from public.match_players mp
      where mp.match_id = p_match_id and mp.player_id = system_id;

      select count(*) into system_team_size
      from public.match_characters mc
      where mc.match_id = p_match_id and mc.owner_player_id = system_id;

      if system_team_size >= 5 then exit; end if;

      select mc.overall_snapshot::integer, mc.power_score_snapshot::integer, mc.verse_id_snapshot
      into current_overall, current_power, current_verse_id
      from public.match_characters mc
      where mc.match_id = p_match_id
        and mc.draft_position = match_row.current_draft_position
        and mc.owner_player_id is null;

      if current_overall is null then exit; end if;

      select s.verse_id, coalesce(s.oc_type_snapshot, o.oc_type_snapshot)
      into selected_verse_id, selected_oc_type
      from public.match_oc_selections s
      left join public.match_oc_options o
        on o.match_id = s.match_id and o.player_id = s.player_id
        and o.player_character_id = s.player_character_id
      where s.match_id = p_match_id and s.player_id = system_id;

      select count(*) into same_verse_count
      from public.match_characters mc
      where mc.match_id = p_match_id and mc.owner_player_id = system_id
        and mc.verse_id_snapshot = selected_verse_id;

      -- Exact-verse synergy raises the current card's effective draft value.
      -- A Champion gets extra credit for a useful absorb tier; a Sacrificial
      -- OC values each additional recipient more, capped to a close-decision
      -- swing so weak synergy cards never masquerade as elite cards.
      draft_synergy_bonus := 0;
      if selected_verse_id = current_verse_id then
        if selected_oc_type = 'champion' then
          draft_synergy_bonus := strategy_oc_draft_synergy_bonus
            + least(2, public.get_sacrifice_ovr_boost(current_overall));
        elsif selected_oc_type = 'sacrificial' then
          draft_synergy_bonus := strategy_oc_draft_synergy_bonus
            + least(
              strategy_oc_reasonable_ovr_gap,
              same_verse_count * strategy_oc_same_verse_density_bonus
            );
        end if;
      end if;
      strategic_overall := least(99, current_overall + draft_synergy_bonus);

      remaining_slots := 5 - system_team_size;
      max_bid := case
        when strategic_overall >= 95 then 6
        when strategic_overall >= 90 then 5
        when strategic_overall >= 85 then 4
        when strategic_overall >= 80 then 3
        when strategic_overall >= 70 then 2
        else 1
      end;
      if current_power >= 9000 then max_bid := max_bid + 1; end if;
      max_bid := least(
        system_balance,
        greatest(0, system_balance - greatest(0, remaining_slots - 1)),
        max_bid
      );

      if match_row.draft_state = 'decision' then
        if match_row.priority_player_id <> system_id then exit; end if;
        if system_balance = 0 or max_bid < 1
          or random() < (case when strategic_overall < 75 then 0.34 else 0.16 end) then
          perform public.draft_pass(p_match_id);
          continue;
        end if;
        opening_bid := least(max_bid, 1 + floor(random() * least(2, max_bid))::integer);
        perform public.draft_bid(p_match_id, greatest(1, opening_bid));
        exit;

      elsif match_row.draft_state = 'bidding' then
        if match_row.current_bidder_id = system_id then exit; end if;
        if match_row.current_bid < max_bid and random() >= .20 then
          perform public.draft_bid(
            p_match_id,
            least(max_bid, match_row.current_bid + 1 + floor(random() * 2)::integer)
          );
          exit;
        end if;
        perform public.draft_fold(p_match_id);
        continue;
      end if;
      exit;

    elsif match_row.status = 'oc_preparation' then
      if exists (
        select 1 from public.match_oc_preparations p
        where p.match_id = p_match_id and p.player_id = system_id
      ) then exit; end if;

      select s.player_character_id, s.verse_id,
        coalesce(s.oc_type_snapshot, o.oc_type_snapshot), s.base_overall,
        s.base_power_score
      into selected_id, selected_verse_id, selected_oc_type,
        selected_oc_overall, selected_oc_power
      from public.match_oc_selections s
      left join public.match_oc_options o
        on o.match_id = s.match_id and o.player_id = s.player_id
        and o.player_character_id = s.player_character_id
      where s.match_id = p_match_id and s.player_id = system_id;

      if selected_id is null then exit; end if;

      if selected_oc_type = 'champion' then
        selected_id := null;
        -- Compare the best five usable OVRs before and after each legal absorb.
        -- The configured four-point tolerance is the maximum aggregate team
        -- strength the OC identity may trade for a meaningfully stronger OC.
        with baseline as (
          select coalesce(sum(r.overall), 0)::integer as roster_score
          from (
            select roster.overall
            from (
              select mc.overall_snapshot::integer as overall
              from public.match_characters mc
              where mc.match_id = p_match_id and mc.owner_player_id = system_id
              union all
              select selected_oc_overall
            ) roster
            order by roster.overall desc
            limit 5
          ) r
        ), candidates as (
          select mc.id,
            public.get_sacrifice_ovr_boost(mc.overall_snapshot::integer) as boost,
            least(99, selected_oc_overall
              + public.get_sacrifice_ovr_boost(mc.overall_snapshot::integer)) as boosted_overall
          from public.match_characters mc
          where mc.match_id = p_match_id and mc.owner_player_id = system_id
            and mc.verse_id_snapshot = selected_verse_id
        ), scored as (
          select c.id, c.boost, c.boosted_overall,
            (select coalesce(sum(roster.overall), 0)::integer
             from (
               select mc.overall_snapshot::integer as overall
               from public.match_characters mc
               where mc.match_id = p_match_id
                 and mc.owner_player_id = system_id and mc.id <> c.id
               union all
               select c.boosted_overall
             ) roster) as post_score
          from candidates c
        )
        select scored.id, scored.boost,
          scored.boosted_overall - selected_oc_overall,
          baseline.roster_score,
          scored.post_score - baseline.roster_score
        into selected_id, boost_value, champion_gain,
          baseline_roster_score, absorb_score_delta
        from scored cross join baseline
        order by scored.post_score - baseline.roster_score desc,
          scored.boosted_overall - selected_oc_overall desc, random()
        limit 1;

        if selected_id is not null and champion_gain >= 2
          and absorb_score_delta >= -strategy_oc_reasonable_ovr_gap then
          perform public.submit_match_oc_preparation(p_match_id, 'absorb', selected_id);
        else
          perform public.submit_match_oc_preparation(p_match_id, 'reserve', null);
        end if;
      elsif selected_oc_type = 'sacrificial' then
        -- The authoritative transfer function evaluates every exact-verse
        -- recipient. Activation requires a meaningful average Power gain.
        select count(*), coalesce(sum(
          x.match_power_score - mc.power_score_snapshot::integer
        ), 0)::integer
        into same_verse_count, total_projected_power_gain
        from public.match_characters mc
        cross join lateral public.calculate_oc_power_transfer(
          selected_oc_power, selected_oc_overall,
          mc.overall_snapshot::integer, mc.power_score_snapshot::integer
        ) x
        where mc.match_id = p_match_id and mc.owner_player_id = system_id
          and mc.verse_id_snapshot = selected_verse_id;

        if same_verse_count > 0
          and total_projected_power_gain >= strategy_sacrificial_min_power_gain * same_verse_count then
          perform public.submit_match_oc_preparation(p_match_id, 'sacrifice', null);
        else
          -- Current canonical rules make Reserve the default mode for every OC.
          perform public.submit_match_oc_preparation(p_match_id, 'reserve', null);
        end if;
      else
        raise exception 'Administrator OC type snapshot is unavailable';
      end if;
      continue;

    elsif match_row.status = 'battle' and match_row.battle_state = 'selecting' then
      if exists (
        select 1 from public.battle_selections bs
        where bs.match_id = p_match_id
          and bs.round_number = match_row.current_battle_round
          and bs.player_id = system_id
      ) then exit; end if;

      select max(available.overall) into best_available_overall
      from (
        select mc.overall_snapshot::integer as overall
        from public.match_characters mc
        where mc.match_id = p_match_id and mc.owner_player_id = system_id
          and not mc.used_in_battle
          and not exists (
            select 1 from public.match_oc_preparations p
            where p.match_id = p_match_id and p.player_id = system_id
              and p.sacrificed_match_character_id = mc.id
          )
        union all
        select p.match_overall
        from public.match_oc_preparations p
        where p.match_id = p_match_id and p.player_id = system_id
          and p.decision in ('reserve', 'absorb')
          and not p.oc_sacrificed and not p.used_in_battle
      ) available;

      select candidate.selection_type, candidate.fighter_id
      into selected_type, selected_id
      from (
        select 'canon'::text selection_type, mc.id fighter_id,
          greatest(1, mc.overall_snapshot::integer - 65)
            + case
                when coalesce(b.match_power_score - b.recipient_base_power, 0) <= 0 then 0
                when mc.overall_snapshot = best_available_overall
                  then strategy_sacrificial_recipient_selection_bonus
                when mc.overall_snapshot >= best_available_overall
                  - strategy_oc_reasonable_ovr_gap
                  then greatest(1, strategy_sacrificial_recipient_selection_bonus / 2)
                else 0
              end
            + case when coalesce(b.match_power_score - b.recipient_base_power, 0) > 0
                and mc.overall_snapshot = best_available_overall
              then least(2, (b.match_power_score - b.recipient_base_power) / 750) else 0 end weight
        from public.match_characters mc
        left join public.match_oc_power_boosts b
          on b.match_id = mc.match_id and b.match_character_id = mc.id
        where mc.match_id = p_match_id and mc.owner_player_id = system_id
          and not mc.used_in_battle
          and not exists (
            select 1 from public.match_oc_preparations p
            where p.match_id = p_match_id and p.player_id = system_id
              and p.sacrificed_match_character_id = mc.id
          )
        union all
        select 'oc'::text, p.player_character_id,
          greatest(1, p.match_overall - 65)
            + case when p.oc_type = 'champion'
                and p.match_overall >= best_available_overall
                  - strategy_oc_reasonable_ovr_gap
              then strategy_champion_selection_bonus else 0 end
            + case when p.oc_type = 'champion' and p.decision = 'absorb'
                and p.match_overall >= best_available_overall
                  - strategy_oc_reasonable_ovr_gap
              then greatest(1, strategy_champion_selection_bonus / 2) else 0 end
        from public.match_oc_preparations p
        where p.match_id = p_match_id and p.player_id = system_id
          and p.decision in ('reserve', 'absorb')
          and not p.oc_sacrificed and not p.used_in_battle
      ) candidate
      order by power(random(), 1.0 / greatest(candidate.weight, 1)) desc
      limit 1;

      if selected_id is null then
        raise exception 'Administrator has no legal battle fighter';
      end if;
      perform public.submit_battle_selection(p_match_id, selected_type, selected_id);
      exit;
    else
      exit;
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', coalesce(original_sub, ''), true);
  update public.administrator_matches as am
  set last_action_at = now(), last_error = null
  where am.match_id = p_match_id;
exception when others then
  perform set_config('request.jwt.claim.sub', coalesce(original_sub, ''), true);
  raise;
end;
$$;

-- Server-authoritative recovery endpoint. It accepts no decisions or actor ID.
create or replace function public.advance_administrator_match(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  system_id uuid;
  match_row public.matches%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select player_id into system_id from public.administrator_config
  where singleton = true and enabled = true;
  select * into match_row from public.matches where id = p_match_id;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception using errcode = '42501', message = 'Administrator match unavailable.';
  end if;
  -- This makes the recovery call safe on every match screen without revealing
  -- whether a non-participant match contains the system player.
  if system_id not in (match_row.player_one_id, match_row.player_two_id)
    or caller_id = system_id then return; end if;
  perform public.administrator_take_turn_internal(p_match_id);
end;
$$;

-- Every authoritative match update can wake the system controller. The depth
-- guard is essential: Administrator actions also update matches and must not
-- recursively create another controller stack.
create or replace function public.trigger_administrator_turn()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_trigger_depth() > 1 then return new; end if;
  if exists (
    select 1 from public.administrator_config c
    where c.singleton = true and c.enabled = true
      and c.player_id in (new.player_one_id, new.player_two_id)
  ) then
    begin
      perform public.administrator_take_turn_internal(new.id);
    exception when others then
      update public.administrator_matches as am
      set last_error = sqlstate || ': ' || sqlerrm
      where am.match_id = new.id;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists administrator_turn_after_match_update on public.matches;
create trigger administrator_turn_after_match_update
after update on public.matches
for each row execute function public.trigger_administrator_turn();

-- 5. Timeout claim. The global matchmaking lock makes this atomic with normal
-- human pairing and cancellation. An eligible real waiting opponent is always
-- claimed before the Administrator fallback.
create or replace function public.claim_administrator_match()
returns table (result_status text, match_id uuid, retry_after_seconds integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  system_id uuid;
  timeout_seconds integer;
  queue_row public.matchmaking_queue%rowtype;
  existing_match_id uuid;
  opponent_id uuid;
  created_match_id uuid;
  remaining integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.profiles p where p.id = caller_id and not p.is_system_player) then
    raise exception 'Player profile required';
  end if;

  perform pg_advisory_xact_lock(hashtext('anime_arena_matchmaking'));

  select m.id into existing_match_id
  from public.matches m
  where caller_id in (m.player_one_id, m.player_two_id)
    and m.status not in ('completed', 'cancelled')
  order by m.created_at desc limit 1;
  if existing_match_id is not null then
    return query select 'existing_match'::text, existing_match_id, 0;
    return;
  end if;

  select * into queue_row
  from public.matchmaking_queue q
  where q.player_id = caller_id
  for update;

  if not found or queue_row.status <> 'waiting' or queue_row.matched_match_id is not null then
    raise exception using errcode = '23514', message = 'Player is not waiting in matchmaking.';
  end if;

  select c.player_id, c.match_timeout_seconds into system_id, timeout_seconds
  from public.administrator_config c
  where c.singleton = true and c.enabled = true;
  if system_id is null then
    raise exception using errcode = '55000', message = 'Administrator is unavailable.';
  end if;

  remaining := greatest(0, ceil(extract(epoch from
    (queue_row.joined_at + make_interval(secs => timeout_seconds) - now())))::integer);
  if remaining > 0 then
    return query select 'waiting'::text, null::uuid, remaining;
    return;
  end if;

  -- Human-first check performed while holding the same global pairing lock.
  select q.player_id into opponent_id
  from public.matchmaking_queue q
  join public.profiles p on p.id = q.player_id and not p.is_system_player
  where q.status = 'waiting' and q.matched_match_id is null
    and q.player_id <> caller_id
    and not exists (
      select 1 from public.matches active_match
      where q.player_id in (active_match.player_one_id, active_match.player_two_id)
        and active_match.status not in ('completed', 'cancelled')
    )
  order by q.joined_at asc
  limit 1 for update of q skip locked;

  if opponent_id is not null then
    insert into public.matches (player_one_id, player_two_id, status)
    values (opponent_id, caller_id, 'initiative')
    returning id into created_match_id;

    update public.matchmaking_queue
    set status = 'matched', matched_match_id = created_match_id
    where player_id in (opponent_id, caller_id);

    return query select 'matched'::text, created_match_id, 0;
    return;
  end if;

  if (select count(*) from public.player_characters pc
      where pc.owner_id = system_id and pc.active = true and pc.equipped = true
        and pc.retired_at is null) <> 2 then
    raise exception using errcode = '55000',
      message = 'Administrator OC family is unavailable.';
  end if;

  insert into public.matches (player_one_id, player_two_id, status)
  values (caller_id, system_id, 'initiative')
  returning id into created_match_id;

  update public.matchmaking_queue
  set status = 'matched', matched_match_id = created_match_id
  where player_id = caller_id and status = 'waiting';
  if not found then raise exception 'Matchmaking state changed before Administrator claim'; end if;

  insert into public.administrator_matches (match_id, system_player_id, human_player_id)
  values (created_match_id, system_id, caller_id)
  on conflict on constraint administrator_matches_pkey do nothing;

  perform public.administrator_take_turn_internal(created_match_id);
  return query select 'administrator_matched'::text, created_match_id, 0;
end;
$$;

revoke all on function public.find_or_create_match() from public, anon;
grant execute on function public.find_or_create_match() to authenticated;
revoke all on function public.claim_administrator_match() from public, anon;
grant execute on function public.claim_administrator_match() to authenticated;
revoke all on function public.advance_administrator_match(uuid) from public, anon;
grant execute on function public.advance_administrator_match(uuid) to authenticated;
revoke all on function public.administrator_take_turn_internal(uuid) from public, anon, authenticated;
revoke all on function public.trigger_administrator_turn() from public, anon, authenticated;

notify pgrst, 'reload schema';
