-- Anime Arena OC Sacrifice / Absorption Preparation (Phase 4)
-- Run after supabase_match_oc_selection.sql and the current online battle SQL.

alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches add constraint matches_status_check check (
  status in ('waiting', 'initiative', 'oc_selection', 'draft', 'oc_preparation', 'battle', 'completed', 'cancelled')
);

create or replace function public.get_character_tier(p_overall bigint)
returns text language plpgsql immutable set search_path = '' as $$
begin
  if p_overall between 50 and 64 then return 'D';
  elsif p_overall between 65 and 74 then return 'C';
  elsif p_overall between 75 and 84 then return 'B';
  elsif p_overall between 85 and 94 then return 'A';
  elsif p_overall between 95 and 98 then return 'S';
  elsif p_overall = 99 then return 'LEGEND';
  end if;
  raise exception using errcode = '22023', message = 'Character OVR cannot be mapped to a tier.';
end;
$$;

create or replace function public.get_sacrifice_ovr_boost(p_overall bigint)
returns integer language plpgsql immutable set search_path = '' as $$
begin
  if p_overall between 50 and 64 then return 1;
  elsif p_overall between 65 and 74 then return 2;
  elsif p_overall between 75 and 84 then return 3;
  elsif p_overall between 85 and 94 then return 4;
  elsif p_overall between 95 and 98 then return 5;
  elsif p_overall = 99 then return 6;
  end if;
  raise exception using errcode = '22023', message = 'Character OVR cannot be mapped to a sacrifice boost.';
end;
$$;

create table if not exists public.match_oc_preparations (
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete restrict,
  player_character_id uuid references public.player_characters(id) on delete restrict,
  verse_id bigint references public.verses(id) on delete restrict,
  decision text not null check (decision in ('none', 'reserve', 'sacrifice')),
  sacrificed_match_character_id uuid references public.match_characters(id) on delete restrict,
  sacrifice_tier text check (sacrifice_tier in ('D', 'C', 'B', 'A', 'S', 'LEGEND')),
  sacrifice_boost integer not null default 0 check (sacrifice_boost between 0 and 6),
  base_overall integer check (base_overall between 1 and 99),
  match_overall integer check (match_overall between 1 and 99),
  base_power_score integer check (base_power_score >= 0),
  locked_at timestamptz not null default now(),
  revealed_at timestamptz,
  primary key (match_id, player_id),
  unique (match_id, sacrificed_match_character_id),
  check (
    (decision = 'none' and player_character_id is null and verse_id is null and sacrificed_match_character_id is null and sacrifice_tier is null and sacrifice_boost = 0 and base_overall is null and match_overall is null and base_power_score is null)
    or
    (decision = 'reserve' and player_character_id is not null and verse_id is not null and sacrificed_match_character_id is null and sacrifice_tier is null and sacrifice_boost = 0 and base_overall is not null and match_overall = base_overall and base_power_score is not null)
    or
    (decision = 'sacrifice' and player_character_id is not null and verse_id is not null and sacrificed_match_character_id is not null and sacrifice_tier is not null and sacrifice_boost between 1 and 6 and base_overall is not null and match_overall is not null and match_overall >= base_overall and base_power_score is not null)
  )
);

create index if not exists match_oc_preparations_match_idx on public.match_oc_preparations (match_id);
alter table public.match_oc_preparations enable row level security;
revoke all on public.match_oc_preparations from public, anon, authenticated;

-- No SELECT policy means Realtime cannot authorize row delivery. Remove the table
-- from a normal table-list publication too; ALL TABLES publications remain RLS-safe.
do $$ begin
  if exists (
    select 1 from pg_publication_tables pt join pg_publication p on p.pubname = pt.pubname
    where pt.pubname = 'supabase_realtime' and pt.schemaname = 'public'
      and pt.tablename = 'match_oc_preparations' and p.puballtables = false
  ) then execute 'alter publication supabase_realtime drop table public.match_oc_preparations'; end if;
end $$;

create or replace function public.get_match_oc_preparation_state(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype; opponent_id uuid;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  select * into match_row from public.matches where id = p_match_id;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception using errcode = '42501', message = 'Match unavailable.';
  end if;
  opponent_id := case when caller_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  return jsonb_build_object(
    'matchId', p_match_id, 'status', match_row.status, 'yourPlayerId', caller_id,
    'yourOC', (select case when s.player_character_id is null then null else jsonb_build_object(
      'characterId', s.player_character_id, 'name', o.name_snapshot, 'verseId', s.verse_id,
      'verseName', o.verse_name_snapshot, 'baseOverall', s.base_overall, 'powerScore', s.base_power_score
    ) end from public.match_oc_selections s left join public.match_oc_options o
      on o.match_id = s.match_id and o.player_id = s.player_id and o.player_character_id = s.player_character_id
      where s.match_id = p_match_id and s.player_id = caller_id),
    'eligibleSacrifices', coalesce((select jsonb_agg(jsonb_build_object(
      'matchCharacterId', mc.id, 'characterId', c.id, 'name', c.name, 'verseId', c.verse_id,
      'verseName', v.name, 'overall', c.overall, 'powerScore', c.power_score,
      'tier', public.get_character_tier(c.overall), 'sacrificeBoost', public.get_sacrifice_ovr_boost(c.overall)
    ) order by mc.draft_position) from public.match_characters mc
      join public.characters c on c.id = mc.character_id join public.verses v on v.id = c.verse_id
      join public.match_oc_selections s on s.match_id = mc.match_id and s.player_id = caller_id
      where mc.match_id = p_match_id and mc.owner_player_id = caller_id
        and s.player_character_id is not null and c.verse_id = s.verse_id), '[]'::jsonb),
    'yourPreparation', (select jsonb_build_object(
      'decision', p.decision, 'sacrificedMatchCharacterId', p.sacrificed_match_character_id,
      'sacrificeTier', p.sacrifice_tier, 'sacrificeBoost', p.sacrifice_boost,
      'baseOverall', p.base_overall, 'matchOverall', p.match_overall,
      'basePowerScore', p.base_power_score, 'lockedAt', p.locked_at
    ) from public.match_oc_preparations p where p.match_id = p_match_id and p.player_id = caller_id),
    'yourLocked', exists(select 1 from public.match_oc_preparations p where p.match_id = p_match_id and p.player_id = caller_id),
    'opponentLocked', exists(select 1 from public.match_oc_preparations p where p.match_id = p_match_id and p.player_id = opponent_id),
    'bothComplete', (select count(*) = 2 from public.match_oc_preparations p where p.match_id = p_match_id)
  );
end;
$$;

create or replace function public.initialize_match_oc_preparation(p_match_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype; one_count integer; two_count integer;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception using errcode = '42501', message = 'Match unavailable.'; end if;
  if match_row.status in ('oc_preparation', 'battle', 'completed') then return public.get_match_oc_preparation_state(p_match_id); end if;
  select count(*) filter (where owner_player_id = match_row.player_one_id), count(*) filter (where owner_player_id = match_row.player_two_id)
    into one_count, two_count from public.match_characters where match_id = p_match_id;
  if match_row.status <> 'draft' or match_row.draft_state <> 'complete' or one_count <> 5 or two_count <> 5 then
    raise exception using errcode = '23514', message = 'Both complete draft teams are required before OC preparation.';
  end if;
  update public.matches set status = 'oc_preparation', action_version = action_version + 1, updated_at = now() where id = p_match_id;
  insert into public.match_oc_preparations (match_id, player_id, decision)
    select p_match_id, s.player_id, 'none' from public.match_oc_selections s
    where s.match_id = p_match_id and s.player_character_id is null on conflict do nothing;
  if (select count(*) from public.match_oc_preparations where match_id = p_match_id) = 2 then
    update public.matches set status = 'battle', action_version = action_version + 1, updated_at = now() where id = p_match_id;
    perform public.initialize_online_battle(p_match_id);
  end if;
  return public.get_match_oc_preparation_state(p_match_id);
end;
$$;

create or replace function public.submit_match_oc_preparation(p_match_id uuid, p_decision text, p_sacrificed_match_character_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype; selection_row public.match_oc_selections%rowtype;
  card_row record; tier_value text; boost_value integer;
begin
  if caller_id is null then raise exception using errcode = '42501', message = 'Authentication required.'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception using errcode = '42501', message = 'Match unavailable.'; end if;
  if match_row.status <> 'oc_preparation' then raise exception using errcode = '23514', message = 'OC preparation is not active.'; end if;
  if exists(select 1 from public.match_oc_preparations where match_id = p_match_id and player_id = caller_id) then raise exception using errcode = '23505', message = 'OC preparation is already locked.'; end if;
  select * into selection_row from public.match_oc_selections where match_id = p_match_id and player_id = caller_id;
  if not found or selection_row.player_character_id is null then raise exception using errcode = '23514', message = 'No selected OC is available for preparation.'; end if;
  if p_decision = 'reserve' then
    if p_sacrificed_match_character_id is not null then raise exception using errcode = '22023', message = 'Reserve cannot include a sacrifice.'; end if;
    insert into public.match_oc_preparations (match_id, player_id, player_character_id, verse_id, decision, base_overall, match_overall, base_power_score)
      values (p_match_id, caller_id, selection_row.player_character_id, selection_row.verse_id, 'reserve', selection_row.base_overall, selection_row.base_overall, selection_row.base_power_score);
  elsif p_decision = 'sacrifice' then
    if p_sacrificed_match_character_id is null then raise exception using errcode = '22023', message = 'Choose a fighter to sacrifice.'; end if;
    -- Canon OVR is currently read from characters at lock-in. Match-level canon
    -- stat snapshots are deferred technical debt; roster stats must remain stable
    -- while a match is active until that snapshot is introduced.
    select mc.id, c.overall, c.verse_id into card_row from public.match_characters mc join public.characters c on c.id = mc.character_id
      where mc.id = p_sacrificed_match_character_id and mc.match_id = p_match_id and mc.owner_player_id = caller_id for update of mc;
    if not found then raise exception using errcode = '42501', message = 'Sacrifice fighter is unavailable.'; end if;
    if card_row.verse_id <> selection_row.verse_id then raise exception using errcode = '23514', message = 'Only a same-verse fighter may be sacrificed.'; end if;
    tier_value := public.get_character_tier(card_row.overall); boost_value := public.get_sacrifice_ovr_boost(card_row.overall);
    insert into public.match_oc_preparations (match_id, player_id, player_character_id, verse_id, decision, sacrificed_match_character_id, sacrifice_tier, sacrifice_boost, base_overall, match_overall, base_power_score)
      values (p_match_id, caller_id, selection_row.player_character_id, selection_row.verse_id, 'sacrifice', card_row.id, tier_value, boost_value,
        selection_row.base_overall, least(99, selection_row.base_overall + boost_value), selection_row.base_power_score);
  else raise exception using errcode = '22023', message = 'Choose reserve or sacrifice.'; end if;
  update public.matches set action_version = action_version + 1, updated_at = now() where id = p_match_id;
  if (select count(*) from public.match_oc_preparations where match_id = p_match_id) = 2 then
    update public.matches set status = 'battle', action_version = action_version + 1, updated_at = now() where id = p_match_id;
    perform public.initialize_online_battle(p_match_id);
  end if;
  return public.get_match_oc_preparation_state(p_match_id);
end;
$$;

-- Canonical draft advancement with only the final transition changed.
create or replace function public.advance_online_draft(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare match_row public.matches%rowtype; player_one_balance integer; player_two_balance integer;
  player_one_count integer; player_two_count integer; assigned_count integer; free_player_id uuid; next_priority uuid; next_tie_priority uuid;
begin
  select * into match_row from public.matches where id = p_match_id for update;
  if not found then raise exception 'Match not found'; end if;
  select count(*) filter (where owner_player_id = match_row.player_one_id), count(*) filter (where owner_player_id = match_row.player_two_id)
    into player_one_count, player_two_count from public.match_characters where match_id = p_match_id;
  if player_one_count = 5 or player_two_count = 5 then
    free_player_id := case when player_one_count = 5 then match_row.player_two_id else match_row.player_one_id end;
    update public.match_characters set owner_player_id = free_player_id, purchase_price = 0, assigned_at = now() where match_id = p_match_id and owner_player_id is null;
  end if;
  select count(*) filter (where owner_player_id = match_row.player_one_id), count(*) filter (where owner_player_id = match_row.player_two_id), count(*) filter (where owner_player_id is not null)
    into player_one_count, player_two_count, assigned_count from public.match_characters where match_id = p_match_id;
  if assigned_count = 10 then
    if player_one_count <> 5 or player_two_count <> 5 then raise exception 'Invalid final roster state'; end if;
    update public.matches set draft_state = 'complete', current_bid = null, current_bidder_id = null, priority_player_id = null,
      current_draft_position = 10, action_version = action_version + 1, updated_at = now() where id = p_match_id;
    perform public.initialize_match_oc_preparation(p_match_id); return;
  end if;
  if match_row.current_draft_position >= 10 then raise exception 'Draft pool exhausted'; end if;
  select balance into player_one_balance from public.match_players where match_id = p_match_id and player_number = 1;
  select balance into player_two_balance from public.match_players where match_id = p_match_id and player_number = 2;
  next_tie_priority := match_row.tie_priority_player_id;
  if player_one_balance > player_two_balance then next_priority := match_row.player_one_id;
  elsif player_two_balance > player_one_balance then next_priority := match_row.player_two_id;
  else next_priority := match_row.tie_priority_player_id; next_tie_priority := case when next_priority = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end; end if;
  update public.matches set current_draft_position = current_draft_position + 1, draft_state = 'decision', current_bid = null,
    current_bidder_id = null, priority_player_id = next_priority, tie_priority_player_id = next_tie_priority,
    action_version = action_version + 1, updated_at = now() where id = p_match_id;
end;
$$;

-- Preserve battle behavior while explicitly rejecting absorbed canon fighters.
create or replace function public.initialize_online_battle(p_match_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype; player_one_count integer; player_two_count integer; assigned_count integer;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status = 'completed' then return; end if;
  if match_row.status <> 'battle' or (select count(*) from public.match_oc_preparations where match_id = p_match_id) <> 2 then raise exception 'Battle is not available'; end if;
  select count(*) filter (where owner_player_id = match_row.player_one_id), count(*) filter (where owner_player_id = match_row.player_two_id), count(*) filter (where owner_player_id is not null)
    into player_one_count, player_two_count, assigned_count from public.match_characters where match_id = p_match_id;
  if player_one_count <> 5 or player_two_count <> 5 or assigned_count <> 10 then raise exception 'Both complete five-fighter teams are required'; end if;
  if match_row.current_battle_round is null then update public.matches set current_battle_round = 1, battle_state = 'selecting', player_one_score = 0,
    player_two_score = 0, action_version = action_version + 1, updated_at = now() where id = p_match_id; end if;
end;
$$;

-- Enforce battle exclusion without rewriting the canonical battle resolver.
create or replace function public.reject_sacrificed_battle_selection()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.match_oc_preparations p where p.match_id = new.match_id and p.sacrificed_match_character_id = new.match_character_id) then
    raise exception using errcode = '23514', message = 'Sacrificed fighters cannot be used in battle.';
  end if;
  return new;
end;
$$;
drop trigger if exists reject_sacrificed_battle_selection on public.battle_selections;
create trigger reject_sacrificed_battle_selection before insert on public.battle_selections
for each row execute function public.reject_sacrificed_battle_selection();

revoke all on function public.get_character_tier(bigint), public.get_sacrifice_ovr_boost(bigint) from public;
revoke all on function public.reject_sacrificed_battle_selection() from public;
revoke all on function public.initialize_match_oc_preparation(uuid), public.get_match_oc_preparation_state(uuid), public.submit_match_oc_preparation(uuid, text, uuid) from public;
grant execute on function public.get_character_tier(bigint), public.get_sacrifice_ovr_boost(bigint) to authenticated;
grant execute on function public.initialize_match_oc_preparation(uuid), public.get_match_oc_preparation_state(uuid), public.submit_match_oc_preparation(uuid, text, uuid) to authenticated;
notify pgrst, 'reload schema';
