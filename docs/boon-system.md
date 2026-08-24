# Anime Arena Boon System

## Status

**Phase 1-4 Foundation, Shop, and Match Snapshot — Implemented (application + migrations ready)**

Phase 1 is implemented by `docs/supabase_boon_phase_1.sql` and the matching
frontend changes. The SQL must be run manually in Supabase before the new UI is
used. No shop, inventory, rolling, Boon definitions, loadout, or match effects
are included yet.

Phase 1 stores each eligible player's private balance in
`profiles.boon_points`. A completed online/ranked match awards +100 BP for a
win, +60 BP for a loss, or +75 BP to each player for a draw. Reward amounts and
the grant timestamp are snapshotted on the match row, and the canonical battle
completion/forfeit transaction performs the grant exactly once. Existing
completed matches are not backfilled.

Authenticated guests and the Administrator/system profile receive zero BP. A
non-guest human in a ranked Administrator match receives the normal result
reward. Local Prototype never creates a persisted online match and therefore
cannot grant BP. Owner-only RPCs expose the balance and the caller's stored
match reward; public/opponent profile payloads omit `boon_points`.

Phase 2 is implemented by `docs/supabase_boon_phase_2.sql`. It adds a
data-driven catalogue of ten active definitions and a private `player_boons`
inventory. Definition keys, rarities, effect types, numeric values, and target
rules are configuration only; they do not affect matches yet.

The initial catalogue contains Ascendant, OC Power Surge, Lucky Draft, Chosen
One, Underdog, Elite Training, Resonance, Balanced Formation, Wild Card, and
Unity. Seed updates are keyed and rerunnable; roll weights are stored for future
use but no probability or rolling behavior exists in Phase 2.

Persistent non-guest players may own at most two distinct definitions and may
equip at most one. The duplicate rule is enforced by an owner/definition unique
constraint, the equipped rule by a partial unique index, and the inventory cap
by a concurrency-safe trigger that serializes on the owner profile. Equip and
unequip are atomic owner-only RPCs. Guests and system profiles cannot own or
equip inventory. No inventory is granted automatically;
`docs/supabase_boon_phase_2_test_seed.sql` is optional SQL-editor-only tooling.

Phase 3 is implemented by `docs/supabase_boon_phase_3.sql`. The player-facing
Shop charges an authoritative 300 BP per roll and selects one active, unowned
definition using its database `roll_weight`. Inventories below two receive the
result immediately and unequipped. A full inventory creates one durable pending
roll that survives refresh; the player must replace one owned Boon or discard
the new result. Replacing an equipped Boon leaves the equipped slot empty, and
discarding never refunds the spent BP. A partial unique index permits only one
unresolved roll per player. Phase 3 still applies no Boon gameplay effects.

Phase 4 is implemented by `docs/supabase_boon_phase_4.sql`. Entering the ranked
queue locks an immutable snapshot of the caller's equipped Boon definition. The
match stores one private snapshot row per participant when it is created, with
an explicit no-Boon state for guests, the Administrator, and players who queue
without a Boon. Replacing, unequipping, deactivating, or rebalancing the source
Boon later cannot change an existing match snapshot.

The waiting player's queue snapshot is captured on the transition into
`waiting` and is preserved by repeat matchmaking calls. The player who matches
that queue entry immediately is snapshotted by the match-insert trigger before
the matchmaking transaction returns opponent information. This trigger-based
integration leaves the canonical human-first and Administrator matchmaking
functions unchanged. Cancelled matches retain their audit snapshot and never
consume inventory; a later match takes a fresh snapshot.

The perspective-safe initiative RPC reveals each participant's snapshotted Boon
at the first competitive phase and supports reconnects without exposing private
OC, draft, preparation, or battle selections. Snapshot tables have no browser
SELECT grant and are not subscribed to directly through Realtime. Phase 4 adds
loadout visibility only; Boons still have no gameplay effects.

This document defines the first version of the Anime Arena **Boon System**, including Boon ownership, equipping, ranked-match rewards, rolling, inventory limits, temporary match effects, and future expansion rules.

The Boon System is a meta-progression and pre-match strategy layer. It must not permanently alter canon fighters, Original Characters (OCs), or existing progression values.

---

## 1. Feature Purpose

Boons give players an additional strategic choice before entering a ranked match.

A Boon is a reusable loadout modifier that can temporarily strengthen or alter part of the player's team during a match.

The system is designed to:

- add pre-match strategy
- reward ranked-match participation
- create a lightweight in-game economy
- give players meaningful reasons to keep playing ranked matches
- provide risk/reward through rolling and limited inventory
- avoid permanent stat inflation
- avoid large inventory-management systems
- support future seasonal and themed content

Boons are not intended to replace drafting, OC progression, or battle strategy.

---

## 2. Core Boon Rules

V1 uses the following rules:

- A player may own a maximum of **2 Boons** at a time.
- A player may equip a maximum of **1 Boon** at a time.
- Boons persist between matches until replaced or discarded.
- The equipped Boon is locked for the match when ranked matchmaking begins.
- Boons apply only to temporary match values.
- Boons never permanently modify character or OC stats.
- Boons are obtained through the Boon Shop by spending **Boon Points**.
- Boon Points are earned only by completing ranked matches.
- Losing a ranked match still grants Boon Points, but fewer than winning.
- If a player rolls while already owning 2 Boons, they must choose whether to replace one of their existing Boons or discard the newly rolled Boon.

---

## 3. Boon Points

### 3.1 Currency

The dedicated Boon currency is called:

**Boon Points**

Suggested internal field name:

```text
boon_points
```

Boon Points are separate from OC progression points.

They must not be interchangeable.

### 3.2 Sources

Boon Points are earned **only from completed ranked matches**.

They should not be earned from:

- login bonuses
- daily rewards
- local prototype matches
- unranked matches
- profile activity
- OC creation
- catalogue browsing
- lore/profile customization

The purpose is to tie Boon progression directly to ranked participation.

### 3.3 Match Rewards

Initial recommended values:

| Ranked Result | Boon Points |
| --- | ---: |
| Win | +100 BP |
| Loss | +60 BP |
| Draw | +75 BP |

These values may be rebalanced later.

The important rule is that a loss should still provide meaningful progress.

The loss reward should generally remain around **60–70% of the winner reward** so stronger players do not snowball too aggressively.

### 3.4 Reward Authority

Boon Points must be awarded by the authoritative backend when a ranked match is officially completed.

Do not award Boon Points from the result-page client.

The reward process should be idempotent so a player cannot earn duplicate rewards by:

- refreshing the result screen
- reconnecting
- replaying a client request
- reopening a completed match

---

## 4. Boon Shop

The Boon Shop is where players spend Boon Points to obtain Boons.

Player navigation groups Boons with the OC Family under the shared Loadout
category. `/loadout` is a lightweight summary hub, while `/boons` remains the
dedicated Boon Shop and `/ocs` remains the dedicated OC management page:

```text
Loadout
├─ OC Family
└─ Boons
```

Dedicated route:

```text
/boons
```

or another route consistent with the application's routing conventions.

The page should show:

- current Boon Point balance
- equipped Boon
- current Boon inventory
- inventory usage, e.g. `2 / 2`
- roll cost
- roll action
- possible rarity information if rarity is enabled
- concise explanations of owned Boons

---

## 5. Rolling Boons

### 5.1 Basic Roll

A player spends Boon Points to roll one Boon from the active Boon pool.

Suggested initial roll cost:

```text
300 BP
```

This is a balance value and may change after testing.

At the initial recommended ranked rewards, this means approximately:

- 3 wins for one roll
- 5 losses for one roll
- roughly 3–4 mixed-result ranked matches per roll

### 5.2 Inventory Below Capacity

If the player owns fewer than 2 Boons:

```text
Inventory 1 / 2
→ Roll
→ Receive Boon
→ Inventory 2 / 2
```

The new Boon is added to their inventory.

It should not automatically become equipped unless product design explicitly decides otherwise.

### 5.3 Inventory Full

If the player already owns 2 Boons, they may still roll.

Boon Points are spent before the result is revealed.

The player then sees the newly rolled Boon and chooses:

```text
Replace Boon A
Replace Boon B
Discard New Boon
```

Do not automatically delete an existing Boon.

This preserves the risk of rerolling because the currency has already been spent, while still preserving player agency.

### 5.4 Duplicate Boons

V1 should define duplicate behavior explicitly.

Recommended approach:

- Do not allow the same exact Boon definition to occupy both inventory slots.
- If the player rolls a Boon they already own, reroll the result server-side from the remaining eligible pool.

If the active pool eventually becomes too small to guarantee this, the rule may be revisited.

---

## 6. Boon Inventory

Each persistent player has:

```text
Maximum Owned: 2
Maximum Equipped: 1
```

Example:

```text
YOUR BOONS

Ascendant
Selected OC gains +3 temporary OVR
EQUIPPED

Underdog
Lowest-OVR drafted fighter gains +3 temporary OVR

Inventory: 2 / 2
```

Inventory size should remain intentionally small.

The Boon System should not become a large collectible inventory system in V1.

---

## 7. Equipping Boons

A player may equip one owned Boon.

Rules:

- only owned Boons may be equipped
- only one may be equipped
- equipping a different Boon automatically unequips the previous one
- a player may choose to enter ranked matchmaking with no Boon equipped
- equipping does not consume the Boon
- Boons are reusable until replaced or discarded

---

## 8. Match Locking

The equipped Boon must lock when ranked matchmaking begins.

Example:

```text
Equipped Boon
ASCENDANT

Locked for this match
```

Once the player enters the ranked queue, they cannot change the Boon for that match.

This prevents players from seeing an opponent or their OC Family and then changing their Boon as a counter-pick.

The authoritative match state should snapshot the equipped Boon.

---

## 9. Match Snapshot

Competitive matches should not depend on the player's live Boon inventory after matchmaking starts.

The match should snapshot the relevant Boon information.

Conceptually:

```text
equipped_boon_id
boon_definition_id
boon_name_snapshot
boon_effect_type
boon_effect_value
boon_target_rule
```

The exact schema should follow the project's existing match snapshot conventions.

If a player later replaces or discards the Boon, an already-started match must remain unaffected.

---

## 10. Temporary Stats Only

Boons must never permanently update:

```text
characters.overall
characters.power_score
player_characters.overall
player_characters.power_score
```

Boon bonuses exist only within the match.

Conceptually:

```text
base_overall = 90
boon_overall_bonus = 2
match_overall = 92
```

and:

```text
base_power_score = 9000
boon_power_bonus = 500
match_power_score = 9500
```

When the match ends, the permanent fighter values remain unchanged.

---

## 11. Interaction With Anime Arena Battle Rules

Anime Arena uses:

1. OVR as the primary battle value.
2. Global Power / `power_score` only when OVR is tied.
3. Exact OVR and Power ties may resolve as draws according to current battle behavior.

Because of this, OVR Boons are significantly more powerful than similarly sized Power Boons.

Example:

```text
+3 OVR
```

can alter many matchups directly.

Meanwhile:

```text
+300 Global Power
```

only affects a matchup when OVR is tied.

OVR Boons therefore require tighter balance and should generally be rarer or more conditional.

---

## 12. Boon Design Philosophy

The best Boons should create decisions rather than simply provide universally optimal stat increases.

Preferred Boon styles include:

- OC-focused
- weak-fighter support
- random-target effects
- same-verse synergy
- Power-based support
- situational effects
- team-composition effects

Avoid designing the entire pool around direct flat OVR bonuses.

A healthy initial Boon pool should contain a mixture of:

- OVR modifiers
- Global Power modifiers
- conditional/team modifiers
- controlled randomness

---

## 13. Initial Boon Concepts

Exact values are subject to balance testing.

### Ascendant
Selected OC gains **+3 temporary OVR**.

### OC Power Surge
Selected OC gains **+500 temporary Global Power**.

### Lucky Draft
One random drafted canon fighter gains **+2 temporary OVR**.

### Chosen One
One random drafted canon fighter gains **+3 temporary OVR**.

### Underdog
Your lowest-OVR drafted fighter gains **+3 temporary OVR**.

### Elite Training
Your highest-OVR drafted fighter gains **+1 temporary OVR**.

### Resonance
Eligible same-verse drafted fighters as the selected OC gain **+250 temporary Global Power**.

Verse matching must use exact `verse_id`.

AU universes remain distinct:

```text
JJK AU != Jujutsu Kaisen
Naruto AU != Naruto
HXH AU != Hunter x Hunter
```

### Balanced Formation
Your three lowest-OVR drafted fighters gain **+1 temporary OVR**.

### Wild Card
A random eligible fighter gains a random **+1 to +4 temporary OVR** bonus.

### Unity
Fighters from one eligible team verse gain temporary Global Power.

Final selection rules and values should be finalized during implementation/balance design.

---

## 14. Boon Rarity

Rarity is recommended but may be implemented after the base system.

Potential tiers:

```text
Common
Rare
Epic
Legendary
```

Rarity affects roll probability.

Rarity should not automatically mean that a Boon is always better in every situation.

---

## 15. Opponent Visibility

Recommended rule:

The opponent's equipped Boon becomes public only after the match has begun.

It should not be exposed while matchmaking is still searching.

For Boons with hidden/random targets, the Boon definition may be public while the actual affected fighter remains hidden until the appropriate reveal point.

The exact reveal timing should avoid leaking secret OC selection or other protected competitive information.

---

## 16. Random Target Authority

Any Boon using randomness must resolve server-side.

Examples:

- random drafted fighter
- random verse
- random bonus amount

Do not let the client choose or reroll the target.

The selected result should be stored as authoritative match state so reconnecting produces the same outcome.

---

## 17. Interaction With OCs

Boons may affect OCs, but they remain independent from OC progression.

A Boon bonus:

- does not change permanent OVR
- does not change permanent Power
- does not change OVR cap
- does not change Power cap
- does not consume progression points
- does not change Champion/Sacrificial type
- does not alter OC lore or Family identity

### Champion

Recommended effect ordering:

1. establish snapshotted base OC stats
2. resolve OC Preparation
3. apply temporary Boon modifier
4. enforce any existing match-stat caps

The exact ordering should be explicitly encoded and tested.

### Sacrificial

If a Sacrificial OC is used as support and never enters battle, an OC-target Boon may require explicit eligibility behavior.

Do not assume every OC-target Boon is useful for both OC types.

---

## 18. Full-Inventory Roll UX

When rolling at `2 / 2`:

```text
NEW BOON

Power Surge
Selected OC gains +500 Global Power

Your Boon inventory is full.

Choose a Boon to replace:

[ Ascendant ]
[ Underdog ]

or

[ Discard New Boon ]
```

Important:

- currency is already spent
- the new Boon should not automatically replace anything
- closing the decision UI must not create an exploitable unresolved state

The backend should maintain a safe pending-roll state until the player resolves the choice.

---

## 19. Recommended Data Model

Final schema should follow the existing Anime Arena architecture.

### Player Currency

```text
boon_points bigint not null default 0
```

### Boon Definitions

```text
boon_definitions
----------------
id
key
name
description
rarity
effect_type
effect_value
target_rule
active
roll_weight
created_at
updated_at
```

### Player Boons

```text
player_boons
------------
id
owner_id
boon_definition_id
equipped
created_at
```

Constraints should enforce:

- maximum 2 owned per player
- maximum 1 equipped
- valid ownership
- valid active Boon definitions

### Pending Roll

```text
boon_rolls
----------
id
owner_id
boon_definition_id
cost
status
created_at
resolved_at
```

Possible statuses:

```text
pending
kept
discarded
cancelled
```

Do not allow new rolls while an unresolved roll exists.

---

## 20. Backend RPC Concepts

Potential RPCs:

```text
roll_boon()
resolve_boon_roll(...)
equip_boon(...)
unequip_boon()
```

Competitive economy operations must be transactional and owner-validated.

Ranked match completion should award Boon Points through the authoritative match-completion process rather than from the client.

---

## 21. Security Rules

Clients must not be allowed to directly:

- change `boon_points`
- insert arbitrary Boons
- choose roll results
- alter rarity/effect values
- equip another player's Boon
- exceed inventory limits
- award match rewards
- change snapshotted match effects

Use the project's existing Supabase RLS / SECURITY DEFINER architecture.

---

## 22. Ranked Match Integration

On ranked match completion:

1. determine official result
2. ensure rewards were not already granted
3. award winner BP
4. award loser BP
5. award draw BP if applicable
6. record reward completion
7. preserve normal W/L updates
8. return safe result data

Boon rewards must not interfere with leaderboard/stat updates.

If Administrator matches are ranked, they should follow the same player reward rules unless explicitly excluded later.

---

## 23. Local Prototype Mode

Local Prototype mode should not grant Boon Points.

If Boons are later previewed there for testing, effects must remain local/test-only and never affect the persistent economy.

---

## 24. Administrator Opponent

If the Administrator participates in ranked matches, Boon behavior should be handled explicitly.

Possible future behavior:

- system-defined equipped Boon
- controlled system Boon pool
- normal match snapshot behavior
- no need for player-style currency/inventory

Do not automatically grant Administrator Boon Points.

---

## 25. Balance Guardrails

### Avoid Guaranteed Dominance
No single Boon should be mathematically mandatory.

### Limit OVR Inflation
Direct OVR bonuses should be relatively rare, limited, or conditional.

### Power Can Be More Generous
Global Power can use larger values because it only breaks equal-OVR matchups.

### Preserve Draft Importance
A poor draft should not consistently beat a strong draft purely because of one Boon.

### Avoid Winner Snowballing
Losses provide meaningful BP to keep acquisition accessible.

### Avoid Pay-to-Win
V1 Boon Points come from ranked matches only.

---

## 26. Initial Pool Size

Recommended V1 pool:

```text
10–15 Boons
```

This is large enough for variety while remaining manageable to balance and understand.

---

## 27. Suggested Implementation Phases

### Phase 1 — Economy Foundation (Implemented)
- [x] Boon Points
- [x] ranked win/loss/draw rewards
- [x] secure/idempotent reward granting
- [x] balance display
- [x] no rolling yet

### Phase 2 — Boon Definitions + Inventory (Implemented)
- [x] definition table and initial ten-definition catalogue
- [x] private player inventory
- [x] maximum 2 distinct Boons owned
- [x] maximum 1 Boon equipped
- [x] atomic equip/unequip management RPCs
- [x] `/boons` management UI

### Phase 3 — Shop + Rolling (Implemented)
- [x] authoritative 300 BP roll cost
- [x] weighted server-side selection from active, unowned definitions
- [x] immediate acquisition while inventory has space
- [x] durable full-inventory replacement/discard decision
- [x] one unresolved roll per player
- [x] non-refundable discard behavior
- [x] reconnect-safe Shop UI

### Phase 4 — Ranked Match Snapshot (Implemented)
- [x] lock equipped Boon on matchmaking commitment
- [x] immutable per-participant definition/effect snapshot
- [x] explicit no-Boon snapshots for guests and Administrator matches
- [x] perspective-safe opponent reveal at initiative
- [x] reconnect-safe initiative and active-loadout state
- [x] no Boon gameplay effects

### Phase 5 — Boon Effects
Start with a small effect set:
- OC OVR
- OC Power
- random drafted fighter
- lowest-OVR fighter
- same-verse Power

### Phase 6 — Balance + Polish
- rarity presentation
- roll weights
- analytics/logging
- mobile polish
- balance tuning
- additional Boons

---

## 28. Out of Scope for V1

Do not include:

- real-money Boon purchases
- player-to-player trading
- marketplace
- unlimited inventory
- multiple equipped Boons
- permanent stat changes
- upgrading/fusing
- crafting
- gifting
- daily-login BP
- local-mode BP farming

---

## 29. Key Product Rules Summary

```text
Currency:
Boon Points

Earned:
Ranked matches only

Win:
Higher BP reward

Loss:
Smaller but meaningful BP reward

Owned:
Maximum 2

Equipped:
Maximum 1

Roll:
Costs BP

Inventory Full:
Spend BP
→ reveal new Boon
→ replace one existing Boon OR discard new Boon

Match:
Equipped Boon locks when entering ranked matchmaking

Stats:
Temporary match modifiers only

Authority:
Supabase/PostgreSQL

Randomness:
Server-side only
```

---

## 30. Design Principle

The Boon System should make players ask:

> Which Boon works best with how I want to play this match?

It should not make them ask:

> Which Boon is mathematically mandatory?

The feature succeeds when Boons increase strategy, replayability, and ranked-match engagement without overpowering drafting, OCs, or the core Anime Arena battle system.
