-- Banini Butter: clear out the rows my testing left behind.
--
-- Paste into a new query tab, highlight nothing, press Run. The last line
-- shows what remains, which should be only real people.

delete from public.preorders
where email in ('diagnose@example.com', 'debug@example.com')
   or full_name in ('Diagnosis Probe', 'Debug Probe', 'Patch Check');

delete from public.waitlist
where email in ('diagnose@example.com', 'debug@example.com');

drop function if exists public.banini_diagnose();

select reference, created_at, full_name, email, phone, city, total_ghs, status
from public.preorders
order by created_at desc;
