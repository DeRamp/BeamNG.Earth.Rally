# Research: online leaderboards

Roadmap item 20, planned for 2.0.0 ("decide then: server, anti-cheat"). Research only, 2026-11-18. Nothing is built:
the alpha is bug fixes only.

## What the owner asked for (2026-11-18)

- One public leaderboard for everyone running the alpha.
- **Two separate boards, never mixed.** The **offline leaderboard** is the real results from a rally pack (what 1.4.0
  built), and it stays on the player's machine. The **online leaderboard** holds players' own times only.
- A free cloud database with next to no upkeep.
- Get past BeamNG's network protections, so the game can reach the board.

## 1. Getting out of the game

**Short answer:** nothing inside the game can reach a cloud service. The way out is a small program beside the game
on 127.0.0.1, which is how BeamMP and BeamNG.Earth already do it. That is the supported route. Breaking the sandbox
is not.

What BeamNG 0.39 and 0.40 allow. These figures are from BeamNG.Earth's own in-game probes on 0.39.4. Its localhost
link still works on 0.40.5, but that 0.40.5 blocks other hosts in the same way has not been checked.

| Route | Works? | Why |
|---|---|---|
| Lua `require('socket')` to a cloud host | No | luasocket is there, but every host goes through an allowlist: localhost, LAN ranges, `*.beamng.com`, `api.openstreetmap.org`. `example.com` gives "connect restricted". |
| HTTPS from Lua (LuaSec) | No | There is no TLS in the game's Lua. |
| `fetch`/XHR from the UI (Vue page) | No | The UI's CSP only allows localhost, and a native filter cancels other requests. |
| BeamNG's own HTTP helper (`core_online` / SecureComm) | No | It is limited to BeamNG's own API hosts and their login. |
| `os.execute`, `io.popen`, `ffi.load` | No | All sandboxed, so the mod cannot start a helper itself. |
| `-disable-sandbox` and similar tricks | Don't | Retail builds appear to force the sandbox anyway, and it would sink publishing. |
| **Lua to a program on 127.0.0.1 over TCP** | **Yes** | This is how BeamNG.Earth's `net.lua` works (port 47613) and how BeamMP's launcher works (port 4444). |

So the chain is: the Vue page → `bngApi.engineLua` → the mod's Lua → a non-blocking luasocket on 127.0.0.1 → a
**Python companion** → HTTPS → the cloud board. The answer comes back the same way, and Lua passes it to the page
with `guihooks.trigger`.

Where the companion runs, best first:

1. **Our own companion under BeamNG.Earth's `companion` add-on kind.** BeamNG.Earth's add-ons page installs it and runs
   it with BeamNG.Earth's own Python, which is already running whenever the game is (the owner always starts through
   its launcher). It needs nothing from the BeamNG.Earth maintainer beyond a registry listing.
2. **Ask BeamNG.Earth for a narrow relay call** (for example `api.relay` to one allowed host, in the next modding
   API). It is neater, but it depends on the maintainer. API 1.8 has no relay today: `api.places` only answers from
   data already on disk.
3. **Fallback when no companion is running:** the mod queues finished times in a file in the user folder, and the
   companion sends them the next time it runs. The online board shows "offline" rather than an error.

To check before building: the companion add-on kind on the current BeamNG.Earth, and the 0.40.5 allowlist (one probe:
connect to `example.com:80` from the console). BeamNG's modding rules could not be read from here. A helper program is
likely not allowed on BeamNG's own mod repository, which matters when it is published.

## 2. The free cloud database

Free tiers have been changing fast this year. Check these against the pricing pages when it is built.

| Service | Free limits | Sleeps? | Server code to check submissions | Notes |
|---|---|---|---|---|
| **Cloudflare Workers + D1** | ~100k requests a day; D1: 5M rows read, 100k written a day, 5 GB | No | Yes (the Worker) | Since 2026-09-01 it refuses past the limit and never bills. Plain SQLite, easy to export. Built-in rate limiting. |
| Supabase | 500 MB Postgres, ~5 GB egress | **Pauses after 7 days** idle | Yes (Postgres function via `/rpc`) | Good tools, but a quiet week takes the board down until someone resumes it by hand. |
| Firebase Firestore | 50k reads, 20k writes a day | No | Rules only; functions need the paid plan (unconfirmed) | The REST API is awkward from Python. |
| Turso, Neon, MongoDB Atlas | Generous storage | Neon cold-starts | No, so a server is still needed | Database only. Turso is being bought by Supabase. |
| PocketBase etc. on a free host | — | Varies | Yes | Fly.io's free tier is gone, Oracle reclaims idle VMs, Deno Deploy is closing. It is also the most upkeep. |
| PlayFab, LootLocker, dreamlo | Trials or cut | — | — | PlayFab's free tier was cut in 2026. dreamlo puts the key in the URL with no TLS. |
| GitHub repo as the store | Free | No | Actions | Rate-limited, slow to update, and players need tokens. Fine as an archive, not as the live board. |

**Recommended: Cloudflare Workers + D1.** It does not sleep, the free limits are 50–100× what a few thousand players
need, its code runs on the server so no secret has to sit in the mod, and it cannot run up a bill.
**Runner-up: Supabase**, if the 7-day pause is kept off with a weekly scheduled ping.

Data model (SQLite):

```
players (id uuid PK, secret_hash, name, created_at, banned)
runs    (id PK, stage_key, class, car, config_hash, player_id, time_ms, splits json, trace blob,
         mod_version, submitted_at, status 'ok' | 'flagged' | 'hidden')
best    (stage_key, class, player_id, run_id, time_ms, PK (stage_key, class, player_id))   -- the board reads this
```

Endpoints:

- `POST /players {name}` returns `{id, secret}`. The companion keeps the secret in the user folder.
- `POST /runs/start {stage_key}` returns a one-time run token.
- `POST /runs {token, time_ms, trace, ...}` is checked (section 3) and returns `{rank, of}`.
- `GET /boards/{stage_key}?class=&top=10&around=<player>` returns the top 10 plus the crews either side of you, the
  same shape the offline board shows. It is cached for about 30 s.

### The stage key: one open problem

On the offline board a stage is named by the rally pack (`eventId`/`stageId`), and each player's line is recced or
matched on their own machine (`events.lineKey`, `events.onLine`). Two players with the same pack may have slightly
different lines, and two packs may name the same road differently. So the online board needs a key that anyone
driving the same road produces: the start and flying finish rounded to roughly 50 m, plus the length rounded to 1 %.
The server can then merge keys that fall within tolerance.

Also undecided: whether stage and rally names are uploaded at all. They come from organisers' packs, and rally data
stays off git and off public servers. A key with no name keeps the online board clear of organisers' material, and the
mod shows the name from the player's own pack.

## 3. Stopping faked times

**What other games show:** nobody stops a determined cheater on a client the player controls. Trackmania re-simulates
every replay and still missed slow-motion runs for over ten years. EA WRC and DiRT Rally 2.0 boards are widely called
cheated, and Forza wiped its boards. The boards people trust (speedrun.com, LFS World) check the top times by hand.
The closest BeamNG example is BeamLap, a hotlap mod with online boards, which also needed an outside relay program.

Our mod is open-source Lua, so any secret or signing key inside it is public. Signing only means anything when the
server signs, for example the run token.

What is worth doing, by value for the cost:

| # | Check | Catches | Cost |
|---|---|---|---|
| 1 | Server plausibility: reject times below length ÷ a top speed for the class; flag anything well ahead of the record | Edited times | Very low |
| 2 | Rate limits, a name word-filter, a report button and an admin hide/ban page | Spam, rude names | Low |
| 3 | One-time run token from the server at the start; compare wall-clock time on the server with the stage time | Resent submissions; crude slow-motion (flag only: pauses give false alarms) | Low |
| 4 | Upload a position trace (2–5 per second, tens of KB) and check it on the server: follows the line, no jumps, no impossible speed or acceleration | Teleports, resets, shortcuts, lazy fakes | Moderate |
| 5 | Vehicle class and config hash; a **stock** board and an **open** board per stage | Honest players with modded cars (sorting, not security) | Moderate |
| 6 | A **verified** badge for the top 3–10, after a moderator watches a video or replay | Determined cheats at the top | Volunteers' time |
| 7 | Accounts: an anonymous player id at first; Discord or GitHub sign-in later | Ban dodging | Moderate |

Not worth it: hiding code, keys in the client, or trying to detect time scale from Lua.

## Recommended design for 2.0.0

- **Path:** the mod's Lua talks to a Python companion on 127.0.0.1 (a BeamNG.Earth `companion` add-on), which talks to
  a Cloudflare Worker with D1.
- **Opt-in:** nothing is sent until the player turns the online board on and picks a name. The settings page says
  exactly what is sent: the name, the stage key, the car, the time and the trace.
- **Checks:** checks 1–5 above. Every time on the online board is marked unverified, and the README says the board
  runs on trust.
- **Later:** the verified badge, ghosts drawn from stored traces (which also lets the community spot impossible
  lines), sign-in accounts, season resets. A BeamMP-timed mode would be the only fully trustworthy option.

## Open questions for the owner

1. A BeamNG.Earth companion add-on, or ask BeamNG.Earth's maintainer for a relay call?
2. Do stage names go up, or only the stage key?
3. Stock and open boards per stage from the start, or one board?
4. Anonymous names at first, or Discord sign-in from day one?
5. Who moderates: the owner only, or volunteers?

## Sources

- BeamNG.Earth: `docs/ARCHITECTURE.md`, `docs/ADDONS.md`, `docs/research/2026-10-11-engine-probes.md`,
  `probes/p1_sandbox.lua`, `lua/ge/extensions/beamngEarth/net.lua` (<https://github.com/TecnaGamer/BeamNG.Earth>).
- BeamMP launcher, localhost 4444 and its local HTTP proxy: <https://github.com/BeamMP/BeamMP-Launcher>
  (`src/Network/Core.cpp`, `src/Network/Http.cpp`).
- BeamLap: <https://beamng.com/resources/beamlap.39886/>.
- Cloudflare D1 pricing and its 2026-09-01 limit change: <https://developers.cloudflare.com/d1/platform/pricing/>,
  <https://developers.cloudflare.com/changelog/post/2026-09-01-d1-free-tier-limit-enforcement/>.
- Supabase free-tier pausing: <https://automationatlas.io/answers/supabase-free-tier-limits-2026/>. Supabase buying
  Turso: <https://supabase.com/blog/supabase-is-acquiring-turso>.
- PlayFab's 2026 change:
  <https://developer.microsoft.com/games/articles/2026/03/gdc-2026-introducing-foundation-mode-for-playfab>.
- Trackmania cheating: <https://www.pcgamer.com/trackmania-dev-analyses-15-years-worth-of-records-to-root-out-the-cheaters>.
  Revalidate: <https://github.com/BigBang1112/revalidate>.
- LFS World: <https://en.lfsmanual.net/wiki/LFS_World>. BeamNG speedrun rules: <https://www.speedrun.com/posts/3i06u>.

Limits: the research could not reach beamng.com, documentation.beamng.com or several vendor pricing pages, so those
figures come from search results and BeamNG.Earth's own probes. Points marked unconfirmed need checking before
building.
