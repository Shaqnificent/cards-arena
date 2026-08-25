-- Anime Arena: focused Boon roll cost update
-- Run this file after the existing Boon Phase 3 migration.
-- The browser never supplies the price; get_my_boons() and roll_boon() both
-- read this private server-side value.

begin;

create or replace function public.get_boon_roll_cost()
returns bigint
language sql
immutable
set search_path = ''
as $$
  select 100::bigint;
$$;

revoke all on function public.get_boon_roll_cost() from public, anon, authenticated;

comment on function public.get_boon_roll_cost() is
  'Private authoritative Boon roll cost. Player rolls cost 100 BP.';

commit;

notify pgrst, 'reload schema';
