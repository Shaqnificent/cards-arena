# Database setup and migration policy

Anime Arena currently keeps its PostgreSQL/Supabase SQL in `docs/`. These files are cumulative implementation phases and corrective patches, not a timestamped migration history and not a single verified bootstrap script.

## Existing Supabase project

Treat the applied schema as authoritative. Before running a SQL file:

1. Confirm its prerequisites in the file header.
2. Compare every replaced function with `pg_get_functiondef(...)` in the target project.
3. Apply only the missing patch in a staging project first.
4. Verify RLS, table/function grants, Realtime publication membership, and Storage policies.
5. run the relevant smoke-test section in [`release-checklist.md`](release-checklist.md).

Do not replay older phase files over a newer database. Several later files intentionally replace functions introduced in earlier files, so replaying an old phase can restore stale behavior.

## Dependency order by subsystem

This is a dependency map, not permission to run every file blindly:

1. Identity and catalogue: `supabase_profiles.sql`, `supabase_profile_identity_customization.sql`, `supabase_characters.sql`.
2. Community: `supabase_suggestions.sql`.
3. Match core: `supabase_matchmaking.sql`, `supabase_online_draft.sql`, `supabase_rps_initiative.sql`, `supabase_match_initiative.sql`.
4. OC persistence and progression: `supabase_oc_foundation.sql`, `supabase_oc_progression.sql`, `supabase_oc_creation_limit.sql`, then the current OC type/social/image/leaderboard patches required by the target schema.
5. OC match flow: `supabase_match_oc_selection.sql`, the current OC type visibility patch, `supabase_oc_sacrifice.sql`, `supabase_oc_battle_integration.sql`.
6. Boons: phases 1 through 5 in order, then `supabase_boon_resolver_v2.sql` and catalogue/Administrator patches that are not already installed.
7. Operational match features: `supabase_match_exit.sql`, `supabase_administrator_opponent.sql`, and `supabase_direct_challenges.sql` when those features are enabled.

The current schema uses these identifiers:

- `profiles.id`: UUID
- `matches.id`: UUID
- `player_characters.id`: UUID
- `match_characters.id`: UUID
- `characters.id`: BIGINT
- `verses.id`: BIGINT

## Release migration verification

The repository does not currently include a schema dump or a timestamped migration directory that can reproduce the live project from zero. Before describing the database as production-ready, create a staging project from a reviewed schema export or consolidate the files into an ordered Supabase migration chain, then test it from an empty database.

Never place a service-role key in the frontend or a `VITE_*` environment variable.
