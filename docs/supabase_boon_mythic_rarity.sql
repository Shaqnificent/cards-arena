-- Anime Arena Boon System - Mythic rarity compatibility.
-- Run before inserting Administrator Mythic Boons.
-- This migration changes only the rarity allowlists; it does not seed or
-- rebalance any Boon.

begin;

alter table public.boon_definitions
  drop constraint if exists boon_definitions_rarity_check;

alter table public.boon_definitions
  add constraint boon_definitions_rarity_check check (
    rarity in ('common', 'rare', 'epic', 'legendary', 'mythic')
  );

-- Player-facing definitions still require a positive roll weight. A system
-- definition is outside the player roll pool, so zero is a valid explicit
-- weight for it; negative values remain invalid for every definition.
alter table public.boon_definitions
  drop constraint if exists boon_definitions_roll_weight_check;

alter table public.boon_definitions
  add constraint boon_definitions_roll_weight_check check (
    (system_only = false and roll_weight > 0)
    or (system_only = true and roll_weight >= 0)
  );

alter table public.match_boon_snapshots
  drop constraint if exists match_boon_snapshots_rarity_check;

alter table public.match_boon_snapshots
  add constraint match_boon_snapshots_rarity_check check (
    boon_rarity_snapshot is null
    or boon_rarity_snapshot in ('common', 'rare', 'epic', 'legendary', 'mythic')
  );

notify pgrst, 'reload schema';
commit;
