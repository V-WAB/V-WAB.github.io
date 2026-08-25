-- Banini Butter: waitlist and unpaid pre-orders.
--
-- Security model
--   Anonymous visitors get read access to the catalogue (scents, sizes) and
--   nothing else. Writes happen only through two SECURITY DEFINER functions,
--   which validate every field and take prices from the sizes table rather
--   than from the browser. No table is writable with the anon key.

create extension if not exists pgcrypto;
create extension if not exists citext;

-- ---------------------------------------------------------------- catalogue

create table if not exists public.scents (
  slug        text primary key,
  name        text not null,
  blend       text not null,
  note        text not null,
  sort        integer not null default 0,
  active      boolean not null default true
);

create table if not exists public.sizes (
  slug        text primary key,
  label       text not null,
  ml          integer not null check (ml > 0),
  price_ghs   numeric(10,2) not null check (price_ghs >= 0),
  sort        integer not null default 0,
  active      boolean not null default true
);

insert into public.scents (slug, name, blend, note, sort) values
  ('sunrise',       'Sunrise',       'Lemongrass and sweet orange',  'Bright and lifting. Made for mornings and for skin that wants waking up.', 1),
  ('warm-heritage', 'Warm Heritage', 'Raw cocoa and benzoin',        'Deep and comforting, the smell of a roasting yard in the north.',          2),
  ('nightfall',     'Nightfall',     'Lavender and frankincense',    'Calm and slow. The jar you reach for once the day is finished.',           3)
on conflict (slug) do update
  set name = excluded.name, blend = excluded.blend, note = excluded.note, sort = excluded.sort;

-- Prices: 300ml is the median our testers named. The other two are scaled
-- from it and are indicative until the first run is costed.
insert into public.sizes (slug, label, ml, price_ghs, sort) values
  ('50ml',  '50ml',  50,   60.00, 1),
  ('300ml', '300ml', 300, 200.00, 2),
  ('600ml', '600ml', 600, 360.00, 3)
on conflict (slug) do update
  set label = excluded.label, ml = excluded.ml, price_ghs = excluded.price_ghs, sort = excluded.sort;

-- ----------------------------------------------------------------- waitlist

create table if not exists public.waitlist (
  id          uuid primary key default gen_random_uuid(),
  email       citext not null unique,
  source      text not null default 'site',
  created_at  timestamptz not null default now()
);

-- --------------------------------------------------------------- pre-orders

create table if not exists public.preorders (
  id          uuid primary key default gen_random_uuid(),
  reference   text not null unique,
  full_name   text not null,
  email       citext not null,
  phone       text,
  city        text,
  notes       text,
  total_ghs   numeric(10,2) not null default 0,
  status      text not null default 'received'
              check (status in ('received','confirmed','packed','shipped','cancelled')),
  created_at  timestamptz not null default now()
);

create table if not exists public.preorder_items (
  id              uuid primary key default gen_random_uuid(),
  preorder_id     uuid not null references public.preorders(id) on delete cascade,
  scent_slug      text not null references public.scents(slug),
  size_slug       text not null references public.sizes(slug),
  quantity        integer not null check (quantity between 1 and 12),
  unit_price_ghs  numeric(10,2) not null check (unit_price_ghs >= 0)
);

create index if not exists preorder_items_preorder_id_idx on public.preorder_items (preorder_id);
create index if not exists preorders_created_at_idx on public.preorders (created_at desc);
create index if not exists preorders_email_idx on public.preorders (email);

-- --------------------------------------------------------------------- RLS

alter table public.scents          enable row level security;
alter table public.sizes           enable row level security;
alter table public.waitlist        enable row level security;
alter table public.preorders       enable row level security;
alter table public.preorder_items  enable row level security;

drop policy if exists "catalogue is public" on public.scents;
create policy "catalogue is public" on public.scents
  for select to anon, authenticated using (active);

drop policy if exists "catalogue is public" on public.sizes;
create policy "catalogue is public" on public.sizes
  for select to anon, authenticated using (active);

-- waitlist, preorders and preorder_items deliberately have no policies, so
-- they are unreachable with the anon key. The dashboard and the service role
-- bypass RLS and can still read everything.

-- ---------------------------------------------------------------- functions

create or replace function public.join_waitlist(p_email text, p_source text default 'site')
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_email citext;
  v_new   boolean;
begin
  v_email := lower(btrim(coalesce(p_email, '')));

  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
    raise exception 'invalid_email' using hint = 'That email does not look right.';
  end if;
  if length(v_email) > 254 then
    raise exception 'invalid_email' using hint = 'That email is too long.';
  end if;

  insert into public.waitlist (email, source)
  values (v_email, coalesce(nullif(btrim(p_source), ''), 'site'))
  on conflict (email) do nothing;

  v_new := found;
  return json_build_object('ok', true, 'already_joined', not v_new);
end;
$$;

drop function if exists public.create_preorder(jsonb);

create or replace function public.create_preorder(p_payload json)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  /* PostgREST passes a nested object as json, so take one cast up front */
  v_body      jsonb := p_payload::jsonb;
  v_name      text := btrim(coalesce(v_body->>'full_name', ''));
  v_email     citext := lower(btrim(coalesce(v_body->>'email', '')));
  v_phone     text := nullif(btrim(coalesce(v_body->>'phone', '')), '');
  v_city      text := nullif(btrim(coalesce(v_body->>'city', '')), '');
  v_notes     text := nullif(btrim(coalesce(v_body->>'notes', '')), '');
  v_items     jsonb := coalesce(v_body->'items', '[]'::jsonb);
  v_item      jsonb;
  v_scent     text;
  v_size      text;
  v_qty       integer;
  v_price     numeric(10,2);
  v_total     numeric(10,2) := 0;
  v_ref       text;
  v_id        uuid;
  v_recent    integer;
begin
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'invalid_name' using hint = 'Please give a name between 2 and 120 characters.';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' or length(v_email) > 254 then
    raise exception 'invalid_email' using hint = 'That email does not look right.';
  end if;
  if v_phone is null or length(regexp_replace(v_phone, '\D', '', 'g')) < 7 then
    raise exception 'invalid_phone' using hint = 'Please give a phone number we can reach you on.';
  end if;
  if length(v_phone) > 40 then
    raise exception 'invalid_phone' using hint = 'That phone number is too long.';
  end if;
  if v_city is not null and length(v_city) > 120 then
    raise exception 'invalid_city' using hint = 'That town or city name is too long.';
  end if;
  if v_notes is not null and length(v_notes) > 1000 then
    raise exception 'invalid_notes' using hint = 'Please keep notes under 1000 characters.';
  end if;
  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
    raise exception 'no_items' using hint = 'Add at least one jar to the reservation.';
  end if;
  if jsonb_array_length(v_items) > 10 then
    raise exception 'too_many_items' using hint = 'A single reservation holds up to 10 lines.';
  end if;

  select count(*) into v_recent
  from public.preorders
  where email = v_email and created_at > now() - interval '1 hour';

  if v_recent >= 5 then
    raise exception 'rate_limited' using hint = 'That is a lot of reservations in one hour. Write to us instead.';
  end if;

  v_ref := 'BB-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  insert into public.preorders (reference, full_name, email, phone, city, notes)
  values (v_ref, v_name, v_email, v_phone, v_city, v_notes)
  returning id into v_id;

  for v_item in select * from jsonb_array_elements(v_items)
  loop
    v_scent := btrim(coalesce(v_item->>'scent', ''));
    v_size  := btrim(coalesce(v_item->>'size', ''));
    v_qty   := coalesce((v_item->>'quantity')::integer, 0);

    if v_qty < 1 or v_qty > 12 then
      raise exception 'invalid_quantity' using hint = 'Each line takes between 1 and 12 jars.';
    end if;

    if not exists (select 1 from public.scents where slug = v_scent and active) then
      raise exception 'unknown_scent' using hint = 'That scent is not one we make.';
    end if;

    select price_ghs into v_price from public.sizes where slug = v_size and active;
    if v_price is null then
      raise exception 'unknown_size' using hint = 'That size is not one we make.';
    end if;

    insert into public.preorder_items (preorder_id, scent_slug, size_slug, quantity, unit_price_ghs)
    values (v_id, v_scent, v_size, v_qty, v_price);

    v_total := v_total + (v_price * v_qty);
  end loop;

  update public.preorders set total_ghs = v_total where id = v_id;

  return json_build_object('ok', true, 'reference', v_ref, 'total_ghs', v_total);
end;
$$;

-- ------------------------------------------------------------------- grants

revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;

grant select on public.scents, public.sizes to anon, authenticated;
grant execute on function public.join_waitlist(text, text)  to anon, authenticated;
grant execute on function public.create_preorder(json)      to anon, authenticated;

-- --------------------------------------------------------------- admin view
-- Readable in the dashboard and with the service role only. No grant to anon.

create or replace view public.preorder_export as
select
  p.reference,
  p.created_at,
  p.status,
  p.full_name,
  p.email,
  p.phone,
  p.city,
  p.notes,
  p.total_ghs,
  s.name  as scent,
  z.label as size,
  i.quantity,
  i.unit_price_ghs
from public.preorders p
join public.preorder_items i on i.preorder_id = p.id
join public.scents s on s.slug = i.scent_slug
join public.sizes  z on z.slug = i.size_slug
order by p.created_at desc, s.name;

revoke all on public.preorder_export from anon, authenticated;
