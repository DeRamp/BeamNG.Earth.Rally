// See the real dashboard on made-up data, with nothing deployed:  node server/preview.mjs  then open
// http://localhost:8787/dashboard  (key: preview). The Worker runs as is; D1 is Node's SQLite (d1shim.mjs) filled
// with 90 days of fake sessions. Downloads are the real ones: the page reads them from GitHub itself.
import { createServer } from "node:http"
import { makeDb } from "./d1shim.mjs"

const PORT = Number(process.env.PORT) || 8787
const { db, D1 } = makeDb()
const env = { DB: D1, DASHBOARD_KEY: "preview" }
globalThis.caches = { default: { match: async () => null, put: async () => {} } }
globalThis.fetch = async () => new Response(JSON.stringify([
  ["v1.6.2-alpha", 412], ["v1.6.1-alpha", 288], ["v1.6.0-alpha", 251], ["ara-2026-pack", 199], ["v1.5.0-alpha", 134],
].map(([tag_name, n]) => ({ tag_name, assets: [{ download_count: n }] }))))
const worker = (await import("./src/worker.js")).default

// ---- fake data
let seed = 7
const rnd = () => (seed = (seed * 9301 + 49297) % 233280) / 233280
const pick = a => a[Math.floor(rnd() * a.length)]
const hex = () => Array.from({ length: 32 }, () => Math.floor(rnd() * 16).toString(16)).join("")
const rallies = [
  { rally: "ARA Rally 2026: Oregon Trail", stages: ["SS1 Dalton", "SS2 Cold Springs", "SS3 Hilltop", "SS4 Pine Ridge"], mins: [6, 7, 5, 9] },
  { rally: "ARA Rally 2026: Sno*Drift", stages: ["SS1 Wildcat", "SS2 Lake Shore", "SS3 Ironwood"], mins: [8, 6, 7] },
  { rally: "Warden Test Rally", stages: ["SS1 Warden", "SS2 Mill Creek", "SS3 Ridge"], mins: [4, 3, 5] },
]
const ins = db.prepare(`INSERT INTO events (day, event, session, mod, game, earth, rally, stage, pass, result, time_s, resets,
  stages_done, stages_total, code, module, message, car, cls) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
const add = (e) => ins.run(e.day, e.event, e.session, e.mod, e.game, e.earth, e.rally ?? null, e.stage ?? null, e.pass ?? null,
  e.result ?? null, e.time_s ?? null, e.resets ?? null, e.stages_done ?? null, e.stages_total ?? null, e.code ?? null, e.module ?? null,
  e.message ?? null, e.car ?? null, e.cls ?? null)
const errs = [["notes_nil_pace", "pacenotes", "attempt to index a nil value (field 'pace')"],
  ["area_dl_timeout", "autoRecce", "area download timed out after 120 s"], ["menu_action_drive", "main", "no vehicle to drive"]]
const cars = ["Hirochi Sunburst", "Ibishu Covet", "Cherrier FCV", "Gavril D-Series", "ETK 800-Series", "Bruckell Bastion"]
for (let d = 89; d >= 0; d--) {
  const day = new Date(Date.now() - d * 86400000).toISOString().slice(0, 10)
  const wk = [0, 6].includes(new Date(day).getUTCDay()) ? 1.6 : 1
  const sessions = Math.round((8 + (90 - d) * 0.12 + rnd() * 6) * wk)
  for (let k = 0; k < sessions; k++) {
    const c = { day, session: hex(), mod: d > 40 ? pick(["1.6.1-alpha", "1.6.2-alpha"]) : pick(["1.6.2-alpha", "1.6.2-alpha", "1.7.0-alpha"]),
      game: rnd() < 0.9 ? "0.40.5.0" : "0.40.4.0", earth: rnd() < 0.8 ? "1.10" : "1.9" }
    add({ ...c, event: "session_start" })
    const own = rnd() < 0.2
    const r = own ? null : pick(rallies)
    const full = !own && rnd() < 0.3
    const n = own ? 1 + Math.floor(rnd() * 3) : full ? r.stages.length : 1 + Math.floor(rnd() * 2)
    if (full) add({ ...c, event: "rally_started", rally: r.rally, stages_total: r.stages.length })
    let done = 0
    for (let i = 0; i < n; i++) {
      const si = full ? i : Math.floor(rnd() * (own ? 1 : r.stages.length))
      const name = own ? ["custom", "custom"] : [r.rally, r.stages[si]]
      add({ ...c, event: "stage_started", rally: name[0], stage: name[1], pass: si + 1 })
      const x = rnd(), result = x < 0.72 ? "finished" : x < 0.86 ? "failed" : "quit"
      add({ ...c, event: "stage_finished", rally: name[0], stage: name[1], pass: si + 1, result, resets: Math.floor(rnd() * rnd() * 4),
        car: pick(cars), cls: rnd() < 0.7 ? "stock" : "open",
        time_s: result === "finished" ? Math.round(((own ? 5 : r.mins[si]) + rnd() * 2) * 60) : null })
      if (result === "finished") done++
      else if (full) break
    }
    if (full && done === r.stages.length) add({ ...c, event: "rally_finished", rally: r.rally, stages_done: done, stages_total: done })
    if (rnd() < 0.04) { const [code, module, message] = pick(errs.slice(0, d < 20 ? 3 : 2)); add({ ...c, event: "error", code, module, message }) }
  }
}

// ---- serve: the Worker as is, plus the key filled in on the preview's dashboard only
createServer(async (req, res) => {
  const chunks = []
  for await (const ch of req) chunks.push(ch)
  const body = chunks.length ? Buffer.concat(chunks) : undefined
  const r = await worker.fetch(new Request("http://localhost:" + PORT + req.url, { method: req.method, headers: req.headers, body }), env, { waitUntil() {} })
  let out = Buffer.from(await r.arrayBuffer())
  if (req.url.startsWith("/dashboard.js")) {
    out = Buffer.from("localStorage.setItem('earthRallyDashboardKey', 'preview');\n" + out.toString())
  }
  res.writeHead(r.status, Object.fromEntries(r.headers))
  res.end(out)
}).listen(PORT, () => console.log("preview: http://localhost:" + PORT + "/dashboard  (key: preview)"))
