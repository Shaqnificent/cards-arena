-- Anime Arena Boon Catalogue V2
-- 100 mechanically varied player-facing Boons.
--
-- IMPORTANT:
-- 1) This seed introduces effect_config JSONB for conditional/scaled effects.
-- 2) Your Phase 5 boon resolver MUST be upgraded to understand effect_config
--    before these Boons are used in live ranked matches.
-- 3) Existing player-facing Boons are deactivated, not deleted.
-- 4) Administrator/system-only Boons are intentionally left untouched.
-- 5) Existing player_boons rows are NOT deleted by this script.
--
-- Recommended rollout:
--   A. run this migration/seed
--   B. update resolver to V2 config rules
--   C. test in non-production
--   D. decide how to handle players who still own legacy inactive Boons

begin;

alter table public.boon_definitions
  add column if not exists effect_config jsonb;

-- Deactivate current PLAYER-FACING catalogue without touching system-only
-- Administrator definitions when a system_only column exists.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'boon_definitions'
      and column_name = 'system_only'
  ) then
    execute '
      update public.boon_definitions
      set active = false
      where coalesce(system_only, false) = false
    ';
  else
    update public.boon_definitions
    set active = false;
  end if;
end $$;

insert into public.boon_definitions
(
  key,
  name,
  description,
  rarity,
  effect_type,
  effect_value,
  target_rule,
  active,
  roll_weight,
  effect_config
)
values
(
  'v2_awakened_instinct',
  'Awakened Instinct',
  'Your selected playable OC gains +1 temporary OVR.',
  'common',
  'oc_overall',
  1,
  'selected_oc',
  true,
  60,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"overall","mode":"flat","value":1,"cap":99}}'::jsonb
),
(
  'v2_limit_break',
  'Limit Break',
  'Your selected playable OC gains +2 temporary OVR.',
  'epic',
  'oc_overall',
  2,
  'selected_oc',
  true,
  18,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_prodigy_aura',
  'Prodigy Aura',
  'Your selected playable OC gains more OVR when its base OVR is lower.',
  'rare',
  'oc_overall',
  4,
  'selected_oc',
  true,
  32,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"overall","mode":"tiered","tiers":[{"max":69,"value":4},{"min":70,"max":79,"value":3},{"min":80,"max":89,"value":2},{"min":90,"value":1}],"cap":99}}'::jsonb
),
(
  'v2_veteran_aura',
  'Veteran Aura',
  'Your selected playable OC gains more Power when it starts at 90+ OVR.',
  'rare',
  'oc_power',
  750,
  'selected_oc',
  true,
  34,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"power","mode":"tiered_by_overall","tiers":[{"max":89,"value":350},{"min":90,"value":750}],"cap":12000}}'::jsonb
),
(
  'v2_apex_energy',
  'Apex Energy',
  'Your selected playable OC gains 12% temporary Global Power.',
  'epic',
  'oc_power',
  12,
  'selected_oc',
  true,
  16,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"power","mode":"percent","percent":12,"round":"floor","cap_bonus":1000,"cap":12000}}'::jsonb
),
(
  'v2_spirit_amplifier',
  'Spirit Amplifier',
  'Your selected playable OC gains 8% temporary Global Power.',
  'rare',
  'oc_power',
  8,
  'selected_oc',
  true,
  34,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"power","mode":"percent","percent":8,"round":"floor","cap_bonus":700,"cap":12000}}'::jsonb
),
(
  'v2_lowborn_potential',
  'Lowborn Potential',
  'Your selected playable OC gains +1 OVR for every 8 OVR below 90, capped at +4.',
  'epic',
  'oc_overall',
  4,
  'selected_oc',
  true,
  15,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"overall","mode":"gap_steps","reference":90,"step":8,"per_step":1,"min_bonus":0,"max_bonus":4,"cap":99}}'::jsonb
),
(
  'v2_pressure_release',
  'Pressure Release',
  'Your selected OC gains +900 Power below 80 OVR, otherwise +350.',
  'rare',
  'oc_power',
  900,
  'selected_oc',
  true,
  30,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"power","mode":"tiered_by_overall","tiers":[{"max":79,"value":900},{"min":80,"value":350}],"cap":12000}}'::jsonb
),
(
  'v2_steady_heart',
  'Steady Heart',
  'Your selected playable OC gains 5% temporary Global Power.',
  'common',
  'oc_power',
  5,
  'selected_oc',
  true,
  58,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"power","mode":"percent","percent":5,"round":"floor","cap_bonus":450,"cap":12000}}'::jsonb
),
(
  'v2_overcap_focus',
  'Overcap Focus',
  'If your selected playable OC is 85 OVR or lower, it gains +3 OVR; otherwise +1.',
  'legendary',
  'oc_overall',
  3,
  'selected_oc',
  true,
  7,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"overall","mode":"tiered","tiers":[{"max":85,"value":3},{"min":86,"value":1}],"cap":99}}'::jsonb
),
(
  'v2_oc_equalizer',
  'OC Equalizer',
  'Your selected OC gains OVR based on the gap to your highest drafted canon fighter, capped at +4.',
  'epic',
  'oc_overall',
  4,
  'selected_oc',
  true,
  14,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"overall","mode":"gap_to_roster_highest","divisor":3,"round":"floor","min_bonus":0,"max_bonus":4,"cap":99}}'::jsonb
),
(
  'v2_oc_power_equalizer',
  'OC Power Equalizer',
  'Your selected OC gains 25% of the Power gap to your strongest drafted canon fighter.',
  'rare',
  'oc_power',
  25,
  'selected_oc',
  true,
  28,
  '{"target":"selected_oc","condition":{"type":"playable_oc"},"effect":{"stat":"power","mode":"gap_percent_to_roster_highest_power","percent":25,"round":"floor","cap_bonus":900,"cap":12000}}'::jsonb
),
(
  'v2_champion_resolve',
  'Champion Resolve',
  'If your selected OC is a Champion, gain +2 OVR and +300 Power.',
  'epic',
  'hybrid',
  2,
  'selected_oc',
  true,
  13,
  '{"target":"selected_oc","condition":{"type":"oc_type","value":"champion"},"effects":[{"stat":"overall","mode":"flat","value":2,"cap":99},{"stat":"power","mode":"flat","value":300,"cap":12000}]}'::jsonb
),
(
  'v2_sacrificial_resonance',
  'Sacrificial Resonance',
  'If your selected OC is Sacrificial, matching canon fighters gain 10% Power.',
  'epic',
  'verse_power',
  10,
  'same_verse_as_selected_oc',
  true,
  14,
  '{"target":"same_verse_canon","condition":{"type":"selected_oc_type","value":"sacrificial"},"effect":{"stat":"power","mode":"percent","percent":10,"round":"floor","cap_bonus":800,"cap":12000}}'::jsonb
),
(
  'v2_oc_last_stand',
  'OC Last Stand',
  'If your selected playable OC is below 75 OVR, gain +3 OVR and +500 Power.',
  'legendary',
  'hybrid',
  3,
  'selected_oc',
  true,
  6,
  '{"target":"selected_oc","condition":{"type":"all","rules":[{"type":"playable_oc"},{"type":"target_overall_below","value":75}]},"effects":[{"stat":"overall","mode":"flat","value":3,"cap":99},{"stat":"power","mode":"flat","value":500,"cap":12000}]}'::jsonb
),
(
  'v2_underdog',
  'Underdog',
  'Your lowest-OVR drafted canon fighter gains +3 temporary OVR.',
  'rare',
  'drafted_overall',
  3,
  'lowest_drafted_canon',
  true,
  34,
  '{"target":"lowest_drafted_canon","effect":{"stat":"overall","mode":"flat","value":3,"cap":99}}'::jsonb
),
(
  'v2_desperate_growth',
  'Desperate Growth',
  'Your lowest-OVR drafted fighter gains more OVR the weaker it is.',
  'epic',
  'drafted_overall',
  5,
  'lowest_drafted_canon',
  true,
  15,
  '{"target":"lowest_drafted_canon","effect":{"stat":"overall","mode":"tiered","tiers":[{"max":69,"value":5},{"min":70,"max":79,"value":4},{"min":80,"max":89,"value":2},{"min":90,"value":1}],"cap":99}}'::jsonb
),
(
  'v2_catch_up',
  'Catch Up',
  'Your lowest-OVR drafted fighter gains OVR based on the gap to your highest-OVR drafted fighter.',
  'rare',
  'drafted_overall',
  4,
  'lowest_drafted_canon',
  true,
  30,
  '{"target":"lowest_drafted_canon","effect":{"stat":"overall","mode":"gap_to_highest","divisor":3,"round":"floor","min_bonus":1,"max_bonus":4,"cap":99}}'::jsonb
),
(
  'v2_second_lowest',
  'Second Wind',
  'Your second-lowest OVR drafted canon fighter gains +2 OVR.',
  'rare',
  'drafted_overall',
  2,
  'second_lowest_drafted',
  true,
  32,
  '{"target":"second_lowest_drafted_canon","effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_middle_ground',
  'Middle Ground',
  'Your median-OVR drafted canon fighter gains +3 OVR.',
  'epic',
  'drafted_overall',
  3,
  'median_drafted_canon',
  true,
  14,
  '{"target":"median_drafted_canon","effect":{"stat":"overall","mode":"flat","value":3,"cap":99}}'::jsonb
),
(
  'v2_elite_training',
  'Elite Training',
  'Your highest-OVR drafted canon fighter gains +1 OVR.',
  'common',
  'drafted_overall',
  1,
  'highest_drafted_canon',
  true,
  58,
  '{"target":"highest_drafted_canon","effect":{"stat":"overall","mode":"flat","value":1,"cap":99}}'::jsonb
),
(
  'v2_ace_pressure',
  'Ace Pressure',
  'Your highest-OVR drafted canon fighter gains +2 OVR only if it is below 95 OVR.',
  'epic',
  'drafted_overall',
  2,
  'highest_drafted_canon',
  true,
  15,
  '{"target":"highest_drafted_canon","condition":{"type":"target_overall_below","value":95},"effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_twin_peaks',
  'Twin Peaks',
  'Your two highest-OVR drafted canon fighters each gain +1 OVR.',
  'rare',
  'team_overall',
  1,
  'two_highest_drafted',
  true,
  30,
  '{"target":"two_highest_drafted_canon","effect":{"stat":"overall","mode":"flat","value":1,"cap":99}}'::jsonb
),
(
  'v2_balanced_formation',
  'Balanced Formation',
  'Your three lowest-OVR drafted canon fighters each gain +1 OVR.',
  'rare',
  'team_overall',
  1,
  'three_lowest_drafted',
  true,
  36,
  '{"target":"three_lowest_drafted_canon","effect":{"stat":"overall","mode":"flat","value":1,"cap":99}}'::jsonb
),
(
  'v2_rising_line',
  'Rising Line',
  'Your two lowest-OVR drafted canon fighters each gain +2 OVR.',
  'epic',
  'team_overall',
  2,
  'two_lowest_drafted',
  true,
  15,
  '{"target":"two_lowest_drafted_canon","effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_low_tier_training',
  'Low Tier Training',
  'Every drafted canon fighter below 80 OVR gains +1 OVR.',
  'common',
  'team_overall',
  1,
  'drafted_below_80',
  true,
  52,
  '{"target":"drafted_canon_matching","condition":{"type":"target_overall_below","value":80},"effect":{"stat":"overall","mode":"flat","value":1,"cap":99}}'::jsonb
),
(
  'v2_breakthrough_85',
  'Breakthrough 85',
  'One random drafted canon fighter below 85 OVR gains +2 OVR.',
  'rare',
  'drafted_overall',
  2,
  'random_drafted_below_85',
  true,
  28,
  '{"target":"random_drafted_canon","condition":{"type":"target_overall_below","value":85},"effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_elite_only',
  'Elite Only',
  'All drafted canon fighters at 90+ OVR gain +1 OVR.',
  'epic',
  'team_overall',
  1,
  'drafted_90_plus',
  true,
  13,
  '{"target":"drafted_canon_matching","condition":{"type":"target_overall_at_least","value":90},"effect":{"stat":"overall","mode":"flat","value":1,"cap":99}}'::jsonb
),
(
  'v2_weakest_two_scale',
  'Twin Underdogs',
  'Your two lowest-OVR drafted fighters gain +1 to +4 OVR based on how far they are below 90.',
  'legendary',
  'team_overall',
  4,
  'two_lowest_drafted',
  true,
  7,
  '{"target":"two_lowest_drafted_canon","effect":{"stat":"overall","mode":"gap_steps","reference":90,"step":8,"per_step":1,"min_bonus":1,"max_bonus":4,"cap":99}}'::jsonb
),
(
  'v2_singleton_hero',
  'Lone Wolf',
  'A drafted fighter whose verse appears only once on your team gains +3 OVR.',
  'epic',
  'drafted_overall',
  3,
  'singleton_verse_fighter',
  true,
  14,
  '{"target":"random_singleton_verse_canon","effect":{"stat":"overall","mode":"flat","value":3,"cap":99}}'::jsonb
),
(
  'v2_same_verse_pair',
  'Twin Souls',
  'If exactly two drafted canon fighters share a verse, both gain +2 OVR.',
  'rare',
  'team_overall',
  2,
  'exactly_two_same_verse',
  true,
  28,
  '{"target":"exactly_two_same_verse_canon","effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_cross_verse_training',
  'Cross-Verse Training',
  'A random drafted canon fighter from a different verse than your selected OC gains +3 OVR.',
  'epic',
  'drafted_overall',
  3,
  'different_verse_from_oc',
  true,
  14,
  '{"target":"random_canon_different_verse_from_selected_oc","effect":{"stat":"overall","mode":"flat","value":3,"cap":99}}'::jsonb
),
(
  'v2_oc_mentor',
  'OC Mentor',
  'Your lowest-OVR canon fighter matching your selected OC''s verse gains +3 OVR.',
  'rare',
  'drafted_overall',
  3,
  'lowest_same_verse_as_oc',
  true,
  28,
  '{"target":"lowest_same_verse_canon_as_selected_oc","effect":{"stat":"overall","mode":"flat","value":3,"cap":99}}'::jsonb
),
(
  'v2_oc_rival',
  'OC Rival',
  'Your highest-OVR canon fighter from a different verse than your selected OC gains +2 OVR.',
  'epic',
  'drafted_overall',
  2,
  'highest_different_verse_from_oc',
  true,
  14,
  '{"target":"highest_canon_different_verse_from_selected_oc","effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_threshold_climber',
  'Threshold Climber',
  'Your lowest-OVR fighter gains +4 OVR below 70, +3 below 80, +2 below 90, otherwise +1.',
  'rare',
  'drafted_overall',
  4,
  'lowest_drafted_canon',
  true,
  28,
  '{"target":"lowest_drafted_canon","effect":{"stat":"overall","mode":"tiered","tiers":[{"max":69,"value":4},{"min":70,"max":79,"value":3},{"min":80,"max":89,"value":2},{"min":90,"value":1}],"cap":99}}'::jsonb
),
(
  'v2_power_awakening',
  'Power Awakening',
  'Your lowest-Power drafted fighter gains more Power the lower its current Power.',
  'rare',
  'drafted_power',
  1000,
  'lowest_power_drafted',
  true,
  32,
  '{"target":"lowest_power_drafted_canon","effect":{"stat":"power","mode":"tiered_by_power","tiers":[{"max":6999,"value":1000},{"min":7000,"max":8499,"value":700},{"min":8500,"max":9999,"value":400},{"min":10000,"value":200}],"cap":12000}}'::jsonb
),
(
  'v2_focused_aura',
  'Focused Aura',
  'Your lowest-Power drafted canon fighter gains 15% temporary Power.',
  'rare',
  'drafted_power',
  15,
  'lowest_power_drafted',
  true,
  30,
  '{"target":"lowest_power_drafted_canon","effect":{"stat":"power","mode":"percent","percent":15,"round":"floor","cap_bonus":1200,"cap":12000}}'::jsonb
),
(
  'v2_heavy_hitter',
  'Heavy Hitter',
  'Your highest-Power drafted canon fighter gains +400 Power.',
  'common',
  'drafted_power',
  400,
  'highest_power_drafted',
  true,
  55,
  '{"target":"highest_power_drafted_canon","effect":{"stat":"power","mode":"flat","value":400,"cap":12000}}'::jsonb
),
(
  'v2_power_gap',
  'Power Gap',
  'Your lowest-Power drafted fighter gains 25% of the gap to your strongest drafted fighter.',
  'rare',
  'drafted_power',
  25,
  'lowest_power_drafted',
  true,
  30,
  '{"target":"lowest_power_drafted_canon","effect":{"stat":"power","mode":"gap_percent_to_highest","percent":25,"round":"floor","cap_bonus":1000,"cap":12000}}'::jsonb
),
(
  'v2_power_spread',
  'Power Spread',
  'Your three lowest-Power drafted canon fighters each gain +300 Power.',
  'rare',
  'team_power',
  300,
  'three_lowest_power',
  true,
  32,
  '{"target":"three_lowest_power_drafted_canon","effect":{"stat":"power","mode":"flat","value":300,"cap":12000}}'::jsonb
),
(
  'v2_low_power_surge',
  'Low Power Surge',
  'Every drafted canon fighter below 8,000 Power gains +500 Power.',
  'epic',
  'team_power',
  500,
  'drafted_below_8000_power',
  true,
  15,
  '{"target":"drafted_canon_matching","condition":{"type":"target_power_below","value":8000},"effect":{"stat":"power","mode":"flat","value":500,"cap":12000}}'::jsonb
),
(
  'v2_high_power_refinement',
  'High Power Refinement',
  'Drafted canon fighters at 9,500+ Power gain +250 Power.',
  'rare',
  'team_power',
  250,
  'drafted_9500_plus_power',
  true,
  28,
  '{"target":"drafted_canon_matching","condition":{"type":"target_power_at_least","value":9500},"effect":{"stat":"power","mode":"flat","value":250,"cap":12000}}'::jsonb
),
(
  'v2_percentage_training',
  'Percentage Training',
  'One random drafted canon fighter gains 5% temporary Power.',
  'common',
  'drafted_power',
  5,
  'random_drafted_canon',
  true,
  54,
  '{"target":"random_drafted_canon","effect":{"stat":"power","mode":"percent","percent":5,"round":"floor","cap_bonus":500,"cap":12000}}'::jsonb
),
(
  'v2_deep_reserves',
  'Deep Reserves',
  'Your lowest-Power fighter gains 12% Power, capped at +1,000.',
  'epic',
  'drafted_power',
  12,
  'lowest_power_drafted',
  true,
  14,
  '{"target":"lowest_power_drafted_canon","effect":{"stat":"power","mode":"percent","percent":12,"round":"floor","cap_bonus":1000,"cap":12000}}'::jsonb
),
(
  'v2_power_equalizer',
  'Power Equalizer',
  'Your lowest-Power fighter gains 40% of the Power gap to your strongest fighter.',
  'epic',
  'drafted_power',
  40,
  'lowest_power_drafted',
  true,
  14,
  '{"target":"lowest_power_drafted_canon","effect":{"stat":"power","mode":"gap_percent_to_highest","percent":40,"round":"floor","cap_bonus":1200,"cap":12000}}'::jsonb
),
(
  'v2_all_rounder',
  'All-Rounder',
  'All drafted canon fighters gain +100 temporary Power.',
  'common',
  'team_power',
  100,
  'all_drafted_canon',
  true,
  52,
  '{"target":"all_drafted_canon","effect":{"stat":"power","mode":"flat","value":100,"cap":12000}}'::jsonb
),
(
  'v2_battle_drill',
  'Battle Drill',
  'All drafted canon fighters gain +180 temporary Power.',
  'rare',
  'team_power',
  180,
  'all_drafted_canon',
  true,
  30,
  '{"target":"all_drafted_canon","effect":{"stat":"power","mode":"flat","value":180,"cap":12000}}'::jsonb
),
(
  'v2_concentrated_force',
  'Concentrated Force',
  'Your median-Power drafted canon fighter gains +900 Power.',
  'epic',
  'drafted_power',
  900,
  'median_power_drafted',
  true,
  13,
  '{"target":"median_power_drafted_canon","effect":{"stat":"power","mode":"flat","value":900,"cap":12000}}'::jsonb
),
(
  'v2_power_floor',
  'Power Floor',
  'Raise your lowest-Power drafted canon fighter to at least 8,500 Power, capped by normal match limits.',
  'rare',
  'drafted_power',
  8500,
  'lowest_power_drafted',
  true,
  28,
  '{"target":"lowest_power_drafted_canon","effect":{"stat":"power","mode":"floor_to_value","value":8500,"cap":12000}}'::jsonb
),
(
  'v2_power_ceiling_push',
  'Ceiling Push',
  'Your highest-Power drafted fighter gains 10% Power, capped at +900.',
  'legendary',
  'drafted_power',
  10,
  'highest_power_drafted',
  true,
  7,
  '{"target":"highest_power_drafted_canon","effect":{"stat":"power","mode":"percent","percent":10,"round":"floor","cap_bonus":900,"cap":12000}}'::jsonb
),
(
  'v2_two_low_power',
  'Twin Batteries',
  'Your two lowest-Power drafted canon fighters each gain +450 Power.',
  'rare',
  'team_power',
  450,
  'two_lowest_power',
  true,
  28,
  '{"target":"two_lowest_power_drafted_canon","effect":{"stat":"power","mode":"flat","value":450,"cap":12000}}'::jsonb
),
(
  'v2_power_by_ovr_gap',
  'Stored Potential',
  'Your lowest-OVR drafted fighter gains +150 Power for every 5 OVR below 90, capped at +900.',
  'epic',
  'drafted_power',
  150,
  'lowest_drafted_canon',
  true,
  14,
  '{"target":"lowest_drafted_canon","effect":{"stat":"power","mode":"gap_steps","reference_stat":"overall","reference":90,"step":5,"per_step":150,"min_bonus":0,"max_bonus":900,"cap":12000}}'::jsonb
),
(
  'v2_ace_support',
  'Ace Support',
  'Your highest-OVR drafted fighter gains +600 Power but no OVR.',
  'rare',
  'drafted_power',
  600,
  'highest_drafted_canon',
  true,
  28,
  '{"target":"highest_drafted_canon","effect":{"stat":"power","mode":"flat","value":600,"cap":12000}}'::jsonb
),
(
  'v2_random_power_burst',
  'Random Power Burst',
  'One random drafted canon fighter gains +700 temporary Power.',
  'rare',
  'drafted_power',
  700,
  'random_drafted_canon',
  true,
  28,
  '{"target":"random_drafted_canon","effect":{"stat":"power","mode":"flat","value":700,"cap":12000}}'::jsonb
),
(
  'v2_power_lottery',
  'Power Lottery',
  'One random eligible fighter gains between +300 and +1,200 Power.',
  'epic',
  'random_power',
  1200,
  'random_eligible_fighter',
  true,
  13,
  '{"target":"random_eligible_fighter","effect":{"stat":"power","mode":"random_range","min":300,"max":1200,"step":100,"cap":12000}}'::jsonb
),
(
  'v2_family_bond',
  'Family Bond',
  'Canon fighters matching your selected OC''s exact verse gain 8% Power.',
  'rare',
  'verse_power',
  8,
  'same_verse_as_selected_oc',
  true,
  32,
  '{"target":"same_verse_canon_as_selected_oc","effect":{"stat":"power","mode":"percent","percent":8,"round":"floor","cap_bonus":700,"cap":12000}}'::jsonb
),
(
  'v2_verse_resonance',
  'Verse Resonance',
  'Canon fighters matching your selected OC''s exact verse gain +250 Power.',
  'common',
  'verse_power',
  250,
  'same_verse_as_selected_oc',
  true,
  50,
  '{"target":"same_verse_canon_as_selected_oc","effect":{"stat":"power","mode":"flat","value":250,"cap":12000}}'::jsonb
),
(
  'v2_home_team',
  'Home Team',
  'If 3+ drafted canon fighters share a verse, that verse group gains +400 Power.',
  'rare',
  'verse_power',
  400,
  'most_represented_verse',
  true,
  30,
  '{"target":"most_represented_verse_canon","condition":{"type":"group_size_at_least","value":3},"effect":{"stat":"power","mode":"flat","value":400,"cap":12000}}'::jsonb
),
(
  'v2_monoverse',
  'Monoverse',
  'If 4+ drafted canon fighters share a verse, that verse group gains +550 Power.',
  'epic',
  'verse_power',
  550,
  'most_represented_verse',
  true,
  14,
  '{"target":"most_represented_verse_canon","condition":{"type":"group_size_at_least","value":4},"effect":{"stat":"power","mode":"flat","value":550,"cap":12000}}'::jsonb
),
(
  'v2_diverse_alliance',
  'Diverse Alliance',
  'If your drafted roster contains 4+ unique verses, all drafted canon fighters gain +250 Power.',
  'rare',
  'team_power',
  250,
  'all_drafted_canon',
  true,
  28,
  '{"target":"all_drafted_canon","condition":{"type":"unique_verse_count_at_least","value":4},"effect":{"stat":"power","mode":"flat","value":250,"cap":12000}}'::jsonb
),
(
  'v2_world_tour',
  'World Tour',
  'If all five drafted canon fighters come from different verses, each gains +350 Power.',
  'epic',
  'team_power',
  350,
  'all_drafted_canon',
  true,
  13,
  '{"target":"all_drafted_canon","condition":{"type":"unique_verse_count_at_least","value":5},"effect":{"stat":"power","mode":"flat","value":350,"cap":12000}}'::jsonb
),
(
  'v2_verse_captain',
  'Verse Captain',
  'The highest-OVR fighter from your most represented verse gains +2 OVR.',
  'rare',
  'hybrid',
  2,
  'highest_in_most_represented_verse',
  true,
  28,
  '{"target":"highest_ovr_in_most_represented_verse","effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_solo_verse',
  'Solo Verse',
  'A fighter whose verse appears only once on your roster gains +650 Power.',
  'rare',
  'drafted_power',
  650,
  'singleton_verse_fighter',
  true,
  28,
  '{"target":"random_singleton_verse_canon","effect":{"stat":"power","mode":"flat","value":650,"cap":12000}}'::jsonb
),
(
  'v2_sibling_worlds',
  'Sibling Worlds',
  'A random same-verse pair of drafted canon fighters each gains +350 Power.',
  'common',
  'verse_power',
  350,
  'random_same_verse_pair',
  true,
  48,
  '{"target":"random_same_verse_pair_canon","effect":{"stat":"power","mode":"flat","value":350,"cap":12000}}'::jsonb
),
(
  'v2_verse_majority',
  'Verse Majority',
  'If one verse represents at least 3 drafted fighters, those fighters gain +1 OVR.',
  'epic',
  'team_overall',
  1,
  'most_represented_verse',
  true,
  13,
  '{"target":"most_represented_verse_canon","condition":{"type":"group_size_at_least","value":3},"effect":{"stat":"overall","mode":"flat","value":1,"cap":99}}'::jsonb
),
(
  'v2_verse_duo',
  'Verse Duo',
  'If exactly two drafted fighters share a verse, both gain +500 Power.',
  'rare',
  'team_power',
  500,
  'exactly_two_same_verse',
  true,
  26,
  '{"target":"exactly_two_same_verse_canon","effect":{"stat":"power","mode":"flat","value":500,"cap":12000}}'::jsonb
),
(
  'v2_oc_homecoming',
  'OC Homecoming',
  'If at least 2 canon fighters match your selected OC''s exact verse, they gain +1 OVR and +200 Power.',
  'epic',
  'hybrid',
  1,
  'same_verse_as_selected_oc',
  true,
  13,
  '{"target":"same_verse_canon_as_selected_oc","condition":{"type":"group_size_at_least","value":2},"effects":[{"stat":"overall","mode":"flat","value":1,"cap":99},{"stat":"power","mode":"flat","value":200,"cap":12000}]}'::jsonb
),
(
  'v2_foreign_exchange',
  'Foreign Exchange',
  'Canon fighters from verses different from your selected OC gain +300 Power.',
  'rare',
  'team_power',
  300,
  'different_verse_from_oc',
  true,
  28,
  '{"target":"canon_different_verse_from_selected_oc","effect":{"stat":"power","mode":"flat","value":300,"cap":12000}}'::jsonb
),
(
  'v2_three_world_pact',
  'Three-World Pact',
  'If your roster contains exactly 3 unique verses, all drafted canon fighters gain +400 Power.',
  'epic',
  'team_power',
  400,
  'all_drafted_canon',
  true,
  13,
  '{"target":"all_drafted_canon","condition":{"type":"unique_verse_count_equals","value":3},"effect":{"stat":"power","mode":"flat","value":400,"cap":12000}}'::jsonb
),
(
  'v2_dual_world_pact',
  'Dual-World Pact',
  'If your roster contains exactly 2 unique verses, all drafted canon fighters gain +300 Power.',
  'rare',
  'team_power',
  300,
  'all_drafted_canon',
  true,
  27,
  '{"target":"all_drafted_canon","condition":{"type":"unique_verse_count_equals","value":2},"effect":{"stat":"power","mode":"flat","value":300,"cap":12000}}'::jsonb
),
(
  'v2_random_verse_amp',
  'Realm Amplifier',
  'One random represented verse on your team gains +600 Power.',
  'epic',
  'verse_power',
  600,
  'random_team_verse',
  true,
  13,
  '{"target":"random_team_verse_canon","effect":{"stat":"power","mode":"flat","value":600,"cap":12000}}'::jsonb
),
(
  'v2_random_verse_percent',
  'Dimensional Harmony',
  'One random represented verse on your team gains 10% temporary Power.',
  'legendary',
  'verse_power',
  10,
  'random_team_verse',
  true,
  6,
  '{"target":"random_team_verse_canon","effect":{"stat":"power","mode":"percent","percent":10,"round":"floor","cap_bonus":900,"cap":12000}}'::jsonb
),
(
  'v2_anchor',
  'Anchor',
  'Your lowest-OVR drafted fighter gains +1 OVR and +500 Power.',
  'rare',
  'hybrid',
  1,
  'lowest_drafted_canon',
  true,
  28,
  '{"target":"lowest_drafted_canon","effects":[{"stat":"overall","mode":"flat","value":1,"cap":99},{"stat":"power","mode":"flat","value":500,"cap":12000}]}'::jsonb
),
(
  'v2_underdog_engine',
  'Underdog Engine',
  'If your lowest-OVR fighter is below 80, it gains +2 OVR and +600 Power.',
  'epic',
  'hybrid',
  2,
  'lowest_drafted_canon',
  true,
  13,
  '{"target":"lowest_drafted_canon","condition":{"type":"target_overall_below","value":80},"effects":[{"stat":"overall","mode":"flat","value":2,"cap":99},{"stat":"power","mode":"flat","value":600,"cap":12000}]}'::jsonb
),
(
  'v2_elite_engine',
  'Elite Engine',
  'If your highest-OVR fighter is 95+, it gains +1 OVR and +500 Power.',
  'epic',
  'hybrid',
  1,
  'highest_drafted_canon',
  true,
  13,
  '{"target":"highest_drafted_canon","condition":{"type":"target_overall_at_least","value":95},"effects":[{"stat":"overall","mode":"flat","value":1,"cap":99},{"stat":"power","mode":"flat","value":500,"cap":12000}]}'::jsonb
),
(
  'v2_powered_underdog',
  'Powered Underdog',
  'If your lowest-Power fighter is below 8,000 Power, it gains +2 OVR.',
  'rare',
  'hybrid',
  2,
  'lowest_power_drafted',
  true,
  28,
  '{"target":"lowest_power_drafted_canon","condition":{"type":"target_power_below","value":8000},"effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_powered_elite',
  'Powered Elite',
  'If your highest-OVR fighter is 90+, it gains +700 Power.',
  'rare',
  'drafted_power',
  700,
  'highest_drafted_canon',
  true,
  28,
  '{"target":"highest_drafted_canon","condition":{"type":"target_overall_at_least","value":90},"effect":{"stat":"power","mode":"flat","value":700,"cap":12000}}'::jsonb
),
(
  'v2_close_gap',
  'Close the Gap',
  'If the OVR gap between your highest and lowest drafted fighters is 10+, your lowest gains +3 OVR.',
  'epic',
  'drafted_overall',
  3,
  'lowest_drafted_canon',
  true,
  13,
  '{"target":"lowest_drafted_canon","condition":{"type":"roster_overall_gap_at_least","value":10},"effect":{"stat":"overall","mode":"flat","value":3,"cap":99}}'::jsonb
),
(
  'v2_tight_formation',
  'Tight Formation',
  'If your highest-to-lowest OVR gap is 5 or less, all drafted canon fighters gain +350 Power.',
  'rare',
  'team_power',
  350,
  'all_drafted_canon',
  true,
  28,
  '{"target":"all_drafted_canon","condition":{"type":"roster_overall_gap_at_most","value":5},"effect":{"stat":"power","mode":"flat","value":350,"cap":12000}}'::jsonb
),
(
  'v2_power_balance',
  'Power Balance',
  'If your roster Power gap is 1,000 or less, all drafted canon fighters gain +250 Power.',
  'rare',
  'team_power',
  250,
  'all_drafted_canon',
  true,
  28,
  '{"target":"all_drafted_canon","condition":{"type":"roster_power_gap_at_most","value":1000},"effect":{"stat":"power","mode":"flat","value":250,"cap":12000}}'::jsonb
),
(
  'v2_power_disparity',
  'Power Disparity',
  'If your roster Power gap is 2,000+, your lowest-Power fighter gains +900 Power.',
  'epic',
  'drafted_power',
  900,
  'lowest_power_drafted',
  true,
  13,
  '{"target":"lowest_power_drafted_canon","condition":{"type":"roster_power_gap_at_least","value":2000},"effect":{"stat":"power","mode":"flat","value":900,"cap":12000}}'::jsonb
),
(
  'v2_exact_90',
  'Ninety Club',
  'One random drafted canon fighter at exactly 90 OVR gains +2 OVR.',
  'rare',
  'drafted_overall',
  2,
  'random_exact_90_drafted',
  true,
  24,
  '{"target":"random_drafted_canon","condition":{"type":"target_overall_equals","value":90},"effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_sub_70_boost',
  'Rookie Blessing',
  'Drafted canon fighters below 70 OVR gain +500 Power.',
  'common',
  'team_power',
  500,
  'drafted_below_70',
  true,
  44,
  '{"target":"drafted_canon_matching","condition":{"type":"target_overall_below","value":70},"effect":{"stat":"power","mode":"flat","value":500,"cap":12000}}'::jsonb
),
(
  'v2_98_guard',
  'Near Apex',
  'One drafted canon fighter at 98+ OVR gains +700 Power.',
  'epic',
  'drafted_power',
  700,
  'random_drafted_98_plus',
  true,
  12,
  '{"target":"random_drafted_canon","condition":{"type":"target_overall_at_least","value":98},"effect":{"stat":"power","mode":"flat","value":700,"cap":12000}}'::jsonb
),
(
  'v2_no_99_bonus',
  'No Gods Allowed',
  'If you drafted no 99 OVR fighter, all drafted canon fighters gain +300 Power.',
  'epic',
  'team_power',
  300,
  'all_drafted_canon',
  true,
  12,
  '{"target":"all_drafted_canon","condition":{"type":"roster_has_no_overall","value":99},"effect":{"stat":"power","mode":"flat","value":300,"cap":12000}}'::jsonb
),
(
  'v2_one_99_bonus',
  'Chosen Apex',
  'If you drafted exactly one 99 OVR fighter, it gains +600 Power.',
  'rare',
  'drafted_power',
  600,
  'highest_drafted_canon',
  true,
  24,
  '{"target":"highest_drafted_canon","condition":{"type":"roster_count_overall_equals","overall":99,"count":1},"effect":{"stat":"power","mode":"flat","value":600,"cap":12000}}'::jsonb
),
(
  'v2_low_average',
  'Low Average',
  'If your drafted canon roster averages below 80 OVR, all drafted canon fighters gain +1 OVR.',
  'legendary',
  'team_overall',
  1,
  'all_drafted_canon',
  true,
  6,
  '{"target":"all_drafted_canon","condition":{"type":"roster_average_overall_below","value":80},"effect":{"stat":"overall","mode":"flat","value":1,"cap":99}}'::jsonb
),
(
  'v2_glass_cannon',
  'Glass Cannon',
  'Your highest-OVR drafted fighter gains +3 OVR, while your lowest loses 2 OVR.',
  'epic',
  'risk_reward',
  3,
  'highest_drafted_canon',
  true,
  13,
  '{"effects":[{"target":"highest_drafted_canon","stat":"overall","mode":"flat","value":3,"cap":99},{"target":"lowest_drafted_canon","stat":"overall","mode":"flat","value":-2,"floor":1}]}'::jsonb
),
(
  'v2_power_transfer',
  'Power Transfer',
  'Your lowest-Power drafted fighter loses 500 Power; your highest gains 1,000.',
  'rare',
  'risk_reward',
  1000,
  'highest_power_drafted',
  true,
  26,
  '{"effects":[{"target":"lowest_power_drafted_canon","stat":"power","mode":"flat","value":-500,"floor":0},{"target":"highest_power_drafted_canon","stat":"power","mode":"flat","value":1000,"cap":12000}]}'::jsonb
),
(
  'v2_sacrifice_the_weak',
  'Sacrifice the Weak',
  'Your lowest-OVR drafted fighter loses 2 OVR; your highest gains 3 OVR.',
  'legendary',
  'risk_reward',
  3,
  'highest_drafted_canon',
  true,
  6,
  '{"effects":[{"target":"lowest_drafted_canon","stat":"overall","mode":"flat","value":-2,"floor":1},{"target":"highest_drafted_canon","stat":"overall","mode":"flat","value":3,"cap":99}]}'::jsonb
),
(
  'v2_balanced_trade',
  'Balanced Trade',
  'Your highest-OVR fighter loses 1 OVR; your lowest gains 2 OVR.',
  'rare',
  'risk_reward',
  2,
  'two_targets',
  true,
  24,
  '{"effects":[{"target":"highest_drafted_canon","stat":"overall","mode":"flat","value":-1,"floor":1},{"target":"lowest_drafted_canon","stat":"overall","mode":"flat","value":2,"cap":99}]}'::jsonb
),
(
  'v2_power_for_ovr',
  'Power for OVR',
  'Your lowest-OVR fighter gains +2 OVR but loses 600 Power.',
  'epic',
  'risk_reward',
  2,
  'lowest_drafted_canon',
  true,
  12,
  '{"target":"lowest_drafted_canon","effects":[{"stat":"overall","mode":"flat","value":2,"cap":99},{"stat":"power","mode":"flat","value":-600,"floor":0}]}'::jsonb
),
(
  'v2_ovr_for_power',
  'OVR for Power',
  'Your highest-Power fighter gains +1,200 Power but loses 1 OVR.',
  'epic',
  'risk_reward',
  1200,
  'highest_power_drafted',
  true,
  12,
  '{"target":"highest_power_drafted_canon","effects":[{"stat":"power","mode":"flat","value":1200,"cap":12000},{"stat":"overall","mode":"flat","value":-1,"floor":1}]}'::jsonb
),
(
  'v2_split_focus',
  'Split Focus',
  'Your two lowest-OVR fighters gain +1 OVR; your highest loses 1 OVR.',
  'rare',
  'risk_reward',
  1,
  'highest_and_lowest',
  true,
  22,
  '{"effects":[{"target":"two_lowest_drafted_canon","stat":"overall","mode":"flat","value":1,"cap":99},{"target":"highest_drafted_canon","stat":"overall","mode":"flat","value":-1,"floor":1}]}'::jsonb
),
(
  'v2_volatile_training',
  'Volatile Training',
  'One random fighter gains +4 OVR and a different random fighter loses 2 OVR.',
  'legendary',
  'risk_reward',
  4,
  'random_eligible_fighter',
  true,
  6,
  '{"effects":[{"target":"random_eligible_fighter","stat":"overall","mode":"flat","value":4,"cap":99},{"target":"random_other_eligible_fighter","stat":"overall","mode":"flat","value":-2,"floor":1}]}'::jsonb
),
(
  'v2_gamblers_blessing',
  'Gambler''s Blessing',
  'One random eligible fighter gains between +1 and +5 OVR.',
  'legendary',
  'random_overall',
  5,
  'random_eligible_fighter',
  true,
  6,
  '{"target":"random_eligible_fighter","effect":{"stat":"overall","mode":"random_range","min":1,"max":5,"step":1,"cap":99}}'::jsonb
),
(
  'v2_roulette_pair',
  'Roulette Pair',
  'Two random drafted canon fighters each gain +2 OVR.',
  'epic',
  'random_overall',
  2,
  'two_random_drafted',
  true,
  12,
  '{"target":"two_random_drafted_canon","effect":{"stat":"overall","mode":"flat","value":2,"cap":99}}'::jsonb
),
(
  'v2_chaos_draft',
  'Chaos Draft',
  'Two random drafted fighters gain +2 OVR; one different random drafted fighter loses 1 OVR.',
  'legendary',
  'risk_reward',
  2,
  'random_multi',
  true,
  6,
  '{"effects":[{"target":"two_random_drafted_canon","stat":"overall","mode":"flat","value":2,"cap":99},{"target":"random_other_drafted_canon","stat":"overall","mode":"flat","value":-1,"floor":1}]}'::jsonb
),
(
  'v2_fortunes_power',
  'Fortune''s Power',
  'One random eligible fighter gains between +200 and +1,000 Power.',
  'epic',
  'random_power',
  1000,
  'random_eligible_fighter',
  true,
  12,
  '{"target":"random_eligible_fighter","effect":{"stat":"power","mode":"random_range","min":200,"max":1000,"step":100,"cap":12000}}'::jsonb
),
(
  'v2_coinflip_focus',
  'Coinflip Focus',
  'Randomly choose your highest- or lowest-OVR drafted fighter; the chosen fighter gains +3 OVR.',
  'epic',
  'random_overall',
  3,
  'random_high_or_low',
  true,
  12,
  '{"target":"random_choice_between","options":["highest_drafted_canon","lowest_drafted_canon"],"effect":{"stat":"overall","mode":"flat","value":3,"cap":99}}'::jsonb
)
on conflict (key) do update
set
  name = excluded.name,
  description = excluded.description,
  rarity = excluded.rarity,
  effect_type = excluded.effect_type,
  effect_value = excluded.effect_value,
  target_rule = excluded.target_rule,
  active = excluded.active,
  roll_weight = excluded.roll_weight,
  effect_config = excluded.effect_config,
  updated_at = now();

commit;

-- ============================================================
-- VERIFY
-- ============================================================

-- Should return 100 player-facing V2 active Boons.
select count(*) as active_v2_boons
from public.boon_definitions
where active = true
  and key like 'v2_%';

-- Breakdown by rarity.
select rarity, count(*) as boon_count
from public.boon_definitions
where active = true
  and key like 'v2_%'
group by rarity
order by rarity;

-- Inspect the catalogue.
select
  key,
  name,
  rarity,
  effect_type,
  effect_value,
  target_rule,
  roll_weight,
  effect_config
from public.boon_definitions
where active = true
  and key like 'v2_%'
order by
  case rarity
    when 'common' then 1
    when 'rare' then 2
    when 'epic' then 3
    when 'legendary' then 4
    else 5
  end,
  name;
