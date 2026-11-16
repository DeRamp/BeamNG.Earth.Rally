# Earth Rally stats server

A Cloudflare Worker with a D1 database, on the free plan. It takes the mod's anonymous stats, deletes an install's
stats on request, and answers the dashboard. Code: `src/worker.js`. Tables: `schema.sql`. Privacy: `../PRIVACY.md`.

## Set it up (owner, once, about 15 minutes)

Run these from this `server` folder. Node is already installed on the desktop.

1. **Make a free Cloudflare account** at dash.cloudflare.com/sign-up, if you don't have one.
2. **Log in from the terminal:** `npx wrangler login`. The browser opens; allow it.
3. **Make the database:** `npx wrangler d1 create earth-rally-stats`. Copy the `database_id` it prints into
   `wrangler.toml`, replacing `PASTE-THE-ID-FROM-wrangler-d1-create-HERE`.
4. **Make the tables:** `npx wrangler d1 execute earth-rally-stats --remote --file=schema.sql`
5. **Set the dashboard key:** `npx wrangler secret put DASHBOARD_KEY`, then paste a long random password. Keep it in
   your password manager. It is never in the mod.
6. **Publish:** `npx wrangler deploy`. It prints the address, like
   `https://earth-rally-stats.<your-subdomain>.workers.dev`.
7. **Check plain HTTP works:** open `http://earth-rally-stats.<your-subdomain>.workers.dev/` (http, not https). It
   should say "Earth Rally anonymous stats". If it switches to https, tell Claude.
8. **Give Claude the address.** It goes into `M.ENDPOINT` in `mod/.../earthRally/stats.lua`, as `http://...`, and
   the build is made again.

Until step 8, the mod still asks the question and keeps stats on the player's PC, but sends nothing.

## Test it offline

`node test_worker.mjs` runs the Worker against Node's built-in SQLite. Nothing to install.

## Cost

Free plan: 100,000 requests a day, 5 GB of D1. The mod sends one batch per menu visit, so this covers thousands of
players. Each install is capped at 400 events a day.

## Still to check once it is live

- That the game's Lua can reach the Worker (BeamNG may filter addresses). Test in game: answer Yes, run a stage,
  open the menu, then look for rows with
  `npx wrangler d1 execute earth-rally-stats --remote --command "SELECT * FROM events LIMIT 5"`.
- Whether Cloudflare's free rate limiting is worth adding on top of the per-install cap.
