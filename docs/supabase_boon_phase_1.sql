-- Anime Arena Boon System - Phase 1: ranked-match Boon Point economy.
--
-- Run this file after the current online battle, OC type/sacrifice, RPS
-- initiative, Administrator opponent, and match-exit SQL. It intentionally
-- replaces the current canonical battle-selection and forfeit functions only
-- to add one transactional reward call at their existing completion points.
-- Existing completed matches are not backfilled and Local Prototype is not
-- connected to any function in this file.

-- 1. Persistent owner balance. PostgreSQL applies the default to existing rows,
-- so all existing profiles begin Phase 1 with zero BP.
alter table public.profiles
  add column if not exists boon_points bigint not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_boon_points_nonnegative'
  ) then
    alter table public.profiles
      add constraint profiles_boon_points_nonnegative check (boon_points >= 0);
  end if;
end
$$;

-- 2. Match-level audit/idempotency snapshot. Null values identify historical
-- matches and deliberately prevent retroactive rewards.
alter table public.matches
  add column if not exists player_one_boon_reward bigint,
  add column if not exists player_two_boon_reward bigint,
  add column if not exists boon_rewards_granted_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.matches'::regclass
      and conname = 'matches_boon_rewards_nonnegative'
  ) then
    alter table public.matches add constraint matches_boon_rewards_nonnegative
      check (
        (player_one_boon_reward is null or player_one_boon_reward >= 0)
        and (player_two_boon_reward is null or player_two_boon_reward >= 0)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.matches'::regclass
      and conname = 'matches_boon_reward_snapshot_complete'
  ) then
    alter table public.matches add constraint matches_boon_reward_snapshot_complete
      check (
        (boon_rewards_granted_at is null
          and player_one_boon_reward is null
          and player_two_boon_reward is null)
        or
        (boon_rewards_granted_at is not null
          and player_one_boon_reward is not null
          and player_two_boon_reward is not null)
      );
  end if;
end
$$;

-- 3. The sole reward policy. This is private and is invoked from the same
-- transaction that completes the authoritative match. The match row lock and
-- stored granted timestamp make retries/reconnects exactly-once.
create or replace function public.grant_ranked_match_boon_rewards(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  match_row public.matches%rowtype;
  win_reward constant bigint := 100;
  loss_reward constant bigint := 60;
  draw_reward constant bigint := 75;
  player_one_eligible boolean := false;
  player_two_eligible boolean := false;
  player_one_reward bigint := 0;
  player_two_reward bigint := 0;
begin
  select * into match_row
  from public.matches
  where id = p_match_id
  for update;

  if not found then raise exception 'Match unavailable'; end if;
  if match_row.status <> 'completed' or match_row.completed_at is null then
    raise exception 'Boon Points require a completed ranked match';
  end if;

  if match_row.boon_rewards_granted_at is not null then
    return jsonb_build_object(
      'playerOneReward', match_row.player_one_boon_reward,
      'playerTwoReward', match_row.player_two_boon_reward,
      'grantedAt', match_row.boon_rewards_granted_at
    );
  end if;

  select coalesce(not p.is_guest and not p.is_system_player, false)
    into player_one_eligible
  from public.profiles p where p.id = match_row.player_one_id;

  select coalesce(not p.is_guest and not p.is_system_player, false)
    into player_two_eligible
  from public.profiles p where p.id = match_row.player_two_id;

  if match_row.winner_id is null then
    player_one_reward := case when coalesce(player_one_eligible, false) then draw_reward else 0 end;
    player_two_reward := case when coalesce(player_two_eligible, false) then draw_reward else 0 end;
  else
    player_one_reward := case
      when not coalesce(player_one_eligible, false) then 0
      when match_row.winner_id = match_row.player_one_id then win_reward
      else loss_reward
    end;
    player_two_reward := case
      when not coalesce(player_two_eligible, false) then 0
      when match_row.winner_id = match_row.player_two_id then win_reward
      else loss_reward
    end;
  end if;

  if player_one_reward > 0 then
    update public.profiles
    set boon_points = boon_points + player_one_reward
    where id = match_row.player_one_id
      and not is_guest and not is_system_player;
  end if;

  if player_two_reward > 0 then
    update public.profiles
    set boon_points = boon_points + player_two_reward
    where id = match_row.player_two_id
      and not is_guest and not is_system_player;
  end if;

  update public.matches
  set player_one_boon_reward = player_one_reward,
      player_two_boon_reward = player_two_reward,
      boon_rewards_granted_at = now()
  where id = p_match_id;

  return jsonb_build_object(
    'playerOneReward', player_one_reward,
    'playerTwoReward', player_two_reward,
    'grantedAt', now()
  );
end;
$$;

-- 4. Canonical battle resolver. All pre-existing OC/canon selection, snapshot,
-- round, score, draw, and W/L behavior is preserved. The only Phase 1 change is
-- the reward call immediately after the existing final W/L update.
create or replace function public.submit_battle_selection(p_match_id uuid,p_selection_type text,p_fighter_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
  caller_id uuid:=auth.uid(); match_row public.matches%rowtype;
  selected_canon public.match_characters%rowtype; selected_oc public.match_oc_preparations%rowtype;
  one_selection public.battle_selections%rowtype; two_selection public.battle_selections%rowtype;
  one_name text; two_name text; one_overall bigint; two_overall bigint; one_power bigint; two_power bigint;
  one_boost integer:=0; two_boost integer:=0; round_winner uuid; next_one_score integer; next_two_score integer; final_winner uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id=p_match_id for update;
  if not found or caller_id not in(match_row.player_one_id,match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status<>'battle' or match_row.battle_state<>'selecting' or match_row.current_battle_round is null then raise exception 'Selections are not open'; end if;
  if p_selection_type='canon' then
    select * into selected_canon from public.match_characters where id=p_fighter_id and match_id=p_match_id for update;
    if not found or selected_canon.owner_player_id<>caller_id then raise exception 'Fighter does not belong to this player'; end if;
    if selected_canon.used_in_battle then raise exception 'Fighter has already been used'; end if;
    if exists(select 1 from public.match_oc_preparations p where p.match_id=p_match_id and p.player_id=caller_id and p.sacrificed_match_character_id=selected_canon.id) then raise exception 'Absorbed fighters cannot be used in battle'; end if;
    insert into public.battle_selections(match_id,round_number,player_id,selection_type,match_character_id) values(p_match_id,match_row.current_battle_round,caller_id,'canon',selected_canon.id);
  elsif p_selection_type='oc' then
    select * into selected_oc from public.match_oc_preparations where match_id=p_match_id and player_id=caller_id and player_character_id=p_fighter_id for update;
    if not found then raise exception 'OC reserve does not belong to this player or match'; end if;
    if selected_oc.decision not in('reserve','absorb') then raise exception 'OC preparation does not allow reserve battle use'; end if;
    if selected_oc.decision='absorb' and selected_oc.oc_type<>'champion' then raise exception 'Only Champion OCs can absorb a fighter'; end if;
    if selected_oc.oc_sacrificed then raise exception 'Sacrificed OCs cannot enter battle'; end if;
    if selected_oc.match_overall is null or selected_oc.base_power_score is null then raise exception 'OC match stats are unavailable'; end if;
    if selected_oc.used_in_battle then raise exception 'OC has already been used'; end if;
    insert into public.battle_selections(match_id,round_number,player_id,selection_type,player_character_id) values(p_match_id,match_row.current_battle_round,caller_id,'oc',selected_oc.player_character_id);
  else raise exception 'Invalid fighter selection type'; end if;
  update public.matches set action_version=action_version+1,updated_at=now() where id=p_match_id;
  select * into one_selection from public.battle_selections where match_id=p_match_id and round_number=match_row.current_battle_round and player_id=match_row.player_one_id;
  select * into two_selection from public.battle_selections where match_id=p_match_id and round_number=match_row.current_battle_round and player_id=match_row.player_two_id;
  if one_selection.player_id is null or two_selection.player_id is null then return; end if;
  if one_selection.selection_type='canon' then
    select c.name,mc.overall_snapshot,coalesce(b.match_power_score,mc.power_score_snapshot),coalesce(b.effective_bonus,0) into one_name,one_overall,one_power,one_boost
    from public.match_characters mc join public.characters c on c.id=mc.character_id left join public.match_oc_power_boosts b on b.match_id=mc.match_id and b.match_character_id=mc.id where mc.id=one_selection.match_character_id;
  else
    select o.name_snapshot,p.match_overall,p.base_power_score into one_name,one_overall,one_power from public.match_oc_preparations p join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id where p.match_id=p_match_id and p.player_id=match_row.player_one_id;
  end if;
  if two_selection.selection_type='canon' then
    select c.name,mc.overall_snapshot,coalesce(b.match_power_score,mc.power_score_snapshot),coalesce(b.effective_bonus,0) into two_name,two_overall,two_power,two_boost
    from public.match_characters mc join public.characters c on c.id=mc.character_id left join public.match_oc_power_boosts b on b.match_id=mc.match_id and b.match_character_id=mc.id where mc.id=two_selection.match_character_id;
  else
    select o.name_snapshot,p.match_overall,p.base_power_score into two_name,two_overall,two_power from public.match_oc_preparations p join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id where p.match_id=p_match_id and p.player_id=match_row.player_two_id;
  end if;
  round_winner:=case when one_overall>two_overall then match_row.player_one_id when two_overall>one_overall then match_row.player_two_id when one_power>two_power then match_row.player_one_id when two_power>one_power then match_row.player_two_id else null end;
  next_one_score:=match_row.player_one_score+case when round_winner=match_row.player_one_id then 1 else 0 end;
  next_two_score:=match_row.player_two_score+case when round_winner=match_row.player_two_id then 1 else 0 end;
  if one_selection.selection_type='canon' then
    update public.match_characters set used_in_battle=true where id=one_selection.match_character_id;
    if one_boost>0 then update public.match_oc_preparations set revealed_at=coalesce(revealed_at,now()) where match_id=p_match_id and player_id=match_row.player_one_id and oc_type='sacrificial' and decision='sacrifice'; end if;
  else update public.match_oc_preparations set used_in_battle=true,used_in_round=match_row.current_battle_round,revealed_at=coalesce(revealed_at,now()) where match_id=p_match_id and player_id=match_row.player_one_id; end if;
  if two_selection.selection_type='canon' then
    update public.match_characters set used_in_battle=true where id=two_selection.match_character_id;
    if two_boost>0 then update public.match_oc_preparations set revealed_at=coalesce(revealed_at,now()) where match_id=p_match_id and player_id=match_row.player_two_id and oc_type='sacrificial' and decision='sacrifice'; end if;
  else update public.match_oc_preparations set used_in_battle=true,used_in_round=match_row.current_battle_round,revealed_at=coalesce(revealed_at,now()) where match_id=p_match_id and player_id=match_row.player_two_id; end if;
  insert into public.match_rounds(match_id,round_number,winner_player_id,player_one_fighter_type,player_one_match_character_id,player_one_player_character_id,player_one_name,player_one_overall,player_one_power_score,player_two_fighter_type,player_two_match_character_id,player_two_player_character_id,player_two_name,player_two_overall,player_two_power_score)
  values(p_match_id,match_row.current_battle_round,round_winner,one_selection.selection_type,one_selection.match_character_id,one_selection.player_character_id,one_name,one_overall,one_power,two_selection.selection_type,two_selection.match_character_id,two_selection.player_character_id,two_name,two_overall,two_power);
  delete from public.battle_selections where match_id=p_match_id and round_number=match_row.current_battle_round;
  if next_one_score>=3 or next_two_score>=3 or match_row.current_battle_round=5 then
    final_winner:=case when next_one_score>next_two_score then match_row.player_one_id when next_two_score>next_one_score then match_row.player_two_id else null end;
    update public.matches set status='completed',battle_state='complete',player_one_score=next_one_score,player_two_score=next_two_score,winner_id=final_winner,completed_at=now(),action_version=action_version+1,updated_at=now() where id=p_match_id and status='battle';
    if final_winner is not null then update public.profiles set wins=wins+1 where id=final_winner; update public.profiles set losses=losses+1 where id=case when final_winner=match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end; end if;
    perform public.grant_ranked_match_boon_rewards(p_match_id);
  else update public.matches set battle_state='revealed',player_one_score=next_one_score,player_two_score=next_two_score,action_version=action_version+1,updated_at=now() where id=p_match_id; end if;
end $$;

create or replace function public.submit_battle_selection(p_match_id uuid,p_match_character_id uuid)
returns void language sql security definer set search_path='' as $$ select public.submit_battle_selection(p_match_id,'canon',p_match_character_id); $$;

-- 5. Canonical battle forfeit completion, with the same private reward call.
create or replace function public.forfeit_active_match(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  opponent_id uuid;
  match_row public.matches%rowtype;
  caller_reward bigint;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;

  select * into match_row from public.matches where id = p_match_id for update;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception 'Match unavailable';
  end if;
  if match_row.status = 'completed' and match_row.forfeited_by = caller_id then
    caller_reward := case when caller_id = match_row.player_one_id then match_row.player_one_boon_reward else match_row.player_two_boon_reward end;
    return jsonb_build_object('status', 'completed', 'winnerId', match_row.winner_id, 'forfeitedBy', caller_id, 'boonPointsEarned', coalesce(caller_reward, 0));
  end if;
  if match_row.status <> 'battle' then raise exception 'Match can no longer be forfeited'; end if;

  opponent_id := case when caller_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  if opponent_id is null then raise exception 'Opponent unavailable'; end if;

  update public.matches set status = 'completed', winner_id = opponent_id, forfeited_by = caller_id,
    completed_at = now(), action_version = action_version + 1, updated_at = now()
  where id = p_match_id and status = 'battle';

  update public.profiles set wins = wins + 1 where id = opponent_id;
  update public.profiles set losses = losses + 1 where id = caller_id;
  update public.matchmaking_queue set status = 'cancelled'
  where player_id in (caller_id, opponent_id);

  perform public.grant_ranked_match_boon_rewards(p_match_id);
  select * into match_row from public.matches where id = p_match_id;
  caller_reward := case when caller_id = match_row.player_one_id then match_row.player_one_boon_reward else match_row.player_two_boon_reward end;

  return jsonb_build_object('status', 'completed', 'winnerId', opponent_id, 'forfeitedBy', caller_id, 'boonPointsEarned', coalesce(caller_reward, 0));
end;
$$;

-- 6. Private owner read APIs. Match rewards are returned from their persisted
-- snapshot, so result refresh/reopen never recalculates or grants currency.
create or replace function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare caller_id uuid := auth.uid();
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  return (
    select jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'avatar_url', p.avatar_url,
      'is_guest', p.is_guest,
      'is_admin', p.is_admin,
      'is_system_player', p.is_system_player,
      'wins', p.wins,
      'losses', p.losses,
      'created_at', p.created_at,
      'boon_points', p.boon_points
    )
    from public.profiles p where p.id = caller_id
  );
end;
$$;

create or replace function public.get_my_boon_balance()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select case when p.is_guest or p.is_system_player then 0 else p.boon_points end
  from public.profiles p
  where p.id = auth.uid();
$$;

create or replace function public.get_my_match_boon_result(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  match_row public.matches%rowtype;
  reward bigint := 0;
  balance bigint := 0;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then
    raise exception 'Match unavailable';
  end if;

  if match_row.boon_rewards_granted_at is not null then
    reward := case when caller_id = match_row.player_one_id
      then match_row.player_one_boon_reward else match_row.player_two_boon_reward end;
  end if;

  select case when p.is_guest or p.is_system_player then 0 else p.boon_points end
    into balance from public.profiles p where p.id = caller_id;

  return jsonb_build_object(
    'boonPointsEarned', coalesce(reward, 0),
    'boonPointBalance', coalesce(balance, 0),
    'awarded', match_row.boon_rewards_granted_at is not null,
    'awardedAt', match_row.boon_rewards_granted_at
  );
end;
$$;

-- 7. Do not let the initiative SECURITY DEFINER response serialize the new
-- private balance. It now exposes only fields used by the initiative UI.
create or replace function public.get_match_initiative_state(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); match_row public.matches%rowtype; opponent_id uuid; resolved public.match_initiative_rounds%rowtype;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id = p_match_id;
  if not found or caller_id not in (match_row.player_one_id, match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  opponent_id := case when caller_id = match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  if match_row.initiative_state = 'revealed' then
    select * into resolved from public.match_initiative_rounds where match_id = p_match_id and initiative_round = match_row.initiative_round;
  end if;
  return jsonb_build_object(
    'matchId', match_row.id, 'status', match_row.status, 'initiativeRound', match_row.initiative_round,
    'initiativeState', match_row.initiative_state, 'yourPlayerId', caller_id, 'opponentPlayerId', opponent_id,
    'yourProfile', (select jsonb_build_object('id',p.id,'username',p.username,'avatar_url',p.avatar_url,'is_system_player',p.is_system_player) from public.profiles p where p.id = caller_id),
    'opponentProfile', (select jsonb_build_object('id',p.id,'username',p.username,'avatar_url',p.avatar_url,'is_system_player',p.is_system_player) from public.profiles p where p.id = opponent_id),
    'yourChoice', case when match_row.initiative_state = 'revealed' then case when caller_id = match_row.player_one_id then resolved.player_one_choice else resolved.player_two_choice end
      else (select c.choice from public.match_initiative_choices c where c.match_id = p_match_id and c.initiative_round = match_row.initiative_round and c.player_id = caller_id) end,
    'opponentLocked', case when match_row.initiative_state = 'revealed' then true else exists(select 1 from public.match_initiative_choices c where c.match_id = p_match_id and c.initiative_round = match_row.initiative_round and c.player_id = opponent_id) end,
    'opponentChoice', case when match_row.initiative_state = 'revealed' then case when caller_id = match_row.player_one_id then resolved.player_two_choice else resolved.player_one_choice end else null end,
    'winnerPlayerId', case when match_row.initiative_state = 'revealed' then resolved.winner_player_id else null end,
    'isDraw', match_row.initiative_state = 'revealed' and resolved.winner_player_id is null
  );
end;
$$;

-- 8. Browser permissions: public game/profile columns remain readable for the
-- existing UI, while boon_points has no direct SELECT or UPDATE grant.
revoke select on table public.profiles from anon, authenticated;
grant select (id, username, avatar_url, is_guest, is_admin, is_system_player, wins, losses, created_at)
  on public.profiles to authenticated;
revoke update (boon_points) on public.profiles from public, anon, authenticated;

revoke all on function public.grant_ranked_match_boon_rewards(uuid) from public, anon, authenticated;
revoke all on function public.get_my_profile() from public, anon;
revoke all on function public.get_my_boon_balance() from public, anon;
revoke all on function public.get_my_match_boon_result(uuid) from public, anon;
revoke all on function public.submit_battle_selection(uuid,text,uuid) from public, anon;
revoke all on function public.submit_battle_selection(uuid,uuid) from public, anon;
revoke all on function public.forfeit_active_match(uuid) from public, anon;
revoke all on function public.get_match_initiative_state(uuid) from public, anon;

grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.get_my_boon_balance() to authenticated;
grant execute on function public.get_my_match_boon_result(uuid) to authenticated;
grant execute on function public.submit_battle_selection(uuid,text,uuid) to authenticated;
grant execute on function public.submit_battle_selection(uuid,uuid) to authenticated;
grant execute on function public.forfeit_active_match(uuid) to authenticated;
grant execute on function public.get_match_initiative_state(uuid) to authenticated;

notify pgrst, 'reload schema';
