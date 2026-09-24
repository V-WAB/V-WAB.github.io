-- Banini Butter: a town or city is required, and Warm Heritage is vanilla.
--
-- Paste this whole file into a NEW query tab in the Supabase SQL editor,
-- highlight nothing, press Run. Safe to run more than once.
--
-- There are no functions in this file, on purpose. The SQL editor splits a
-- script into statements without respecting dollar quoting, so a function body
-- gets cut in half and you get "unterminated dollar-quoted string" or a syntax
-- error on the first line inside it. Everything below is a single ordinary
-- statement that no splitter can get wrong.

-- ----------------------------------------------- Warm Heritage is vanilla
update public.scents
   set blend = 'Raw cocoa and vanilla'
 where slug = 'warm-heritage';

-- ------------------------------------------- a reservation needs a town
-- The browser asks for it and refuses to submit without one. This is the
-- backstop underneath that, so a reservation cannot be created without a
-- town by any route at all.
--
-- NOT VALID means reservations already taken without a town are left alone.
-- Everything inserted from now on is checked.

alter table public.preorders
  drop constraint if exists preorders_city_present;

alter table public.preorders
  add constraint preorders_city_present
  check (city is not null and length(btrim(city)) >= 2)
  not valid;

-- --------------------------------------------------------- read it back
select slug, name, blend from public.scents order by sort;
