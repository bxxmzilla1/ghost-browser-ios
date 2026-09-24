-- Heavenzy · saved-login cloud storage
-- Run once in your Supabase project: Dashboard → SQL Editor → New query → paste → Run.
-- Then in the Heavenzy app: Settings → Account → paste the Project URL + anon key → Create Account.
--
-- Everything is scoped per user with Row Level Security: a signed-in user can only see, upload,
-- rename or delete their own rows and their own archives. The anon key alone can read nothing.

-- ---------------------------------------------------------------------------------------------
-- 1. Metadata table (one row per saved login)
-- ---------------------------------------------------------------------------------------------
create extension if not exists pgcrypto;

create table if not exists public.containers (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  bundle_id     text not null,                 -- e.g. com.burbn.instagram
  app_name      text,                          -- e.g. Instagram
  name          text not null,                 -- the login's display name
  saved_at      timestamptz,                   -- when the tweak captured it
  app_version   text,
  app_build     text,
  bytes         bigint default 0,              -- size of the .tar.gz archive
  storage_path  text,                          -- object path in the `containers` bucket
  identity      jsonb,                         -- spoofed identity saved alongside the login
  device        text,                          -- phone that captured it
  created_at    timestamptz not null default now(),
  unique (user_id, bundle_id, name)
);

create index if not exists containers_user_app_idx on public.containers (user_id, bundle_id, saved_at desc);

alter table public.containers enable row level security;

drop policy if exists "containers: own rows select" on public.containers;
drop policy if exists "containers: own rows insert" on public.containers;
drop policy if exists "containers: own rows update" on public.containers;
drop policy if exists "containers: own rows delete" on public.containers;

create policy "containers: own rows select" on public.containers
  for select to authenticated using (user_id = auth.uid());
create policy "containers: own rows insert" on public.containers
  for insert to authenticated with check (user_id = auth.uid());
create policy "containers: own rows update" on public.containers
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "containers: own rows delete" on public.containers
  for delete to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------------------------------
-- 2. Private bucket for the archives. Objects live at  <user id>/<bundle id>/<row id>.tar.gz
-- ---------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('containers', 'containers', false, null)
on conflict (id) do update set public = false;

drop policy if exists "containers bucket: own folder select" on storage.objects;
drop policy if exists "containers bucket: own folder insert" on storage.objects;
drop policy if exists "containers bucket: own folder update" on storage.objects;
drop policy if exists "containers bucket: own folder delete" on storage.objects;

create policy "containers bucket: own folder select" on storage.objects
  for select to authenticated
  using (bucket_id = 'containers' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "containers bucket: own folder insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'containers' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "containers bucket: own folder update" on storage.objects
  for update to authenticated
  using (bucket_id = 'containers' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'containers' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "containers bucket: own folder delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'containers' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------------------------
-- 3. Optional: Authentication → Providers → Email → turn OFF "Confirm email" if you want
--    Create Account in the app to sign you in immediately instead of sending a confirmation link.
-- ---------------------------------------------------------------------------------------------
