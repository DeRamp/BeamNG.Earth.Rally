# Earth Rally stats server

A Cloudflare Worker with a D1 database, on the free plan. It takes the anonymous stats the Python companion sends
(over HTTPS) and answers the dashboard. Code: `src/worker.js`, the dashboard page `src/dashboard.js`. Tables: `schema.sql`. Privacy: `../PRIVACY.md`.

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
7. **Check plain HTTP works:** run `curl -i http://earth-rally-stats.<your-subdomain>.workers.dev/` (http, not
   https). It should answer `200` and "Earth Rally anonymous stats". If it answers a redirect (`301`), tell Claude.
   Don't check in a browser: browsers always switch `.dev` addresses to https.
8. **Give Claude the address.** It goes into `M.ENDPOINT` in `mod/.../earthRally/stats.lua`, as `http://...`, and
   the build is made again.

Until step 8 (done 2026-11-16: http://earth-rally-stats.station68.workers.dev), the mod still asks the question and keeps stats on the player's PC, but sends nothing.

## Update the live database (2026-11-18: error message, car, class)

The live D1 was made before these columns. Run once from this folder, then deploy:
`npx wrangler d1 execute earth-rally-stats --remote --file=migrate-2026-11-18.sql`. A second run fails with
"duplicate column name", which is harmless. New databases get them from `schema.sql`.

## Update the live database (2026-11-18b: players)

Run once from this folder, after the one above, then deploy:
`npx wrangler d1 execute earth-rally-stats --remote --file=migrate-2026-11-18b.sql`, then `npx wrangler deploy`.
It adds the install number (`install_seen` events only), which the dashboard counts as players.

## Your dashboard

Open `https://earth-rally-stats.<your-subdomain>.workers.dev/dashboard` and type the DASHBOARD_KEY from step 5. The
browser remembers it; **forget key** at the top right clears it. Bookmark the page. It is empty until players send
stats.

**See it before setting anything up:** `node preview.mjs`, then open http://localhost:8787/dashboard. It runs the
same page on made-up data, nothing deployed. Ctrl+C stops it.

## Optional: a rate limit

Anyone can post to the address. Each session is capped at 1,000 rows, but a script could make new sessions. If the
database ever fills with junk: Cloudflare dashboard › your Worker › Settings › add a rate limiting rule for
`/v1/events`, such as 20 requests a minute per IP.

## Test it offline

`node test_worker.mjs` runs the Worker against Node's built-in SQLite. Nothing to install.

## Cost

Free plan: 100,000 requests a day, 5 GB of D1. The mod sends one batch per menu visit, so this covers thousands of
players.

## Still to check once it is live

- That the companion's posts arrive (BeamNG blocks the game's Lua from the network, so events go through the
  companion). Test in game: answer Yes, run a stage,
  open the menu, then look for rows with
  `npx wrangler d1 execute earth-rally-stats --remote --command "SELECT * FROM events LIMIT 5"`.
