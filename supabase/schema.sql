-- Full schema for karaj-khaled, extracted verbatim from the live production database
-- (rqailwsjdhsmkajkvkpn) via information_schema / pg_catalog introspection on 2026-11-24.
-- This is the FIRST time this schema has existed as a file rather than only live in
-- production SQL-editor history - run this against any fresh Supabase project (e.g.
-- a staging project) to get an exact schema match.
--
-- Usage: paste into the target project's SQL Editor and run, top to bottom.

-- ============================================================
-- Tables
-- ============================================================

create table public.app_admins (
  user_id uuid not null primary key
);

create table public.listings (
  id text not null primary key,
  owner_id uuid references auth.users(id) on delete cascade,
  cat text not null,
  title text not null,
  brand text,
  price numeric default 0,
  city text,
  description text,
  seller text,
  photos jsonb,
  specs jsonb,
  rooms integer,
  plate_type text,
  status text,
  featured_until bigint,
  created_at bigint,
  inserted_at timestamptz default now(),
  phone text
);

create table public.favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  listing_id text not null,
  created_at timestamptz default now(),
  primary key (user_id, listing_id)
);

create table public.listing_views (
  listing_id text not null primary key,
  view_count bigint default 0
);

create table public.renew_cooldowns (
  listing_id text not null primary key,
  owner_id uuid references auth.users(id) on delete cascade,
  last_renewed_at bigint
);

create table public.messages (
  id uuid not null primary key default gen_random_uuid(),
  listing_id text not null,
  listing_title text,
  sender_id uuid references auth.users(id) on delete cascade,
  sender_name text,
  recipient_id uuid references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz default now(),
  is_read boolean default false
);

create table public.reports (
  id uuid not null primary key default gen_random_uuid(),
  listing_id text not null,
  reason text not null,
  details text,
  reporter text,
  created_at timestamptz default now(),
  status text default 'open'
);

create table public.rate_limit_settings (
  id integer not null primary key default 1,
  max_listings_per_day integer default 5
);

insert into public.rate_limit_settings (id, max_listings_per_day) values (1, 5);

-- ============================================================
-- Role grants
-- ============================================================
-- Supabase normally grants these automatically on project bootstrap, relying on
-- RLS policies (below) for actual access control. Do this explicitly too, since a
-- brand-new project created mid-incident was observed missing them entirely
-- (2026-11-24, on a project created while status.supabase.com reported a live
-- platform issue) -- without this, every table request 401s even with correct
-- RLS policies in place.

grant select, insert, update, delete on all tables in schema public to anon, authenticated;
alter default privileges in schema public grant select, insert, update, delete on tables to anon, authenticated;

-- ============================================================
-- Row Level Security
-- ============================================================

alter table public.app_admins enable row level security;
alter table public.listings enable row level security;
alter table public.favorites enable row level security;
alter table public.listing_views enable row level security;
alter table public.renew_cooldowns enable row level security;
alter table public.messages enable row level security;
alter table public.reports enable row level security;
-- rate_limit_settings: RLS enabled with ZERO policies, on purpose - this locks it
-- completely to direct API access. It is only ever read via the SECURITY DEFINER
-- trigger function below, which bypasses RLS.
alter table public.rate_limit_settings enable row level security;

create policy app_admins_self_check on public.app_admins for select using (auth.uid() = user_id);

create policy listings_select_all on public.listings for select using (true);
create policy listings_insert_own on public.listings for insert with check (auth.uid() = owner_id);
create policy listings_update_own on public.listings for update using (auth.uid() = owner_id);
create policy listings_delete_own on public.listings for delete using (auth.uid() = owner_id);

create policy favorites_own on public.favorites for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy views_select_all on public.listing_views for select using (true);

create policy renew_select_all on public.renew_cooldowns for select using (true);
create policy renew_insert_own on public.renew_cooldowns for insert with check (auth.uid() = owner_id);
create policy renew_update_own on public.renew_cooldowns for update using (auth.uid() = owner_id);

create policy messages_select_own on public.messages for select using (auth.uid() = sender_id or auth.uid() = recipient_id);
create policy messages_insert_own on public.messages for insert with check (auth.uid() = sender_id);
create policy messages_update_own on public.messages for update using (auth.uid() = recipient_id);

create policy reports_insert_all on public.reports for insert with check (true);
create policy reports_select_admin on public.reports for select using (exists (select 1 from app_admins where app_admins.user_id = auth.uid()));
create policy reports_update_admin on public.reports for update using (exists (select 1 from app_admins where app_admins.user_id = auth.uid()));

-- ============================================================
-- Functions (SECURITY DEFINER RPCs + trigger function)
-- ============================================================

create or replace function public.increment_view(p_listing_id text)
 returns void
 language sql
 security definer
 set search_path to 'public'
as $function$ insert into public.listing_views (listing_id, view_count) values (p_listing_id, 1) on conflict (listing_id) do update set view_count = listing_views.view_count + 1; $function$;

create or replace function public.admin_delete_listing(p_listing_id text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$ begin if not exists (select 1 from public.app_admins where user_id = auth.uid()) then raise exception 'not authorized'; end if; delete from public.listings where id = p_listing_id; end; $function$;

create or replace function public.admin_get_listing_messages(p_listing_id text)
 returns setof messages
 language plpgsql
 security definer
 set search_path to 'public'
as $function$ begin if not exists (select 1 from public.app_admins where user_id = auth.uid()) then raise exception 'not_authorized'; end if; return query select * from public.messages where listing_id = p_listing_id order by created_at asc; end; $function$;

create or replace function public.admin_add_admin(p_username text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$ declare target_id uuid; begin if not exists (select 1 from public.app_admins where user_id = auth.uid()) then raise exception 'not_authorized'; end if; select id into target_id from auth.users where email = lower(p_username) || '@karajkhaled.local'; if target_id is null then raise exception 'user_not_found'; end if; insert into public.app_admins (user_id) values (target_id) on conflict do nothing; end; $function$;

create or replace function public.check_listing_rate_limit()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$ declare recent_count int; max_allowed int; begin select max_listings_per_day into max_allowed from public.rate_limit_settings where id = 1; select count(*) into recent_count from public.listings where owner_id = new.owner_id and inserted_at > now() - interval '24 hours'; if recent_count >= max_allowed then raise exception 'rate_limit_exceeded'; end if; return new; end; $function$;

create trigger listings_rate_limit before insert on public.listings for each row execute function check_listing_rate_limit();

-- ============================================================
-- Storage: listing-photos bucket
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-photos', 'listing-photos', true, 5242880, array['image/*'])
on conflict (id) do nothing;

create policy listing_photos_insert_own on storage.objects for insert
  with check (bucket_id = 'listing-photos' and auth.role() = 'authenticated' and (storage.foldername(name))[1] = auth.uid()::text);

create policy listing_photos_delete_own on storage.objects for delete
  using (bucket_id = 'listing-photos' and (storage.foldername(name))[1] = auth.uid()::text);
