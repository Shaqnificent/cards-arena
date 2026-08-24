-- Anime Arena Boon Phase 2 manual test seed.
-- DO NOT run this file unchanged. Replace <PROFILE_UUID> with one persistent,
-- non-guest, non-system profile UUID. This is SQL-editor/admin tooling only and
-- is deliberately not exposed as an authenticated RPC.
--
-- The production Phase 2 migration grants no Boons automatically.

do $$
declare
  target_profile_id uuid := '<PROFILE_UUID>'::uuid;
begin
  insert into public.player_boons (owner_id, boon_definition_id)
  select target_profile_id, d.id
  from public.boon_definitions d
  where d.key in ('ascendant', 'underdog')
  order by d.key
  on conflict (owner_id, boon_definition_id) do nothing;
end;
$$;

-- Optional verification after replacing the same UUID:
-- select pb.id, d.key, d.name, pb.equipped, pb.created_at
-- from public.player_boons pb
-- join public.boon_definitions d on d.id = pb.boon_definition_id
-- where pb.owner_id = '<PROFILE_UUID>'::uuid
-- order by pb.created_at;
