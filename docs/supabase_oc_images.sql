-- Anime Arena OC portraits. Run after docs/supabase_oc_foundation.sql.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('oc-images', 'oc-images', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.can_manage_oc_portrait(p_character_id text)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists (
    select 1 from public.player_characters pc
    where pc.id::text=p_character_id and pc.owner_id=auth.uid()
      and pc.active=true and pc.equipped=true and pc.retired_at is null
  );
$$;
revoke all on function public.can_manage_oc_portrait(text) from public;
grant execute on function public.can_manage_oc_portrait(text) to authenticated;

drop policy if exists "OC portrait owner insert" on storage.objects;
drop policy if exists "OC portrait owner update" on storage.objects;
drop policy if exists "OC portrait owner delete" on storage.objects;

create policy "OC portrait owner insert" on storage.objects for insert to authenticated
with check (bucket_id = 'oc-images' and (storage.foldername(name))[1] = auth.uid()::text
  and public.can_manage_oc_portrait((storage.foldername(name))[2]));
create policy "OC portrait owner update" on storage.objects for update to authenticated
using (bucket_id = 'oc-images' and owner_id = auth.uid())
with check (bucket_id = 'oc-images' and (storage.foldername(name))[1] = auth.uid()::text
  and public.can_manage_oc_portrait((storage.foldername(name))[2]));
create policy "OC portrait owner delete" on storage.objects for delete to authenticated
using (bucket_id = 'oc-images'
  and (storage.foldername(name))[1] = auth.uid()::text
  and public.can_manage_oc_portrait((storage.foldername(name))[2]));

alter table public.match_oc_options add column if not exists image_url_snapshot text;
-- Backfill only pre-column rows. Reruns never refresh an existing match
-- snapshot from mutable player_characters data.
update public.match_oc_options o set image_url_snapshot=pc.image_url from public.player_characters pc
where pc.id=o.player_character_id and o.image_url_snapshot is null;
create or replace function public.snapshot_match_oc_image() returns trigger language plpgsql set search_path='' as $$
begin select pc.image_url into new.image_url_snapshot from public.player_characters pc where pc.id=new.player_character_id; return new; end $$;
drop trigger if exists snapshot_match_oc_image_trigger on public.match_oc_options;
create trigger snapshot_match_oc_image_trigger before insert on public.match_oc_options for each row execute function public.snapshot_match_oc_image();

create or replace function public.get_match_oc_portraits(p_match_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare caller_id uuid:=auth.uid(); match_row public.matches%rowtype;
begin
  if caller_id is null then raise exception using errcode='42501', message='Authentication required.'; end if;
  select * into match_row from public.matches where id=p_match_id;
  if not found or caller_id not in (match_row.player_one_id,match_row.player_two_id) then raise exception using errcode='42501', message='Match unavailable.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('characterId',o.player_character_id,'imageUrl',o.image_url_snapshot))
    from public.match_oc_options o where o.match_id=p_match_id and (
      match_row.status in ('oc_selection','draft','oc_preparation')
      or o.player_id=caller_id
      or exists (select 1 from public.match_oc_preparations prep
        where prep.match_id=o.match_id and prep.player_id=o.player_id
          and prep.player_character_id=o.player_character_id and prep.revealed_at is not null)
    )),'[]'::jsonb);
end $$;

create or replace function public.set_player_character_image(p_character_id uuid, p_image_path text)
returns public.player_characters language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); result public.player_characters;
begin
  if caller_id is null then raise exception using errcode='42501', message='Authentication required.'; end if;
  p_image_path := btrim(p_image_path);
  if p_image_path !~ ('^' || caller_id::text || '/' || p_character_id::text || '/portrait-[0-9]+\.(jpg|png|webp)$')
    or not exists (select 1 from storage.objects so where so.bucket_id='oc-images' and so.name=p_image_path) then
    raise exception using errcode='23514', message='Invalid OC portrait object.';
  end if;
  update public.player_characters set image_url=p_image_path, updated_at=now()
  where id=p_character_id and owner_id=caller_id and active and equipped and retired_at is null returning * into result;
  if not found then raise exception using errcode='42501', message='Only an active equipped OC owner may change its portrait.'; end if;
  return result;
end $$;

create or replace function public.remove_player_character_image(p_character_id uuid)
returns public.player_characters language plpgsql security definer set search_path = '' as $$
declare caller_id uuid := auth.uid(); result public.player_characters;
begin
  if caller_id is null then raise exception using errcode='42501', message='Authentication required.'; end if;
  update public.player_characters set image_url=null, updated_at=now()
  where id=p_character_id and owner_id=caller_id and active and equipped and retired_at is null returning * into result;
  if not found then raise exception using errcode='42501', message='Only an active equipped OC owner may remove its portrait.'; end if;
  return result;
end $$;

revoke all on function public.set_player_character_image(uuid,text) from public;
revoke all on function public.remove_player_character_image(uuid) from public;
grant execute on function public.set_player_character_image(uuid,text) to authenticated;
grant execute on function public.remove_player_character_image(uuid) to authenticated;
revoke all on function public.get_match_oc_portraits(uuid) from public;
grant execute on function public.get_match_oc_portraits(uuid) to authenticated;
notify pgrst, 'reload schema';
