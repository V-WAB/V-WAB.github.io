-- Banini Butter: a town or city is now required, and Warm Heritage is vanilla.
--
-- Paste this whole file into a NEW query tab in the Supabase SQL editor,
-- highlight nothing, press Run. Safe to run more than once.
--
-- Why: the reserve page now insists on a town or city, because an order
-- cannot be delivered without one. The browser asks for it, but the browser
-- is not the thing that decides. This teaches the database to insist too,
-- so a reservation without a town cannot be created by any route.
--
-- The preorders.city column stays nullable, because reservations already
-- placed without a town would fail a NOT NULL. The function is what
-- enforces it from here on.

-- ------------------------------------------------ Warm Heritage is vanilla
update public.scents
   set blend = 'Raw cocoa and vanilla'
 where slug = 'warm-heritage';

-- -------------------------------------------- the order path wants a town
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
  if v_city is null or length(v_city) < 2 then
    raise exception 'invalid_city' using hint = 'Please tell me which town or city to send them to.';
  end if;
  if length(v_city) > 120 then
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

notify pgrst, 'reload schema';

-- ------------------------------------------------------------- read it back
select slug, name, blend from public.scents order by sort;
