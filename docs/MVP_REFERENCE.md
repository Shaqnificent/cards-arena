# Anime Arena — MVP Reference

## 1. Product Overview

**Anime Arena** is a competitive anime team-builder and PvP card game.

The MVP is designed to validate one core question:

> Is the team-building auction plus 5v5 card battle fun enough that players want to play again?

The application should prioritize a simple multiplayer loop over collection systems, monetization, deep progression, or multiple game modes.

Core flow:

**Login → Lobby → Matchmaking → Team Builder/Auction → 5v5 Battle → Match Result → Leaderboard**

---

## 2. MVP Goals

The MVP should allow a player to:

- Sign in with Google or continue as a guest.
- Enter a simple multiplayer lobby.
- Find another available player.
- Build a 5-character team through the auction system.
- Play a 5v5 card battle.
- Receive a win or loss.
- View their player record.
- View the leaderboard.
- Browse the current anime character and verse roster.

The MVP should be playable end-to-end without requiring card ownership, packs, decks, or progression.

---

## 3. Tech Stack

### Frontend

- React
- Vite
- TypeScript

### Backend / Platform

- Supabase

Supabase will provide:

- Authentication
- PostgreSQL database
- Realtime multiplayer updates
- Row Level Security
- Server-side/database functions where needed

### Character Data

An external anime API such as Jikan may be used as an **import/catalogue source** for:

- Character names
- Character images
- Anime relationships
- Basic metadata

The live game should primarily use character records stored in Supabase rather than depending on the external API during matches.

---

## 4. Authentication

The MVP supports two login methods.

### Google Sign-In

Google users receive a persistent account.

Their profile may contain:

- User ID
- Display name
- Avatar
- Wins
- Losses
- Created date

### Guest Sign-In

Guest users should be able to enter the game quickly using Supabase anonymous authentication.

Example generated username:

`Guest_4821`

Guests should use the same player/profile infrastructure as Google-authenticated players.

A future version may allow guests to upgrade/link their account to Google.

### Leaderboard Rule for Guests

For the MVP, guest accounts may play normal matches and maintain stats, but they should not appear on the public Top 100 leaderboard unless this behavior is intentionally changed later.

---

## 5. Main MVP Screens

### 5.1 Login

Primary actions:

- Continue with Google
- Play as Guest

The screen should be simple and focused on getting the player into the game.

---

### 5.2 Lobby

The lobby is the primary authenticated landing page.

Display:

- Player avatar
- Player username
- Wins
- Losses
- Win percentage
- Find Match button
- Top 10 leaderboard preview
- Navigation to Characters
- Navigation to Leaderboard
- Sign Out

Primary CTA:

**Find Match**

---

### 5.3 Matchmaking

The first matchmaking version should be intentionally simple.

Behavior:

1. Player selects **Find Match**.
2. Player enters the matchmaking queue.
3. The app searches for another waiting player.
4. Once two players are matched, a match record is created.
5. Both clients enter the same match room.

No ranked/unranked queue separation is required for MVP.

Potential states:

- Idle
- Searching
- Match found
- Entering match
- Cancelled
- Disconnected

Supabase Realtime is expected to synchronize relevant multiplayer state.

---

### 5.4 Direct Challenges

Persistent authenticated players can invite another eligible real player from the Players leaderboard or that player's public profile. An invitation is private to its two participants, expires after 60 seconds, and can be accepted, declined, or cancelled. Realtime delivers the invite globally while an initial authenticated read restores a pending invitation after refresh.

Accepted invitations create one match with the authoritative `direct_challenge` source and reuse the standard Initiative, OC Selection, Draft, OC Preparation, Battle, and Result flow. Direct Challenges are unranked in V1: they do not change ranked wins/losses, leaderboard standings, or Boon Points. They never enter the matchmaking queue and never invoke the Administrator fallback.

---

## 6. Character and Verse System

### Verse

A **verse** represents a franchise/universe rather than an individual anime season.

Examples:

- Naruto
- Dragon Ball
- Bleach
- One Piece
- Jujutsu Kaisen

Multiple anime entries may map into the same verse.

For example:

- Naruto
- Naruto Shippuden

should both belong to:

**Naruto Verse**

---

### Character Versions

Playable entities should eventually represent specific character versions rather than only the base character.

Examples:

- Naruto Uzumaki — Part I
- Naruto Uzumaki — Sage Mode
- Naruto Uzumaki — KCM2
- Naruto Uzumaki — Six Paths

This allows the game to represent changes in character power across a series.

For an early MVP roster, one primary version per character is acceptable if that simplifies development.

---

## 7. Character Power System

Each playable character has a visible **Overall Rating** similar to an NBA 2K rating.

Example:

`OVR 94`

The rating should represent the character relative to the entire playable roster, not only within their own verse.

Being the strongest character in a low-powered verse does not automatically mean the character receives a 99.

### Visible Overall

Recommended visible range:

- 99 — Apex
- 95–98 — God Tier
- 90–94 — Elite
- 85–89 — High Tier
- 80–84 — Strong
- 75–79 — Above Average
- 70–74 — Average
- 60–69 — Lower Tier

The exact ranges may change during balancing.

### Internal Power Score

Each character should also have a more precise internal power score.

Example:

- Display OVR: `94`
- Internal Power Score: `9437`

The internal score determines the winner if two characters display the same OVR.

Example:

- Character A: OVR 94 / Power Score 9437
- Character B: OVR 94 / Power Score 9381

Character A wins.

The intent is for character power to reflect the best available objective interpretation of who is actually stronger overall.

The MVP does not need detailed sub-stats such as speed, durability, hax, stamina, or battle IQ.

Those may be added later.

---

## 8. Team Builder / Auction Mode

This is the core drafting system.

### Starting State

Each player begins with:

- `$20`
- `0 / 5` characters

The goal is to finish with a team of exactly 5 characters.

Characters are presented from a shared draft pool.

The initial MVP may use a pool of approximately 10 characters per match.

---

## 9. Draft Priority

At the start of each character round, the player with the **highest remaining balance** receives priority.

Priority determines who acts first on the current character.

Example:

- Player A: $8
- Player B: $13

Player B receives priority.

### Tied Balance

If both players have the same balance, priority should alternate fairly between players.

One player should not permanently receive tie-break priority.

---

## 10. Auction Actions

The priority player chooses between:

- Bid
- Pass

### Bid

A bid starts the auction for that character.

Once bidding begins, players may raise the current bid.

The auction ends when one player folds or cannot/will not raise.

The winning player:

- Receives the character
- Pays the winning bid
- Uses one roster slot

There is no artificial maximum bid.

Players may spend aggressively if they choose.

The game should not prevent a player from reaching `$0`.

Overspending is balanced naturally through the priority/pass system.

---

## 11. Fold

**Fold** means the player concedes an active auction.

Example:

- Player A bids $5
- Player B folds
- Player A receives the character for $5

Fold is different from Pass.

---

## 12. Pass

**Pass** happens before the auction begins.

When the priority player passes:

- The opposing player is forced to receive the current character.
- The character costs the receiving player `$0`.
- The receiving player uses one roster slot.

Only one person can pass on a character round because the priority player makes the pass decision before bidding begins.

Pass is therefore both:

- A defensive decision
- An offensive drafting tool

A player may use it to force an unwanted character onto the opponent.

---

## 13. Zero-Balance Rule

A player is allowed to reach `$0`.

A player at `$0`:

- Cannot place a positive bid
- Is still active in the draft
- Can still receive free characters
- Can still be forced to receive a character when the opponent passes

Example:

- Player A: $0
- Player B: $4
- Player B has priority
- Player B passes
- Player A automatically receives the character for $0

This is an intentional consequence of spending all available money early.

---

## 14. Full-Team Rule

A player stops receiving characters after their roster reaches 5.

Pass behavior should never force a sixth character onto a completed roster.

Once one player's team is complete, remaining draft behavior should ensure the other player can complete their roster without invalid states.

Exact end-of-draft handling may be refined during implementation/testing.

---

## 15. Battle Phase

After both teams contain 5 characters, the match moves into the battle phase.

Both players should be able to see the available cards on each team unless a later design decision changes this.

Each round:

1. Each player selects one unused character.
2. The selection is locked.
3. Once both players are locked, both cards are revealed.
4. The stronger character wins the round.
5. Both cards become used and cannot be selected again.

---

## 16. Determining the Round Winner

The internal power score determines the winner.

Example:

- Goku — OVR 99 / Power Score 9980
- Naruto — OVR 95 / Power Score 9520

Goku wins the round.

If two visible OVR ratings are equal, the internal power score acts as the tie-breaker.

A true internal score tie should be extremely rare. If required later, a deterministic secondary tie-break rule can be introduced.

---

## 17. Match Winner

The match is best-of-five.

The first player to win **3 rounds** wins the match.

Maximum rounds:

`5`

Example final score:

`3 - 2`

After the match completes:

- Winner receives +1 win
- Loser receives +1 loss
- Match is marked complete
- Match result is stored
- Both players can return to the lobby

Match results should be validated server-side/database-side where possible rather than trusting a client to arbitrarily update its own wins.

---

## 18. Player Profiles

Each player profile should support at least:

- id
- username
- avatar_url
- is_guest
- wins
- losses
- created_at

Win percentage should be derived rather than stored.

Formula:

`wins / (wins + losses)`

If the player has zero completed matches:

`0%`

---

## 19. Leaderboard

The leaderboard page should display up to the **Top 100 players**.

The lobby may show a preview of the **Top 10**.

Recommended columns:

- Rank
- Player
- Wins
- Losses
- Games Played
- Win Rate

### Ranking

Do not rank purely by win percentage without a minimum-game requirement.

Otherwise a player with:

`1 win / 0 losses`

would have a 100% win rate and could incorrectly rank first.

Initial MVP rule:

- Minimum 10 completed matches to qualify
- Sort by win percentage
- Use total wins as a tie-breaker

A future version may replace this with Elo/MMR.

---

## 20. Character Listing

Route example:

`/characters`

Purpose:

Allow players to browse the currently playable roster.

Support:

- Character search
- Verse filter
- Overall filter
- Character image
- Character name
- Character version
- Verse
- OVR

Example card:

```text
Goku
Ultra Instinct
Dragon Ball
OVR 99
```

The first MVP does not require deep character detail pages.

### Random Verse

The Random verse broadens the playable roster with generic low- and mid-tier canon filler fighters. Its characters use a small reusable portrait set with deterministic frontend background themes so repeated portraits remain visually distinct.

Random fighters remain available in the normal character catalogue and canon draft pool. Random is not selectable as the verse for newly created OCs.

---

## 21. Verse Listing

Route example:

`/verses`

Display available verses and character counts.

Example:

```text
Dragon Ball
24 Characters

Naruto
22 Characters

Bleach
18 Characters
```

Selecting a verse may simply route to the character listing with the verse filter applied.

Example:

`/characters?verse=naruto`

---

## 22. Initial Navigation

Suggested authenticated navigation:

- Play
- Characters
- Leaderboard
- Profile / Avatar

The lobby/play experience should remain the primary focus.

---

## 23. Suggested Supabase Tables

The exact schema may evolve, but the MVP is expected to include concepts similar to the following.

### profiles

- id
- username
- avatar_url
- is_guest
- wins
- losses
- created_at

### verses

- id
- name
- slug
- image_url
- active

### characters

- id
- name
- slug
- verse_id
- version
- image_url
- overall
- power_score
- active

### matchmaking_queue

- player_id
- status
- joined_at

### matches

- id
- player_one_id
- player_two_id
- player_one_score
- player_two_score
- winner_id
- status
- created_at
- completed_at

### match_players

- id
- match_id
- player_id
- balance
- priority

### match_characters

- id
- match_id
- player_id
- character_id
- purchase_price
- draft_order
- used

### match_rounds

- id
- match_id
- round_number
- player_one_character_id
- player_two_character_id
- winner_id

The final schema should favor consistency, server-side validation, and clean Realtime subscriptions.

---

## 24. Suggested React Structure

The project should remain feature-oriented and avoid placing all application logic inside `App.tsx`.

Example:

```text
src/
├── components/
│   ├── CharacterCard/
│   ├── Navbar/
│   ├── PlayerCard/
│   └── MatchScore/
├── pages/
│   ├── Login/
│   ├── Lobby/
│   ├── Characters/
│   ├── Leaderboard/
│   ├── Match/
│   └── Profile/
├── features/
│   ├── auth/
│   ├── matchmaking/
│   ├── draft/
│   └── battle/
├── hooks/
├── lib/
│   └── supabase.ts
├── services/
└── types/
```

Exact organization can evolve as the application grows.

---

## 25. Recommended Development Order

### Phase 1 — Foundation

Implement:

- Supabase project connection
- Google authentication
- Guest authentication
- Player profiles
- Navigation
- Character database
- Character listing
- Verse listing

### Phase 2 — Local Game Prototype

Before building multiplayer networking, implement the game locally or with a simulated second player.

Validate:

- Character pool generation
- $20 balances
- Priority
- Bid
- Raise
- Fold
- Pass
- $0 behavior
- 5-character rosters
- Battle card selection
- Card reveal
- Power comparison
- Scoring
- First to 3 wins

The goal is to confirm the game rules are fun and internally consistent.

### Phase 3 — Multiplayer

Add:

- Matchmaking queue
- Match room creation
- Supabase Realtime
- Synchronized draft state
- Synchronized bids
- Synchronized passes/folds
- Synchronized battle card selection
- Match completion
- Basic reconnect handling

### Phase 4 — Competitive Layer

Add:

- Persistent W/L records
- Win-rate calculation
- Top 100 leaderboard
- Top 10 lobby preview
- Recent match history if useful

---

## 26. Explicitly Out of Scope for MVP

Do not add these unless the MVP scope is intentionally changed:

- Card packs
- Loot boxes
- Paid cards
- Card ownership
- Custom decks
- Trading
- Friends system
- Tournaments
- Guilds/clans
- Ranked divisions
- Multiple battle modes
- Character abilities
- Buffs/debuffs
- Detailed character sub-stats
- Card crafting
- Marketplace
- In-game currency
- Mobile-native application
- Push notifications
- Complex progression systems
- Cosmetic rarity system

All players should initially use the same shared game roster.

---

## 27. Product Principles

When implementing new features, favor these principles:

### Keep the core loop fast

Players should reach an actual match with as little friction as possible.

### Strategy should come from player decisions

The most important decisions should be:

- When to spend money
- When to preserve balance
- When to pass
- When to fold
- Which character to play in each battle round

### Spending has consequences

There should be no arbitrary maximum bid.

The natural cost of aggressive spending is:

- Lower remaining balance
- Loss of future priority
- Increased risk of being forced to accept passed characters

### Keep competition fair

For MVP:

- Players do not own stronger cards.
- Everyone draws from the same playable roster.
- Winning should primarily depend on drafting and battle decisions.

### Server authority where important

Do not trust browser clients with authoritative changes to:

- Wins
- Losses
- Match winner
- Final match state
- Other competitive data that can be manipulated

---

## 28. Source of Truth for Codex

This file should be treated as the main reference for the Anime Arena MVP.

Before implementing a significant feature, Codex should:

1. Review this document.
2. Inspect the existing codebase.
3. Follow existing project conventions.
4. Avoid introducing features that conflict with the MVP scope.
5. Avoid silently changing game rules.
6. Call out ambiguities when a rule cannot be safely inferred from this reference.
7. Prefer incremental, testable changes over large unnecessary rewrites.

If implementation details conflict with this document, this document represents the intended product behavior unless a later user instruction explicitly overrides it.
