-- Banini Butter: the customer emails, in the brand's own voice.
--
-- Paste this whole file into a NEW query tab, highlight nothing, press Run.
-- It ends by printing a preview of both emails so you can read them before
-- anyone else does.

-- ------------------------------------------------------------------- shell
-- One branded wrapper, so every email looks like it came from the same house.

create or replace function public.email_shell(p_heading text, p_body text)
returns text
language sql
immutable
as $$
  select
  '<div style="margin:0;padding:0;background:#FBF7EC;">' ||
  '<div style="max-width:560px;margin:0 auto;padding:32px 24px 40px;font-family:Georgia,''Times New Roman'',serif;color:#2A2318;">' ||

    '<div style="text-align:center;padding-bottom:28px;">' ||
      '<div style="font-size:24px;letter-spacing:5px;color:#B8923F;">BANINI</div>' ||
      '<div style="font-size:15px;letter-spacing:2px;color:#5A5040;font-style:italic;">butter</div>' ||
    '</div>' ||

    '<div style="height:1px;background:#DACAA6;"></div>' ||

    '<h1 style="font-size:23px;font-weight:normal;line-height:1.3;color:#2B4A32;margin:28px 0 20px;">'
      || p_heading || '</h1>' ||

    p_body ||

    '<div style="height:1px;background:#DACAA6;margin:32px 0 18px;"></div>' ||
    '<p style="font-size:12px;line-height:1.7;color:#5A5040;margin:0;text-align:center;">' ||
      'Banini Butter &nbsp;&#183;&nbsp; Tamale and Accra, Ghana<br>' ||
      'Nurtured by nature, finished by hand.' ||
    '</p>' ||

  '</div></div>'
$$;

-- ------------------------------------------------------------ the welcome
-- The founder's own words. p_order is the reservation block, or empty for
-- someone who has only joined the waitlist.

create or replace function public.email_welcome(p_first_name text, p_order text default '')
returns text
language sql
immutable
as $$
  select public.email_shell(
    'You&#8217;re on the list. ✨<br>The Banini Butter glow is coming.',
    '<p style="font-size:16px;line-height:1.75;margin:0 0 16px;">Hey ' ||
      coalesce(nullif(p_first_name, ''), 'there') || ',</p>' ||
    '<p style="font-size:16px;line-height:1.75;margin:0 0 16px;">Thank you so much for claiming your spot on the Banini Butter waitlist.</p>' ||
    '<p style="font-size:16px;line-height:1.75;margin:0 0 16px;">True radiance takes time, and we are working hard behind the scenes to perfect our products just for you. As a waitlist VIP, you are officially part of our inner circle, which means you will receive priority access the moment we officially drop.</p>' ||
    '<p style="font-size:16px;line-height:1.75;margin:0 0 16px;">Keep an eye on your inbox for updates, behind the scenes sneak peeks, and launch details.</p>' ||
    '<p style="font-size:16px;line-height:1.75;margin:0 0 4px;">Stay glowing,</p>' ||
    '<p style="font-size:16px;line-height:1.75;margin:0 0 8px;color:#B8923F;">The Banini Butter Team 🤎</p>' ||
    p_order
  )
$$;

-- ------------------------------------------------------- the order block

create or replace function public.email_order_block(p_reference text, p_lines text, p_total numeric)
returns text
language sql
immutable
as $$
  select
    '<div style="margin:30px 0 0;padding:22px 24px;background:#E7DAC0;">' ||
      '<div style="font-family:Courier New,monospace;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#5A5040;margin-bottom:10px;">Your reservation</div>' ||
      '<div style="font-family:Courier New,monospace;font-size:17px;letter-spacing:3px;color:#B8923F;margin-bottom:16px;">' || p_reference || '</div>' ||
      '<div style="font-size:15px;line-height:1.9;color:#2A2318;">' || coalesce(p_lines, '') || '</div>' ||
      '<div style="height:1px;background:#C9B896;margin:14px 0;"></div>' ||
      '<div style="font-size:15px;color:#2B4A32;"><b>Indicative total &#8373;' || p_total || '</b></div>' ||
      '<p style="font-size:13px;line-height:1.7;color:#5A5040;margin:14px 0 0;">' ||
        'Nothing has been charged and nothing is owed. We will write to confirm the final total and delivery before anything is paid.' ||
      '</p>' ||
    '</div>'
$$;

-- --------------------------------------------- who gets which from address
-- Only you can be reached from the shared Resend address. Everyone else needs
-- the verified domain, so those sends wait for from_email to be configured.

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

  if p_kind in ('owner', 'test') then
    v_from := 'Banini Butter <onboarding@resend.dev>';
  elsif v_from is null then
    insert into public.email_log (kind, recipient, reference, note)
    values (p_kind, coalesce(p_to, 'unset'), p_reference,
            'not sent: from_email is not set, so there is no verified sending domain');
    return;
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

-- ------------------------------------------------- reservation, to customer

create or replace function public.on_preorder_complete()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_owner text;
  v_lines text;
  v_html  text;
begin
  begin
    select string_agg(
             i.quantity || ' &#215; ' || s.name || ', ' || z.label ||
             '<span style="float:right;">&#8373;' || (i.unit_price_ghs * i.quantity) || '</span>',
             '<br>' order by s.name)
      into v_lines
    from public.preorder_items i
    join public.scents s on s.slug = i.scent_slug
    join public.sizes  z on z.slug = i.size_slug
    where i.preorder_id = new.id;

    select value into v_owner from public.app_config where key = 'owner_email';

    -- your copy, plain and quick to scan
    perform public.send_email('owner', v_owner,
      'Reservation ' || new.reference || ' from ' || new.full_name,
      '<h2>' || new.reference || '</h2>' ||
      '<p><b>' || new.full_name || '</b><br>' || new.email || '<br>' || coalesce(new.phone, '') ||
      case when new.city is null then '' else '<br>' || new.city end || '</p>' ||
      '<p>' || coalesce(v_lines, 'no lines') || '</p>' ||
      '<p><b>Indicative total &#8373;' || new.total_ghs || '</b></p>' ||
      case when new.notes is null then '' else '<p><i>' || new.notes || '</i></p>' end,
      new.reference);

    -- theirs, in the brand's voice, with the reservation underneath
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

-- --------------------------------------------------- waitlist, to the joiner
-- They used to get nothing at all, which is a poor welcome for someone who
-- has just handed over their address.

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
  begin
    select value into v_owner from public.app_config where key = 'owner_email';
    select count(*) into v_count from public.waitlist;

    perform public.send_email('owner', v_owner,
      'Waitlist: ' || new.email,
      '<p><b>' || new.email || '</b> joined the waitlist.</p><p>That makes ' || v_count || ' in total.</p>',
      null);

    perform public.send_email('welcome', new.email,
      'You''re on the list! ✨ The Banini Butter glow is coming.',
      public.email_welcome(null, ''),
      null);
  exception when others then
    insert into public.email_log (kind, recipient, reference, note)
    values ('welcome', new.email, null, 'trigger failed: ' || sqlerrm);
  end;

  return new;
end;
$$;

-- ------------------------------------------------------------------ preview

select 'reservation email' as which,
       length(public.email_welcome('Ama', public.email_order_block('BB-EXAMPLE', '2 &#215; Nightfall, 600ml', 800))) as characters
union all
select 'waitlist email', length(public.email_welcome(null, ''));
