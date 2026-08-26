-- Anime Arena Administrator Mythic Boon: Tyrant's Verdict.
-- Run after docs/supabase_boon_mythic_rarity.sql and before (or together with)
-- the latest docs/supabase_boon_resolver_v2.sql.
-- Balance values in this seed are authoritative and intentionally unchanged.

begin;

insert into public.boon_definitions (
  key,
  name,
  description,
  rarity,
  effect_type,
  effect_value,
  target_rule,
  active,
  roll_weight,
  system_only,
  effect_config
)
values (
  'admin_tyrants_verdict',
  'Tyrant''s Verdict',
  'The Administrator''s selected OC gains +4 temporary OVR and +1,500 temporary Global Power. One random drafted canon fighter gains +3 OVR and +750 Power. A second different drafted canon fighter gains +1 OVR.',
  'mythic',
  'admin_multi_effect',
  4,
  'admin_selected_oc_and_random_canon',
  true,
  0,
  true,
  '{
    "effects": [
      {
        "target": "selected_oc",
        "condition": { "type": "playable_oc" },
        "stat": "overall",
        "mode": "flat",
        "value": 4,
        "cap": 99
      },
      {
        "target": "selected_oc",
        "condition": { "type": "playable_oc" },
        "stat": "power",
        "mode": "flat",
        "value": 1500,
        "cap": 12000
      },
      {
        "target": "random_drafted_canon",
        "group": "secondary_target_1",
        "stat": "overall",
        "mode": "flat",
        "value": 3,
        "cap": 99
      },
      {
        "target": "same_resolved_target",
        "source_group": "secondary_target_1",
        "stat": "power",
        "mode": "flat",
        "value": 750,
        "cap": 12000
      },
      {
        "target": "random_other_drafted_canon",
        "exclude_group": "secondary_target_1",
        "stat": "overall",
        "mode": "flat",
        "value": 1,
        "cap": 99
      }
    ]
  }'::jsonb
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
  system_only = excluded.system_only,
  effect_config = excluded.effect_config,
  updated_at = now();

notify pgrst, 'reload schema';
commit;
