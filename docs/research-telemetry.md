# Research: player stats, bug reports, log upload

Research 2026-11-16; decisions taken the same day (end of page). Planned for **1.9.0**. Nothing is built. Mock-up: [`mockups-telemetry/telemetry.html`](mockups-telemetry/telemetry.html).
A new system, so it goes in a minor after the alpha MVP (bug fixes only until then).

## What the owner asked for

- How many players downloaded and installed the mod.
- Which stages they run, and how many rallies they play.
- A pop-up on first load asking whether stats may be sent.
- A bug report button, and a button that sends the log.

## What others do

| Who | Asks first? | What it sends |
|---|---|---|
| BeamNG.drive itself | **Opt-in**, blocking prompt, `ask/enable/disable` | Session length, level, vehicle, scenarios, resets, controls, hardware, mod list. Anonymous ID = SHA-256 of a random salt file. |
| Vortex (Nexus Mods) | Opt-in toggle | Anonymous page views |
| Unity Analytics | Nothing until the game passes consent | gameStarted, newPlayer, gameRunning + user/session ID |
| Homebrew | Opt-out, notice before first send | Package, OS, version. No user ID, no IP. Kept 365 days. |
| bStats (Minecraft) | Opt-out | Random server ID, versions, player count |
| Factorio crash upload | Opt-out | Crash log, lightly cleaned (still had Windows usernames in 2025) |
| Blender add-ons | Community leaned to: no automatic telemetry; sending on a button press is fine |

Backlash to learn from: Audacity 2021 (telemetry announced without asking, withdrawn with an apology).

Sources: beamng.com/game/support/policies/privacy-policy-game, help.nexusmods.com/article/121,
docs.unity.com/en-us/analytics/events/standard-events, docs.brew.sh/Analytics,
forum.blender.org/t/extensions-policy-for-add-on-telemetry/35959, theregister.com/2021/05/14/audacity_telemetry.

## Rules we should follow

- **Opt-in, asked once, nothing sent before the answer.** Closing the prompt counts as No. "No" is as easy as "Yes".
  This is what BeamNG does, and it is the simplest rule that holds in the EU: a stored install ID is "information on
  the user's device" under ePrivacy Art. 5(3), so it needs consent. Not legal advice.
- **Say exactly what is sent** in the prompt, and again in a `PRIVACY.md` in the repo, with how long it is kept.
- **Random install ID, nothing else that identifies.** No Steam ID, BeamNG name, hardware, other mods, location.
  Don't store IP addresses on the server.
- **Dates, not times.** Day is enough.
- **Let players see and delete.** Every message also written to `earthRally/telemetry/sent.jsonl`; a "Delete my
  stats" button that removes the ID's rows and makes a new ID.
- **Keep raw events 12 months**, then only totals per stage and rally.
- **Bug reports and logs are a separate yes, every time**, even with stats off. Show the player what is sent.

## Download and install counts

- **Downloads, today, no code:** GitHub's API gives `download_count` per release zip:
  `GET /repos/DeRamp/BeamNG.Earth.Rally/releases`. A running total with no dates, raw clicks (not unique people), and
  the automatic source zips aren't counted. Saving it daily gives a history. The BeamNG repository page shows its own
  download count if the mod is listed there.
- **Installs:** only from players who say yes, so it undercounts. Count distinct install IDs that sent
  `session_start`. How many will opt in is unknown; treat it as a sample, not a census.

## Events (proposal)

All carry: install ID, mod version, game version, BeamNG.Earth version, day. Sent in one batch at the end of a stage
and when the menu opens, never mid-stage.

| Event | Extra fields |
|---|---|
| `session_start` | game language |
| `stage_started` / `stage_finished` | stage ID, pack ID, result (finished / quit / retired / crashed out), stage time (whole seconds), resets, pacenotes on/off, auto recce or file |
| `rally_started` / `rally_finished` | rally ID, stages done of total, result |
| `recce_done` | stage ID, auto recce success/fail |
| `error` | error code, mod module, mod version (no log text) |

Stage IDs: only for stages from packs we ship. A player's own imported stage is sent as `custom` (its name may
be a private place or event).

Not collected: positions, driving traces, vehicle setups, other mods, hardware, free text, per-minute pings.

## The hard part: getting data out of the game

Checked in the game files (0.40.5):

- The game's Lua web library (`luasocket`) has **no HTTPS**, plain HTTP only. No `ssl` module ships.
- The game's own web call (`core_online.apiCall` → C++ `SecureComm`) needs the player logged in to BeamNG online and
  is built to talk to BeamNG's servers; it very probably attaches the BeamNG session token. **Not usable**: we would
  receive players' login tokens.
- A 2024 forum thread says the engine filters URLs the UI can reach; untested in 0.40.5.
- `openWebBrowser(url)` works: it opens the player's browser.

So, three ways out:

1. **Plain HTTP from Lua to our server.** Works today, no extra install. Fine for anonymous counts. Not fine for
   logs: they would cross the internet readable. Needs an in-game test that luasocket can reach an outside host. The
   send blocks the game for up to the timeout, so only at the menu or a stage end, with a short timeout.
2. **Browser hand-off for reports.** The game saves the cleaned log, opens a pre-filled GitHub "new issue" page; the
   player drags the file in. HTTPS, no server, no cost. Needs a GitHub account, so fewer reports.
3. **Through BeamNG.Earth's launcher** (Python, runs next to the game, can do HTTPS). Cleanest, but ties our data to
   another project's process; we dropped a companion add-on for that reason before. Only via our fork.

**Recommendation:** 1 for stats, 2 for bug reports and logs at first. Revisit direct log upload if 3 becomes
possible or an in-game test shows the UI can reach HTTPS.

## The server

One **Cloudflare Worker** (free tier: 100k requests/day) on a `workers.dev` address:

- `/event` → stores events in **D1** (free SQL database). Rate limited, fixed event names, small bodies only.
- No report route: bug reports go through the browser to GitHub (decision 2).
- A workers.dev address answered plain HTTP without redirecting in a quick test; confirm on our own Worker. A custom
  domain must not have "Always Use HTTPS" on, or the game's plain HTTP is redirected and fails.

Cost: about $0 at 100, 1,000 and 10,000 players with batched sends. $5/month only if flooded.

Rejected: Google Analytics (needs a secret in the client), Discord webhooks (the URL is the password, anyone can
spam it from the open-source mod), any GitHub token in the mod, PostHog/Aptabase/Sentry (HTTPS-only as far as we
could tell; heavier than needed). Val Town shuts down January 2027.

## Cleaning a log before it leaves

The game log (`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\beamng.log`, 0.2-0.7 MB) holds: the Windows username in
paths, Steam account ID and Steam name, CPU/GPU/driver, input device IDs, a hardware hash, local IP and port, the full
mod list, timezone. Before saving or sending:

- `C:\Users\<name>\` → `C:\Users\<you>\`
- Steam IDs (17 digits starting `7656119`), the Steam name, emails, IPs → `<removed>`
- The `H2` hash line removed.
- Only our lines plus the last few hundred lines around the error, under 1 MB.
- A "Preview" shows the exact cleaned text before the player sends or saves it.

## Decisions (the owner, 2026-11-16)

1. **Stats over plain HTTP: yes, as long as they are fully anonymous.** So: no IP stored, no account, no hardware,
   no free text, imported stage names sent as `custom`. The random install number stays (without it installs
   can't be counted); it is made on the player's PC, tied to nothing, and replaced by "Delete my stats".
2. **Bug reports go through the browser** to a pre-filled new issue on
   `https://github.com/DeRamp/BeamNG.Earth.Rally/issues/new`, so they land in GitHub issues. No direct send, no
   report server: the Worker only takes stats.
3. **The pop-up appears when the rally menu first opens.**
4. **Its own feature version: 1.9.0** "player stats and bug reports" (docs/roadmap.md), after the alpha MVP.
5. **Owner of `PRIVACY.md` and deletion requests: DeRamp.**

## Unverified

- luasocket reaching an outside host from inside the game (engine URL filter).
- Whether `fetch()` from our UI app can do HTTPS.
- What `SecureComm` attaches to requests (C++, not readable).
- Cloudflare rate limiting on the free plan; Always Use HTTPS per route.
- Whether an EU representative is needed (GDPR Art. 27) for a non-EU hobby developer.
