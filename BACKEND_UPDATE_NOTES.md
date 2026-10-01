# Latest Backend Update

## Bingo rule correction
The production backend now enforces the same rule as the latest prototype:

- **BINGO:** at least one complete horizontal **row AND** at least one complete vertical **column**.
- A completed row by itself is **not** Bingo.
- A completed column by itself is **not** Bingo.
- The stored first-Bingo pattern records both, e.g. `Row 2 + Column G`.
- **BLACKOUT:** all 24 attendee squares must be completed. The center Free Space is automatically complete and counts toward the full board.

## Deployment
For a new Supabase project, run `001_accelarate_bingo.sql` and then `002_latest_bingo_rules.sql`.

For an already-deployed project, run **only** `002_latest_bingo_rules.sql` in the Supabase SQL Editor, then redeploy the included `game-api` Edge Function and the updated `public/` files.

The player UI retains both photo paths:
- **Take Photo** — camera input with front-facing preference where supported.
- **Choose from Photos** — device photo/file picker.

The original card palette and accessibility-oriented mobile UI remain intact.
