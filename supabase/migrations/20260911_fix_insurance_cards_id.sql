alter table public.insurance_cards
alter column id set default gen_random_uuid();
