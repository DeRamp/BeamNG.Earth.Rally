// Offline test of the stats Worker: D1 stood in by Node's built-in SQLite (Node 22.5+), no install needed.
//   node server/test_worker.mjs
import assert from "node:assert/strict"
import { makeDb } from "./d1shim.mjs"

const here = new URL(".", import.meta.url)
const { db, D1 } = makeDb()
const env = { DB: D1, DASHBOARD_KEY: "k".repeat(32) }
globalThis.caches = { default: { match: async () => null, put: async () => {} } }
globalThis.fetch = async () => new Response(JSON.stringify([{ tag_name: "v1.6.2-alpha", assets: [{ download_count: 12 }] }]))
const ctx = { waitUntil() {} }

const worker = (await import(new URL("src/worker.js", here))).default
const { clean } = await import(new URL("src/worker.js", here))
const post = (path, body) => worker.fetch(new Request("http://x" + path, { method: "POST", body: JSON.stringify(body) }), env, ctx)

const id = "0123456789abcdef0123456789abcdef"
const day = new Date().toISOString().slice(0, 10)
const base = { session: id, mod: "1.6.2-alpha+stats", game: "0.40.5.0", earth: "1.10", day }

// clean: unknown events, bad ids and extra fields refused
assert.equal(clean({ ...base, event: "nope" }), null)
assert.equal(clean({ ...base, event: "session_start", session: "Bob" }), null)
assert.equal(clean({ ...base, event: "stage_started", message: "hi" }).message, undefined)   // only on errors
assert.equal(clean({ ...base, event: "error", code: "x", message: "m".repeat(300) }).message.length, 200)
assert.equal(clean({ ...base, event: "error", code: "c".repeat(100) }).code.length, 80)
assert.equal(clean({ ...base, event: "stage_finished", cls: "stock" }).cls, "stock")
assert.equal(clean({ ...base, event: "stage_finished", cls: "open" }).cls, "open")
assert.equal(clean({ ...base, event: "stage_finished", cls: "Stock" }).cls, undefined)
assert.equal(clean({ ...base, event: "stage_finished", cls: "hacked" }).cls, undefined)
assert.equal(clean({ ...base, event: "stage_started", cls: "stock" }).cls, undefined)
assert.equal(clean({ ...base, event: "stage_finished", car: "x".repeat(100) }).car.length, 80)
assert.equal(clean({ ...base, event: "session_start", day: "1999-01-01" }).day, day)
assert.equal(clean({ ...base, event: "stage_finished", time_s: 412.4, resets: -3 }).time_s, 412)
assert.equal(clean({ ...base, event: "stage_finished", resets: -3 }).resets, undefined)
// install_seen: the install number, never a session; nothing else carries an install number
const inst = "abcdefabcdefabcdefabcdefabcdef01"
const seen = { event: "install_seen", install: inst, mod: "1.8.1-alpha", game: "0.40.5.0", earth: "1.10", day }
assert.deepEqual(clean({ ...seen, session: id, rally: "ARA 2026" }), { day, event: "install_seen", install: inst, mod: "1.8.1-alpha", game: "0.40.5.0", earth: "1.10" })
assert.equal(clean({ ...seen, install: "Bob" }), null)
assert.equal(clean({ ...seen, install: undefined }), null)
assert.equal(clean({ ...base, event: "stage_finished", install: inst }).install, undefined)

let r = await post("/v1/events", { events: [
  { ...base, event: "session_start" },
  { ...base, event: "stage_started", rally: "ARA 2026", stage: "SS1", pass: 1 },
  { ...base, event: "stage_finished", rally: "ARA 2026", stage: "SS1", pass: 1, result: "finished", time_s: 400, resets: 1, car: "Hirochi Sunburst", cls: "stock" },
  { ...base, event: "stage_started", rally: "ARA 2026", stage: "SS1", pass: 1 },
  { ...base, event: "stage_finished", rally: "ARA 2026", stage: "SS1", pass: 1, result: "finished", time_s: 420, resets: 0, car: "Hirochi Sunburst", cls: "open" },
  { ...base, event: "stage_finished", rally: "ARA 2026", stage: "SS2", pass: 1, result: "quit", car: "Ibishu Covet", cls: "bogus" },
  { ...base, event: "error", code: "menu_action_drive", module: "main", message: "old text" },
  { ...base, event: "error", code: "menu_action_drive", module: "main" },
  { ...base, event: "error", code: "menu_action_drive", module: "main", message: "x".repeat(250) + "<b>" },
] })
assert.equal(r.status, 204)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM events").get().n, 9)
assert.equal(db.prepare("SELECT car FROM events WHERE event = 'stage_finished' AND stage = 'SS2'").get().car, "Ibishu Covet")
assert.equal(db.prepare("SELECT cls FROM events WHERE event = 'stage_finished' AND stage = 'SS2'").get().cls, null)
assert.equal(db.prepare("SELECT MAX(length(message)) AS n FROM events").get().n, 200)
assert.equal((await post("/v1/events", { events: new Array(51).fill({ ...base, event: "session_start" }) })).status, 400)
assert.equal((await worker.fetch(new Request("http://x/v1/events", { method: "POST", body: "x".repeat(40000) }), env, ctx)).status, 400)

// the dashboard: locked without the key
assert.equal((await worker.fetch(new Request("http://x/api/summary"), env, ctx)).status, 401)
r = await worker.fetch(new Request("http://x/api/summary?days=30", { headers: { authorization: "Bearer " + env.DASHBOARD_KEY } }), env, ctx)
assert.equal(r.status, 200)
const s = await r.json()
assert.equal(s.totals.sessions, 1)
assert.equal(s.totals.started, 2)
assert.equal(s.totals.finished, 2)
assert.equal(s.stages[0].runs, 2)
assert.equal(s.stages[0].median_s, 410)
assert.equal(s.stages[0].best_s, 400)
assert.equal(s.stages.find(x => x.stage === "SS2").best_s, null)
assert.equal(s.errors[0].code, "menu_action_drive")
assert.equal(s.errors[0].times, 3)
assert.equal(s.errors[0].message, "x".repeat(200))            // the newest message, cut to 200 (the "<b>" cut off)
assert.deepEqual(s.cars.top, [{ v: "Hirochi Sunburst", n: 2 }, { v: "Ibishu Covet", n: 1 }])
assert.deepEqual(s.cars.cls.map(c => [c.v, c.n]).sort(), [["open", 1], ["stock", 1], [null, 1]].sort())
assert.equal(s.downloads, undefined)          // (fetched by the owner's browser from GitHub)
assert.equal(s.errors[0].first_ever, day)
assert.equal(s.errors[0].first_code, day)
assert.equal(s.totals.last_day, day)
assert.equal(s.totals.sessions_ever, undefined)  // (a full scan nobody reads)
assert.deepEqual([s.players.all_time, s.players.last7, s.players.in_range, s.players.daily.length], [0, 0, 0, 0])

// players: install_seen stored in installs once per install and day, never in events; counted apart from sessions
const inst2 = "0000000000000000000000000000beef", old = new Date(Date.now() - 10 * 86400000).toISOString().slice(0, 10)
assert.equal((await post("/v1/events", { events: [seen, seen, { ...seen, install: inst2 }, { ...base, event: "session_start" }] })).status, 204)
assert.equal((await post("/v1/events", { events: [seen] })).status, 204)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM installs").get().n, 2)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM events WHERE event = 'install_seen' OR install IS NOT NULL").get().n, 0)
assert.deepEqual(Object.keys(db.prepare("SELECT * FROM installs LIMIT 1").get()).sort(), ["day", "earth", "game", "install", "mod"])
db.exec(`INSERT INTO installs (day, install) VALUES ('${old}', '${inst}'), ('${old}', '${"9".repeat(32)}')`)
r = await worker.fetch(new Request("http://x/api/summary?days=30", { headers: { authorization: "Bearer " + env.DASHBOARD_KEY } }), env, ctx)
const p = (await r.json())
assert.deepEqual([p.players.all_time, p.players.last7, p.players.in_range], [3, 2, 3])
assert.deepEqual(p.players.daily, [{ day: old, players: 2 }, { day, players: 2 }])
assert.equal(p.totals.sessions, 1)
assert.equal(p.versions.mod.reduce((a, v) => a + v.n, 0), 1)
db.exec("DELETE FROM installs")

// the dashboard page: served without the key (it asks for it), carries no data, https only off localhost
r = await worker.fetch(new Request("http://localhost/dashboard"), env, ctx)
assert.equal(r.status, 200)
assert.match(r.headers.get("content-type"), /text\/html/)
const csp = r.headers.get("content-security-policy")
assert.match(csp, /frame-ancestors 'none'/)
assert.match(csp, /script-src 'self';/)        // no inline script can run, so a player-made name can never be code
const page = await r.text()
assert.ok(!/<script>/.test(page) && page.includes('<script src="/dashboard.js"></script>'), "no inline script")
assert.ok(!page.includes(env.DASHBOARD_KEY) && !page.includes("ARA 2026"), "no key, no data in the page")
r = await worker.fetch(new Request("http://localhost/dashboard.js"), env, ctx)
assert.match(r.headers.get("content-type"), /javascript/)
const script = await r.text()
assert.ok(script.includes("/api/summary") && script.includes("function esc("))
assert.ok(script.includes("esc(e.message"), "message escaped like other player text")
assert.ok(script.includes("playersDaily") && page.includes('id="players"'), "the players card")
// the script parses (a stray backtick or dollar-brace in String.raw would break it)
new Function(script)
r = await worker.fetch(new Request("http://stats.example.workers.dev/dashboard"), env, ctx)
assert.equal(r.status, 301)
assert.equal(r.headers.get("location"), "https://stats.example.workers.dev/dashboard")
r = await worker.fetch(new Request("http://localhost/dashboard", { method: "HEAD" }), env, ctx)
assert.equal(r.status, 200)

// first seen reads by the events_err index, not the whole table
const plan = db.prepare("EXPLAIN QUERY PLAN SELECT code, module, mod, MIN(day) AS first FROM events WHERE event = 'error' GROUP BY code, module, mod").all()
assert.ok(plan.some(p => /events_err/.test(p.detail)), JSON.stringify(plan))

// no delete route any more (no install number to delete by)
assert.equal((await post("/v1/delete", { session: id })).status, 404)

// a message with two sessions (events waiting from an earlier game): both stored
const id2 = "fedcba9876543210fedcba9876543210"
assert.equal((await post("/v1/events", { events: [{ ...base, event: "session_start" }, { ...base, session: id2, event: "session_start" }] })).status, 204)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM events WHERE session = ?").get(id2).n, 1)

// the per-session cap, counted over every day: a full session skipped, the other in the same message still stored
const count = () => db.prepare("SELECT COUNT(*) AS n FROM events").get().n
db.exec(`INSERT INTO events (day, event, session) SELECT '2026-01-01', 'session_start', '${id}' FROM (WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 1000) SELECT x FROM c)`)
let n = count()
assert.equal((await post("/v1/events", { events: [{ ...base, event: "session_start" }, { ...base, session: id2, event: "error", code: "y" }] })).status, 204)
assert.equal(count(), n + 1)

// prune: a year-old row archived
db.exec("DELETE FROM events")
db.exec(`INSERT INTO events (day, event, session) VALUES ('2020-01-05', 'session_start', '${id}')`)
db.exec(`INSERT INTO installs (day, install) VALUES ('2020-01-05', '${inst}')`)
await worker.scheduled({}, env)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM events").get().n, 0)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM installs").get().n, 0)
assert.equal(db.prepare("SELECT n FROM archive WHERE month = '2020-01'").get().n, 1)

// migrate-2026-11-19.sql: old install_seen rows in events moved to installs, then gone from events; runs twice
{
  const { readFileSync } = await import("node:fs")
  const mig = readFileSync(new URL("migrate-2026-11-19.sql", here), "utf8")
  db.exec("DELETE FROM events; DELETE FROM installs")
  db.exec(`INSERT INTO events (day, event, session, install, mod) VALUES ('${day}', 'install_seen', '', '${inst}', '1.8.1-alpha'),
    ('${day}', 'install_seen', '', '${inst}', '1.8.1-alpha'), ('${day}', 'session_start', '${id}', NULL, '1.8.1-alpha')`)
  db.exec(mig)
  db.exec(mig)
  assert.deepEqual(db.prepare("SELECT install, day, mod FROM installs").all().map(r => ({ ...r })), [{ install: inst, day, mod: "1.8.1-alpha" }])
  assert.deepEqual(db.prepare("SELECT event FROM events").all().map(r => r.event), ["session_start"])
  db.exec("DELETE FROM events; DELETE FROM installs")
}

// the board's moderation, passed on: dashboard key needed, only the listed calls, the admin token added here
{
  const seen = []
  const board = { fetch: async req => {
    seen.push({ method: req.method, url: req.url, auth: req.headers.get("authorization"), body: req.method === "POST" ? await req.text() : null })
    if (req.url.endsWith("/v1/admin/stages")) return new Response(JSON.stringify({ stages: [{ id: "ab12", name: "SS1" }] }))
    if (req.url.includes("/runs/7")) return new Response(JSON.stringify({ error: "not an admin" }), { status: 401 })
    return new Response(JSON.stringify({ ok: true }))
  } }
  const benv = { ...env, BOARD: board, BOARD_ADMIN_TOKEN: "tok" }
  const call = (method, path, e = benv, key = env.DASHBOARD_KEY, body) => worker.fetch(new Request("http://x" + path,
    { method, body, headers: key ? { authorization: "Bearer " + key } : {} }), e, ctx)
  assert.equal((await call("GET", "/api/board/stages", benv, null)).status, 401)
  assert.equal((await call("GET", "/api/board/stages", benv, "wrong")).status, 401)
  assert.equal(seen.length, 0)
  r = await call("GET", "/api/board/stages")
  assert.equal(r.status, 200)
  assert.deepEqual((await r.json()).stages[0].id, "ab12")
  assert.deepEqual(seen.pop(), { method: "GET", url: "https://board/v1/admin/stages", auth: "Bearer admin:tok", body: null })
  await call("POST", "/api/board/runs/12/hide", benv, env.DASHBOARD_KEY, JSON.stringify({ status: "ok", evil: 1 }))
  assert.deepEqual(seen.pop(), { method: "POST", url: "https://board/v1/admin/runs/12", auth: "Bearer admin:tok", body: '{"status":"hidden"}' })
  await call("POST", "/api/board/runs/12/restore")
  assert.equal(seen.pop().body, '{"status":"ok"}')
  await call("POST", "/api/board/runs/12/move")
  assert.equal(seen.pop().url, "https://board/v1/admin/runs/12/move")
  await call("POST", "/api/board/runs/12/approve")
  assert.equal(seen.pop().url, "https://board/v1/admin/runs/12/approve")
  await call("POST", "/api/board/players/00ff/ban")
  assert.deepEqual(seen.pop(), { method: "POST", url: "https://board/v1/admin/players/00ff", auth: "Bearer admin:tok", body: '{"banned":true}' })
  await call("POST", "/api/board/players/00ff/unban")
  assert.equal(seen.pop().body, '{"banned":false}')
  await call("GET", "/api/board/stages/ab12/runs")
  assert.equal(seen.pop().url, "https://board/v1/admin/stages/ab12/runs")
  await call("GET", "/api/board/flagged")
  assert.equal(seen.pop().url, "https://board/v1/admin/flagged")
  // nothing else passed on
  for (const [m, pth] of [["GET", "/api/board/players"], ["POST", "/api/board/stages"], ["GET", "/api/board/runs/1/move"],
    ["POST", "/api/board/runs/../players/x/ban"], ["POST", "/api/board/runs/1/delete"], ["DELETE", "/api/board/runs/1"]]) {
    assert.equal((await call(m, pth)).status, 404, m + " " + pth)
  }
  assert.equal(seen.length, 0)
  // the board refusing our token: a 502 (a 401 would make the page forget the dashboard key)
  r = await call("GET", "/api/board/runs/7")
  assert.equal(r.status, 502)
  assert.match((await r.json()).error, /BOARD_ADMIN_TOKEN/)
  // no token set: said so, nothing sent
  r = await call("GET", "/api/board/stages", { ...env, BOARD: board })
  assert.equal(r.status, 503)
  assert.equal(seen.length, 1)
  // no binding: the public address
  const realFetch = globalThis.fetch
  let got = null
  globalThis.fetch = async (u, init) => { got = [u, init.headers.authorization]; return new Response("{}") }
  r = await call("GET", "/api/board/flagged", { ...env, BOARD_ADMIN_TOKEN: "tok" })
  assert.deepEqual(got, ["https://earth-rally-board.station68.workers.dev/v1/admin/flagged", "Bearer admin:tok"])
  globalThis.fetch = async () => { throw new Error("down") }
  assert.equal((await call("GET", "/api/board/flagged", { ...env, BOARD_ADMIN_TOKEN: "tok" })).status, 502)
  globalThis.fetch = realFetch
  // the page's Leaderboards tab never holds the token
  const js = await (await worker.fetch(new Request("http://localhost/dashboard.js"), benv, ctx)).text()
  assert.ok(!js.includes("tok\"") && js.includes("/api/board/") && !js.includes("ADMIN_TOKEN"))
}

console.log("test_worker: all passed")
