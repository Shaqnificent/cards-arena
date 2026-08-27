# Final stability and portfolio audit

## Summary

The React application is type-safe under the production build, passes Oxlint, has a clean SPA rewrite, uses a public Supabase client configuration, and follows a generally sound server-authoritative multiplayer pattern. Realtime handlers are used as invalidation notifications and are removed during effect cleanup. Sensitive mutations are routed through authenticated RPCs in the reviewed SQL.

The release pass fixed deployment failure handling, route bundle size, confirmed BIGINT TypeScript/schema mismatches, bootstrap SQL ID mismatches, and historical SECURITY DEFINER profile overexposure. No game rules or balance values were changed.

This repository is a strong portfolio candidate, but it is not yet a fully certified release: the live applied Supabase schema was not accessible from this workspace, the SQL collection is not a reproducible timestamped migration chain, and no connected browser was available for the required visual/multi-session regression matrix.

## Critical issues found

No BLOCKER was reproduced in the local build.

### HIGH — fixed

- The documented bootstrap SQL declared `verses.id`, `characters.id`, and the OC verse foreign key as UUID while the confirmed application schema uses BIGINT. The base catalogue/OC files now consistently use BIGINT.
- Historical SECURITY DEFINER initiative/battle functions serialized an entire `profiles` row. Their repository definitions now construct only the identity/record fields used by the match UI.
- Profile-dependent routes could remain on a loading screen forever after a failed profile RPC. They now show a retryable error boundary.

### HIGH — unresolved verification risk

- The applied Supabase schema, grants, policies, function hashes, publication membership, and Storage configuration could not be queried. Static SQL review cannot prove production state.
- `docs/` contains cumulative phase files and later function replacements rather than a tested, timestamped clean-install migration chain. Running files out of order can restore stale function bodies. [`DATABASE_SETUP.md`](DATABASE_SETUP.md) documents the safe operating policy, but consolidation and an empty-database rehearsal remain required.
- A browser/mobile session was unavailable, so the full visual matrix and two-session multiplayer smoke test remain manual release gates.

## Issues fixed

- Added `.env.example` with client-safe placeholder names only.
- Added a user-facing configuration state for missing Supabase environment variables.
- Added retryable profile-route failure states.
- Lazy-loaded route pages. The former 697.17 kB main chunk became a 223.68 kB app entry plus route chunks; the Vite chunk-size warning is gone.
- Corrected canon `Character`/`Verse` TypeScript IDs and local battle selection IDs to `number` for PostgreSQL BIGINT compatibility.
- Corrected BIGINT bootstrap SQL and OC creation signatures.
- Restricted initiative and battle profile JSON in historical/canonical SQL bodies and retained the Administrator `is_system_player` field required by the UI.

## Remaining known issues

### MEDIUM

- There is no automated test framework or `npm test` script. Battle rules and multiplayer state transitions rely on build/lint plus manual regression testing.
- Local prototype progression is initiated from client-simulated results. Existing ownership/transaction checks help, but anti-farming validation remains weaker than the online authoritative flow.
- The compiled CSS is 195.29 kB (38.26 kB gzip) and the SCSS contains a meaningful number of targeted `!important` overrides. The files are feature-separated, but future cleanup should reduce cascade coupling.
- Two Administrator source portraits are roughly 2 MB each. They are not imported into the initial JavaScript bundle, but deployment image optimization would improve first display in Administrator matches.

### LOW

- Several route/page components are dense and would benefit from smaller presentation components, especially `PlayerCharacters.tsx` and `InitiativeScreen.tsx`.
- Console error logging is retained for actionable development diagnostics. Reviewed calls log errors/context, not sessions or tokens.

## Security review

- Frontend code references only `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`; no service-role key was found.
- `.env.local` is ignored by the existing `*.local` rule; `.env.example` contains no secret.
- Reviewed OC, Boon, challenge, suggestion, match, and Storage mutations are ownership/auth checked in RLS or SECURITY DEFINER RPCs.
- SECURITY DEFINER functions generally use `auth.uid()`, explicit empty `search_path`, qualified relations, and restricted grants.
- Sensitive match tables are designed to be inaccessible directly; perspective RPCs expose caller selections plus opponent lock/reveal status.
- Historical full-profile serialization in the base RPS/battle SQL was removed. Public game types explicitly omit Boon balance.
- Static repository review cannot establish the policies actually installed in Supabase. Run the security section in the release checklist against staging.

## Multiplayer review

- Match hooks use scoped match/user Realtime filters and call `removeChannel` on cleanup, including under React StrictMode remounting.
- Realtime payloads trigger authoritative refetches rather than resolving gameplay in the browser.
- Request-version/current flags prevent stale async responses in the primary draft/battle loaders.
- SQL uses row/advisory locks and conflict handling around matchmaking, challenge acceptance, OC equipment, match initialization, and reward/resolution paths.
- Direct challenges are explicitly unranked in the supplied migration and have a unique/idempotent acceptance path.
- Full idempotency and reconnect behavior still require two-session staging tests because the applied function definitions were unavailable.

## Responsive review

- The SCSS is organized by abstracts/base/components/features/layout/utilities and includes shared mobile breakpoints and reduced-motion support.
- Existing responsive rules address mobile navigation, leaderboard challenge actions, card hands, pagination, dialogs, and toasts.
- Source inspection found no unbounded fixed-width page container; intentional table minimum widths are wrapped by leaderboard overflow containers.
- Visual verification at 320–768 px remains outstanding because no browser target was connected.

## Performance review

- Route-level code splitting removed the production chunk warning.
- Catalogue cards lazy-load noncritical images and provide deterministic fallbacks.
- Catalogue filtering/pagination and OC ranking requests avoid per-card query loops.
- Parallel reads are used for normalized match state and then checked against `action_version` for coherence.
- Production dependency audit reported zero known vulnerabilities.
- Registry metadata showed only small compatible updates for Supabase, React DOM types, and Oxlint plus intentionally deferred major versions of Node types/TypeScript. No dependency upgrade was required for this stabilization pass.

## Deployment review

- `vercel.json` rewrites all paths to `index.html`, supporting BrowserRouter refresh/direct navigation.
- OAuth redirect uses `window.location.origin`, avoiding a hard-coded localhost production redirect.
- Missing Vercel Supabase variables now render a clear configuration error.
- Supabase Site URL and allowed local/Preview/Production redirect URLs remain dashboard configuration tasks.

## Portfolio readiness

The code and documentation are portfolio quality, and the local release candidate builds cleanly. Do not label the deployed system fully portfolio-ready until the applied Supabase schema is compared with the repository's current definitions and the manual browser/two-session checklist passes.

## Recommended future improvements

- Consolidate the current live schema into ordered Supabase migrations and prove an empty-database install in CI.
- Add focused tests for battle comparison, RPC payload transformations, Boon configuration calculations, and profile/auth helpers.
- Add a small CI workflow for `npm ci`, build, lint, and migration linting.
- Optimize the Administrator portrait assets and capture verified README screenshots.
- Add stronger anti-farming attestation/rate controls for local progression if it remains reward-bearing.

## Final live verification — 2026-08-27

### Scope and evidence

The production deployment is `https://cards-arena.vercel.app`. GitHub reports the latest Production deployment as successful. Its deployed commit is `ae2d15317267fa2bf33c43ea45d013cc7e6933d2`, which matches local `HEAD`.

The current working tree is **not** identical to that deployed commit: it contains uncommitted stability/audit changes. The current working tree builds and lints successfully, but those uncommitted changes are not proven to be present in production.

Direct HTTP verification established:

- The root and direct SPA routes `/leaderboard`, `/loadout`, `/ocs`, `/boons`, `/community`, `/profile/:id`, and `/match/:id` return HTTP 200 HTML.
- The production client contains a Supabase project URL and a public publishable key; no secret key was extracted from the client bundle.
- Live Auth settings have Google and anonymous users enabled. The Google authorize endpoint returns HTTP 302 to `accounts.google.com`.
- Focused PostgREST probes confirm the expected challenge table/RPC names and `get_oc_family_leaderboard` are present in the live schema cache. Anonymous calls receive PostgreSQL `42501` permission-denied responses rather than missing-function responses, confirming the anonymous role has no execute permission.
- The public Storage endpoints for `oc-images`, `oc-family-logos`, and `character-art` return `Object not found` for a deliberately nonexistent object instead of `Bucket not found`, confirming those bucket names exist and their public read endpoints are reachable.
- `npm.cmd run build` and `npm.cmd run lint` both pass on the current working tree.

Supabase's OpenAPI schema endpoint requires a secret API key, and this environment has no Supabase management connector/CLI credentials. Therefore the deployed pg catalog, function bodies/hashes, constraints, indexes, RLS enablement/policies, grants beyond focused anonymous probes, Realtime publication, and Storage mutation policies were not inspectable. The in-app browser runtime was also unavailable, so interactive, mobile, cross-browser, and two-session checks could not be executed.

### Release-gate results

1. **Supabase schema verified: NO.** Selected tables/RPCs and bucket names were observed, but the full applied schema was not accessible.
2. **RLS verified: NO.** Anonymous denial was observed on protected endpoints; policy definitions and cross-owner authenticated tests remain outstanding.
3. **RPCs verified: NO.** Direct-challenge and Family leaderboard RPC installation plus anonymous denial were observed; definitions, search paths, authenticated grants, perspective safety, and idempotency were not fully verified.
4. **Storage verified: NO.** Expected public buckets exist; MIME limits and write/delete ownership policies remain outstanding.
5. **Realtime verified: NO.** Publication membership and live subscription/reconnect behavior were not inspected.
6. **Direct challenges verified: NO.** `player_challenges` and all five current challenge RPCs are installed, but authenticated send/accept/decline/cancel/expiry and unranked-result behavior were not executed.
7. **OC Family identity SQL verified: NO.** `get_oc_family_leaderboard` is installed and `oc-family-logos` exists, but the live function body, dependent schema/policies, and rendered identity were not verified.
8. **Browser smoke test: FAIL.** No browser runtime was connected. HTTP route reachability passed, but that is not an interactive smoke test.
9. **Mobile smoke test: FAIL.** Required 320–768 px visual matrix was not executed.
10. **Two-player multiplayer: FAIL.** Two independent authenticated sessions were unavailable.
11. **Administrator: FAIL.** Fallback timing, Boon, OC, battle, and result behavior were not executed.
12. **Remaining blockers:** live Supabase management visibility; two authenticated browser sessions; mobile/cross-browser coverage; Realtime inspection; and deployment of the current uncommitted audit changes if they are intended for release.
13. **SQL still required:** none identified from the focused live probes. Do not rerun historical SQL. A read-only pg-catalog comparison is required before deciding whether any focused corrective SQL is necessary.
14. **Manual Supabase/Vercel actions still required:** inspect the live pg catalog/policies/grants/publications/Storage policies with an authorized Supabase connection; verify Production and Preview environment variables and OAuth redirect allowlists; commit/push/deploy the intended working tree; then run the authenticated browser, mobile, direct-challenge, multiplayer, and Administrator matrices in `release-checklist.md`.

### Final decision

**NOT PORTFOLIO READY**

No deployed gameplay defect was proven by the limited HTTP probes, but multiple HIGH release gates remain unverified and the tested working tree is not the exact deployed artifact. Portfolio readiness must not be claimed until the live Supabase and interactive two-session/browser gates pass.
