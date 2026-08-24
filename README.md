# Anime Arena

Anime Arena is a React, TypeScript, and Supabase anime PvP team-building game. Players enter online matchmaking, compete for draft priority, build a five-fighter team, prepare a persistent Original Character (OC), and resolve battles through an OVR-first combat system.

The application currently includes online multiplayer, a local prototype mode, a database-driven character catalogue, OC creation and progression, player and OC leaderboards, and a community game guide with suggestions and voting.

## Features

- Server-authoritative online matchmaking, draft, OC preparation, battle, and match results
- Human-first matchmaking with an Administrator system-opponent fallback
- Local prototype draft and battle mode against a client-side opponent
- Searchable, sortable, paginated anime character catalogue with dynamic verse filters
- Persistent OCs with portraits, progression, retirement, permanent fighter types, and a three-slot OC Family
- Player, individual OC, and OC Family leaderboards
- Google OAuth and anonymous guest sign-in
- Community area with How to Play, FAQ, suggestions, voting, and suggestion statuses
- Responsive catalogue, draft, fighter selection, opponent-team browsing, battle, and result interfaces
- Optional sound effects for gameplay interactions

## Gameplay

### Online match flow

Competitive matches move through authoritative Supabase states:

1. **Matchmaking** - join the queue and match with a human or the Administrator fallback.
2. **Initiative** - both players secretly lock Rock, Paper, or Scissors.
3. **OC Selection** - each player sees the opponent's possible OC Family but secretly selects their own match OC.
4. **Draft** - auction a shared pool of ten canon-style fighters until each player owns five.
5. **OC Preparation** - keep the selected OC as a reserve or use its type-specific preparation option.
6. **Battle** - secretly select one unused fighter per round; both choices reveal together.
7. **Match Result** - first to three round wins takes the match, with a maximum of five rounds.
8. **Rankings** - completed non-draw matches update player wins and losses.

Before battle, a participant may cancel an active match. During battle, leaving is a forfeit and awards the opponent the win.

### Initiative

Initiative uses Rock, Paper, Scissors. Choices remain hidden until both participants lock. A winner receives initial draft priority; a draw starts another initiative round. The interface reports opponent lock-in and round results without revealing a pending opponent choice.

### Auction draft

- Ten active fighters are selected for a shared draft pool.
- Each participant starts with **$20** and drafts exactly **five fighters**.
- The priority player may pass or open bidding.
- Players may bid/raise while they can afford the amount; the non-leading player may fold.
- Passing gives the fighter to the opponent for $0. Folding awards it to the current bidder at the current bid.
- After the first fighter, the higher remaining balance receives priority. Tied balances use alternating tie priority.
- Once one roster is full, the remaining fighters safely fill the other roster.

Online draft transitions are handled by PostgreSQL functions rather than trusted to browser state.

### Battle resolution

Anime Arena resolves every canon and OC matchup in this order:

1. Higher **OVR** wins.
2. If OVR is equal, higher **Global Power** (`power_score` in the schema) wins.
3. If both values are equal, the round is a draw.

OVR always has priority, including across different verses. A 99 OVR fighter defeats a 98 OVR fighter regardless of Global Power. Global Power is the cross-verse strength metric and equal-OVR tiebreaker; it never overrides a higher OVR.

Both selected fighters are consumed for the match after a resolved round, including a draw. A fighter cannot be selected twice.

### Local prototype

The `/play/test` route runs a local auction draft and battle against a client-side opponent using the active character catalogue. It follows the same five-fighter, $20 draft shape and OVR-first battle resolver, includes audio feedback and responsive fighter/opponent card browsing, and can issue progression rewards for eligible local wins through Supabase.

Local prototype decisions and opponent AI are browser-simulated. It is useful for testing the core loop, but it is not identical to the server-authoritative online implementation.

## Original Characters

OCs are persistent player-owned fighters associated with an exact verse. A player may keep up to **five active OCs**, while retired OCs remain stored outside the active limit. Up to **three active OCs** may be equipped as the player's OC Family, and one is secretly selected for each online match.

Each OC stores:

- starting and current OVR
- an OVR cap
- starting and current Global Power
- a Global Power cap
- progression points
- verse, portrait, active/equipped state, and retirement state
- a permanent **Champion** or **Sacrificial** fighter type

OC identity, type, stats, cap, verse, and portrait are snapshotted for a match. Changes made to the persistent OC after matchmaking do not rewrite an in-progress match.

### Creation and progression

New OCs receive a trusted server-side weighted starting OVR from 50 to 60 and begin at 5,000 Global Power. Starting OVR determines the growth archetype and permanent caps:

| Starting OVR | Archetype | OVR cap | Global Power cap |
| ---: | --- | ---: | ---: |
| 50-52 | High Potential | 92 | 10,000 |
| 53-55 | Growth-Focused | 93 | 9,500 |
| 56-58 | Balanced | 94 | 9,000 |
| 59-60 | Prodigy | 95 | 8,500 |

This creates a tradeoff: lower starters have a larger long-term Global Power ceiling, while higher starters can reach a slightly higher permanent OVR.

Eligible local prototype wins create claimable progression rewards. Points may be assigned to an active OC and spent on either:

- **OVR:** +1 per upgrade, with costs increasing at higher OVR bands
- **Global Power:** up to +50 per point, limited by the OC's power cap

Reward creation, claiming, and spending are transactional and ownership-checked in PostgreSQL. Local match results are still client-simulated, so stronger anti-farming validation remains a production-hardening area.

### Champion

A Champion is combat-oriented. During OC Preparation it may:

- **Reserve:** keep all five drafted canon fighters and remain available to fight once; or
- **Absorb:** give up one drafted fighter with the exact same `verse_id` for a temporary tier-based OVR increase.

The absorbed canon fighter becomes unavailable for that match. Champion Global Power and persistent OC stats do not change, and temporary OVR cannot exceed 99.

Resulting battle roster:

- Reserve: five canon fighters plus the Champion
- Absorb: four usable canon fighters plus the temporarily boosted Champion

### Sacrificial

A Sacrificial OC is support-oriented, but **Reserve is still available by default**. During OC Preparation it may:

- **Reserve:** keep all five canon fighters at normal stats and remain available to fight once; or
- **Sacrifice OC:** leave the battle roster and grant temporary Global Power to every drafted canon fighter with the exact same `verse_id`.

Sacrificial support does not increase OVR or permanently change any fighter. The transfer is calculated and capped by the current server function.

Resulting battle roster:

- Reserve: five canon fighters plus the Sacrificial OC
- Sacrifice: five canon fighters, with eligible exact-verse fighters receiving temporary Global Power support

Verse matching is exact. AU universes are independent verses: for example, JJK AU does not count as Jujutsu Kaisen.

### Type permanence and portraits

New OCs choose Champion or Sacrificial during creation. That choice is server-protected and intended to be permanent. Legacy untyped OCs receive a one-time type-selection flow.

Equipped, active, non-retired OCs can upload a JPG, PNG, or WebP portrait up to 5 MB. Portrait objects use the Supabase `oc-images` bucket and are rendered with an initial-based fallback when no usable image is available.

## Character roster

The catalogue is database-driven: it loads active `characters`, joins their `verses`, and derives both the dropdown and chip filters from the returned data. Adding an active database verse with active fighters does not require a hard-coded frontend filter update.

The current project roster is designed to cover canon universes such as:

- Attack on Titan
- Black Clover
- Bleach
- Chainsaw Man
- Demon Slayer
- Dragon Ball
- Hunter x Hunter
- Jujutsu Kaisen
- My Hero Academia
- Naruto
- One Piece
- Solo Leveling

AU/custom verse content includes JJK AU, HXH AU, and Naruto AU. These are separate verse records, not canon aliases.

### Random

Random is a utility verse containing regular draftable filler fighters. It broadens the lower/mid-OVR roster and reduces catalogue and draft top-heaviness. Random fighters use reusable generic portraits with deterministic frontend background themes so repeated source art remains visually distinct.

Random appears in the normal catalogue and draft pool, but the OC creation form explicitly excludes it.

### Character art

Canon-style fighters reference artwork through `characters.image_url`. The frontend supports normal hosted images, transparent portrait assets, Random-specific presentation, and an initial fallback when an image is absent or fails to load.

This repository provisions the `oc-images` bucket for player OC portraits. It does **not** currently contain a SQL migration that provisions a separate `character-art` bucket, so canon artwork hosting should follow the deployment's existing `image_url` data rather than an assumed bucket structure.

## Leaderboards

### Players

The player leaderboard includes non-guest profiles that have at least one recorded result (`wins + losses > 0`). It displays wins, losses, games played, and win rate, ordered by win rate with deterministic tie-breakers. The public Administrator profile participates in the same records and may appear with a System badge.

### OCs

Individual active OCs can be ranked by:

- OVR
- Global Power
- Growth from starting OVR

OC Family rankings require exactly three active, equipped fighters and provide separate Family OVR, Family Power, and Family Growth views. These metrics remain separate rather than being combined into one cross-scale score.

## Administrator opponent

Matchmaking is human-first. When no human opponent has claimed the waiting player before the configured fallback window (currently 12 seconds in both frontend configuration and the provided SQL default), the client may request a match with the **Administrator** system player. The server checks for a real waiting human again under the matchmaking lock before creating the system match.

The Administrator:

- is a persistent, publicly identified non-guest profile
- has tracked wins and losses and can appear on the player leaderboard
- owns a dedicated equipped OC Family and selects one of its available match options
- participates in initiative, draft, OC Preparation, and battle through server-side actions
- values useful exact-verse OC synergy while avoiding clearly poor roster trades
- generally tries to make meaningful use of its selected OC when it remains strategically reasonable

Contextual Administrator toasts appear at match start and after match results. The client also shows the fallback countdown and the transition into an Administrator match.

## Community and game guide

The `/community` page contains:

- a quick-start and full-match guide
- FAQs covering battle, draft, OCs, and match exits
- a searchable suggestion board with categories, sorting, voting, and status tracking
- administrator-only suggestion status controls when the current profile has that role

The root README is the implementation overview. Detailed design and historical system context live in:

- [`docs/MVP_REFERENCE.md`](docs/MVP_REFERENCE.md)
- [`docs/ANIME_ARENA_OC_SYSTEM.md`](docs/ANIME_ARENA_OC_SYSTEM.md)

When these references describe recommendations or future phases, the current source and latest SQL patches remain the implementation source of truth.

## Tech stack

| Area | Technology |
| --- | --- |
| Frontend | React 19, TypeScript, React Router |
| Build tooling | Vite 8 |
| Backend/platform | Supabase PostgreSQL, Auth, Realtime, Storage, and PostgreSQL RPC functions |
| Client SDK | `@supabase/supabase-js` |
| Audio | `use-sound` / Howler-backed browser audio |
| Linting | Oxlint |
| Package management | npm with `package-lock.json` |
| Deployment | Vercel |
| Version control | Git / GitHub |

No additional state-management framework or CSS component dependency is currently used.

## Architecture

Supabase/PostgreSQL is authoritative for competitive online state. Trusted RPCs validate ownership, legal transitions, draft actions, OC snapshots/preparation, hidden fighter choices, battle resolution, and match completion. Supabase Realtime primarily tells clients that state changed; clients then refetch the perspective-safe authoritative state.

Sensitive choices are kept out of ordinary browser-readable tables where implemented. Pending initiative choices, selected OCs, OC preparation details, and battle selections are returned from the player's perspective, exposing opponent lock status rather than an unrevealed choice. Resolved rounds reveal the fighters and snapshotted match stats required by the result UI.

The principal authenticated routes are:

| Route | Purpose |
| --- | --- |
| `/` | Player Lobby and matchmaking |
| `/characters` | Character catalogue |
| `/loadout` | Pre-match Loadout hub for OC Family and Boon summaries |
| `/ocs` | OC Family, collection, progression, and portraits |
| `/boons` | Boon inventory, equipment, and Shop |
| `/leaderboard` | Player and OC rankings |
| `/community` | Game guide, FAQ, and suggestions |
| `/play/test` | Local prototype mode |
| `/match/:matchId` | Online initiative, OC selection, draft, preparation, and battle |

The primary navigation groups `/ocs` and `/boons` under one top-level Loadout
entry. Both dedicated management URLs remain available and share lightweight
page-level Loadout navigation. `/suggestions` is retained as a redirect to
`/community`; unknown client routes return to the Lobby after the SPA loads.

## Project structure

```text
src/
  assets/       Static assets imported by the application
  components/   Shared navigation, cards, avatars, toasts, and UI states
  data/         Static application copy such as Administrator quotes
  features/     Audio, local game, matchmaking, OCs, online game, suggestions
  hooks/        Shared data-loading and authentication hooks
  lib/          Supabase client and reusable utilities
  pages/        Route-level screens
  types/        Shared domain types

public/         Public icons, sounds, and Administrator portrait assets
docs/           Reference documents and Supabase SQL migrations/patches
```

There is no top-level `supabase/` migrations directory in the current repository; database SQL is maintained under `docs/`.

## Getting started

### Prerequisites

- Node.js with npm
- A Supabase project configured for this application's schema and authentication providers

### Install and run

```bash
git clone https://github.com/Shaqnificent/cards-arena.git
cd cards-arena
npm install
```

Create `.env.local` in the project root:

```dotenv
VITE_SUPABASE_URL=
VITE_SUPABASE_PUBLISHABLE_KEY=
```

Then start Vite:

```bash
npm run dev
```

Do not put a Supabase service-role key in a `VITE_*` variable. Vite variables are included in browser code; use only the project's public/publishable key.

### Authentication setup

Enable Anonymous Sign-Ins and the Google provider in Supabase Auth. Add the local and deployed application URLs to Supabase's allowed redirect URLs. The frontend redirects Google OAuth back to the application's origin.

Google users receive persistent profile/stat data through their account. Guest users use a Supabase anonymous session; their data remains tied to that anonymous identity and may be lost if the browser session/identity is cleared. Guest profiles are excluded from the public player leaderboard.

## Supabase setup

The SQL under `docs/` covers profiles, verses and characters, suggestions, matchmaking, initiative, online draft/battle, OC foundation/progression/types/portraits/leaderboards, match exit behavior, and the Administrator.

These files are cumulative, dependency-sensitive migration and patch artifacts—not a single fresh-database script. Do **not** blindly execute every SQL file. Before applying one:

1. Inspect the file header and its stated prerequisite migrations.
2. Compare it with the functions and tables already installed in the target Supabase project.
3. Apply only the missing/current migration in dependency order.
4. Recheck RLS, grants, Realtime publication membership, and the PostgREST schema cache.

Useful entry points include:

- [`docs/supabase_profiles.sql`](docs/supabase_profiles.sql)
- [`docs/supabase_characters.sql`](docs/supabase_characters.sql)
- [`docs/supabase_matchmaking.sql`](docs/supabase_matchmaking.sql)
- [`docs/supabase_online_draft.sql`](docs/supabase_online_draft.sql)
- [`docs/supabase_rps_initiative.sql`](docs/supabase_rps_initiative.sql)
- [`docs/supabase_match_oc_selection.sql`](docs/supabase_match_oc_selection.sql)
- [`docs/supabase_oc_types_and_sacrifice.sql`](docs/supabase_oc_types_and_sacrifice.sql)
- [`docs/supabase_oc_creation_limit.sql`](docs/supabase_oc_creation_limit.sql)
- [`docs/supabase_oc_leaderboards.sql`](docs/supabase_oc_leaderboards.sql)
- [`docs/supabase_oc_images.sql`](docs/supabase_oc_images.sql)
- [`docs/supabase_match_exit.sql`](docs/supabase_match_exit.sql)
- [`docs/supabase_administrator_opponent.sql`](docs/supabase_administrator_opponent.sql)

Because later files replace functions from earlier phases, preserving the latest canonical function body is essential. For a new environment, review the dependency comments and consolidate a tested installation order before treating the SQL collection as a production migration chain.

## Development scripts

| Command | Purpose |
| --- | --- |
| `npm run dev` | Start the Vite development server |
| `npm run build` | Run the TypeScript project build and create a Vite production bundle |
| `npm run lint` | Run Oxlint |
| `npm run preview` | Preview the production bundle locally |

The current `package.json` does not define an automated test script.

## Deployment

The project is configured for Vercel:

1. Import the GitHub repository into Vercel.
2. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` to the deployment environment.
3. Use the Vite production build (`npm run build`); Vercel serves the generated `dist/` output.
4. Add the Vercel production/preview URLs to Supabase Auth redirect configuration, including the Google OAuth flow.

[`vercel.json`](vercel.json) rewrites all application routes to `index.html`, allowing direct navigation and browser refreshes on React Router paths such as `/characters`, `/ocs`, and `/match/:matchId` without a Vercel 404.

## Screenshots

Current product screenshots are not tracked in the repository. Add verified image assets here before introducing README image links.

## Current status

Anime Arena has a working end-to-end online match path, local prototype mode, persistent OC management/progression, Administrator fallback opponent, rankings, catalogue, community guide, responsive UI, and Vercel SPA configuration.

The main operational caveat is database installation: the repository contains an evolving sequence of SQL migrations and corrective patches rather than one consolidated bootstrap migration. Local prototype gameplay is client-simulated, and its progression endpoint should receive additional anti-farming validation before production use.
