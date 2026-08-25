-- Banini Butter, diagnosis
--
-- Paste this whole file into a NEW query tab in the Supabase SQL Editor,
-- highlight nothing, and press Run. Everything comes back as one table.
-- Send me a screenshot of it. It writes nothing except one test reservation
-- you can delete afterwards.

create or replace function public.banini_diagnose()
returns table (check_name text, result text)
language plpgsql
as $$
declare
  v_result json;
begin
  return query
    select 'function'::text,
           p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
           || '  search_path=' || coalesce(array_to_string(p.proconfig, ' '), 'NOT SET')
           || '  '
           || case when pg_get_functiondef(p.oid) like '%gen_random_bytes%'
                   then 'STILL CALLS gen_random_bytes'
                   else 'patched' end
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('create_preorder', 'join_waitlist');

  return query
    select 'extension'::text, e.extname || ' lives in ' || n.nspname
    from pg_extension e
    join pg_namespace n on n.oid = e.extnamespace
    where e.extname <> 'plpgsql';

  return query select 'postgres'::text, split_part(version(), ' on ', 1);

  return query select 'catalogue'::text,
    (select count(*)::text || ' sizes, ' ||
            (select count(*) from public.scents)::text || ' scents'
     from public.sizes);

  begin
    v_result := public.create_preorder('{
      "full_name": "Diagnosis Probe",
      "email": "diagnose@example.com",
      "phone": "0000000000",
      "city": "Diagnosis",
      "notes": "safe to delete",
      "items": [{"scent": "sunrise", "size": "50ml", "quantity": 1}]
    }'::json);
    return query select 'RESERVATION'::text, 'SUCCESS ' || v_result::text;
  exception when others then
    return query select 'RESERVATION'::text, 'FAILED  sqlstate=' || sqlstate;
    return query select 'the real error'::text, sqlerrm;
  end;
end;
$$;

select * from public.banini_diagnose();
