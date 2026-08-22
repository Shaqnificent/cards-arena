-- Run this file in the Supabase SQL Editor.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null check (length(btrim(username)) between 1 and 50),
  avatar_url text,
  is_guest boolean not null default false,
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_username text;
  generated_avatar_url text;
  user_is_anonymous boolean;
begin
  user_is_anonymous := coalesce(new.is_anonymous, false);

  if user_is_anonymous then
    generated_username := 'Guest_' || lpad(floor(random() * 10000)::text, 4, '0');
    generated_avatar_url := null;
  else
    generated_username := coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Player_' || substr(new.id::text, 1, 8)
    );
    generated_avatar_url := coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'avatar_url'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'picture'), '')
    );
  end if;

  insert into public.profiles (id, username, avatar_url, is_guest)
  values (new.id, generated_username, generated_avatar_url, user_is_anonymous)
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;

create policy "Authenticated users can read profiles"
  on public.profiles for select
  to authenticated
  using (true);

create policy "Users can update their own profile"
  on public.profiles for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- No INSERT or DELETE policies are intentionally defined. Profile creation is
-- owned by the auth.users trigger, and cascading deletion is owned by Auth.
-- Limit browser clients to cosmetic profile fields so competitive stats cannot
-- be manipulated from the frontend. A server-side match function can update
-- wins and losses later.
revoke update on public.profiles from authenticated;
grant update (username, avatar_url) on public.profiles to authenticated;
