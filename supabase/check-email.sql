-- Banini Butter: what is configured, and what happened to recent emails.
-- Paste into a NEW query tab, highlight nothing, press Run. Reads only.

select public.sync_email_results();

select item, detail from (
  select 1 as sort, 'CONFIG  ' || key as item,
         case when key = 'resend_api_key' then '(hidden, ' || length(value) || ' chars)' else value end as detail,
         null::timestamptz as at
  from public.app_config
  union all
  select 2, 'EMAIL   ' || to_char(created_at, 'HH24:MI') || '  ' || kind || ' to ' || recipient,
         coalesce(reference || '  ', '') || note, created_at
  from public.email_log
  where created_at > now() - interval '2 hours'
) x
order by sort, at desc nulls last, item;
