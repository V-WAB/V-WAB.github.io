-- Banini Butter, patch 0003
--
-- Run this whole file in the Supabase SQL Editor.
--
-- Why: Supabase keeps pgcrypto in a schema called `extensions`, while these
-- functions pinned their search path to `public` alone. So gen_random_bytes,
-- used to make the BB- reference, was invisible to them. A reservation with
-- items in it failed on that line with "function gen_random_bytes(integer)
-- does not exist", whose hint reads "No function matches the given name and
-- argument types". An empty basket never reached the line, which is why the
-- earlier probe looked healthy.
--
-- The reference now uses gen_random_uuid, which is core Postgres and needs no
-- extension, and both functions carry `extensions` on their search path.
--
-- Safe to run more than once.

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

grant execute on function public.join_waitlist(text, text) to anon, authenticated;
grant execute on function public.create_preorder(json)     to anon, authenticated;

notify pgrst, 'reload schema';

-- proof it works: this should return a BB- reference
select public.create_preorder('{"full_name":"Patch Check","email":"patch@example.com","phone":"0241234567","items":[{"scent":"sunrise","size":"50ml","quantity":1}]}'::json);
