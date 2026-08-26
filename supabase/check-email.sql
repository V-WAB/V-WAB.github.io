-- Banini Butter: why did an email not arrive?
--
-- Paste into a new SQL Editor tab, highlight nothing, press Run.
-- Reads only. The last statement is the one that answers the question.

select
  l.created_at,
  l.kind,
  l.recipient,
  l.reference,
  l.note                              as what_we_recorded,
  r.status_code                       as resend_replied,
  left(r.content, 300)                as resend_said,
  left(r.error_msg, 200)              as network_error
from public.email_log l
left join net._http_response r on r.id = l.request_id
order by l.id desc
limit 15;
