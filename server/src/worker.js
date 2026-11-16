// Earth Rally stats Worker (+stats). Takes the mod's anonymous events over plain HTTP, stores them in D1, and answers
// the owner's dashboard. Setup: server/README.md. Privacy: PRIVACY.md.
//
//   POST /v1/events   { events: [...] }   from the mod (stats.lua), at most MAX_EVENTS a message
//   GET  /api/summary?days=30             the dashboard's numbers; needs  Authorization: Bearer <DASHBOARD_KEY>
//   GET  /                                one line saying what this is
//
// Each event carries a session number: random, made new each time the game starts, never reused, so there
// is no install to link sessions by, and nothing to delete by. Never stored: the IP address (never read here),
// headers, anything not in EVENTS.

const MAX_BODY = 32 * 1024
const MAX_EVENTS = 50
const MAX_PER_SESSION = 1000
const KEEP_DAYS = 365
const REPO = "DeRamp/BeamNG.Earth.Rally"
const PRIVACY = `https://github.com/${REPO}/blob/main/PRIVACY.md`

// event -> its own fields (the common ones: session, mod, game, earth, day)
const EVENTS = {
  session_start: [],
  stage_started: ["rally", "stage", "pass", "line"],
  stage_finished: ["rally", "stage", "pass", "result", "time_s", "resets", "line"],
  rally_started: ["rally", "stages_total"],
  rally_finished: ["rally", "stages_done", "stages_total"],
  recce_done: ["result"],
  error: ["code", "module"],
}
const NUMBERS = { pass: [0, 999], time_s: [0, 86400], resets: [0, 9999], stages_total: [0, 999], stages_done: [0, 999] }
const COLUMNS = ["day", "event", "session", "mod", "game", "earth", "rally", "stage", "pass", "result", "time_s",
  "resets", "line", "stages_done", "stages_total", "code", "module"]

const text = (s, n = 80) => (typeof s === "string" || typeof s === "number") ? String(s).slice(0, n) : null
const today = () => new Date().toISOString().slice(0, 10)
const daysAgo = n => new Date(Date.now() - n * 86400000).toISOString().slice(0, 10)

// One event checked and cut down to its columns, or null.
export function clean(e) {
  if (!e || typeof e !== "object" || !EVENTS[e.event]) return null
  if (typeof e.session !== "string" || !/^[0-9a-f]{32}$/.test(e.session)) return null
  // the player's day, unless it is far off (a wrong clock): then ours
  const day = typeof e.day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(e.day) && e.day >= daysAgo(2) && e.day <= daysAgo(-2) ? e.day : today()
  const row = { day, event: e.event, session: e.session, mod: text(e.mod, 40), game: text(e.game, 40), earth: text(e.earth, 20) }
  for (const f of EVENTS[e.event]) {
    const v = e[f]
    if (v === undefined || v === null) continue
    if (NUMBERS[f]) {
      const n = Math.round(Number(v))
      if (Number.isFinite(n) && n >= NUMBERS[f][0] && n <= NUMBERS[f][1]) row[f] = n
    } else row[f] = text(v)
  }
  return row
}

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json", "cache-control": "no-store" } })
const empty = status => new Response(null, { status })

async function readBody(req) {
  const len = Number(req.headers.get("content-length") || 0)
  if (len > MAX_BODY) return null
  const raw = await req.text()
  if (raw.length > MAX_BODY) return null
  try { return JSON.parse(raw) } catch { return null }
}

// A message can hold several sessions (events waiting from an earlier game). Each session is capped at
// MAX_PER_SESSION rows in all, so one broken client cannot fill the database; a session over it is skipped.
async function postEvents(req, env) {
  const body = await readBody(req)
  if (!body || !Array.isArray(body.events) || body.events.length > MAX_EVENTS) return empty(400)
  const rows = body.events.map(clean).filter(Boolean)
  const bySession = new Map()
  for (const r of rows) bySession.set(r.session, [...(bySession.get(r.session) || []), r])
  const sql = `INSERT INTO events (${COLUMNS.join(", ")}) VALUES (${COLUMNS.map(() => "?").join(", ")})`
  const inserts = []
  for (const [session, mine] of bySession) {
    const { n } = await env.DB.prepare("SELECT COUNT(*) AS n FROM events WHERE session = ?").bind(session).first()
    if (n + mine.length > MAX_PER_SESSION) continue
    for (const r of mine) inserts.push(env.DB.prepare(sql).bind(...COLUMNS.map(c => r[c] ?? null)))
  }
  if (inserts.length) await env.DB.batch(inserts)
  return empty(204)
}

// GitHub's download counts, cached an hour (the API allows 60 unauthenticated calls an hour)
async function downloads(ctx) {
  const url = `https://api.github.com/repos/${REPO}/releases?per_page=100`
  const cache = caches.default
  let res = await cache.match(url)
  if (!res) {
    res = await fetch(url, { headers: { "user-agent": "earth-rally-stats", accept: "application/vnd.github+json" } })
    if (!res.ok) return null
    res = new Response(res.body, res)
    res.headers.set("cache-control", "max-age=3600")
    ctx.waitUntil(cache.put(url, res.clone()))
  }
  const releases = await res.json()
  return releases.map(r => ({ release: r.tag_name || r.name,
    downloads: (r.assets || []).reduce((a, x) => a + (x.download_count || 0), 0) }))
}

function median(a) {
  if (!a.length) return null
  const s = [...a].sort((x, y) => x - y), m = s.length >> 1
  return s.length % 2 ? s[m] : Math.round((s[m - 1] + s[m]) / 2)
}

async function summary(url, env, ctx) {
  const days = Math.min(Math.max(Number(url.searchParams.get("days")) || 30, 1), KEEP_DAYS)
  const since = daysAgo(days - 1)
  const q = (sql, ...b) => env.DB.prepare(sql).bind(...b)
  const [tot, daily, stages, times, rallies, mods, games, earths, errors] = await env.DB.batch([
    q(`SELECT
         (SELECT COUNT(DISTINCT session) FROM events) AS sessions_ever,
         (SELECT COUNT(DISTINCT session) FROM events WHERE day >= ?1) AS sessions,
         (SELECT COUNT(*) FROM events WHERE day >= ?1 AND event = 'stage_started') AS started,
         (SELECT COUNT(*) FROM events WHERE day >= ?1 AND event = 'stage_finished' AND result = 'finished') AS finished,
         (SELECT COUNT(*) FROM events WHERE day >= ?1 AND event = 'rally_finished') AS rallies_finished,
         (SELECT MIN(day) FROM events) AS since`, since),
    q(`SELECT day, SUM(event = 'stage_started') AS started, SUM(event = 'stage_finished' AND result = 'finished') AS finished
         FROM events WHERE day >= ? GROUP BY day ORDER BY day`, since),
    q(`SELECT rally, stage,
         SUM(event = 'stage_started') AS runs, COUNT(DISTINCT session) AS sessions,
         SUM(event = 'stage_finished' AND result = 'finished') AS finished,
         SUM(event = 'stage_finished' AND result = 'failed') AS failed,
         SUM(event = 'stage_finished' AND result = 'quit') AS quit,
         AVG(CASE WHEN event = 'stage_finished' THEN resets END) AS resets
         FROM events WHERE day >= ? AND event IN ('stage_started', 'stage_finished')
         GROUP BY rally, stage ORDER BY runs DESC LIMIT 200`, since),
    q(`SELECT rally, stage, time_s FROM events WHERE day >= ? AND event = 'stage_finished' AND result = 'finished'
         AND time_s IS NOT NULL LIMIT 50000`, since),
    q(`SELECT rally, MAX(stages_total) AS stages, SUM(event = 'rally_started') AS started,
         SUM(event = 'rally_finished') AS finished, COUNT(DISTINCT session) AS sessions
         FROM events WHERE day >= ? AND event IN ('rally_started', 'rally_finished') GROUP BY rally ORDER BY started DESC`, since),
    q(`SELECT mod AS v, COUNT(DISTINCT session) AS n FROM events WHERE day >= ? GROUP BY mod ORDER BY n DESC`, since),
    q(`SELECT game AS v, COUNT(DISTINCT session) AS n FROM events WHERE day >= ? GROUP BY game ORDER BY n DESC`, since),
    q(`SELECT earth AS v, COUNT(DISTINCT session) AS n FROM events WHERE day >= ? GROUP BY earth ORDER BY n DESC`, since),
    q(`SELECT code, module, mod, COUNT(*) AS times, COUNT(DISTINCT session) AS sessions, MIN(day) AS first, MAX(day) AS last
         FROM events WHERE event = 'error' AND day >= ? GROUP BY code, module, mod ORDER BY sessions DESC LIMIT 100`, since),
  ])
  const byStage = {}
  for (const t of times.results) (byStage[t.rally + "\u0000" + t.stage] ||= []).push(t.time_s)
  const stageRows = stages.results.map(s => ({ ...s, median_s: median(byStage[s.rally + "\u0000" + s.stage] || []) }))
  return json({
    days, since, totals: tot.results[0], daily: daily.results,
    stages: stageRows, rallies: rallies.results, versions: { mod: mods.results, game: games.results, earth: earths.results },
    errors: errors.results, downloads: await downloads(ctx).catch(() => null),
  })
}

// Kept a year: older rows are added to the monthly totals and deleted.
async function prune(env) {
  const cut = daysAgo(KEEP_DAYS)
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO archive (month, event, rally, stage, result, n)
      SELECT substr(day, 1, 7), event, rally, stage, result, COUNT(*) FROM events WHERE day < ?
      GROUP BY substr(day, 1, 7), event, rally, stage, result`).bind(cut),
    env.DB.prepare("DELETE FROM events WHERE day < ?").bind(cut),
  ])
}

function authorised(req, env) {
  const key = env.DASHBOARD_KEY
  const got = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "")
  if (!key || got.length !== key.length) return false
  let d = 0
  for (let i = 0; i < key.length; i++) d |= key.charCodeAt(i) ^ got.charCodeAt(i)
  return d === 0
}

export default {
  async fetch(req, env, ctx) {
    const url = new URL(req.url)
    try {
      if (req.method === "POST" && url.pathname === "/v1/events") return await postEvents(req, env)
      if (req.method === "GET" && url.pathname === "/api/summary") {
        if (!authorised(req, env)) return empty(401)
        return await summary(url, env, ctx)
      }
      if (req.method === "GET" && url.pathname === "/") {
        return new Response(`Earth Rally anonymous stats. What is kept and why: ${PRIVACY}\n`, { headers: { "content-type": "text/plain" } })
      }
      return empty(404)
    } catch (err) {
      console.error(String(err && err.message || err))
      return empty(500)
    }
  },
  async scheduled(_event, env) { await prune(env) },
}
