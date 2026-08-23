-- Read-only diagnosis for "OC reserve is unavailable".
-- Run in Supabase SQL Editor and return the result rows. This changes nothing.

with recent_battles as (
  select m.id, m.status, m.battle_state, m.updated_at
  from public.matches m
  where m.status in ('battle', 'completed')
  order by m.updated_at desc
  limit 5
)
select
  rb.id as match_id,
  rb.status,
  rb.battle_state,
  p.username,
  s.player_id,
  s.player_character_id as selected_oc_id,
  pc.name as persistent_oc_name,
  pc.oc_type as persistent_type,
  o.oc_type_snapshot as option_type,
  s.oc_type_snapshot as selection_type,
  prep.oc_type as preparation_type,
  prep.decision,
  prep.oc_sacrificed,
  prep.sacrificed_match_character_id,
  prep.base_overall,
  prep.match_overall,
  prep.base_power_score,
  prep.used_in_battle,
  case
    when prep.player_character_id is null then 'NO_PREPARATION_ROW'
    when prep.player_character_id is distinct from s.player_character_id then 'PREPARATION_OC_ID_MISMATCH'
    when prep.oc_type is distinct from 'champion' then 'PREPARATION_NOT_CHAMPION'
    when prep.decision not in ('reserve', 'absorb') then 'INVALID_CHAMPION_DECISION'
    when prep.oc_sacrificed then 'OC_MARKED_SACRIFICED'
    when prep.match_overall is null then 'MATCH_OVR_MISSING'
    when prep.base_power_score is null then 'MATCH_POWER_MISSING'
    when prep.used_in_battle then 'OC_ALREADY_USED'
    else 'RESERVE_ELIGIBLE'
  end as server_eligibility
from recent_battles rb
join public.match_oc_selections s on s.match_id=rb.id
join public.profiles p on p.id=s.player_id
left join public.player_characters pc on pc.id=s.player_character_id
left join public.match_oc_options o
  on o.match_id=s.match_id and o.player_id=s.player_id
  and o.player_character_id=s.player_character_id
left join public.match_oc_preparations prep
  on prep.match_id=s.match_id and prep.player_id=s.player_id
order by rb.updated_at desc, p.username;
