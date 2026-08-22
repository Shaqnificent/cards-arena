# Anime Arena — OC / AU Character System Reference

## Purpose

This document defines the proposed **OC / AU Character system** for Anime Arena.

An **OC / AU Character** is a custom fighter created by a player as a version of themselves inside an anime verse.

Examples:
- Naruto-verse OC
- Bleach-verse OC
- Dragon Ball-verse OC
- One Piece-verse OC

The system is intended to add long-term progression, player identity, draft bluffing, sacrifice strategy, reserve-card uncertainty, and dedicated OC leaderboards.

Anime Arena's existing combat rule remains:

1. Compare **OVR** first.
2. Higher OVR wins.
3. If OVR is equal, compare **Battle Power / `power_score`**.
4. Higher Battle Power wins.
5. If both are equal, the round is a draw.

---

## 1. OC Creation

Each player may create personal OC fighters tied to anime verses.

Recommended model:
- A player may own multiple OCs.
- Up to **3 OCs** may be equipped in the active OC family/loadout.
- Only **1 OC may be selected for a match**.
- The selected OC remains hidden from the opponent during the draft.

Each OC should store at minimum:
- ID
- owner/player ID
- name
- verse
- avatar/image
- starting OVR
- current OVR
- permanent OVR cap
- starting Battle Power
- current Battle Power
- Battle Power cap
- unspent progression points
- created date
- equipped/active state
- retired/deleted state

Optional later fields:
- biography
- class/archetype
- special ability theme
- title
- cosmetics
- progression history

---

## 2. Verse Selection

Each OC belongs to exactly one anime verse.

Example:

```text
Kairo Uchiha
Verse: Naruto

Ren Kurosaki
Verse: Bleach

Kai D. Zen
Verse: One Piece
```

The verse determines:
- which drafted canon fighters are eligible for sacrifice
- the OC's identity/theme
- future verse-specific customization
- possible future verse-specific abilities

---

## 3. Random Starting OVR

New OCs should not all begin with identical OVR.

Recommended starting range:

```text
50–60 OVR
```

Battle Power begins at a **fixed base value** so a lucky OVR roll does not also grant a Power advantage.

Example:

| OC | Starting OVR | Starting Battle Power |
|---|---:|---:|
| Naruto OC | 52 | 5,000 |
| Bleach OC | 58 | 5,000 |
| One Piece OC | 55 | 5,000 |

The starting roll must be generated server-side and permanently stored.

Do not use client-side `Math.random()` as the authoritative source.

---

## 4. Weighted Potential Roll

A weighted roll is preferred so average outcomes are common and exceptional starts are rare.

Suggested distribution:

| Starting OVR | Approx. Chance | Archetype |
|---|---:|---|
| 50–52 | 20% | High Potential |
| 53–55 | 40% | Growth-Focused |
| 56–58 | 30% | Balanced |
| 59–60 | 10% | Prodigy |

A lower roll should not mean the player simply received a worse character.

It should determine a different growth path.

---

## 5. Potential vs Immediate Strength

Starting OVR should determine both the OC's permanent OVR ceiling and Battle Power ceiling.

Lower starting OVR:
- lower permanent OVR cap
- higher long-term Battle Power cap

Higher starting OVR:
- higher permanent OVR cap
- lower Battle Power cap

Suggested initial model:

| Starting OVR | Permanent OVR Cap | Battle Power Cap | Identity |
|---:|---:|---:|---|
| 50–52 | 92 | 10,000 | High-potential late bloomer |
| 53–55 | 93 | 9,500 | Growth-focused |
| 56–58 | 94 | 9,000 | Balanced |
| 59–60 | 95 | 8,500 | Prodigy |

These values are balancing targets and may change after testing.

Core design rule:

> A weaker starting roll must have a meaningful long-term upside.

---

## 6. Preserve Starting OVR

Store both:

```text
starting_overall
overall
```

Example:

```text
Starting OVR: 52
Current OVR: 87
Growth: +35
```

This supports growth statistics and future leaderboard categories.

---

## 7. Progression Points

Players earn progression points from designated eligible wins.

Concept:

```text
Win eligible match
      ↓
Earn progression points
      ↓
Spend them on OC development
```

Progression must be server-authoritative and idempotent.

A refresh, retry, reconnect, or repeated result callback must not grant rewards twice.

---

## 8. Eligible Progression Matches

The initial idea is to award OC progression from designated local/progression matches.

The implementation should explicitly identify which matches award progression.

Recommended rule:
- only matches marked progression-eligible award points
- rewards are issued once by trusted server/database logic
- test/debug matches should not accidentally award progression

Online PvP progression may be added later.

---

## 9. Spending Progression Points

Before reaching their permanent OVR cap, players may choose to spend points on either:

- **OVR**
- **Battle Power**

Example:

```text
Unspent Points: 4

[ Increase OVR ]
[ Increase Battle Power ]
```

This creates different development paths.

Because OVR is compared first in battle, OVR-focused builds gain broader matchup consistency, while Power-focused builds become stronger against equal-OVR opponents.

---

## 10. Suggested OVR Upgrade Costs

OVR should become progressively more expensive.

| Current OVR | Suggested Cost per +1 OVR |
|---|---:|
| 50–69 | 1 point |
| 70–79 | 2 points |
| 80–89 | 3 points |
| 90–94 | 4 points |
| Final step to cap | 5+ points |

These values are tunable.

---

## 11. Battle Power Upgrades

Battle Power may be increased independently.

Example starting conversion:

```text
1 progression point
→ +50 Battle Power
```

Battle Power cannot exceed the OC's assigned power cap.

Once an OC reaches its permanent OVR cap, future progression may continue through Battle Power until that cap is reached.

---

## 12. Permanent OVR Cap

OCs should not permanently occupy the same tier as the most legendary 99 OVR canon characters.

Recommended permanent OC ceiling:

```text
92–95 OVR
```

The exact cap is assigned at creation based on the starting roll.

This keeps canon 99s prestigious while still allowing highly developed OCs to become elite.

---

## 13. Temporary OVR Beyond the Permanent Cap

An OC may temporarily exceed its permanent cap through the sacrifice system.

Absolute temporary match cap:

```text
99 OVR
```

Example:

```text
Persistent OVR: 95
Sacrifice Bonus: +4
Match OVR: 99

After the match:
Persistent OVR returns to 95
```

---

## 14. OC Family / Loadout

Players may own multiple OCs but equip only a limited active set.

Recommended active family size:

```text
3 OCs
```

The active family is the group visible as possible choices before a match.

Only one may become the active OC for that match.

---

## 15. Different Verses

Different verses should be encouraged among the three equipped OCs.

Example:

```text
ACTIVE OC FAMILY

Naruto OC
Bleach OC
One Piece OC
```

This creates more draft uncertainty than three OCs from the same verse.

The first implementation may either:
- enforce unique verses among equipped OCs, or
- encourage it without enforcing it

---

## 16. Secret OC Selection

Recommended multiplayer flow:

```text
Match Found
    ↓
RPS Initiative
    ↓
Secret OC Selection
    ↓
Draft
    ↓
OC Preparation / Sacrifice
    ↓
Battle
```

Each player secretly selects **1 of their 3 equipped OCs** before the draft.

The opponent may see the three possible OCs, but not which one was selected.

---

## 17. Why Selection Happens Before Draft

Selecting before the draft creates commitment and bluffing.

Example opponent loadout:

```text
Naruto OC
Bleach OC
One Piece OC

ACTIVE OC: ???
```

A player who secretly chose Bleach may aggressively bid on Naruto cards to make the opponent believe they want Naruto sacrifice material.

This adds uncertainty to bidding behavior.

---

## 18. Opponent Visibility

Before the draft, show the opponent's possible OC family:

```text
RIADA'S OC FAMILY

Naruto OC
Bleach OC
One Piece OC

Selected OC: ???
```

Do not reveal the active OC before the intended reveal point.

---

## 19. OC as a Reserve Fighter

The selected OC may act as an additional hidden reserve option during battle.

A player may keep all five drafted fighters and retain the OC as an extra possible selection.

The battle may still remain:
- first to 3 wins
- maximum 5 rounds

The OC increases uncertainty without necessarily increasing match length.

---

## 20. Sacrifice System

After the draft, enter an **OC Preparation** phase.

The player chooses:

```text
KEEP OC AS RESERVE
```

or:

```text
SACRIFICE A SAME-VERSE CARD
```

Only drafted canon fighters from the active OC's verse may be sacrificed.

Example:

```text
Active OC Verse: Naruto

Eligible:
Sasuke
Gaara
Deidara

Not Eligible:
Goku
Ichigo
```

---

## 21. Sacrifice Cost

Sacrifice must have a real cost.

The sacrificed fighter:
- becomes unusable for the rest of the match
- cannot be selected in battle
- is not permanently deleted
- returns normally after the match

The player trades a known canon fighter for a stronger temporary OC.

---

## 22. Card Tier System

Add a Tier derived from OVR.

Suggested initial brackets:

| Tier | OVR | Suggested Sacrifice Boost |
|---|---:|---:|
| D | 50–64 | +1 OVR |
| C | 65–74 | +2 OVR |
| B | 75–84 | +3 OVR |
| A | 85–94 | +4 OVR |
| S | 95–98 | +5 OVR |
| Legend | 99 | +6 OVR |

Tier should preferably be derived from OVR rather than manually maintained.

---

## 23. Sacrifice Boost

The sacrifice provides a temporary OVR increase.

Example:

```text
OC Base OVR: 92

Gaara
A Tier
Bonus: +4

Temporary Match OVR: 96
```

Temporary OVR cannot exceed 99.

Example:

```text
Base: 95
Legend Bonus: +6
Calculated: 101
Actual Match OVR: 99
```

Excess boost is lost.

This creates efficiency decisions about which card is worth sacrificing.

---

## 24. Sacrifice Is Temporary

Sacrifice does not permanently increase OVR.

```text
Persistent OVR: 92
Match Boost: +4
Match OVR: 96

Match ends
→ Persistent OVR remains 92
```

Persistent progression and match sacrifice remain separate systems.

---

## 25. Sacrifice and Battle Power

For the first version:

```text
Sacrifice increases temporary OVR only.
```

It does not directly increase Battle Power.

Persistent progression is responsible for permanent OVR and Power development.

---

## 26. Hidden Sacrifice Information

The opponent should not necessarily know during the draft whether a player intends to sacrifice a specific card.

The active OC is hidden, and the sacrifice decision may remain hidden until the OC is revealed.

This creates bluffing around:
- verse targeting
- bidding
- denial bidding
- sacrifice material
- reserve strategy

---

## 27. OC Reveal

When an OC is first played, reveal its relevant match information.

Example:

```text
AU FIGHTER REVEALED

Kairo Uchiha
Naruto

97 OVR
8,450 POWER

Absorbed:
Gaara — A Tier
```

Exact reveal details may be tuned later.

---

## 28. OC Battle Resolution

OCs use the standard Anime Arena battle resolver:

```text
1. Compare OVR.
2. Higher OVR wins.
3. If equal, compare Battle Power.
4. Higher Battle Power wins.
5. If both equal, draw.
```

There should be no hidden special multiplier that bypasses this rule in the first implementation.

---

## 29. OC Deletion and Reroll Abuse

Random starting OVR creates a potential exploit:

```text
Create OC
→ bad roll
→ delete
→ recreate
→ repeat until 60
```

Unrestricted deletion effectively removes the randomness.

Recommended protections include:

### Option A — Recreation Cooldown
Deleting/retiring an OC slot prevents immediate replacement.

### Option B — Recreation Resource
Recreating an OC consumes a limited token/resource.

### Option C — Retirement
OCs are retired instead of destructively deleted.

### MVP Option
Allow easier deletion during testing but explicitly treat anti-reroll protection as required before production.

---

## 30. Deletion Restrictions

At minimum, an OC should not be deletable while:
- selected in an active match
- referenced by an unresolved match
- involved in a pending progression operation

Deletion must be server-authoritative.

If historical match data references the OC, prefer retirement/soft deletion.

---

## 31. OC Retirement

Long-term, retirement is preferable to hard deletion.

A retired OC:
- cannot be equipped
- cannot enter new matches
- remains available for historical records
- retains its progression history
- may optionally be restorable later

Possible fields:

```text
active = false
retired_at = timestamp
```

---

## 32. OC Management Page

Players should have a dedicated OC management page.

Suggested structure:

```text
MY OC FAMILY

ACTIVE SLOTS
1. Naruto OC
2. Bleach OC
3. One Piece OC

OC COLLECTION
All active/retired OCs
```

Each OC card may show:
- name
- verse
- starting OVR
- current OVR
- OVR cap
- Battle Power
- Battle Power cap
- unspent points
- total growth
- equipped status

Possible actions:
- View
- Equip
- Unequip
- Spend Progression Points
- Retire/Delete

---

## 33. Creation Reveal Experience

OC creation should present the random result as a meaningful archetype.

Example:

```text
CHARACTER CREATED

Your potential is being evaluated...

Starting OVR
52

Growth Type
HIGH POTENTIAL

Permanent OVR Cap
92

Battle Power Cap
10,000

Starting Battle Power
5,000
```

This makes a low starting OVR feel different rather than simply worse.

---

# OC Leaderboards

## 34. Existing Player Leaderboard

Keep the existing player leaderboard focused on normal match performance:

- Wins
- Losses
- Games
- Win Rate

OC competition should be a separate leaderboard area.

---

## 35. OC Ranking Structure

Recommended leaderboard structure:

```text
LEADERBOARD

[ Players ]
[ OC Rankings ]
```

Inside OC Rankings:

```text
[ Individual ]
[ Family Overall ]
[ Family Battle Power ]
[ Family Growth ]
```

Avoid forcing all OC metrics into one composite number initially.

---

## 36. Individual OC Rankings

Rank individual custom characters.

Possible sort/ranking modes:
- OVR
- Battle Power
- Growth

Example:

| Rank | OC | Owner | Verse | OVR | Power |
|---|---|---|---|---:|---:|
| 1 | Kairo Uchiha | Riada | Naruto | 95 | 9,820 |
| 2 | Ren Kurosaki | Akuma | Bleach | 95 | 9,610 |
| 3 | Kai D. Zen | Zen | One Piece | 94 | 9,940 |

Recommended OVR ranking:

```text
overall DESC
power_score DESC
```

Recommended Battle Power ranking:

```text
power_score DESC
overall DESC
```

---

## 37. Family Overall Rankings

Rank players based on the average OVR of their active OC family.

Example:

```text
95 + 92 + 89
────────────
     3

= 92.0 Avg OVR
```

Example leaderboard:

| Rank | Player | OCs | Avg OVR |
|---|---|---:|---:|
| 1 | Riada | 3 | 93.7 |
| 2 | Akuma | 3 | 92.3 |
| 3 | Zen | 3 | 90.7 |

---

## 38. Family Battle Power Rankings

Rank players based on average Battle Power across the active OC family.

Example:

```text
8,700
9,600
9,200
──────
Avg = 9,167
```

This category allows lower-starting/high-potential families to compete independently from OVR-heavy families.

---

## 39. Family Growth Rankings

Family Growth rewards how much a player has developed their OCs from their original rolls.

Per OC:

```text
growth = current_overall - starting_overall
```

Example:

```text
OC A
51 → 89
Growth +38

OC B
57 → 91
Growth +34

OC C
54 → 88
Growth +34

Family Growth = 106
```

Recommended first ranking metric:

```text
SUM(current_overall - starting_overall)
```

across the active family.

This gives weaker-starting OCs another competitive identity.

---

## 40. Minimum Family Size

Family leaderboards should require:

```text
3 active/equipped OCs
```

Without this requirement, a player with only one highly developed OC could produce an artificially high family average.

Individual rankings have no family-size requirement.

---

## 41. OC Leaderboard Eligibility

Suggested rules:

### Individual
OC must:
- be active/non-retired
- belong to a valid profile

### Family
Player must:
- have 3 active/equipped OCs
- have all 3 eligible for ranking

Guest eligibility should follow the same product policy as the existing public leaderboard.

---

## 42. Do Not Use a Composite Family Score Initially

Avoid calculations such as:

```text
Avg OVR + Avg Power
```

because OVR and Battle Power use different scales and meanings.

Keep them as separate rankings:
- Family Overall
- Family Battle Power
- Family Growth

A composite score can be considered later.

---

# Suggested Technical Model

## 43. Persistent OC Table

Possible table:

```text
player_characters
-------------------------
id uuid
owner_id uuid
verse_id
name
image_url

starting_overall
overall
overall_cap

starting_power_score
power_score
power_score_cap

progression_points

equipped
active

created_at
updated_at
retired_at
```

Exact naming should follow the existing project conventions.

---

## 44. Match-Specific OC State

Do not modify persistent OC stats when applying match-only sacrifice effects.

Use match-specific state such as:

```text
match_oc_selections
-------------------------
match_id
player_id
player_character_id

base_overall
match_overall

sacrificed_match_character_id
created_at
```

This lets a match persist:
- selected OC
- temporary OVR
- sacrificed fighter
- ownership
- reveal state

without changing the player's permanent character.

---

## 45. Secret OC Security

The active OC should be hidden at the database/API level before reveal.

The opponent must not be able to discover it through:
- direct SELECT
- nested query
- Realtime payload
- browser network response

Use private tables, RLS, and/or perspective-safe RPCs.

---

# Match Flow

## 46. Recommended Full Flow

```text
MATCHMAKING
     ↓
MATCH FOUND
     ↓
RPS INITIATIVE
     ↓
SECRET OC SELECTION
Choose 1 of 3 equipped OCs
     ↓
ONLINE DRAFT
Draft 5 canon fighters
     ↓
OC PREPARATION
Keep OC as reserve
OR
sacrifice one same-verse drafted fighter
     ↓
BATTLE
OC remains hidden until used/revealed
     ↓
MATCH RESULT
     ↓
PLAYER STATS
     ↓
OC PROGRESSION
if the mode is progression-eligible
```

---

# Strategic Goals

## 47. Character Creation
The player receives a random growth archetype.

## 48. Progression
The player chooses between:
- OVR growth
- Battle Power growth

## 49. Pre-Match
The player secretly chooses one OC from three possibilities.

## 50. Draft
The player may:
- chase sacrifice material
- bluff a different verse
- deny suspected opponent sacrifice cards
- preserve auction balance for other goals

## 51. Post-Draft
The player chooses:
- keep the OC as reserve
- sacrifice a same-verse fighter for temporary OVR

## 52. Battle
The opponent must account for:
- an unknown reserve OC
- possible temporary OVR boost
- uncertain sacrifice choice

---

# Balance Principles

1. **Canon 99s remain prestigious.**
2. **OCs do not permanently reach 99.**
3. **Low starting rolls receive greater long-term Power potential.**
4. **High starting rolls receive greater OVR potential but lower Power ceilings.**
5. **Sacrifice must cost a usable drafted fighter.**
6. **Sacrifice boosts are temporary.**
7. **OVR remains the primary battle stat.**
8. **Battle Power is only the equal-OVR tiebreaker.**
9. **Hidden information must actually remain hidden server-side.**
10. **Progression rewards must be authoritative and idempotent.**
11. **Deletion must not become a free reroll exploit.**
12. **The system should reward different OC development strategies rather than create one obvious optimal path.**

---

# Recommended Implementation Phases

## Phase 1 — OC Foundation
- persistent OC table
- OC creation
- verse selection
- weighted random starting OVR
- OVR/Power cap assignment
- management page
- three equipped OC slots
- retirement/deletion rules

## Phase 2 — Progression
- progression points
- eligible match rewards
- OVR upgrades
- Battle Power upgrades
- cap enforcement
- server-authoritative spending

## Phase 3 — Match OC Selection
- choose 1 of 3 OCs
- hidden selection
- opponent sees possible family
- selected OC remains secret

## Phase 4 — Sacrifice System
- card Tier trait
- same-verse eligibility
- sacrifice action
- temporary OVR
- 99 temporary cap
- sacrificed fighter removal

## Phase 5 — Battle Integration
- OC reserve
- OC reveal
- standard battle resolution
- reconnect/persistence
- match history

## Phase 6 — OC Leaderboards
- Individual OCs
- Family Overall
- Family Battle Power
- Family Growth

---

# Deferred Features

Do not require these for the first OC implementation:

- special OC abilities
- equipment
- skill trees
- PvE campaign
- clans
- trading
- marketplace
- paid rerolls
- rarity monetization
- permanent sacrifice
- multiple active OCs in one match
- complicated family composite score

---

# Summary

The OC system should create this long-term loop:

```text
Create OC
    ↓
Receive random starting potential
    ↓
Develop OVR and Battle Power
    ↓
Equip up to 3 OCs
    ↓
Secretly select 1 for each match
    ↓
Draft canon fighters
    ↓
Keep OC as reserve
OR
sacrifice a same-verse fighter
    ↓
Temporarily strengthen OC
    ↓
Battle
    ↓
Continue progression
    ↓
Compete in dedicated OC rankings
```

The goal is for custom characters to become a persistent strategic system connected to player identity, progression, bluffing, draft decisions, sacrifice choices, and long-term leaderboard competition—not merely cosmetic avatars.
