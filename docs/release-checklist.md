# Anime Arena release checklist

Use this checklist against a staging Supabase project and the exact commit intended for deployment. Test with two separate authenticated browser sessions where a human-versus-human flow is required.

## Live verification status — 2026-08-27

Status meanings in this pass:

- **PASS** — directly verified in this session, or explicitly supplied as a completed prerequisite.
- **FAIL** — applicable but not verified, unavailable in this session, or a release mismatch was found. A FAIL marked "not executed" is a verification failure, not a claim that the feature itself is broken.
- **NOT APPLICABLE** — the item does not apply to this deployment. No items were classified this way.

## Build and configuration

- **PASS** — `npm ci` was supplied as an already-passed prerequisite for this live-only pass.
- **PASS** — `npm.cmd run build` passes on the current working tree.
- **PASS** — `npm.cmd run lint` passes with Oxlint on the current working tree.
- **FAIL** — the Production bundle contains the expected public Supabase configuration, but Preview variables and dashboard configuration were not inspectable.
- **FAIL** — the built client exposes a publishable key, but the complete Vercel variable set was not inspectable to rule out unused private variables.
- **PASS** — `/leaderboard`, `/loadout`, `/ocs`, `/boons`, `/community`, `/profile/:id`, and `/match/:id` all returned the SPA HTML with HTTP 200.

## Authentication

- **FAIL** — Google is enabled and the authorize endpoint redirects to `accounts.google.com`, but sign-in, callback, and refresh restoration were not executed.
- **FAIL** — anonymous users are enabled in live Auth settings, but guest creation/restoration was not executed.
- **FAIL** — not executed in a connected browser.
- **FAIL** — the retryable state exists in source, but its deployed browser behavior was not executed.

## Lobby and matchmaking

- **FAIL** — not executed in an authenticated browser session.
- **FAIL** — not executed in an authenticated browser session.
- **FAIL** — two-session test unavailable.
- **FAIL** — Administrator fallback was not executed.
- **FAIL** — two-session cancellation/forfeit test unavailable.

## Direct challenge

- **FAIL** — the live challenge table and send RPC are installed, but authenticated behavior was not executed.
- **FAIL** — the accept RPC is installed, but idempotency and match creation were not executed.
- **FAIL** — decline/cancel RPCs are installed; decline, cancel, expiration, and client synchronization were not executed.
- **FAIL** — eligibility protections were not tested with live participants.
- **FAIL** — challenge result isolation was not executed.

## Initiative and OC selection

- **FAIL** — two-session secrecy test unavailable.
- **FAIL** — multiplayer initiative flow not executed.
- **FAIL** — two-session OC perspective test unavailable.
- **FAIL** — snapshot behavior not executed against live data.
- **FAIL** — no-OC path not executed.

## Draft and OC preparation

- **FAIL** — draft initialization was not executed.
- **FAIL** — draft actions/reconnect were not executed.
- **FAIL** — Champion preparation was not executed.
- **FAIL** — Sacrificial preparation was not executed.
- **FAIL** — preparation idempotency was not executed.

## Boons

- **FAIL** — live Boon UI/data was not inspected in an authenticated browser.
- **FAIL** — equip limit was not executed.
- **FAIL** — replace/discard transaction was not executed.
- **FAIL** — Boon snapshot behavior was not executed.
- **FAIL** — Resolver V2 persistence/idempotency was not executed.
- **FAIL** — shop filtering was not inspected in an authenticated browser.

## Battle and result

- **FAIL** — two-session hidden-selection test unavailable.
- **FAIL** — live battle comparison cases were not executed.
- **FAIL** — fighter reuse rules were not executed.
- **FAIL** — round limit/completion idempotency was not executed.
- **FAIL** — deployed result presentation was not inspected in a browser.
- **FAIL** — live reward idempotency was not executed.

## Catalogue, OC Family, leaderboards, and profiles

- **FAIL** — browser catalogue interaction was not executed.
- **FAIL** — OC workflows and server enforcement were not executed.
- **FAIL** — the live Family leaderboard RPC and logo bucket exist, but rendering was not inspected.
- **FAIL** — live leaderboard rows/links were not inspected.
- **FAIL** — live ranking filter behavior was not inspected.
- **FAIL** — deployed UI state coverage was not inspected.

## Mobile, accessibility, and reconnect

- **FAIL** — no connected browser was available for the required viewport matrix.
- **FAIL** — responsive reachability/overflow was not visually inspected.
- **FAIL** — keyboard/dialog behavior was not executed.
- **FAIL** — reduced-motion behavior was not executed.
- **FAIL** — phase refresh/reconnect was not executed.
- **FAIL** — cross-browser verification was not executed.

## Supabase security spot checks

- **FAIL** — no two authenticated live users or management connection was available for cross-owner mutation tests.
- **FAIL** — protected direct-write tests were not executed.
- **FAIL** — selected authenticated-only RPCs reject the anonymous role, but nonparticipant/function-body coverage was not executed.
- **FAIL** — perspective RPC and Realtime payloads were not captured with two sessions.
- **FAIL** — `oc-images` and `oc-family-logos` exist and are publicly readable as intended, but write/delete policies were not exercised or inspected live.
