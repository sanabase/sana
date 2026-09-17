-- Add per-user preference columns:
--   reminders_enabled : global on/off for reminder scheduling (Dart + Edge Function)
--   language          : stored UI language preference

alter table public.users
  add column if not exists reminders_enabled boolean not null default true,
  add column if not exists language text not null default 'en';

comment on column public.users.reminders_enabled is
  'Global toggle: when false, SANA suppresses reminder alarms and Edge Function push.';
comment on column public.users.language is
  'Preferred UI language code (e.g. en, ar, es, fr, de, tr, hi, zh).';