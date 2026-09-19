-- SANA owner isolation
-- Staged locally; this migration is NOT applied by creating this file.

begin;

-- Remove the old permissive policies.
drop policy if exists "doctors_authenticated_all" on public.doctors;
drop policy if exists "doctors_public_anon_all" on public.doctors;
drop policy if exists "sana doctors guest" on public.doctors;
drop policy if exists "sana doctors user" on public.doctors;

drop policy if exists "documents_authenticated_all" on public.documents;
drop policy if exists "documents_public_anon_all" on public.documents;
drop policy if exists "guests share pool" on public.documents;
drop policy if exists "sana documents guest" on public.documents;
drop policy if exists "sana documents user" on public.documents;

drop policy if exists "insurance_cards_authenticated_all" on public.insurance_cards;
drop policy if exists "insurance_cards_public_anon_all" on public.insurance_cards;
drop policy if exists "sana insurance guest" on public.insurance_cards;
drop policy if exists "sana insurance user" on public.insurance_cards;

drop policy if exists "medications_authenticated_all" on public.medications;
drop policy if exists "medications_public_anon_all" on public.medications;
drop policy if exists "sana medications guest delete" on public.medications;
drop policy if exists "sana medications guest insert" on public.medications;
drop policy if exists "sana medications guest select" on public.medications;
drop policy if exists "sana medications guest update" on public.medications;
drop policy if exists "sana medications user" on public.medications;

drop policy if exists "pharmacies_authenticated_all" on public.pharmacies;
drop policy if exists "pharmacies_public_anon_all" on public.pharmacies;
drop policy if exists "sana pharmacies guest" on public.pharmacies;
drop policy if exists "sana pharmacies user" on public.pharmacies;

drop policy if exists "reminders_authenticated_all" on public.reminders;
drop policy if exists "reminders_public_anon_all" on public.reminders;

-- RLS must be enabled.
alter table public.doctors enable row level security;
alter table public.documents enable row level security;
alter table public.insurance_cards enable row level security;
alter table public.medications enable row level security;
alter table public.pharmacies enable row level security;
alter table public.reminders enable row level security;

-- Anonymous REST access is no longer allowed.
-- Anonymous guests must first sign in anonymously through Supabase Auth.
revoke all on table public.doctors from anon;
revoke all on table public.documents from anon;
revoke all on table public.insurance_cards from anon;
revoke all on table public.medications from anon;
revoke all on table public.pharmacies from anon;
revoke all on table public.reminders from anon;

-- Supabase anonymous users use the authenticated database role.
grant select, insert, update, delete on table public.doctors to authenticated;
grant select, insert, update, delete on table public.documents to authenticated;
grant select, insert, update, delete on table public.insurance_cards to authenticated;
grant select, insert, update, delete on table public.medications to authenticated;
grant select, insert, update, delete on table public.pharmacies to authenticated;
grant select, insert, update, delete on table public.reminders to authenticated;

-- Helpful indexes for owner-based RLS.
create index if not exists doctors_user_id_idx on public.doctors (user_id);
create index if not exists doctors_guest_id_idx on public.doctors (guest_id);

create index if not exists documents_user_id_idx on public.documents (user_id);
create index if not exists documents_guest_id_idx on public.documents (guest_id);

create index if not exists insurance_cards_user_id_idx on public.insurance_cards (user_id);
create index if not exists insurance_cards_guest_id_idx on public.insurance_cards (guest_id);

create index if not exists medications_user_id_idx on public.medications (user_id);
create index if not exists medications_guest_id_idx on public.medications (guest_id);

create index if not exists pharmacies_user_id_idx on public.pharmacies (user_id);
create index if not exists pharmacies_guest_id_idx on public.pharmacies (guest_id);

create index if not exists reminders_user_id_idx on public.reminders (user_id);
create index if not exists reminders_guest_id_idx on public.reminders (guest_id);

-- DOCTORS
create policy "sana doctors select own"
on public.doctors for select to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana doctors insert own"
on public.doctors for insert to authenticated
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana doctors update own"
on public.doctors for update to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
)
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana doctors delete own"
on public.doctors for delete to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

-- DOCUMENTS
create policy "sana documents select own"
on public.documents for select to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana documents insert own"
on public.documents for insert to authenticated
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana documents update own"
on public.documents for update to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
)
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana documents delete own"
on public.documents for delete to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

-- INSURANCE CARDS
create policy "sana insurance cards select own"
on public.insurance_cards for select to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana insurance cards insert own"
on public.insurance_cards for insert to authenticated
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana insurance cards update own"
on public.insurance_cards for update to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
)
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana insurance cards delete own"
on public.insurance_cards for delete to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

-- MEDICATIONS
create policy "sana medications select own"
on public.medications for select to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana medications insert own"
on public.medications for insert to authenticated
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana medications update own"
on public.medications for update to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
)
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana medications delete own"
on public.medications for delete to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

-- PHARMACIES
create policy "sana pharmacies select own"
on public.pharmacies for select to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana pharmacies insert own"
on public.pharmacies for insert to authenticated
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana pharmacies update own"
on public.pharmacies for update to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
)
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana pharmacies delete own"
on public.pharmacies for delete to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

-- REMINDERS
create policy "sana reminders select own"
on public.reminders for select to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana reminders insert own"
on public.reminders for insert to authenticated
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana reminders update own"
on public.reminders for update to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
)
with check (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
    and guest_id is null
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and user_id is null
    and guest_id = (select auth.uid())::text
  )
);

create policy "sana reminders delete own"
on public.reminders for delete to authenticated
using (
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = false
    and user_id = (select auth.uid())
  )
  or
  (
    (select coalesce((auth.jwt()->>'is_anonymous')::boolean, false)) = true
    and guest_id = (select auth.uid())::text
  )
);

commit;
