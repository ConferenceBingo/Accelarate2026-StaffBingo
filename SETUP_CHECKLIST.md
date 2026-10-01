# ACCELARATE 2026 — Production Setup Checklist

## A. Create the Supabase project

1. Create a Supabase project.
2. In Authentication -> Providers / General configuration, enable **Anonymous Sign-Ins**.
3. Copy the project URL and publishable key into `public/config.js`.

Anonymous users are appropriate here because players only need a temporary authenticated session; Supabase treats anonymous users as authenticated users with their own UUID/JWT. A player cannot recover the same anonymous session after clearing browser data or moving to another device, so players should stay on the same phone for the game.

## B. Create the database

Run:

`supabase/migrations/001_accelarate_bingo.sql`

in the Supabase SQL Editor.

This creates:
- game configuration
- the five supplied card layouts
- attendee squares
- player sessions
- player square completion records
- event/audit records
- organizer allowlist
- private selfie storage bucket
- RLS policies
- server-side join / photo / verification functions

## C. Deploy the Edge Function

Install/login to the Supabase CLI, link the project, then:

`supabase functions deploy game-api --use-api`

The function uses the project service key server-side only. Never place the service key in `public/config.js` or any browser code.

## D. Configure the service key

The deployed function needs `SUPABASE_SERVICE_ROLE_KEY` in its server-side environment. Supabase provides a service-role/secret server credential for privileged operations. Keep it secret.

The function also uses `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_ANON_KEY`.

## E. Create organizer access

1. Supabase Dashboard -> Authentication -> Users -> Add user.
2. Create an email/password user for the event organizer.
3. Copy that user's Auth UUID.
4. Run:

`insert into public.admin_users(user_id, display_name) values ('UUID-HERE','Event Organizer');`

Only users listed in `admin_users` can use organizer actions.

## F. Publish the web app

Publish everything in `public/` to an HTTPS static host.

Player page:
`/player.html`

Organizer page:
`/admin.html`

For a polished event URL, configure your host so `/` redirects to `player.html` and keep `/admin.html` unlinked from the player-facing QR code.

## G. Recommended event setup

1. Open the game shortly before the networking activity.
2. Put the player URL/QR code on the event screen or handout.
3. Each participant enters their name and receives a server-assigned card.
4. Players take selfies from the same phone throughout the game.
5. Organizer keeps `/admin.html` open on a laptop/tablet.
6. When the first Blackout claim arrives, verify the earliest claim first.
7. The system blocks approval of a later claim while an earlier non-rejected claim exists.
8. Once the first valid claim is approved, announce the Grand Prize winner.
9. Close the game after the competition.

## H. Rules to publish to players

- A selfie is required to complete an attendee square.
- The center Free Space is automatic.
- BINGO = any complete horizontal row OR vertical column.
- BLACKOUT = all 24 attendee squares completed.
- Players continue toward Blackout after getting Bingo.
- The first valid Blackout claim is determined by server time.
- The Grand Prize goes to the first **verified** Blackout.
- If a Blackout claim is rejected, the next valid claim becomes eligible.

## I. Privacy / retention

Selfies are stored in a private bucket. Decide how long you want to retain event photos before the event and delete them after the retention period if they are no longer needed. The package intentionally does not make the selfie bucket public.
