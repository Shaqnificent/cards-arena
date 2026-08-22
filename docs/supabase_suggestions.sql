-- Run after supabase_profiles.sql. Safe to rerun where practical.
alter table public.profiles add column if not exists is_admin boolean not null default false;

create table if not exists public.suggestions (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(btrim(title)) between 3 and 120),
  description text not null check (length(btrim(description)) between 10 and 2000),
  category text not null check (category in ('gameplay','characters','verses','ui-ux','balance','bugs','other')),
  status text not null default 'submitted' check (status in ('submitted','under_review','planned','implemented','declined')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.suggestion_votes (
  suggestion_id uuid not null references public.suggestions(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (suggestion_id, player_id)
);
create index if not exists suggestions_created_idx on public.suggestions (created_at desc);
create index if not exists suggestions_category_idx on public.suggestions (category);
create index if not exists suggestions_status_idx on public.suggestions (status);
create index if not exists suggestion_votes_suggestion_idx on public.suggestion_votes (suggestion_id);

alter table public.suggestions enable row level security;
alter table public.suggestion_votes enable row level security;
drop policy if exists "Authenticated users read suggestions" on public.suggestions;
create policy "Authenticated users read suggestions" on public.suggestions for select to authenticated using (true);
drop policy if exists "Players submit own suggestions" on public.suggestions;
create policy "Players submit own suggestions" on public.suggestions for insert to authenticated
  with check (author_id = auth.uid() and status = 'submitted');
drop policy if exists "Authenticated users read votes" on public.suggestion_votes;
create policy "Authenticated users read votes" on public.suggestion_votes for select to authenticated using (true);
drop policy if exists "Players add own votes" on public.suggestion_votes;
create policy "Players add own votes" on public.suggestion_votes for insert to authenticated with check (player_id = auth.uid());
drop policy if exists "Players remove own votes" on public.suggestion_votes;
create policy "Players remove own votes" on public.suggestion_votes for delete to authenticated using (player_id = auth.uid());

revoke all on public.suggestions, public.suggestion_votes from anon, authenticated;
grant select on public.suggestions to authenticated;
grant insert (author_id, title, description, category) on public.suggestions to authenticated;
grant select, delete on public.suggestion_votes to authenticated;
grant insert (suggestion_id, player_id) on public.suggestion_votes to authenticated;

create or replace function public.get_suggestions()
returns table (id uuid, title text, description text, category text, status text, created_at timestamptz,
  author_id uuid, author_username text, vote_count bigint, current_user_voted boolean)
language sql stable security definer set search_path = '' as $$
  select s.id, s.title, s.description, s.category, s.status, s.created_at,
    s.author_id, p.username,
    (select count(*) from public.suggestion_votes v where v.suggestion_id = s.id),
    exists(select 1 from public.suggestion_votes v where v.suggestion_id = s.id and v.player_id = auth.uid())
  from public.suggestions s join public.profiles p on p.id = s.author_id;
$$;

create or replace function public.set_suggestion_status(p_suggestion_id uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.profiles where id = auth.uid() and is_admin) then
    raise exception 'Administrator access required';
  end if;
  if p_status not in ('submitted','under_review','planned','implemented','declined') then raise exception 'Invalid status'; end if;
  update public.suggestions set status = p_status, updated_at = now() where id = p_suggestion_id;
  if not found then raise exception 'Suggestion not found'; end if;
end;
$$;
revoke all on function public.get_suggestions() from public;
revoke all on function public.set_suggestion_status(uuid, text) from public;
grant execute on function public.get_suggestions() to authenticated;
grant execute on function public.set_suggestion_status(uuid, text) to authenticated;
notify pgrst, 'reload schema';

-- Promote an account manually in the SQL Editor (replace the UUID):
-- update public.profiles set is_admin = true where id = 'YOUR-PROFILE-UUID';
