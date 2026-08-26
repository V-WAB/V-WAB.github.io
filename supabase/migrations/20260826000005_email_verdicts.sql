-- Banini Butter: record what Resend actually said, and never let an
-- unverified domain cost you the notification.
--
-- Paste this whole file into a NEW query tab, highlight nothing, press Run.
-- It ends by printing your recent emails with their real outcomes.

-- 1. Pull the answers pg_net stored into the log, so "queued" stops standing
--    in for "accepted". Called on every send, so the log is self healing.

create or replace function public.sync_email_results()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.email_log l
     set note = case
                  when r.status_code between 200 and 299 then 'accepted by Resend'
                  when r.status_code is null then coalesce('failed: ' || r.error_msg, l.note)
                  else 'REFUSED ' || r.status_code || ': ' ||
                       coalesce(nullif(r.content::jsonb->>'message', ''), left(r.content, 160))
                end
    from net._http_response r
   where r.id = l.request_id
     and l.note = 'queued';
exception when others then
  null;   /* diagnosis must never break sending */
end;
$$;

-- 2. The owner notification goes from the shared Resend address unless a
--    verified domain is proven to work. Missing a reservation because a DNS
--    record is pending is the worst outcome available here.

create or replace function public.send_email(p_kind text, p_to text, p_subject text, p_html text, p_reference text default null)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_key   text;
  v_from  text;
  v_req   bigint;
begin
  perform public.sync_email_results();

  select value into v_key  from public.app_config where key = 'resend_api_key';
  select value into v_from from public.app_config where key = 'from_email';

  /* Your own copy always goes from the shared Resend address, which Resend
     delivers to the account owner whether or not a domain is verified. Only
     the customer's confirmation needs your domain, because Resend will not
     write to other people from the shared one. */
  if p_kind = 'customer' then
    v_from := coalesce(v_from, 'Banini Butter <onboarding@resend.dev>');
  else
    v_from := 'Banini Butter <onboarding@resend.dev>';
  end if;

  if v_key is null or p_to is null or p_to = '' then
    insert into public.email_log (kind, recipient, reference, note)
    values (p_kind, coalesce(p_to, 'unset'), p_reference,
            case when v_key is null then 'not sent: resend_api_key is not set in app_config'
                 else 'not sent: no recipient' end);
    return;
  end if;

  select net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
    body    := jsonb_build_object('from', v_from, 'to', jsonb_build_array(p_to), 'subject', p_subject, 'html', p_html)
  ) into v_req;

  insert into public.email_log (kind, recipient, reference, request_id, note)
  values (p_kind, p_to, p_reference, v_req, 'queued');
exception when others then
  insert into public.email_log (kind, recipient, reference, note)
  values (p_kind, coalesce(p_to, 'unset'), p_reference, 'failed: ' || sqlerrm);
end;
$$;

-- 3. The whole reservation trigger becomes non fatal. An email must never be
--    able to undo an order, whatever goes wrong inside it.

create or replace function public.on_preorder_complete()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner text;
  v_from  text;
  v_lines text;
  v_html  text;
begin
  begin
    select string_agg(
             i.quantity || ' x ' || s.name || ' ' || z.label || '  &#8373;' || (i.unit_price_ghs * i.quantity),
             '<br>' order by s.name)
      into v_lines
    from public.preorder_items i
    join public.scents s on s.slug = i.scent_slug
    join public.sizes  z on z.slug = i.size_slug
    where i.preorder_id = new.id;

    select value into v_owner from public.app_config where key = 'owner_email';
    select value into v_from  from public.app_config where key = 'from_email';

    v_html :=
      '<h2>' || new.reference || '</h2>' ||
      '<p><b>' || new.full_name || '</b><br>' || new.email || '<br>' || coalesce(new.phone, '') ||
      case when new.city is null then '' else '<br>' || new.city end || '</p>' ||
      '<p>' || coalesce(v_lines, 'no lines') || '</p>' ||
      '<p><b>Indicative total &#8373;' || new.total_ghs || '</b></p>' ||
      case when new.notes is null then '' else '<p><i>' || new.notes || '</i></p>' end;

    perform public.send_email('owner', v_owner,
      'Reservation ' || new.reference || ' from ' || new.full_name, v_html, new.reference);

    if v_from is not null then
      v_html :=
        '<p>Thank you, ' || split_part(new.full_name, ' ', 1) || '.</p>' ||
        '<p>Your jars are held under <b>' || new.reference || '</b>.</p>' ||
        '<p>' || coalesce(v_lines, '') || '</p>' ||
        '<p>Indicative total &#8373;' || new.total_ghs ||
        '. Nothing has been charged and nothing is owed until you confirm. ' ||
        'I will write again when the first run is whipped.</p>' ||
        '<p>Banini Butter, Tamale</p>';

      perform public.send_email('customer', new.email,
        'Your Banini reservation, ' || new.reference, v_html, new.reference);
    end if;
  exception when others then
    insert into public.email_log (kind, recipient, reference, note)
    values ('owner', 'unknown', new.reference, 'trigger failed: ' || sqlerrm);
  end;

  return new;
end;
$$;

grant execute on function public.sync_email_results() to postgres;

select public.sync_email_results();

select created_at, kind, recipient, reference, note
from public.email_log
order by id desc
limit 10;
