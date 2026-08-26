# Banini Butter backend

The site is static and hosted on GitHub Pages, which cannot run server code, so
the waitlist and the reservations live in Supabase. There is no server to deploy
and nothing to keep alive: the browser talks to Supabase directly, and Postgres
does the validating.

## What is in here

`migrations/20260824000001_init.sql` creates everything:

| Object | What it is for |
|---|---|
| `scents`, `sizes` | The catalogue. Publicly readable, which is how the page shows live prices. |
| `waitlist` | One row per email address, deduplicated, case insensitive. |
| `preorders`, `preorder_items` | Unpaid reservations and their lines. |
| `join_waitlist(email, source)` | The only way to write to the waitlist. |
| `create_preorder(payload)` | The only way to write a reservation. |
| `preorder_export` | A flat view of reservations and their lines, for the dashboard. |

## Setting it up

1. Create a project at supabase.com. Any region near your customers is fine, `eu-west` and `us-east` both work from Ghana.
2. Open the SQL editor, paste the whole of `migrations/20260824000001_init.sql`, and run it. Re-running it later is safe, it will not duplicate or wipe data.
3. Go to Project Settings, API, and copy the project URL and the `anon` `public` key.
4. Put both into `config.js` at the root of this repository, then commit and push. The site picks them up on the next page load.

That is the whole setup. There is no build step and nothing else to configure.

## Why the anon key in a public file is fine

The anon key identifies the project, it does not grant access. Row level
security is on for every table, and the anon role has:

- `select` on `scents` and `sizes` only, which is the catalogue the page already shows
- `execute` on `join_waitlist` and `create_preorder`
- nothing at all on `waitlist`, `preorders`, `preorder_items` or `preorder_export`

So a visitor cannot read the waitlist, cannot read anyone's reservation, and
cannot write a row except through the two functions. Both functions validate
every field, and `create_preorder` reads prices from the `sizes` table rather
than trusting the browser, so a tampered payload cannot change what a jar costs.

The `service_role` key is the one that bypasses all of this. Keep it in the
Supabase dashboard and never put it in this repository.

## Reading what comes in

In the Supabase dashboard, the table editor shows `waitlist` and `preorders`
directly. For reservations with their lines, run this in the SQL editor:

```sql
select * from public.preorder_export;
```

Every table view there has an export to CSV button.

Moving a reservation along:

```sql
update public.preorders set status = 'confirmed' where reference = 'BB-XXXXXXXX';
```

Statuses are `received`, `confirmed`, `packed`, `shipped` and `cancelled`.

## Changing prices or blends

Prices live in the database, and the page reads them on load, so a price change
takes effect without touching the site:

```sql
update public.sizes set price_ghs = 220 where slug = '300ml';
```

Retiring a blend is `update public.scents set active = false where slug = '...'`.
The catalogue query filters on `active`, and `create_preorder` refuses anything
inactive. Note that the three blend cards and the three radio buttons in
`index.html` are still written by hand, so adding a brand new blend means adding
it in both places.

## Limits worth knowing

- **50ml and 600ml prices are guesses.** ₵200 for 300ml is the median our testers named. The other two were scaled from it and should be replaced with real costed prices before launch.
- **Nobody is emailed.** Neither a joiner nor a customer gets a confirmation message, and neither do you. The reference on screen is all they get. Sending email needs an edge function and a provider such as Resend, which is the obvious next piece of work.
- **Rate limiting is light.** One email address can place five reservations an hour. There is a honeypot field on the form against basic bots. Supabase's own protections sit in front of everything.
- **No payments.** Reservations are unpaid by design. Taking money later means Paystack for cards and Ghana mobile money.

## Emails

`migrations/20260825000004_email_notifications.sql` sends you an email on every
reservation and every waitlist sign-up, and sends the customer a confirmation
once you have a sending domain. It uses Resend, called straight from a database
trigger through `pg_net`, so there is no edge function to deploy.

Setting it up:

1. Sign up at resend.com and create an API key. The free tier is 3,000 emails a month.
2. Run the migration file in the SQL Editor.
3. Tell it who to write to, and give it the key:

```sql
update public.app_config set value = 'you@example.com' where key = 'owner_email';
insert into public.app_config (key, value) values ('resend_api_key', 're_your_key_here')
  on conflict (key) do update set value = excluded.value;
```

4. Check it works, without placing a reservation:

```sql
select public.send_test_email();
```

**Until you own a domain, Resend will only deliver to the address you signed up
with.** So `owner_email` must be that address, and customers get nothing. Once
you verify a domain in Resend, add it and customer confirmations start:

```sql
insert into public.app_config (key, value)
values ('from_email', 'Banini Butter <hello@yourdomain.com>')
  on conflict (key) do update set value = excluded.value;
```

### Your own copy versus the customer's

Your notification is always sent from the shared Resend address, because Resend
will deliver that to the account owner whether or not a domain is verified.
Only the customer's confirmation uses `from_email`, since Resend refuses to
write to other people from the shared address. That way a pending DNS record
can never cost you the news of a reservation.

### When an email does not arrive

Every attempt is recorded, including the ones that never left:

```sql
select created_at, kind, recipient, reference, note from public.email_log order by id desc limit 20;
```

`queued` means it went to Resend; the delivery itself is then visible in the
Resend dashboard. Anything else says what stopped it.

A broken email setup can never block an order. The sending happens after the
reservation is written, failures are caught and logged, and a reservation still
returns its reference with the email machinery entirely removed. That is tested,
not assumed.

### Where the key lives

In `public.app_config`, which has row level security on, no policies, and no
grants to `anon`. The browser cannot read it. Only the dashboard and the
`SECURITY DEFINER` functions can.

## If you see "No function matches the given name and argument types"

Two separate causes wore this same message.

Supabase keeps pgcrypto in a schema called `extensions`, while these functions
pinned their search path to `public` alone, so `gen_random_bytes`, used to make
the BB- reference, was invisible to them. The reference now uses
`gen_random_uuid`, which is core Postgres and needs no extension at all, and
both functions carry `extensions` on their search path. Note that the error a
caller sees is the *hint* attached to "function gen_random_bytes(integer) does
not exist", which reads like a signature problem and is not one.

The other cause:

PostgREST hands a nested JSON object to a function as `json`, and Postgres has
no implicit cast from `json` to `jsonb`, so a `create_preorder(jsonb)` never
matches the call. The migration now declares the parameter as `json` and casts
once inside the function. Re-run the whole migration file to pick this up: it
drops the old signature first, and nothing else in it is destructive.

## Testing changes to the SQL

The migration was developed against a local Postgres 16, which is the quickest
way to check a change before it touches the live project:

```sh
initdb -D /tmp/pg -A trust -U postgres
pg_ctl -D /tmp/pg -o "-p 5433" -l /tmp/pg.log start
psql -p 5433 -U postgres -c 'create database banini'
psql -p 5433 -U postgres -c 'create role anon nologin' -c 'create role authenticated nologin'
psql -p 5433 -U postgres -d banini -c 'grant usage on schema public to anon, authenticated'
psql -p 5433 -U postgres -d banini -f migrations/20260824000001_init.sql
```

Then `set role anon;` in psql and try to break it.
