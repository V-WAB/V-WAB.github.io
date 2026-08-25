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

## If you see "No function matches the given name and argument types"

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
