-- Focused OC selection type visibility repair.
-- Run after docs/supabase_oc_types_and_sacrifice.sql.
-- Own option types are returned from the immutable match snapshot.
-- Opponent option types are deliberately omitted.

-- Repair snapshots created while an older initializer/trigger version was active.
update public.match_oc_options o
set oc_type_snapshot=pc.oc_type
from public.player_characters pc
where pc.id=o.player_character_id and o.oc_type_snapshot is null;

update public.match_oc_selections s
set oc_type_snapshot=o.oc_type_snapshot
from public.match_oc_options o
where o.match_id=s.match_id and o.player_id=s.player_id
  and o.player_character_id=s.player_character_id
  and s.oc_type_snapshot is distinct from o.oc_type_snapshot;

-- Older preparation rows predate the role column. Preserve the player's
-- already-locked decision and restore only its immutable match role.
update public.match_oc_preparations p
set oc_type=coalesce(s.oc_type_snapshot,o.oc_type_snapshot)
from public.match_oc_selections s
left join public.match_oc_options o
  on o.match_id=s.match_id and o.player_id=s.player_id
  and o.player_character_id=s.player_character_id
where s.match_id=p.match_id and s.player_id=p.player_id
  and p.player_character_id=s.player_character_id
  and p.oc_type is distinct from coalesce(s.oc_type_snapshot,o.oc_type_snapshot);

do $$ declare c record; begin
  for c in select conname from pg_constraint
    where conrelid='public.match_oc_preparations'::regclass and contype='c'
      and (pg_get_constraintdef(oid) ilike '%decision%' or pg_get_constraintdef(oid) ilike '%sacrifice_boost%')
  loop execute format('alter table public.match_oc_preparations drop constraint %I',c.conname); end loop;
end $$;
alter table public.match_oc_preparations
  add constraint match_oc_preparations_role_check check(
    (decision='none' and player_character_id is null and oc_type is null)
    or (decision='reserve' and sacrificed_match_character_id is null and not oc_sacrificed and match_overall=base_overall)
    or (oc_type='champion' and decision='absorb' and sacrificed_match_character_id is not null and sacrifice_boost between 1 and 6 and not oc_sacrificed and match_overall>=base_overall)
    or (oc_type='sacrificial' and decision='inactive' and sacrificed_match_character_id is null and not oc_sacrificed and recipient_count=0)
    or (oc_type='sacrificial' and decision='sacrifice' and sacrificed_match_character_id is null and oc_sacrificed and recipient_count>0 and match_overall=base_overall)
  );
alter table public.match_oc_preparations
  add constraint match_oc_preparations_role_values_check
  check(sacrifice_boost between 0 and 6 and base_transfer_power>=0 and recipient_count>=0);
update public.match_oc_preparations p
set decision='reserve'
from public.matches m
where m.id=p.match_id and m.status<>'completed'
  and p.oc_type='sacrificial' and p.decision='inactive' and not p.oc_sacrificed;

create or replace function public.snapshot_match_oc_role() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  select pc.oc_type into new.oc_type_snapshot
  from public.player_characters pc where pc.id=new.player_character_id;
  if new.oc_type_snapshot is null then
    raise exception using errcode='23514',message='OC role snapshot is unavailable.';
  end if;
  return new;
end $$;
drop trigger if exists snapshot_match_oc_role on public.match_oc_options;
create trigger snapshot_match_oc_role before insert on public.match_oc_options
for each row execute function public.snapshot_match_oc_role();

create or replace function public.snapshot_selected_oc_role() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.player_character_id is not null then
    select o.oc_type_snapshot into new.oc_type_snapshot
    from public.match_oc_options o
    where o.match_id=new.match_id and o.player_id=new.player_id
      and o.player_character_id=new.player_character_id;
    if new.oc_type_snapshot is null then
      raise exception using errcode='23514',message='Selected OC role snapshot is unavailable.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists snapshot_selected_oc_role on public.match_oc_selections;
create trigger snapshot_selected_oc_role before insert on public.match_oc_selections
for each row execute function public.snapshot_selected_oc_role();

-- Defense in depth: an absorbed canon fighter can never be inserted as a
-- battle selection, even if a stale client fails to mark it disabled.
create or replace function public.reject_sacrificed_battle_selection()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.selection_type='canon' and exists(
    select 1 from public.match_oc_preparations p
    where p.match_id=new.match_id and p.player_id=new.player_id
      and p.sacrificed_match_character_id=new.match_character_id
  ) then
    raise exception using errcode='23514',message='Absorbed fighters cannot be used in battle.';
  end if;
  return new;
end $$;
drop trigger if exists reject_sacrificed_battle_selection on public.battle_selections;
create trigger reject_sacrificed_battle_selection
before insert on public.battle_selections
for each row execute function public.reject_sacrificed_battle_selection();

-- Compatibility overload for BIGINT canon snapshots. The canonical transfer
-- implementation remains the integer version; battle stat constraints keep
-- these values safely within the integer range.
create or replace function public.calculate_oc_power_transfer(
  p_oc_power integer,
  p_oc_overall integer,
  p_recipient_overall bigint,
  p_recipient_power bigint
)
returns table(
  base_transfer integer,
  ovr_difference integer,
  compatibility_percent integer,
  calculated_bonus integer,
  effective_bonus integer,
  match_power_score integer
)
language sql immutable set search_path='' as $$
  with transfer_values as (
    select
      floor(p_oc_power*20/100.0)::integer as base,
      abs(p_recipient_overall-p_oc_overall)::integer as gap
  ), compatibility_values as (
    select base,gap,
      case
        when gap<=4 then 100
        when gap<=9 then 85
        when gap<=14 then 70
        when gap<=19 then 55
        else 40
      end::integer as pct
    from transfer_values
  ), calculated_values as (
    select base,gap,pct,floor(base*pct/100.0)::integer as calculated
    from compatibility_values
  )
  select
    base,
    gap,
    pct,
    calculated,
    least(2000,calculated),
    least(12000,p_recipient_power::integer+least(2000,calculated))
  from calculated_values;
$$;

create table if not exists public.match_oc_power_boosts(
  match_id uuid not null references public.matches(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete restrict,
  player_character_id uuid not null references public.player_characters(id) on delete restrict,
  match_character_id uuid not null references public.match_characters(id) on delete restrict,
  oc_overall integer not null,
  oc_power_score integer not null,
  recipient_overall integer not null,
  recipient_base_power integer not null,
  ovr_difference integer not null,
  compatibility_percent integer not null,
  calculated_bonus integer not null,
  effective_bonus integer not null,
  match_power_score integer not null,
  created_at timestamptz not null default now(),
  primary key(match_id,match_character_id),
  check(compatibility_percent in(40,55,70,85,100)),
  check(effective_bonus between 0 and 2000),
  check(match_power_score between recipient_base_power and 12000)
);
create index if not exists match_oc_power_boosts_player_idx
  on public.match_oc_power_boosts(match_id,player_id);
alter table public.match_oc_power_boosts enable row level security;
revoke all on public.match_oc_power_boosts from public,anon,authenticated;
do $$ begin
  if exists(
    select 1 from pg_publication_tables pt
    join pg_publication p on p.pubname=pt.pubname
    where pt.pubname='supabase_realtime' and pt.schemaname='public'
      and pt.tablename='match_oc_power_boosts' and not p.puballtables
  ) then
    execute 'alter publication supabase_realtime drop table public.match_oc_power_boosts';
  end if;
end $$;

create or replace function public.get_match_oc_selection_state(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare caller_id uuid:=auth.uid(); match_row public.matches%rowtype; opponent_id uuid;
begin
  if caller_id is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  select * into match_row from public.matches where id=p_match_id;
  if not found or caller_id not in(match_row.player_one_id,match_row.player_two_id) then raise exception using errcode='42501',message='Match unavailable.'; end if;
  opponent_id:=case when caller_id=match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  return jsonb_build_object(
    'matchId',match_row.id,'status',match_row.status,'yourPlayerId',caller_id,'opponentPlayerId',opponent_id,
    'yourProfile',(select jsonb_build_object('id',p.id,'username',p.username,'avatar_url',p.avatar_url) from public.profiles p where p.id=caller_id),
    'opponentProfile',(select jsonb_build_object('id',p.id,'username',p.username,'avatar_url',p.avatar_url) from public.profiles p where p.id=opponent_id),
    'yourOptions',coalesce((select jsonb_agg(jsonb_build_object('characterId',o.player_character_id,'slot',o.slot,'name',o.name_snapshot,'verseId',o.verse_id,'verseName',o.verse_name_snapshot,'overall',o.overall_snapshot,'powerScore',o.power_score_snapshot,'overallCap',o.overall_cap_snapshot,'ocType',o.oc_type_snapshot) order by o.slot) from public.match_oc_options o where o.match_id=p_match_id and o.player_id=caller_id),'[]'::jsonb),
    'opponentOptions',coalesce((select jsonb_agg(jsonb_build_object('characterId',o.player_character_id,'slot',o.slot,'name',o.name_snapshot,'verseId',o.verse_id,'verseName',o.verse_name_snapshot,'overall',o.overall_snapshot,'powerScore',o.power_score_snapshot,'overallCap',o.overall_cap_snapshot) order by o.slot) from public.match_oc_options o where o.match_id=p_match_id and o.player_id=opponent_id),'[]'::jsonb),
    'yourSelectedCharacterId',(select s.player_character_id from public.match_oc_selections s where s.match_id=p_match_id and s.player_id=caller_id),
    'yourLocked',exists(select 1 from public.match_oc_selections s where s.match_id=p_match_id and s.player_id=caller_id),
    'opponentLocked',exists(select 1 from public.match_oc_selections s where s.match_id=p_match_id and s.player_id=opponent_id),
    'bothComplete',(select count(*)=2 from public.match_oc_selections s where s.match_id=p_match_id));
end $$;

create or replace function public.get_match_oc_preparation_state(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare caller_id uuid:=auth.uid(); match_row public.matches%rowtype; opponent_id uuid;
begin
  if caller_id is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  select * into match_row from public.matches where id=p_match_id;
  if not found or caller_id not in(match_row.player_one_id,match_row.player_two_id) then raise exception using errcode='42501',message='Match unavailable.'; end if;
  opponent_id:=case when caller_id=match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  return jsonb_build_object('matchId',p_match_id,'status',match_row.status,'yourPlayerId',caller_id,
    'yourOC',(select case when s.player_character_id is null then null else jsonb_build_object('characterId',s.player_character_id,'name',o.name_snapshot,'verseId',s.verse_id,'verseName',o.verse_name_snapshot,'baseOverall',s.base_overall,'powerScore',s.base_power_score,'ocType',coalesce(s.oc_type_snapshot,o.oc_type_snapshot)) end from public.match_oc_selections s left join public.match_oc_options o on o.match_id=s.match_id and o.player_id=s.player_id and o.player_character_id=s.player_character_id where s.match_id=p_match_id and s.player_id=caller_id),
    'eligibleSacrifices',coalesce((select jsonb_agg(jsonb_build_object('matchCharacterId',mc.id,'characterId',c.id,'name',c.name,'verseId',mc.verse_id_snapshot,'verseName',v.name,'overall',mc.overall_snapshot,'powerScore',mc.power_score_snapshot,'tier',public.get_character_tier(mc.overall_snapshot),'sacrificeBoost',public.get_sacrifice_ovr_boost(mc.overall_snapshot),'compatibilityPercent',x.compatibility_percent,'effectiveBonus',x.effective_bonus,'matchPowerScore',x.match_power_score) order by mc.draft_position)
      from public.match_characters mc join public.characters c on c.id=mc.character_id join public.verses v on v.id=mc.verse_id_snapshot join public.match_oc_selections s on s.match_id=mc.match_id and s.player_id=caller_id cross join lateral public.calculate_oc_power_transfer(s.base_power_score,s.base_overall,mc.overall_snapshot::integer,mc.power_score_snapshot::integer) x where mc.match_id=p_match_id and mc.owner_player_id=caller_id and s.player_character_id is not null and mc.verse_id_snapshot=s.verse_id),'[]'::jsonb),
    'yourPreparation',(select jsonb_build_object('ocType',p.oc_type,'decision',p.decision,'ocSacrificed',p.oc_sacrificed,'sacrificedMatchCharacterId',p.sacrificed_match_character_id,'sacrificeTier',p.sacrifice_tier,'sacrificeBoost',p.sacrifice_boost,'baseOverall',p.base_overall,'matchOverall',p.match_overall,'basePowerScore',p.base_power_score,'baseTransferPower',p.base_transfer_power,'recipientCount',p.recipient_count,'lockedAt',p.locked_at) from public.match_oc_preparations p where p.match_id=p_match_id and p.player_id=caller_id),
    'yourLocked',exists(select 1 from public.match_oc_preparations p where p.match_id=p_match_id and p.player_id=caller_id),
    'opponentLocked',exists(select 1 from public.match_oc_preparations p where p.match_id=p_match_id and p.player_id=opponent_id),
    'bothComplete',(select count(*)=2 from public.match_oc_preparations p where p.match_id=p_match_id));
end $$;

create or replace function public.submit_match_oc_preparation(p_match_id uuid,p_decision text,p_sacrificed_match_character_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  caller_id uuid:=auth.uid(); match_row public.matches%rowtype; selection_row public.match_oc_selections%rowtype;
  card_row public.match_characters%rowtype; tier_value text; boost_value integer; recipients integer; transfer integer;
begin
  if caller_id is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  select * into match_row from public.matches where id=p_match_id for update;
  if not found or caller_id not in(match_row.player_one_id,match_row.player_two_id) then raise exception using errcode='42501',message='Match unavailable.'; end if;
  if match_row.status<>'oc_preparation' then raise exception using errcode='23514',message='OC preparation is not active.'; end if;
  if exists(select 1 from public.match_oc_preparations where match_id=p_match_id and player_id=caller_id) then raise exception using errcode='23505',message='OC preparation is already locked.'; end if;
  select * into selection_row from public.match_oc_selections where match_id=p_match_id and player_id=caller_id for update;
  if not found or selection_row.player_character_id is null then raise exception using errcode='23514',message='No selected OC is available for preparation.'; end if;
  if selection_row.oc_type_snapshot='champion' then
    if p_decision='reserve' then
      if p_sacrificed_match_character_id is not null then raise exception using errcode='22023',message='Reserve cannot include an absorbed fighter.'; end if;
      insert into public.match_oc_preparations(match_id,player_id,player_character_id,verse_id,oc_type,decision,base_overall,match_overall,base_power_score) values(p_match_id,caller_id,selection_row.player_character_id,selection_row.verse_id,'champion','reserve',selection_row.base_overall,selection_row.base_overall,selection_row.base_power_score);
    elsif p_decision in('absorb','sacrifice') then
      if p_sacrificed_match_character_id is null then raise exception using errcode='22023',message='Choose a fighter to absorb.'; end if;
      select * into card_row from public.match_characters where id=p_sacrificed_match_character_id and match_id=p_match_id and owner_player_id=caller_id for update;
      if not found then raise exception using errcode='42501',message='Absorption fighter is unavailable.'; end if;
      if card_row.verse_id_snapshot<>selection_row.verse_id then raise exception using errcode='23514',message='Only a same-verse fighter may be absorbed.'; end if;
      tier_value:=public.get_character_tier(card_row.overall_snapshot); boost_value:=public.get_sacrifice_ovr_boost(card_row.overall_snapshot);
      insert into public.match_oc_preparations(match_id,player_id,player_character_id,verse_id,oc_type,decision,sacrificed_match_character_id,sacrifice_tier,sacrifice_boost,base_overall,match_overall,base_power_score) values(p_match_id,caller_id,selection_row.player_character_id,selection_row.verse_id,'champion','absorb',card_row.id,tier_value,boost_value,selection_row.base_overall,least(99,selection_row.base_overall+boost_value),selection_row.base_power_score);
    else raise exception using errcode='22023',message='Choose Reserve or Absorb Fighter for a Champion.'; end if;
  elsif selection_row.oc_type_snapshot='sacrificial' then
    if p_sacrificed_match_character_id is not null then raise exception using errcode='22023',message='Sacrificial recipients are determined by the server.'; end if;
    if p_decision='reserve' then
      insert into public.match_oc_preparations(match_id,player_id,player_character_id,verse_id,oc_type,decision,base_overall,match_overall,base_power_score) values(p_match_id,caller_id,selection_row.player_character_id,selection_row.verse_id,'sacrificial','reserve',selection_row.base_overall,selection_row.base_overall,selection_row.base_power_score);
    elsif p_decision='sacrifice' then
      select count(*) into recipients from public.match_characters mc where mc.match_id=p_match_id and mc.owner_player_id=caller_id and mc.verse_id_snapshot=selection_row.verse_id;
      if recipients=0 then raise exception using errcode='23514',message='This OC cannot empower your current team.'; end if;
      transfer:=floor(selection_row.base_power_score*20/100.0)::integer;
      insert into public.match_oc_preparations(match_id,player_id,player_character_id,verse_id,oc_type,decision,oc_sacrificed,base_overall,match_overall,base_power_score,base_transfer_power,recipient_count) values(p_match_id,caller_id,selection_row.player_character_id,selection_row.verse_id,'sacrificial','sacrifice',true,selection_row.base_overall,selection_row.base_overall,selection_row.base_power_score,transfer,recipients);
      insert into public.match_oc_power_boosts(match_id,player_id,player_character_id,match_character_id,oc_overall,oc_power_score,recipient_overall,recipient_base_power,ovr_difference,compatibility_percent,calculated_bonus,effective_bonus,match_power_score)
      select p_match_id,caller_id,selection_row.player_character_id,mc.id,selection_row.base_overall,selection_row.base_power_score,mc.overall_snapshot,mc.power_score_snapshot,x.ovr_difference,x.compatibility_percent,x.calculated_bonus,x.effective_bonus,x.match_power_score from public.match_characters mc cross join lateral public.calculate_oc_power_transfer(selection_row.base_power_score,selection_row.base_overall,mc.overall_snapshot::integer,mc.power_score_snapshot::integer) x where mc.match_id=p_match_id and mc.owner_player_id=caller_id and mc.verse_id_snapshot=selection_row.verse_id on conflict(match_id,match_character_id) do nothing;
    else raise exception using errcode='22023',message='Choose Reserve or Sacrifice OC.'; end if;
  else raise exception using errcode='23514',message='Selected OC role snapshot is unavailable.'; end if;
  update public.matches set action_version=action_version+1,updated_at=now() where id=p_match_id;
  if (select count(*) from public.match_oc_preparations where match_id=p_match_id)=2 then update public.matches set status='battle',action_version=action_version+1,updated_at=now() where id=p_match_id; perform public.initialize_online_battle(p_match_id); end if;
  return public.get_match_oc_preparation_state(p_match_id);
end $$;

-- Canonical role-aware battle state. Every OC may use Reserve; role-specific
-- modes are Champion/Absorb and Sacrificial/Sacrifice.
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
    select c.name,mc.overall_snapshot,coalesce(b.match_power_score,mc.power_score_snapshot),coalesce(b.effective_bonus,0) into one_name,one_overall,one_power,one_boost from public.match_characters mc join public.characters c on c.id=mc.character_id left join public.match_oc_power_boosts b on b.match_id=mc.match_id and b.match_character_id=mc.id where mc.id=one_selection.match_character_id;
  else select o.name_snapshot,p.match_overall,p.base_power_score into one_name,one_overall,one_power from public.match_oc_preparations p join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id where p.match_id=p_match_id and p.player_id=match_row.player_one_id; end if;
  if two_selection.selection_type='canon' then
    select c.name,mc.overall_snapshot,coalesce(b.match_power_score,mc.power_score_snapshot),coalesce(b.effective_bonus,0) into two_name,two_overall,two_power,two_boost from public.match_characters mc join public.characters c on c.id=mc.character_id left join public.match_oc_power_boosts b on b.match_id=mc.match_id and b.match_character_id=mc.id where mc.id=two_selection.match_character_id;
  else select o.name_snapshot,p.match_overall,p.base_power_score into two_name,two_overall,two_power from public.match_oc_preparations p join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id where p.match_id=p_match_id and p.player_id=match_row.player_two_id; end if;
  round_winner:=case when one_overall>two_overall then match_row.player_one_id when two_overall>one_overall then match_row.player_two_id when one_power>two_power then match_row.player_one_id when two_power>one_power then match_row.player_two_id else null end;
  next_one_score:=match_row.player_one_score+case when round_winner=match_row.player_one_id then 1 else 0 end;
  next_two_score:=match_row.player_two_score+case when round_winner=match_row.player_two_id then 1 else 0 end;
  if one_selection.selection_type='canon' then update public.match_characters set used_in_battle=true where id=one_selection.match_character_id; if one_boost>0 then update public.match_oc_preparations set revealed_at=coalesce(revealed_at,now()) where match_id=p_match_id and player_id=match_row.player_one_id and oc_type='sacrificial' and decision='sacrifice'; end if; else update public.match_oc_preparations set used_in_battle=true,used_in_round=match_row.current_battle_round,revealed_at=coalesce(revealed_at,now()) where match_id=p_match_id and player_id=match_row.player_one_id; end if;
  if two_selection.selection_type='canon' then update public.match_characters set used_in_battle=true where id=two_selection.match_character_id; if two_boost>0 then update public.match_oc_preparations set revealed_at=coalesce(revealed_at,now()) where match_id=p_match_id and player_id=match_row.player_two_id and oc_type='sacrificial' and decision='sacrifice'; end if; else update public.match_oc_preparations set used_in_battle=true,used_in_round=match_row.current_battle_round,revealed_at=coalesce(revealed_at,now()) where match_id=p_match_id and player_id=match_row.player_two_id; end if;
  insert into public.match_rounds(match_id,round_number,winner_player_id,player_one_fighter_type,player_one_match_character_id,player_one_player_character_id,player_one_name,player_one_overall,player_one_power_score,player_two_fighter_type,player_two_match_character_id,player_two_player_character_id,player_two_name,player_two_overall,player_two_power_score) values(p_match_id,match_row.current_battle_round,round_winner,one_selection.selection_type,one_selection.match_character_id,one_selection.player_character_id,one_name,one_overall,one_power,two_selection.selection_type,two_selection.match_character_id,two_selection.player_character_id,two_name,two_overall,two_power);
  delete from public.battle_selections where match_id=p_match_id and round_number=match_row.current_battle_round;
  if next_one_score>=3 or next_two_score>=3 or match_row.current_battle_round=5 then
    final_winner:=case when next_one_score>next_two_score then match_row.player_one_id when next_two_score>next_one_score then match_row.player_two_id else null end;
    update public.matches set status='completed',battle_state='complete',player_one_score=next_one_score,player_two_score=next_two_score,winner_id=final_winner,completed_at=now(),action_version=action_version+1,updated_at=now() where id=p_match_id and status='battle';
    if final_winner is not null then update public.profiles set wins=wins+1 where id=final_winner; update public.profiles set losses=losses+1 where id=case when final_winner=match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end; end if;
  else update public.matches set battle_state='revealed',player_one_score=next_one_score,player_two_score=next_two_score,action_version=action_version+1,updated_at=now() where id=p_match_id; end if;
end $$;

create or replace function public.get_online_battle_state(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare caller_id uuid:=auth.uid(); match_row public.matches%rowtype; opponent_id uuid;
begin
  if caller_id is null then raise exception 'Authentication required'; end if;
  select * into match_row from public.matches where id=p_match_id;
  if not found or caller_id not in(match_row.player_one_id,match_row.player_two_id) then raise exception 'Match unavailable'; end if;
  if match_row.status not in('battle','completed') then raise exception 'Battle is not available'; end if;
  opponent_id:=case when caller_id=match_row.player_one_id then match_row.player_two_id else match_row.player_one_id end;
  return jsonb_build_object(
    'matchId',match_row.id,'status',match_row.status,'roundNumber',match_row.current_battle_round,'battleState',match_row.battle_state,
    'yourPlayerId',caller_id,'opponentPlayerId',opponent_id,
    'yourScore',case when caller_id=match_row.player_one_id then match_row.player_one_score else match_row.player_two_score end,
    'opponentScore',case when caller_id=match_row.player_one_id then match_row.player_two_score else match_row.player_one_score end,'matchWinnerId',match_row.winner_id,
    'yourProfile',(select jsonb_build_object('id',p.id,'username',p.username,'wins',p.wins,'losses',p.losses,'is_system_player',p.is_system_player) from public.profiles p where p.id=caller_id),
    'opponentProfile',(select jsonb_build_object('id',p.id,'username',p.username,'is_system_player',p.is_system_player) from public.profiles p where p.id=opponent_id),
    'yourTeam',coalesce((select jsonb_agg(jsonb_build_object('id',mc.id,'used',mc.used_in_battle,
      'sacrificed',exists(select 1 from public.match_oc_preparations prep where prep.match_id=p_match_id and prep.player_id=caller_id and prep.sacrificed_match_character_id=mc.id),
      'empowered',coalesce(b.effective_bonus,0)>0,'basePowerScore',mc.power_score_snapshot,'matchPowerScore',coalesce(b.match_power_score,mc.power_score_snapshot),'powerBoost',coalesce(b.effective_bonus,0),
      'character',to_jsonb(c)||jsonb_build_object('overall',mc.overall_snapshot,'power_score',coalesce(b.match_power_score,mc.power_score_snapshot),'verses',(select to_jsonb(v) from public.verses v where v.id=mc.verse_id_snapshot))) order by mc.draft_position)
      from public.match_characters mc join public.characters c on c.id=mc.character_id left join public.match_oc_power_boosts b on b.match_id=mc.match_id and b.match_character_id=mc.id where mc.match_id=p_match_id and mc.owner_player_id=caller_id),'[]'::jsonb),
    'opponentTeam',coalesce((select jsonb_agg(jsonb_build_object('id',mc.id,'used',mc.used_in_battle,
      'character',to_jsonb(c)||jsonb_build_object('overall',mc.overall_snapshot,'power_score',mc.power_score_snapshot,'verses',(select to_jsonb(v) from public.verses v where v.id=mc.verse_id_snapshot))) order by mc.draft_position)
      from public.match_characters mc join public.characters c on c.id=mc.character_id where mc.match_id=p_match_id and mc.owner_player_id=opponent_id),'[]'::jsonb),
    'yourOC',(select case when p.player_character_id is null or not (p.decision='reserve' or (p.oc_type='champion' and p.decision='absorb')) then null else jsonb_build_object('id',p.player_character_id,'name',o.name_snapshot,'verseName',o.verse_name_snapshot,'overall',p.match_overall,'powerScore',p.base_power_score,'used',p.used_in_battle,'boost',p.sacrifice_boost,'ocType',p.oc_type,'decision',p.decision) end from public.match_oc_preparations p left join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id where p.match_id=p_match_id and p.player_id=caller_id),
    'opponentOC',(select case when p.revealed_at is null or not (p.decision='reserve' or (p.oc_type='champion' and p.decision='absorb')) then null else jsonb_build_object('id',p.player_character_id,'name',o.name_snapshot,'verseName',o.verse_name_snapshot,'overall',p.match_overall,'powerScore',p.base_power_score,'used',p.used_in_battle,'boost',p.sacrifice_boost,'ocType',p.oc_type,'decision',p.decision,'sacrificeTier',p.sacrifice_tier,'sacrificeBoost',p.sacrifice_boost,'sacrificedName',(select c.name from public.match_characters mc join public.characters c on c.id=mc.character_id where mc.id=p.sacrificed_match_character_id)) end from public.match_oc_preparations p left join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id where p.match_id=p_match_id and p.player_id=opponent_id),
    'yourSupport',(select case when p.player_character_id is null or p.oc_type<>'sacrificial' or p.decision not in('inactive','sacrifice') then null else jsonb_build_object('id',p.player_character_id,'name',o.name_snapshot,'verseName',o.verse_name_snapshot,'overall',p.match_overall,'powerScore',p.base_power_score,'used',true,'boost',0,'ocType',p.oc_type,'decision',p.decision,'recipientCount',p.recipient_count) end from public.match_oc_preparations p left join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id where p.match_id=p_match_id and p.player_id=caller_id),
    'opponentSupport',(select case when p.revealed_at is null or p.oc_type<>'sacrificial' or p.decision not in('inactive','sacrifice') then null else jsonb_build_object('id',p.player_character_id,'name',o.name_snapshot,'verseName',o.verse_name_snapshot,'overall',p.match_overall,'powerScore',p.base_power_score,'used',true,'boost',0,'ocType',p.oc_type,'decision',p.decision,'recipientCount',p.recipient_count) end from public.match_oc_preparations p left join public.match_oc_options o on o.match_id=p.match_id and o.player_id=p.player_id and o.player_character_id=p.player_character_id where p.match_id=p_match_id and p.player_id=opponent_id),
    'yourSelection',(select jsonb_build_object('type',bs.selection_type,'id',coalesce(bs.match_character_id,bs.player_character_id)) from public.battle_selections bs where bs.match_id=p_match_id and bs.round_number=match_row.current_battle_round and bs.player_id=caller_id),
    'opponentLocked',exists(select 1 from public.battle_selections bs where bs.match_id=p_match_id and bs.round_number=match_row.current_battle_round and bs.player_id=opponent_id),
    'latestRound',(select jsonb_build_object('roundNumber',r.round_number,
      'yourFighter',case when caller_id=match_row.player_one_id then jsonb_build_object('type',r.player_one_fighter_type,'id',coalesce(r.player_one_match_character_id,r.player_one_player_character_id),'name',r.player_one_name,'overall',r.player_one_overall,'powerScore',r.player_one_power_score,'empowered',coalesce(b1.effective_bonus,0)>0,'powerBoost',coalesce(b1.effective_bonus,0)) else jsonb_build_object('type',r.player_two_fighter_type,'id',coalesce(r.player_two_match_character_id,r.player_two_player_character_id),'name',r.player_two_name,'overall',r.player_two_overall,'powerScore',r.player_two_power_score,'empowered',coalesce(b2.effective_bonus,0)>0,'powerBoost',coalesce(b2.effective_bonus,0)) end,
      'opponentFighter',case when caller_id=match_row.player_one_id then jsonb_build_object('type',r.player_two_fighter_type,'id',coalesce(r.player_two_match_character_id,r.player_two_player_character_id),'name',r.player_two_name,'overall',r.player_two_overall,'powerScore',r.player_two_power_score,'empowered',coalesce(b2.effective_bonus,0)>0,'powerBoost',coalesce(b2.effective_bonus,0)) else jsonb_build_object('type',r.player_one_fighter_type,'id',coalesce(r.player_one_match_character_id,r.player_one_player_character_id),'name',r.player_one_name,'overall',r.player_one_overall,'powerScore',r.player_one_power_score,'empowered',coalesce(b1.effective_bonus,0)>0,'powerBoost',coalesce(b1.effective_bonus,0)) end,
      'winnerPlayerId',r.winner_player_id) from public.match_rounds r left join public.match_oc_power_boosts b1 on b1.match_id=r.match_id and b1.match_character_id=r.player_one_match_character_id left join public.match_oc_power_boosts b2 on b2.match_id=r.match_id and b2.match_character_id=r.player_two_match_character_id where r.match_id=p_match_id order by r.round_number desc limit 1));
end $$;

revoke all on function public.get_match_oc_selection_state(uuid) from public, anon;
grant execute on function public.get_match_oc_selection_state(uuid) to authenticated;
revoke all on function public.get_match_oc_preparation_state(uuid) from public, anon;
grant execute on function public.get_match_oc_preparation_state(uuid) to authenticated;
revoke all on function public.submit_match_oc_preparation(uuid,text,uuid) from public, anon;
grant execute on function public.submit_match_oc_preparation(uuid,text,uuid) to authenticated;
revoke all on function public.get_online_battle_state(uuid) from public, anon;
grant execute on function public.get_online_battle_state(uuid) to authenticated;
revoke all on function public.submit_battle_selection(uuid,text,uuid) from public, anon;
grant execute on function public.submit_battle_selection(uuid,text,uuid) to authenticated;
revoke all on function public.snapshot_match_oc_role(), public.snapshot_selected_oc_role() from public, anon, authenticated;
revoke all on function public.reject_sacrificed_battle_selection() from public, anon, authenticated;
revoke all on function public.calculate_oc_power_transfer(integer,integer,bigint,bigint) from public, anon, authenticated;
notify pgrst,'reload schema';
