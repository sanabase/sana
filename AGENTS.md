# AGENTS.md — Sana project instructions

## Project
- Flutter/Dart mobile application.
- Repository: sana
- Working directory: D:\sana
- Current branch: fix-auth-owner-isolation
- Base commit for this work: 8ee642

## Current task
We are correcting authentication ownership isolation between:
1. permanent Supabase Auth users
2. anonymous Supabase Auth users

Supabase Auth is the only identity authority.

## Ownership rules

Permanent user:
- Supabase Auth user exists.
- `user.isAnonymous == false`
- Database owner:
  - `user_id = auth.currentUser.id`
  - `guest_id = null`

Anonymous user:
- Supabase Auth user exists.
- `user.isAnonymous == true`
- Database owner:
  - `user_id = null`
  - `guest_id = auth.currentUser.id`

NEVER use a locally generated `guest_...` identifier as database ownership.
NEVER trust widget/UI owner IDs for authorization.
NEVER use request header `x-sana-guest-id` for authorization.

## Supabase RLS design

RLS must enforce ownership in the database.

SELECT/DELETE ownership:
- permanent user: `user_id = auth.uid()`
- anonymous user: `guest_id = auth.uid()::text`

INSERT/UPDATE WITH CHECK:
- permanent user: `user_id = auth.uid()` and `guest_id IS NULL`
- anonymous user: `user_id IS NULL` and `guest_id = auth.uid()::text`

Use the JWT `is_anonymous` claim to distinguish the two cases.

Do not weaken RLS to make the Flutter client work.

## Important database facts

Main tables:
- doctors
- documents
- insurance_cards
- medications
- pharmacies
- reminders

`medication_logs` DOES NOT EXIST in the live public schema.
Do not create or invent that table unless explicitly instructed.

Existing `sana_guest_scope()` trusts `x-sana-guest-id`.
It is a legacy security problem.
Keep it temporarily for compatibility, but do not use it for new authorization logic.

Do not automatically delete, migrate, or reassign legacy guest rows.
Do not automatically delete ownerless rows.

## Existing migration

A staged migration exists at:

`supabase/migrations/20260918_fix_owner_isolation.sql`

It has NOT been applied to the remote database yet.

Do not apply database migrations or modify the remote database unless explicitly instructed.

## Existing data warning

The live database contains:
- user-owned rows
- guest-owned rows
- ownerless legacy rows

Some legacy `guest_id` values are not normal local guest IDs and must not be automatically reassigned.

## Flutter changes already made

The following files have intentional working-tree changes:

- `lib/main.dart`
- `lib/providers/doctor_provider.dart`
- `lib/providers/document_provider.dart`
- `lib/providers/medication_provider.dart`
- `lib/providers/pharmacy_provider.dart`
- `lib/services/guest_identity_service.dart`

`lib/services/user_identity_service.dart` is intentionally deleted.

A snapshot file may exist:
- `before-auth-owner-isolation.patch`

Do NOT reset, checkout, restore, or discard existing working-tree changes.

## Important code changes already completed

Medication provider:
- removed client-side `user_id` filtering
- uses Supabase Auth ownership
- update/delete use only record ID and let RLS enforce ownership

Doctor provider:
- update/delete use Auth session ownership
- anonymous users write `guest_id = auth user id`
- permanent users write `user_id = auth user id`

Document provider:
- removed legacy guest identity filtering
- uses Auth ownership
- signed URL access checks current Auth ownership
- local document loading checks current Auth ownership

Pharmacy provider:
- removed client-side `.eq('user_id', user.id)` ownership filter

GuestIdentityService:
- now derives identity directly from Supabase Auth
- anonymous identity is `auth.currentUser.id`
- permanent users are not treated as guests

Main:
- session ownership is based on `auth.currentUser`
- several legacy `widget.guestMode`, `widget.ownerId`, and `isFilter('user_id', ...)` database authorization paths have been removed
- save paths now derive ownership from the current Supabase Auth user

## Known remaining work

Inspect the current working tree before making changes.

There was still a legacy delete path in `lib/main.dart` around the RecordListScreen delete operation using:

- `widget.guestMode`
- `widget.ownerId`
- `.isFilter('user_id', null)`
- `.eq('user_id', widget.ownerId)`

This needs to be corrected so deletion is:

1. verify a current Supabase Auth user exists
2. delete by record ID only
3. let RLS enforce ownership

Also inspect for any remaining database authorization/filtering based on:
- `widget.ownerId`
- `widget.guestMode`
- `GuestIdentityService`
- `user_identity_service`
- `sana_guest_scope`
- `x-sana-guest-id`
- `.eq('user_id', user.id)`
- `.eq('user_id', widget.ownerId)`
- `.isFilter('user_id', null)`

Do not blindly remove `widget.ownerId` or `widget.guestMode` if they are only UI/navigation state. They must only stop being used as database authorization.

## Safety rules

- Preserve existing changes.
- Do not reset the repository.
- Do not use `git reset --hard`.
- Do not discard uncommitted work.
- Do not modify the remote Supabase database unless explicitly instructed.
- Do not invent database tables or columns.
- Do not automatically migrate/delete legacy data.
- Prefer small, targeted edits.
- After edits, inspect the diff.
- Run `flutter analyze`.
- Report every file changed and every test/check performed.
- If an issue is ambiguous, inspect the code first rather than guessing.

## Goal

Finish the auth ownership isolation correction cleanly.

Then:
1. inspect all relevant Flutter ownership code
2. fix remaining legacy authorization paths
3. run `flutter analyze`
4. fix errors caused by the changes
5. inspect `git diff`
6. report remaining issues without hiding them

Do not apply the Supabase SQL migration yet.
