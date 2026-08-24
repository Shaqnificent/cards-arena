# Anime Arena — OC Family Social System

## 1. Purpose

The OC Family Social System expands Anime Arena's Original Character (OC) feature beyond combat and progression by giving player-created OCs more personality, identity, and public presence.

The system introduces a lightweight social and slice-of-life layer where players can:

- write lore/background descriptions for their OCs
- create a recognizable identity for their active OC Family
- upload a custom OC Family logo
- visit other players' public profiles from the leaderboard
- view another player's currently equipped OC Family
- inspect the lore and identity of individual OCs

This feature is intended to increase player attachment to OCs without changing battle balance, progression, matchmaking, or competitive rules.

---

## 2. Core Design Principles

### 2.1 Cosmetic and Social Only

Lore, family branding, logos, descriptions, and profile presentation are cosmetic/social features.

They must not affect:

- OVR
- Global Power / `power_score`
- progression points
- OC caps
- matchmaking
- leaderboard calculations
- Champion or Sacrificial mechanics
- battle outcomes

### 2.2 Lore Belongs to the OC

OC lore belongs to the OC itself, not to an OC Family loadout slot.

If an OC moves from Slot 1 to Slot 3, its lore remains unchanged.

The OC Family loadout only determines which equipped OCs are currently showcased as the player's active family.

### 2.3 Public Data Must Be Intentional

Public profiles should expose only game-facing information intended for other players to see.

Do not expose private account information, authentication details, email addresses, internal IDs, or unrelated profile metadata.

### 2.4 Keep the Social Layer Lightweight

V1 should focus on profile viewing and OC showcase features.

Do not add comments, private messaging, follower systems, or other moderation-heavy social features as part of this phase.

---

## 3. Public Player Profiles

Players should be able to open another player's profile from surfaces such as the player leaderboard.

Suggested route:

```text
/profile/:playerId
```

The route should use the existing public player/profile identifier already used by the application rather than relying on usernames as unique keys.

### 3.1 Public Profile Content

A public player profile should display, where available:

- display name / username
- avatar
- leaderboard rank
- wins
- losses
- win rate
- OC Family name
- OC Family logo
- OC Family tagline
- OC Family summary/description
- button or section to view the active OC Family

Example presentation:

```text
RIADA
Rank #4

12 Wins · 6 Losses · 66.7%

[ Family Logo ]
HOUSE OF RIADA
"The last breath never fades."

View OC Family
```

### 3.2 Leaderboard Navigation

Player names and/or avatars on the leaderboard should become navigable to the public profile where appropriate.

System-only rows should remain compatible with the current Administrator behavior.

If the Administrator receives a public profile, clearly distinguish it as a system-controlled profile.

### 3.3 Guest Profiles

Guests should not receive the full editable public-profile experience unless the game explicitly supports persistent guest identity.

Recommended V1 behavior:

- guests can participate in supported gameplay
- guests do not create persistent OC Family branding
- guest-only data should not create public social profiles unless a persistent profile already exists

---

## 4. OC Family Identity

An OC Family represents the player's currently equipped active OC loadout.

The family should feel like a personal anime faction, team, clan, house, guild, or organization created by the player.

### 4.1 Family Properties

Recommended family fields:

- Family Name
- Tagline
- Description
- Logo
- Owner
- Created At
- Updated At

Suggested constraints:

- Family Name: short, readable, required once family customization is enabled
- Tagline: optional, short single-line text
- Description: optional, longer summary
- Logo: optional image

### 4.2 Recommended Data Model

Prefer a dedicated table rather than placing all family-specific fields directly on `profiles`.

Suggested structure:

```sql
public.oc_families
- id uuid primary key
- owner_id uuid not null references public.profiles(id)
- name text
- tagline text
- description text
- logo_url text
- created_at timestamptz
- updated_at timestamptz
```

Recommended relationship:

- one active OC Family per player in V1
- the player's currently equipped active OCs determine the family members
- do not introduce a separate family-member table unless future requirements make it necessary

A unique constraint on `owner_id` is appropriate if V1 supports only one family per player.

---

## 5. OC Family Membership

The public OC Family should be based on the player's active equipped OC loadout.

Current intended family size:

```text
Maximum active family: 3 equipped OCs
```

### 5.1 Public Family Rules

By default, the public family page should show:

- active OCs
- equipped OCs
- non-retired OCs

Do not publicly show retired or inactive OCs as active family members unless a future collection/history feature explicitly supports it.

### 5.2 Loadout Changes

When a player changes which OCs are equipped:

- the public family showcase should update automatically
- OC lore stays attached to the original OC
- family branding remains unchanged

---

## 6. OC Lore / Background

Each player-created OC should support a public lore/background field.

Suggested new field:

```sql
alter table public.player_characters
add column if not exists lore text;
```

The final migration should follow the project's existing migration conventions rather than relying solely on the example above.

### 6.1 Lore Content

Lore can describe things such as:

- origin
- personality
- motivations
- relationships
- fighting philosophy
- place within the chosen universe
- personal history
- goals
- role within the OC Family

### 6.2 Character Limit

Recommended initial limit:

```text
1000 characters
```

A smaller range such as 500–1000 characters is acceptable if the UI benefits from tighter content.

The final value should be enforced consistently in:

- frontend validation
- database/RPC validation where appropriate

### 6.3 Lore Editing

Owners should be able to edit lore from an OC management/detail surface.

Potential actions:

- Edit Lore
- Save
- Cancel

Lore should not require recreating or retiring the OC.

### 6.4 Empty Lore State

If an OC has no lore, public UI should use a clean empty state such as:

```text
No story has been written for this OC yet.
```

Do not generate lore automatically without the user's request.

---

## 7. OC Public Showcase

Each OC shown through another player's OC Family should have a public-facing detail presentation.

Recommended information:

- portrait
- name
- verse
- fighter type
- current OVR
- OVR cap
- Global Power
- Power cap where appropriate
- growth/progression summary where appropriate
- lore/background

Avoid exposing private progression controls or owner-only management actions.

### 7.1 Fighter Type

Display the permanent OC fighter type clearly:

- Champion
- Sacrificial

This is informational only on public profiles.

### 7.2 Family Card Example

```text
SHAQNIFICENT
Champion
Attack on Titan

61 OVR
5,150 Global Power

"Born beyond the walls..."

View OC
```

---

## 8. OC Family Logo

Players should be able to upload a logo representing their OC Family.

### 8.1 Image Use

The logo may appear on:

- public player profile
- OC Family showcase page
- OC Family leaderboard surfaces
- future match-introduction/social surfaces

### 8.2 Recommended Storage

Use a dedicated Supabase Storage bucket or a clearly separated folder inside an appropriate existing bucket.

Preferred concept:

```text
oc-family-logos/
  {ownerId}/
    family-logo.png
```

or equivalent project-consistent naming.

Do not mix family branding assets into canon `character-art`.

### 8.3 Upload Restrictions

Recommended V1 constraints:

- image formats: PNG, JPEG, WebP
- maximum file size: approximately 2–5 MB
- one active logo per family
- owner-only upload/update/delete
- public read access if public profiles need direct rendering

### 8.4 Storage Security

Storage policies should verify that:

- authenticated user owns the target OC Family
- user may only mutate assets inside their own folder/path
- other users may read public family logos
- other users cannot overwrite another player's logo

### 8.5 Logo Replacement

Uploading a replacement logo should:

- update the family's `logo_url`
- avoid creating uncontrolled orphaned assets where practical
- preserve a clean fallback if upload fails

---

## 9. OC Family Profile / Showcase Page

Suggested route patterns:

```text
/profile/:playerId/family
```

or integrate the family directly within:

```text
/profile/:playerId
```

Choose the route model that best fits the existing router and UI architecture.

### 9.1 Suggested Layout

#### Header

- Family logo
- Family name
- tagline
- owner
- short description

#### Family Stats

If already supported by existing OC leaderboard calculations:

- Family OVR
- Family Power
- Family Growth

#### Members

Show the currently equipped OC Family members as polished cards.

For each member:

- portrait
- name
- verse
- Champion/Sacrificial badge
- OVR
- Global Power
- growth indicator if appropriate
- View OC action

### 9.2 Example

```text
HOUSE OF RIADA
"The last breath never fades."

Owner: Riada

Family OVR      72.7
Family Power    6,240
Family Growth   +41

[ OC 1 ]  [ OC 2 ]  [ OC 3 ]
```

---

## 10. Existing OC Leaderboards

The social system should complement the existing OC leaderboard systems rather than replace them.

Where currently supported, public profiles/family pages may surface:

### Individual OC Rankings

- Overall
- Power
- Growth

### OC Family Rankings

Continue using the current Family ranking metrics and current equipped-family rules.

Do not introduce a new composite competitive score solely for this social feature.

---

## 11. Profile Privacy and Data Exposure

Public profile RPCs/queries must expose only required public game data.

Recommended publicly readable fields may include:

- display name
- avatar URL
- public W/L statistics
- leaderboard rank/result data
- OC Family branding
- equipped public OC information
- public OC lore

Do not expose:

- email
- auth provider details
- private account settings
- internal authentication metadata
- unrelated private profile fields

Prefer perspective-safe / explicit public profile queries or RPCs instead of giving broad unrestricted access to private profile tables.

---

## 12. Authorization Rules

### Owner Can

- edit Family name
- edit Family tagline
- edit Family description
- upload/replace/delete Family logo
- edit lore for OCs they own
- manage which OCs are equipped using existing OC loadout rules

### Other Players Can

- view public player profile
- view active OC Family
- view public OC lore
- view public OC stats

### Other Players Cannot

- edit another player's profile
- edit another player's family
- upload another player's logo
- edit another player's OC lore
- change another player's equipped OCs

---

## 13. Administrator / System Player

The Administrator should remain compatible with public-profile and OC-Family views.

Possible V1 behavior:

- Administrator profile is viewable from leaderboard
- clearly show `SYSTEM` designation
- show Administrator's active OC Family
- show Administrator OC portraits/stats
- Family branding may use a fixed system-owned logo/name
- editing controls are never exposed to normal users

The Administrator should not require the same owner-editing workflow as a normal player.

---

## 14. User Interface Surfaces

Potential UI additions:

### Leaderboard

Make eligible player rows navigable.

Possible interaction:

```text
Tap player -> Public Profile
```

### My OCs

Add owner actions such as:

- Edit Lore
- View Public Profile
- Customize OC Family

### Public Profile

Display:

- player identity
- competitive record
- OC Family preview
- Family logo
- View Family action

### OC Family

Display:

- branding
- family stats
- three equipped members
- individual OC lore links/details

### Individual OC Detail

Display:

- portrait
- stats
- type
- verse
- lore

---

## 15. Responsive Design

All new social surfaces should support desktop and mobile.

### Mobile

Recommended behavior:

- stacked profile sections
- centered or compact Family branding
- horizontally scrollable or responsive OC cards if necessary
- readable lore blocks
- touch-friendly controls for owners

### Desktop

Recommended behavior:

- larger Family header
- 3-column OC Family member presentation
- profile statistics alongside branding where space allows

Do not allow long lore or Family descriptions to cause horizontal overflow.

---

## 16. Text Validation

Recommended V1 limits:

```text
Family Name:        40 characters
Family Tagline:     80 characters
Family Description: 500 characters
OC Lore:            1000 characters
```

Exact values may be adjusted during implementation, but the frontend and backend must agree.

Trim leading/trailing whitespace before saving.

Do not allow empty whitespace-only names if Family Name becomes required.

---

## 17. Image Fallbacks

If no Family logo exists:

- use initials
- use a generic Anime Arena family emblem
- or use an existing neutral placeholder

Do not show broken images.

Existing OC portrait fallback behavior should continue to work on public profile surfaces.

---

## 18. Suggested Database Changes

The final migration should inspect the current schema before applying changes.

Conceptually:

### `player_characters`

Add:

```text
lore text
```

### `oc_families`

Potential table:

```text
id
owner_id
name
tagline
description
logo_url
created_at
updated_at
```

Potential constraints:

- `owner_id` references `profiles(id)`
- one Family per owner in V1
- owner deletion behavior should follow existing profile lifecycle rules

### Public Profile Retrieval

Prefer a dedicated public query/RPC/view that returns only intentionally public fields.

Do not rely on broad client access to private profile data.

---

## 19. Recommended RPC / Service Responsibilities

Exact function names should follow existing project conventions.

Potential operations:

- get public player profile
- get public OC Family
- update own Family identity
- update own OC lore
- set Family logo URL

All mutations must verify ownership using authenticated user identity server-side.

Do not trust an owner ID supplied only by the client.

---

## 20. Realtime Requirements

Realtime is not required for V1 social/profile functionality.

Profile and lore changes may appear after normal refetch/navigation.

If existing app architecture naturally invalidates/refetches profile data after edits, reuse that approach.

Do not add unnecessary Realtime subscriptions solely for Family branding.

---

## 21. Moderation / Safety Scope

Because users can supply text and images, V1 should keep customization constrained.

At minimum:

- text length limits
- image size/type limits
- owner-only editing
- public rendering should safely escape text

Do not add public comments or user-to-user messaging in this phase.

Any future broader social functionality should receive its own moderation/privacy design review.

---

## 22. Phase Plan

### Phase 1 — Public Player Profiles

Implement:

- leaderboard -> player profile navigation
- public player profile route
- W/L + rank display
- OC Family preview using existing equipped OCs

Goal:

Establish the social navigation layer before adding customization.

#### Phase 1 implementation status — Implemented

Stable Phase 1 decisions:

- Public player profiles use `/profile/:playerId` with the existing profile UUID.
- Eligible normal-player rows on the player leaderboard link to the profile route.
- Guest and Administrator/system profiles are intentionally unavailable in V1.
- `public.get_public_player_profile(uuid)` is the only data source used by the public-profile screen. It returns an explicit, game-facing JSON shape rather than a raw `profiles` or `player_characters` row.
- Player rank follows the existing player leaderboard order: win rate, wins, games played, username, and UUID.
- The public OC Family is derived directly from active, equipped, non-retired `player_characters`, limited to the existing three loadout slots.
- Phase 1 does not create `oc_families`. Family identity fields remain scheduled for Phase 3 so players do not need a metadata row to receive a public profile.
- Phase 1 does not add lore, editing, uploads, comments, reactions, follows, messaging, or any gameplay changes.
- The manual migration is `docs/supabase_oc_family_social_phase1.sql`.

### Phase 2 — OC Lore

Implement:

- `player_characters.lore`
- owner lore editor
- lore character limit
- public lore rendering

Goal:

Give individual OCs personality and history.

### Phase 3 — OC Family Identity

Implement:

- `oc_families`
- Family name
- tagline
- description
- owner customization UI

Goal:

Turn the equipped OC group into a recognizable faction.

### Phase 4 — Family Logo

Implement:

- Storage location/bucket
- upload policies
- upload/replace/remove UI
- public logo rendering

Goal:

Give each Family a visual identity.

### Phase 5 — Family Showcase Polish

Implement:

- dedicated Family presentation
- family leaderboard statistics where available
- polished responsive member cards
- individual OC detail views

Goal:

Complete the public OC Family experience.

---

## 23. Future Ideas — Not V1

Potential future extensions:

- Family banner/header art
- Family theme colors
- favorite OC designation
- OC relationship notes
- OC timeline / achievements
- match history per OC
- badges earned through progression
- featured OC on player profile
- Family creation date / age
- profile showcase achievements
- shareable Family card
- public OC catalogue filtered by player

Do not implement these automatically as part of the initial social system.

---

## 24. Explicit Non-Goals

This feature does not change:

- OC creation stat generation
- Champion mechanics
- Sacrificial mechanics
- OC progression costs
- OVR caps
- Global Power caps
- match OC selection
- OC Preparation
- draft rules
- battle rules
- leaderboard scoring
- Administrator battle AI

Any change to those systems requires separate gameplay design approval.

---

## 25. Acceptance Criteria

The initial feature should eventually satisfy the following:

### Public Profiles

- leaderboard player can be opened
- public profile loads only safe public data
- W/L record is visible
- active OC Family can be viewed

### OC Lore

- owner can add/edit lore on owned OC
- lore persists independently of loadout slot
- other users can read lore
- lore does not affect gameplay

### OC Family

- currently equipped active OCs form the public Family
- changing equipped OCs changes public Family membership
- retired/inactive OCs are not shown by default

### Family Branding

- owner can customize Family name/tagline/description
- owner can upload a Family logo
- logo is publicly visible
- unauthorized users cannot modify it

### Security

- public profile does not expose private account information
- all mutation operations verify ownership
- Storage policies prevent cross-user modification

### Compatibility

- existing OC progression still works
- existing OC leaderboards still work
- Champion/Sacrificial behavior is unchanged
- Administrator remains compatible with public profile display
- mobile and desktop layouts remain usable

---

## 26. Final Product Vision

The OC Family Social System should make an Anime Arena profile feel like more than a record of wins and losses.

A player should be able to build a small identity around their OCs:

- who they are
- where they came from
- what their Family represents
- how they have progressed
- how they compare with other players' creations

The competitive game remains driven by OVR, Global Power, progression, drafting, and battle strategy.

The social layer gives those fighters a reason to matter outside the match itself.
