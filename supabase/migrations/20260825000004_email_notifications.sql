-- Banini Butter: email on every reservation and every waitlist sign-up.
--
-- Paste this whole file into a NEW query tab in the Supabase SQL Editor,
-- highlight nothing, press Run. It ends by printing what it configured.
--
-- Nothing sends until you add your Resend key, which is the last step and a
-- single line, given at the bottom of this file.

create extension if not exists pg_net with schema extensions;

-- ------------------------------------------------------------------ config
-- Locked away from the browser: RLS on, no policies, no grants. Only the
-- dashboard and SECURITY DEFINER functions can read it.

create table if not exists public.app_config (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now()
);

alter table public.app_config enable row level security;
revoke all on public.app_config from anon, authenticated;

-- ---------------------------------------------------------------- email log
-- Every attempt is recorded, so a silent failure is still a visible one.

create table if not exists public.email_log (
  id          bigserial primary key,
  created_at  timestamptz not null default now(),
  kind        text not null,
  recipient   text not null,
  reference   text,
  request_id  bigint,
  note        text
);

alter table public.email_log enable row level security;
revoke all on public.email_log from anon, authenticated;
create index if not exists email_log_created_at_idx on public.email_log (created_at desc);

-- ------------------------------------------------------------------ sending

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
  select value into v_key  from public.app_config where key = 'resend_api_key';
  select value into v_from from public.app_config where key = 'from_email';
  v_from := coalesce(v_from, 'Banini Butter <onboarding@resend.dev>');

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

-- ------------------------------------------------------- reservation emails
-- Fires when create_preorder writes the total, which happens after the jars
-- are in. An insert trigger would send an email with no lines in it.

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

  -- to you
  v_html :=
    '<h2>' || new.reference || '</h2>' ||
    '<p><b>' || new.full_name || '</b><br>' || new.email || '<br>' || coalesce(new.phone, '') ||
    case when new.city is null then '' else '<br>' || new.city end || '</p>' ||
    '<p>' || coalesce(v_lines, 'no lines') || '</p>' ||
    '<p><b>Indicative total &#8373;' || new.total_ghs || '</b></p>' ||
    case when new.notes is null then '' else '<p><i>' || new.notes || '</i></p>' end;

  perform public.send_email('owner', v_owner,
    'Reservation ' || new.reference || ' from ' || new.full_name, v_html, new.reference);

  -- to the customer, but only once you have your own sending domain. Resend
  -- will not deliver to other people from the shared onboarding address.
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
  else
    insert into public.email_log (kind, recipient, reference, note)
    values ('customer', new.email, new.reference,
            'not sent: from_email is not set, so there is no verified sending domain yet');
  end if;

  return new;
end;
$$;

drop trigger if exists preorder_complete_email on public.preorders;
create trigger preorder_complete_email
  after update of total_ghs on public.preorders
  for each row
  when (new.total_ghs > 0 and old.total_ghs = 0)
  execute function public.on_preorder_complete();

-- ---------------------------------------------------------- waitlist emails

create or replace function public.on_waitlist_join()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner text;
  v_count bigint;
begin
  select value into v_owner from public.app_config where key = 'owner_email';
  select count(*) into v_count from public.waitlist;

  perform public.send_email('owner', v_owner,
    'Waitlist: ' || new.email,
    '<p><b>' || new.email || '</b> joined the waitlist.</p><p>That makes ' || v_count || ' in total.</p>',
    null);

  return new;
end;
$$;

drop trigger if exists waitlist_join_email on public.waitlist;
create trigger waitlist_join_email
  after insert on public.waitlist
  for each row
  execute function public.on_waitlist_join();


-- --------------------------------------------------------------- self test
-- select public.send_test_email();  ->  sends one email and tells you what
-- happened, without having to place a reservation.

create or replace function public.send_test_email()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner text;
  v_note  text;
begin
  select value into v_owner from public.app_config where key = 'owner_email';

  if v_owner is null or v_owner = 'CHANGE_ME' then
    return 'owner_email is not set. Run: update public.app_config set value = ''you@example.com'' where key = ''owner_email'';';
  end if;

  perform public.send_email('test', v_owner, 'Banini Butter, test email',
    '<p>If you are reading this, reservations and waitlist sign-ups will reach you too.</p>', null);

  select note into v_note from public.email_log order by id desc limit 1;
  return 'sent to ' || v_owner || '  ->  ' || v_note;
end;
$$;

-- ------------------------------------------------------------------- finish

insert into public.app_config (key, value)
values ('owner_email', 'CHANGE_ME')
on conflict (key) do nothing;

select 'configured' as status,
       (select count(*) from public.app_config where key = 'resend_api_key') as has_api_key,
       (select value from public.app_config where key = 'owner_email')        as owner_email,
       coalesce((select value from public.app_config where key = 'from_email'), 'the shared Resend address') as sends_from;
