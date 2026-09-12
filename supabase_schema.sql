-- sana schema
-- Run this in your Supabase project's SQL editor.
-- Safe to re-run: every statement uses IF NOT EXISTS / OR REPLACE.

-- =========================================================
-- USERS (profile info collected at sign up)
-- =========================================================
create table if not exists users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  phone text,
  email text,
  created_at timestamptz not null default now()
);

-- =========================================================
-- MEDICATIONS
-- =========================================================
create table if not exists medications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  guest_id uuid,
  name text not null,
  dosage text not null,
  quantity integer not null,
  photo_url text,
  description text default '',
  reminder_time text default '',
  reminder_times text default '',
  repeat_type text not null default 'daily',
  repeat_ends timestamptz,
  specific_date timestamptz,
  status text not null default 'pending',
  medication_status text not null default 'active',
  date_taken timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- If you already had a `medications` table from an earlier version, run
-- these to add the new columns without losing existing data:
alter table medications add column if not exists description text default '';
alter table medications add column if not exists reminder_time text default '';
alter table medications add column if not exists reminder_times text default '';
alter table medications add column if not exists repeat_type text not null default 'daily';
alter table medications add column if not exists repeat_ends timestamptz;
alter table medications add column if not exists specific_date timestamptz;
alter table medications add column if not exists medication_status text not null default 'active';
alter table medications add column if not exists status text not null default 'pending';
alter table medications add column if not exists date_taken timestamptz;
alter table medications add column if not exists is_active boolean not null default true;

-- =========================================================
-- MEDICATION LOGS (permanent history - never update/delete rows)
-- =========================================================
create table if not exists medication_logs (
  id uuid primary key default gen_random_uuid(),
  medication_id uuid references medications(id) on delete set null,
  -- snapshot fields so history stays meaningful even if the medication
  -- is later edited or deleted
  medication_name text not null default 'Medication',
  dosage text default '',
  -- 'taken' | 'not_taken'
  status text not null,
  taken_at timestamptz not null default now()
);

alter table medication_logs add column if not exists medication_name text not null default 'Medication';
alter table medication_logs add column if not exists dosage text default '';

-- =========================================================
-- DOCTORS
-- =========================================================
create table if not exists doctors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  guest_id uuid,
  name text not null,
  specialty text default '',
  phone text default '',
  email text default '',
  address text default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table doctors add column if not exists guest_id uuid;
alter table doctors add column if not exists email text default '';
alter table doctors add column if not exists address text default '';

-- =========================================================
-- PHARMACIES
-- =========================================================
create table if not exists pharmacies (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  guest_id uuid,
  name text not null,
  phone text not null,
  address text default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table pharmacies add column if not exists guest_id uuid;

-- =========================================================
-- DOCUMENTS (matches the Dart app's "documents" table)
-- =========================================================
create table if not exists documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  guest_id uuid,
  title text not null,
  category text default '',
  file_url text not null,
  file_type text not null,
  created_at timestamptz not null default now()
);

alter table documents add column if not exists guest_id uuid;
alter table documents add column if not exists category text default '';

-- Keep the old medical_documents table for backward compatibility
create table if not exists medical_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  name text not null,
  file_url text not null,
  -- 'image' | 'pdf' | 'video'
  file_type text not null,
  date timestamptz not null,
  created_at timestamptz not null default now()
);

-- =========================================================
-- INSURANCE CARDS (new)
-- =========================================================
create table if not exists insurance_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  provider_name text not null default 'Insurance Card',
  front_image_url text,
  back_image_url text,
  created_at timestamptz not null default now()
);

-- =========================================================
-- ROW LEVEL SECURITY
-- =========================================================
alter table users enable row level security;
alter table medications enable row level security;
alter table medication_logs enable row level security;
alter table doctors enable row level security;
alter table pharmacies enable row level security;
alter table medical_documents enable row level security;
alter table documents enable row level security;
alter table insurance_cards enable row level security;

drop policy if exists "Users manage own row" on users;
create policy "Users manage own row" on users
  for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "Users manage own medications" on medications;
create policy "Users manage own medications" on medications
  for all using (auth.uid() = user_id or auth.uid() = guest_id)
  with check (auth.uid() = user_id or auth.uid() = guest_id);

drop policy if exists "Users manage own logs" on medication_logs;
create policy "Users manage own logs" on medication_logs
  for all using (
    exists (
      select 1 from medications m
      where m.id = medication_logs.medication_id
        and (m.user_id = auth.uid() or m.guest_id = auth.uid())
    )
    or medication_id is null
  );

drop policy if exists "Users manage own doctors" on doctors;
create policy "Users manage own doctors" on doctors
  for all using (auth.uid() = user_id or auth.uid() = guest_id)
  with check (auth.uid() = user_id or auth.uid() = guest_id);

drop policy if exists "Users manage own pharmacies" on pharmacies;
create policy "Users manage own pharmacies" on pharmacies
  for all using (auth.uid() = user_id or auth.uid() = guest_id)
  with check (auth.uid() = user_id or auth.uid() = guest_id);

drop policy if exists "Users manage own documents" on documents;
create policy "Users manage own documents" on documents
  for all using (auth.uid() = user_id or auth.uid() = guest_id)
  with check (auth.uid() = user_id or auth.uid() = guest_id);

drop policy if exists "Users manage own documents legacy" on medical_documents;
create policy "Users manage own documents legacy" on medical_documents
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage own insurance" on insurance_cards;
create policy "Users manage own insurance" on insurance_cards
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- =========================================================
-- STORAGE BUCKETS
-- =========================================================
insert into storage.buckets (id, name, public)
values ('medication_photos', 'medication_photos', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('documents', 'documents', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('insurance_cards', 'insurance_cards', true)
on conflict (id) do nothing;