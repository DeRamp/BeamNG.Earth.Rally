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
assert.equal(clean({ ...base, event: "error", code: "x", message: "C:/Users/Bob" }).message, undefined)
assert.equal(clean({ ...base, event: "session_start", day: "1999-01-01" }).day, day)
assert.equal(clean({ ...base, event: "stage_finished", time_s: 412.4, resets: -3 }).time_s, 412)
assert.equal(clean({ ...base, event: "stage_finished", resets: -3 }).resets, undefined)

let r = await post("/v1/events", { events: [
  { ...base, event: "session_start" },
  { ...base, event: "stage_started", rally: "ARA 2026", stage: "SS1", pass: 1 },
  { ...base, event: "stage_finished", rally: "ARA 2026", stage: "SS1", pass: 1, result: "finished", time_s: 400, resets: 1 },
  { ...base, event: "stage_started", rally: "ARA 2026", stage: "SS1", pass: 1 },
  { ...base, event: "stage_finished", rally: "ARA 2026", stage: "SS1", pass: 1, result: "finished", time_s: 420, resets: 0 },
  { ...base, event: "error", code: "menu_action_drive", module: "main" },
] })
assert.equal(r.status, 204)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM events").get().n, 6)
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
assert.equal(s.errors[0].code, "menu_action_drive")
assert.equal(s.downloads[0].downloads, 12)

assert.equal(s.errors[0].first_ever, day)
assert.equal(s.errors[0].first_code, day)

// the dashboard page: served without the key (it asks for it), carries no data, https only off localhost
r = await worker.fetch(new Request("http://localhost/dashboard"), env, ctx)
assert.equal(r.status, 200)
assert.match(r.headers.get("content-type"), /text\/html/)
assert.match(r.headers.get("content-security-policy"), /frame-ancestors 'none'/)
const page = await r.text()
assert.ok(page.includes("/api/summary") && page.includes("function esc("))
assert.ok(!page.includes(env.DASHBOARD_KEY) && !page.includes("ARA 2026"), "no key, no data in the page")
r = await worker.fetch(new Request("http://stats.example.workers.dev/dashboard"), env, ctx)
assert.equal(r.status, 301)
assert.equal(r.headers.get("location"), "https://stats.example.workers.dev/dashboard")
// the page's own script parses (a stray backtick or dollar-brace in String.raw would break it)
new Function(page.slice(page.indexOf("<script>") + 8, page.lastIndexOf("</script>")))

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
await worker.scheduled({}, env)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM events").get().n, 0)
assert.equal(db.prepare("SELECT n FROM archive WHERE month = '2020-01'").get().n, 1)

console.log("test_worker: all passed")
