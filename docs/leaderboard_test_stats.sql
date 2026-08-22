-- OPTIONAL DEVELOPMENT DATA ONLY.
-- Replace TEST_USER_UUID with the UUID of an existing non-guest test profile.
-- Run manually in the Supabase SQL Editor; never expose stat editing in React.
update public.profiles
set wins = 18,
    losses = 7
where id = 'TEST_USER_UUID'
  and is_guest = false;

-- Reset the same test profile when finished:
-- update public.profiles
-- set wins = 0, losses = 0
-- where id = 'TEST_USER_UUID';
