# ACCELARATE 2026 Multiplayer Bingo — Shared Backend Package

This package upgrades the prototype into a real multiplayer game using Supabase:
- Anonymous player sessions (no player email required)
- Five supplied Bingo card layouts
- Server-assigned cards
- Private selfie storage
- Server-side completion timestamps
- Automatic Bingo detection: BOTH a full horizontal row AND a full vertical column
- Automatic Blackout (24 attendee squares + Free Space) detection
- First verified Blackout winner lock
- Organizer dashboard with verification controls
- Public/live leaderboard

## Architecture

Browser (iPhone/Android Safari/Chrome)
  -> Supabase Auth (anonymous player session)
  -> Supabase Postgres (players, cards, squares, events)
  -> Supabase Storage (private selfies)
  -> Edge Function `game-api` (server-side game rules and timestamps)

## Important production behavior

The client never decides the official Bingo/Blackout completion time. The Edge Function writes `completed_at` using the database/server time. Blackout claims are ordered by the database timestamp and verified by an organizer.

## Setup

1. Create a Supabase project.
2. Enable Auth -> Anonymous Sign-Ins.
3. Run `supabase/migrations/001_accelarate_bingo.sql` in the Supabase SQL Editor.
4. Deploy `supabase/functions/game-api/index.ts` as an Edge Function named `game-api`.
5. In Supabase Storage, the migration creates a private `selfies` bucket. Do not make it public.
6. In Authentication -> Users, create the organizer's email/password account.
7. Copy that user's Auth UUID into `admin_users`:

   insert into public.admin_users(user_id, display_name)
   values ('AUTH-USER-UUID-HERE', 'Event Organizer');

8. Put the Supabase project URL and publishable key into `public/config.js` (copy from `public/config.example.js`).
9. Host the `public/` folder on any HTTPS static host (Vercel, Netlify, GitHub Pages with a suitable setup, etc.).
10. Open the player URL on phones. Open `admin.html` for the organizer dashboard.

## Deploy Edge Function

Using the Supabase CLI:

supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy game-api --use-api

The current Supabase docs support deploying Edge Functions from the Dashboard or CLI. The function runtime is TypeScript/Deno. See the official docs linked below.

## API actions

POST /functions/v1/game-api

- `{ action: "join", player_name: string }`
- `{ action: "record_photo", player_id: string, square_index: number, storage_path: string }`
- `{ action: "player_state", player_id: string }`
- `{ action: "leaderboard" }`
- `{ action: "admin_snapshot" }` (admin only)
- `{ action: "verify_blackout", player_id: string, approved: boolean, note?: string }` (admin only)
- `{ action: "game_control", command: "open"|"pause"|"close" }` (admin only)

## Photo flow

The browser signs in anonymously, uploads a compressed selfie to the private `selfies` bucket under:
`{auth_user_id}/{player_id}/{square_index}.jpg`

Then it calls `record_photo`. The Edge Function validates the player/session/square and records the official completion timestamp. Admins receive signed photo URLs when loading a verification view.

## Fairness rule

The first valid Blackout is the earliest server-side `blackout_claimed_at`. The Grand Prize is awarded only after organizer verification. If the first claim is rejected, the next valid claim becomes eligible.

## Sources / current platform notes

Supabase Anonymous Sign-Ins: https://supabase.com/docs/guides/auth/auth-anonymous
Supabase RLS: https://supabase.com/docs/guides/database/postgres/row-level-security
Supabase Storage access control: https://supabase.com/docs/guides/storage/security/access-control
Supabase private buckets: https://supabase.com/docs/guides/storage/buckets/fundamentals
Supabase Edge Functions: https://supabase.com/docs/guides/functions/quickstart


## Latest Bingo rule
BINGO is not awarded for a row OR a column alone. The server awards BINGO only when the player has at least one complete horizontal row AND at least one complete vertical column. BLACKOUT remains a full 24-attendee board plus the automatic Free Space.

## Photo input options
The player UI explicitly offers both **Take Photo** (front-facing camera on supported phones) and **Choose from Photos** (photo library/file picker). Both paths use the same secure private selfie storage and server-side Bingo/Blackout processing.

## Visual accessibility
The player card preserves the source card palette: navy header/text, alternating light-blue and white squares, and the orange Free Space. Text uses high-contrast navy/dark text, visible keyboard/focus indicators, semantic labels, progress-bar semantics, and larger touch targets. The interface is designed toward WCAG 2.1 AA readability; final accessibility conformance should still be tested on the deployed site with real devices and assistive technology.
