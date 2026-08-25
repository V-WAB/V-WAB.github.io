-- Banini Butter, diagnosis
--
-- Paste this whole file into the Supabase SQL Editor and press Run, then send
-- back everything it prints. It changes nothing, it only reports.

-- 1. which create_preorder exists, and what search path it carries
select
  p.proname                                        as function_name,
  pg_get_function_identity_arguments(p.oid)        as arguments,
  coalesce(array_to_string(p.proconfig, ', '), 'no search_path set') as settings,
  case when pg_get_functiondef(p.oid) like '%gen_random_bytes%'
       then 'OLD, still calls gen_random_bytes'
       else 'patched, no pgcrypto needed' end     as reference_style
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('create_preorder', 'join_waitlist')
order by p.proname;

-- 2. where the extensions actually live
select e.extname as extension, n.nspname as schema
from pg_extension e
join pg_namespace n on n.oid = e.extnamespace
order by 1;

-- 3. the postgres version, because gen_random_uuid needs 13 or newer
select version();

-- 4. place a real reservation as the website's own role, and print whatever
--    goes wrong, in full, rather than only the hint
do $$
declare
  v_result json;
begin
  set local role anon;
  v_result := public.create_preorder('{
    "full_name": "Diagnosis Probe",
    "email": "diagnose@example.com",
    "phone": "0000000000",
    "city": "Diagnosis",
    "notes": "safe to delete",
    "items": [{"scent": "sunrise", "size": "50ml", "quantity": 1}]
  }'::json);
  raise notice 'SUCCESS: %', v_result;
exception when others then
  raise notice 'FAILED';
  raise notice '  sqlstate: %', sqlstate;
  raise notice '  message : %', sqlerrm;
end $$;
