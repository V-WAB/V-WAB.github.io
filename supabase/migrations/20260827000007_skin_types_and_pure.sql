-- Banini Butter: the full range. Four blends, three skin types, three sizes.
--
-- Paste this whole file into a NEW query tab, highlight nothing, press Run.
-- It ends by printing all thirty-six products with their prices, so you can
-- read the range back before anyone else orders from it.
--
-- Safe to run more than once. The price seeding uses "do nothing" on conflict,
-- so once you have edited a price in the dashboard, re-running this file will
-- never overwrite it.

-- --------------------------------------------------------------- skin types

create table if not exists public.skin_types (
  slug        text primary key,
  name        text not null,
  for_skin    text not null,
  note        text not null,
  sort        integer not null default 0,
  active      boolean not null default true
);

insert into public.skin_types (slug, name, for_skin, note, sort) values
  ('deep-moisture', 'Deep Moisture', 'For dry skin',
   'The richest of the three. For skin that drinks it in and asks for more.', 1),
  ('matte',         'Matte',         'For oily skin',
   'Lighter, and it finishes without shine. Sits down quickly and stays down.', 2),
  ('balanced',      'Balanced',      'For combination skin',
   'The middle road. Enough for the dry patches without overdoing the rest.', 3)
on conflict (slug) do update
  set name = excluded.name, for_skin = excluded.for_skin,
      note = excluded.note, sort = excluded.sort;

-- ------------------------------------------------------------ fourth blend

insert into public.scents (slug, name, blend, note, sort) values
  ('pure', 'Pure', 'Unscented',
   'The shea and nothing else. For sensitive skin, and for anyone who would rather not smell of anything.', 4)
on conflict (slug) do update
  set name = excluded.name, blend = excluded.blend, note = excluded.note, sort = excluded.sort;

-- ------------------------------------------------------------------ prices
-- One row per product, so any single one can be priced on its own without
-- touching the rest.
--
-- The list below is the price list. Warm Heritage carries the cocoa butter,
-- so it is a quarter more than the others. Pure is unscented and comes in
-- nine per cent under. Skin type makes no difference to the price, so each
-- line here is charged for all three of Deep Moisture, Matte and Balanced.
--
-- THIS FILE DECIDES THE PRICES. Running it again sets them back to what is
-- written here, so change a price in this file rather than only in the
-- dashboard, or a later run will quietly undo you.

create table if not exists public.product_prices (
  scent_slug  text not null references public.scents(slug)     on update cascade,
  skin_slug   text not null references public.skin_types(slug) on update cascade,
  size_slug   text not null references public.sizes(slug)      on update cascade,
  price_ghs   numeric(10,2) not null check (price_ghs >= 0),
  active      boolean not null default true,
  primary key (scent_slug, skin_slug, size_slug)
);

with price_list (scent_slug, size_slug, price_ghs) as (values
  ('sunrise',       '50ml',   80.00), ('sunrise',       '300ml', 200.00), ('sunrise',       '600ml', 400.00),
  ('warm-heritage', '50ml',  100.00), ('warm-heritage', '300ml', 250.00), ('warm-heritage', '600ml', 500.00),
  ('nightfall',     '50ml',   80.00), ('nightfall',     '300ml', 200.00), ('nightfall',     '600ml', 400.00),
  ('pure',          '50ml',   72.80), ('pure',          '300ml', 182.00), ('pure',          '600ml', 364.00)
)
insert into public.product_prices (scent_slug, skin_slug, size_slug, price_ghs)
select pl.scent_slug, sk.slug, pl.size_slug, pl.price_ghs
from price_list pl
cross join public.skin_types sk
on conflict (scent_slug, skin_slug, size_slug) do update
  set price_ghs = excluded.price_ghs;

-- ------------------------------------------------------- the ordered lines

alter table public.preorder_items
  add column if not exists skin_slug text references public.skin_types(slug) on update cascade;

-- ---------------------------------------------------------------------- RLS

alter table public.skin_types     enable row level security;
alter table public.product_prices enable row level security;

drop policy if exists "catalogue is public" on public.skin_types;
create policy "catalogue is public" on public.skin_types
  for select to anon, authenticated using (active);

drop policy if exists "catalogue is public" on public.product_prices;
create policy "catalogue is public" on public.product_prices
  for select to anon, authenticated using (active);

grant select on public.skin_types     to anon, authenticated;
grant select on public.product_prices to anon, authenticated;

-- ----------------------------------------------------------- the order path

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
  v_skin      text;
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
    v_skin  := btrim(coalesce(v_item->>'skin', ''));
    v_size  := btrim(coalesce(v_item->>'size', ''));
    v_qty   := coalesce((v_item->>'quantity')::integer, 0);

    if v_qty < 1 or v_qty > 12 then
      raise exception 'invalid_quantity' using hint = 'Each line takes between 1 and 12 jars.';
    end if;

    /* each axis is checked on its own, so the message names what is wrong */
    if not exists (select 1 from public.scents where slug = v_scent and active) then
      raise exception 'unknown_scent' using hint = 'That blend is not one we make.';
    end if;
    if not exists (select 1 from public.skin_types where slug = v_skin and active) then
      raise exception 'unknown_skin' using hint = 'Please choose Deep Moisture, Matte or Balanced.';
    end if;
    if not exists (select 1 from public.sizes where slug = v_size and active) then
      raise exception 'unknown_size' using hint = 'That size is not one we make.';
    end if;

    /* the price is the database's to decide, never the browser's */
    select price_ghs into v_price
    from public.product_prices
    where scent_slug = v_scent and skin_slug = v_skin and size_slug = v_size and active;

    if v_price is null then
      raise exception 'unknown_product'
        using hint = 'That combination is not one we make yet. Please pick another.';
    end if;

    insert into public.preorder_items
      (preorder_id, scent_slug, skin_slug, size_slug, quantity, unit_price_ghs)
    values (v_id, v_scent, v_skin, v_size, v_qty, v_price);

    v_total := v_total + (v_price * v_qty);
  end loop;

  update public.preorders set total_ghs = v_total where id = v_id;

  return json_build_object('ok', true, 'reference', v_ref, 'total_ghs', v_total);
end;
$$;

grant execute on function public.create_preorder(json) to anon, authenticated;

-- ------------------------------------------- the emails name the skin type

create or replace function public.on_preorder_complete()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner text;
  v_lines text;
begin
  begin
    select string_agg(
             i.quantity || ' &#215; ' || s.name ||
             coalesce(', ' || k.name, '') || ', ' || z.label ||
             '<span style="float:right;">&#8373;' || (i.unit_price_ghs * i.quantity) || '</span>',
             '<br>' order by s.name)
      into v_lines
    from public.preorder_items i
    join public.scents s on s.slug = i.scent_slug
    join public.sizes  z on z.slug = i.size_slug
    left join public.skin_types k on k.slug = i.skin_slug
    where i.preorder_id = new.id;

    select value into v_owner from public.app_config where key = 'owner_email';

    perform public.send_email('owner', v_owner,
      'Reservation ' || new.reference || ' from ' || new.full_name,
      '<h2>' || new.reference || '</h2>' ||
      '<p><b>' || new.full_name || '</b><br>' || new.email || '<br>' || coalesce(new.phone, '') ||
      case when new.city is null then '' else '<br>' || new.city end || '</p>' ||
      '<p>' || coalesce(v_lines, 'no lines') || '</p>' ||
      '<p><b>Indicative total &#8373;' || new.total_ghs || '</b></p>' ||
      case when new.notes is null then '' else '<p><i>' || new.notes || '</i></p>' end,
      new.reference);

    perform public.send_email('customer', new.email,
      'You''re on the list! ✨ The Banini Butter glow is coming.',
      public.email_welcome(
        split_part(new.full_name, ' ', 1),
        public.email_order_block(new.reference, v_lines, new.total_ghs)),
      new.reference);
  exception when others then
    insert into public.email_log (kind, recipient, reference, note)
    values ('owner', 'unknown', new.reference, 'trigger failed: ' || sqlerrm);
  end;

  return new;
end;
$$;

notify pgrst, 'reload schema';

-- ------------------------------------------------------------- the range

select
  sc.name  as blend,
  sk.name  as skin,
  sz.label as size,
  '&#8373;' || p.price_ghs as price
from public.product_prices p
join public.scents     sc on sc.slug = p.scent_slug
join public.skin_types sk on sk.slug = p.skin_slug
join public.sizes      sz on sz.slug = p.size_slug
order by sc.sort, sk.sort, sz.sort;
