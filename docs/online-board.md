# Leaderboards (prototype)

Players see it as **Leaderboards** (#72); the code and add-on file keep the name `online`.

A public leaderboard of players' own stage times, beside the **offline** board (a rally pack's real results, which
never leave the player's computer). Design and research: [research-online-leaderboards.md](research-online-leaderboards.md).
On its own branch; not in a release.

```
the game (online.lua) --TCP 127.0.0.1:47820--> companion (earth_rally_online.py) --HTTPS--> Worker + D1 (Cloudflare)
```

The game's Lua can only reach this computer, so the companion makes the internet calls.

## Parts

| Part | Where | What it does |
|---|---|---|
| Server | `online/worker/` | Cloudflare Worker on D1 (`src/index.js`, `src/checks.js`, `schema.sql`). Players, stages found by start / finish / length, run tokens, checks, boards, reports, admin. |
| Local server | `online/worker/dev/` | The same Worker under Node 22 with its built-in SQLite standing in for D1. For trying it without Cloudflare. |
| Companion | `online/companion/earth_rally_online.py` | One file, standard library only, run by BeamNG.Earth's Python as a `companion` add-on. Keeps the player's id and secret in `~/.earth_rally_online/`, and queues a finished run when the board can't be reached at the finish. A run whose start couldn't reach the board gets no token and is not sent. |
| Mod | `earthRally/online.lua`, hooks in `runner.lua` and `main.lua` | Off until **Settings > Online leaderboard** is on. A token at the run's start (before the drive to the start), then from GO the car's position every 0.5 s, its resets and recoveries, and any time the game's clock ran slow. The run is sent at the flying finish. |
| UI | `EarthRallyOnline.vue`, the Offline / Online switch on the stage page | Shown only with the setting on. Add-on not running / no board address / pick a name / no line / the board, with Stock and Open tabs. |

**Stock or Open (#75, the owner, 2026-11-18):** the class is only about the car. Stock: one of the game's own
presets, untouched (a `.pc` configuration, labelled `BeamNG - Official`, or with no such label loaded from the
game's own files). Open: any other car, including a tune saved in the garage, parts changed and not saved, and mod
cars. The reset penalty and full rallies do not change the class. The game log says why each run got its class.
The leaderboard opens on the class of the car you are driving (#74).

**Stats (#76):** a separate yes or no, asked when Leaderboards are turned on. With yes, `stats.lua` sends anonymous
events and Earth Rally's errors (cleaned) through the companion's `stats` op to the stats server (`server/`), never
with the player's id. See PRIVACY.md.

**One stage:** players' lines count as the same stage when their start and finish are each within 30 m and their
lengths within 1.5 %. The offline board's own rule is 25 m and 1 %. The first player to drive a stage names it.

**What the server checks** (`checks.js`):
- **Refused outright:** an average over 200 km/h, a run shorter than the server's own clock saw, a resent run, someone
  else's token, or a bad trace.
- **Held for a look:**
  - a jump that no reported reset explains (a teleport);
  - not starting at the start or finishing at the finish;
  - a trace much shorter than the stage;
  - a trace clock that doesn't match the time;
  - on Stock, resets reported but not paid for in penalties, or more than ten jumps put down to resets;
  - more than 15 % faster than the board's best, once it has ten times.

  Slow motion (the game's clock behind real time for more than 5 % of the stage) is noted but doesn't hold the run
  yet: a long hitch looks the same, so the limit needs tuning in game. Rude stage and rally names are stored as
  "Unnamed stage", not refused.

  A held run stays off the board.
- **Limits:** 20 new stages a day per player.

Every time is marked unverified.

## Trying it on one computer

1. Start the local server: `node online/worker/dev/server.mjs --port 8787 --db board.sqlite --admin mysecret`.
   This needs Node 22+.
2. Start the companion: `python online/companion/earth_rally_online.py --server http://127.0.0.1:8787`.
3. Install the mod. Then in game, turn on **Settings > Leaderboards**, open a stage, pick **Leaderboard** and choose
   a name.

## Putting it on Cloudflare (free plan)

Run these from `online/worker/`:

1. `npx wrangler login`
2. `npx wrangler d1 create earth-rally`, then put the `database_id` it prints into `wrangler.toml`.
3. `npx wrangler d1 execute earth-rally --remote --file schema.sql`
4. `npx wrangler secret put ADMIN_TOKEN` (a long random string, used for the admin calls).
5. `npx wrangler deploy`, which prints the address (`https://earth-rally-board.<account>.workers.dev`).
6. Put that address in `DEFAULT_SERVER` in `earth_rally_online.py`, or pass `--server`.

The free plan refuses requests past its daily limits instead of billing.

## The companion in BeamNG.Earth

BeamNG.Earth's **Add-ons** page only adds add-ons from GitHub. For a local copy, add an entry to
`%LOCALAPPDATA%\beamng-earth\addons\local.json` (kind `companion`, a `local` file path to `earth_rally_online.py`,
`run: { "port": 47820 }`) and restart BeamNG.Earth: it then shows on the Add-ons page as a program beside the game. Start it, or tick **Start with BeamNG.Earth**. Its log is `run.log` beside it. For a registry
entry later: `kind: "companion"`, `run: { "port": 47820 }`.

Not tried in game yet. To check:
- that BeamNG.Earth's local-file add-on runs it with no options;
- the `Source` labels;
- typing a name in the game's UI (it uses `setCEFTyping`, as BeamNG.Earth's add-ons page does).

## Moderation

Every call carries `Authorization: Bearer admin:<ADMIN_TOKEN>`.

- `GET /v1/admin/flagged`: runs held for a look, or reported by a player. The report button isn't in the game yet:
  reports come only from the API for now.
- `GET /v1/admin/runs/<id>`: one run, with its trace and resets.
- `POST /v1/admin/runs/<id> {"status": "ok" | "hidden"}`: clear or remove a run.
- `POST /v1/admin/players/<id> {"banned": true}`: removes the player from every board.

## Tests

- `cd online/worker && npm test`: the server, 8 tests.
- `python tests/run_tests.py test_online`: the mod's client, against a fake companion.
- `python tests/test_online_companion.py`: the companion's identity and queue, against a fake server.
- `python tests/test_online_e2e.py`: the mod's client, then the companion, then the local server, about 15 s. Set
  `EARTH_RALLY_TEST_BOARD=http://127.0.0.1:8799` to run it against `npx wrangler dev` instead (passed on workerd and
  local D1, 2026-11-18).
