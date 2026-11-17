# Earth Rally downloads dashboard

A Cloudflare Worker on the free plan that serves one page: how many times each release of the mod was downloaded.
The page reads the counts from GitHub's public API in your browser. The mod sends nothing, so there is no database
and no key. Code: `src/worker.js`, the page `src/dashboard.js`.

## Your dashboard

Open https://earth-rally-stats.station68.workers.dev/dashboard and bookmark it.

- **Tiles:** mod downloads in all, the latest release, the number of releases, and other files such as rally packs.
- **Bars:** mod zip downloads per release.
- **Table:** every release with its date. Hover a row for each file's count.

Counts are downloads, not people. GitHub keeps only the running total, so there is no history by day.

## Publish a change

From this `server` folder: `npx wrangler deploy`.

## See it before publishing

`node preview.mjs`, then open http://localhost:8787/dashboard. Ctrl+C stops it.

## Test it offline

`node test_worker.mjs`. Nothing to install.

## Cost

Free. GitHub allows 60 reads an hour from one connection without a login; each page load is one read.
