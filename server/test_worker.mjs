// Offline test of the stats Worker: D1 stood in by Node's built-in SQLite (Node 22.5+), no install needed.
//   node server/test_worker.mjs
import { DatabaseSync } from "node:sqlite"
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const here = new URL(".", import.meta.url)
const db = new DatabaseSync(":memory:")
db.exec(readFileSync(new URL("schema.sql", here), "utf8"))

// D1's surface as worker.js uses it: prepare().bind().first()/all()/run(), batch()
class Stmt {
  constructor(sql, args = []) { this.sql = sql; this.args = args }
  bind(...a) { return new Stmt(this.sql, a) }
  exec() {
    const s = db.prepare(this.sql)
    const named = this.sql.includes("?1")
    const args = named ? Object.fromEntries(this.args.map((v, i) => [String(i + 1), v])) : this.args
    if (/^\s*(SELECT|WITH)/i.test(this.sql)) return { results: named ? s.all(args) : s.all(...args) }
    named ? s.run(args) : s.run(...args)
    return { results: [] }
  }
  async first() { return this.exec().results[0] }
  async all() { return this.exec() }
  async run() { return this.exec() }
}
const env = { DB: { prepare: sql => new Stmt(sql), batch: async list => list.map(s => s.exec()) }, DASHBOARD_KEY: "k".repeat(32) }
globalThis.caches = { default: { match: async () => null, put: async () => {} } }
globalThis.fetch = async () => new Response(JSON.stringify([{ tag_name: "v1.6.2-alpha", assets: [{ download_count: 12 }] }]))
const ctx = { waitUntil() {} }

const worker = (await import(new URL("src/worker.js", here))).default
const { clean } = await import(new URL("src/worker.js", here))
const post = (path, body) => worker.fetch(new Request("http://x" + path, { method: "POST", body: JSON.stringify(body) }), env, ctx)

const id = "0123456789abcdef0123456789abcdef"
const day = new Date().toISOString().slice(0, 10)
const base = { install: id, mod: "1.6.2-alpha+stats", game: "0.40.5.0", earth: "1.10", day }

// clean: unknown events, bad ids and extra fields refused
assert.equal(clean({ ...base, event: "nope" }), null)
assert.equal(clean({ ...base, event: "session_start", install: "Bob" }), null)
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
assert.equal(s.totals.installs, 1)
assert.equal(s.totals.started, 2)
assert.equal(s.totals.finished, 2)
assert.equal(s.stages[0].runs, 2)
assert.equal(s.stages[0].median_s, 410)
assert.equal(s.errors[0].code, "menu_action_drive")
assert.equal(s.downloads[0].downloads, 12)

// the per-day cap
db.exec(`INSERT INTO events (day, event, install) SELECT '${day}', 'session_start', '${id}' FROM (WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 400) SELECT x FROM c)`)
assert.equal((await post("/v1/events", { events: [{ ...base, event: "session_start" }] })).status, 429)

// delete
assert.equal((await post("/v1/delete", { install: id })).status, 204)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM events").get().n, 0)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM deletes").get().n, 1)

// prune: a year-old row archived
db.exec(`INSERT INTO events (day, event, install) VALUES ('2020-01-05', 'session_start', '${id}')`)
await worker.scheduled({}, env)
assert.equal(db.prepare("SELECT COUNT(*) AS n FROM events").get().n, 0)
assert.equal(db.prepare("SELECT n FROM archive WHERE month = '2020-01'").get().n, 1)

console.log("test_worker: all passed")
