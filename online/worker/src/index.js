// Earth Rally online board: a Cloudflare Worker over a D1 database (schema.sql). The players' times only: the real
// results of a rally pack (the offline leaderboard) never come here. docs/research-online-leaderboards.md.
//
// API (JSON in and out; a player's calls carry `Authorization: Bearer <id>:<secret>`):
//   POST /v1/players               { name }                      -> { id, secret, name }
//   POST /v1/players/me            { name }                      -> { name }                (rename)
//   POST /v1/runs/start            { stage }                     -> { token, stageId }
//   POST /v1/runs                  { token, board, car, timeMs, penaltyMs, trace, modVersion }
//                                                                -> { runId, status, flags, best, pos, of }
//   POST /v1/boards                { stage, board, top, around, n } -> { stage, board, rows, of, you }
//   POST /v1/reports               { runId, why }                -> { ok }
//   POST /v1/admin/runs/:id        { status: ok | hidden | flagged } (Bearer admin:<ADMIN_TOKEN>)
//   POST /v1/admin/players/:id     { banned: true | false }      (Bearer admin:<ADMIN_TOKEN>)
//   GET  /v1/admin/flagged                                       -> { runs }
//   GET  /v1/health                                              -> { ok, version }
// A stage is described, never named by a key: { name, rally, start: [lat, lon], finish: [lat, lon], lengthM }.
// The server finds the stage within a tolerance (checks.stageDistance), so players whose lines differ by a few
// metres share a board. Boards: 'stock' (the game's own cars as they come) and 'open' (anything).

import { LIMITS, cleanName, cleanStage, stageDistance, startBox, checkRun, hardFlags } from "./checks.js"

const VERSION = "0.1.0"         // (not exported: workerd takes every export of the main module as a handler)
const BOARDS = new Set(["stock", "open"])
const RATE = { any: 60, submit: 6, register: 5 }          // per minute (register: per address)
const BODY_MAX = 512 * 1024

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status }
}
const fail = (status, message) => { throw new HttpError(status, message) }

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
})

async function sha256(s) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, "0")).join("")
}
function randomHex(bytes) {
  const a = new Uint8Array(bytes)
  crypto.getRandomValues(a)
  return [...a].map(b => b.toString(16).padStart(2, "0")).join("")
}
// Constant-time string compare (for the admin token).
function sameText(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false
  let x = 0
  for (let i = 0; i < a.length; i++) x |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return x === 0
}

async function body(req) {
  const len = Number(req.headers.get("content-length") || 0)
  if (len > BODY_MAX) fail(413, "too large")
  const text = await req.text()
  if (text.length > BODY_MAX) fail(413, "too large")
  if (!text) return {}
  try {
    const v = JSON.parse(text)
    if (!v || typeof v !== "object" || Array.isArray(v)) fail(400, "a JSON object is needed")
    return v
  } catch (e) {
    if (e instanceof HttpError) throw e
    fail(400, "bad JSON")
  }
}

function bearer(req) {
  const h = req.headers.get("authorization") || ""
  const m = /^Bearer ([^:\s]+):(\S+)$/.exec(h)
  return m ? { id: m[1], secret: m[2] } : null
}

async function rateLimit(db, key, max, now) {
  const win = Math.floor(now / 60000)
  const row = await db.prepare(
    "INSERT INTO hits (key, win, n) VALUES (?, ?, 1) ON CONFLICT (key, win) DO UPDATE SET n = n + 1 RETURNING n",
  ).bind(key, win).first()
  if (row && row.n > max) fail(429, "too many requests: wait a minute")
  // (old windows cleared now and then)
  if (Math.random() < 0.02) await db.prepare("DELETE FROM hits WHERE win < ?").bind(win - 60).run()
}

async function player(env, req, now) {
  const b = bearer(req)
  if (!b) fail(401, "no player")
  const p = await env.DB.prepare("SELECT id, name, secret_hash, banned FROM players WHERE id = ?").bind(b.id).first()
  if (!p || !sameText(p.secret_hash, await sha256(b.secret))) fail(401, "unknown player")
  if (p.banned) fail(403, "this player is banned")
  await rateLimit(env.DB, "p:" + p.id, RATE.any, now)
  return p
}

function admin(env, req) {
  const b = bearer(req)
  if (!env.ADMIN_TOKEN || !b || b.id !== "admin" || !sameText(b.secret, env.ADMIN_TOKEN)) fail(401, "not an admin")
}

// The stage row a description matches (the nearest), or null.
async function findStage(db, st) {
  const [la0, la1, lo0, lo1] = startBox(st)
  const { results } = await db.prepare(
    "SELECT * FROM stages WHERE start_lat BETWEEN ? AND ? AND start_lon BETWEEN ? AND ?",
  ).bind(la0, la1, lo0, lo1).all()
  let best = null, bestD = Infinity
  for (const r of results || []) {
    const d = stageDistance(r, st)
    if (d !== null && d < bestD) { best = r; bestD = d }
  }
  return best
}

async function findOrMakeStage(db, st, now) {
  const found = await findStage(db, st)
  if (found) return found
  const id = randomHex(8)
  await db.prepare(
    "INSERT INTO stages (id, name, rally, start_lat, start_lon, finish_lat, finish_lon, length_m, created_at) " +
    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
  ).bind(id, st.name, st.rally, st.start[0], st.start[1], st.finish[0], st.finish[1], st.lengthM, now).run()
  return db.prepare("SELECT * FROM stages WHERE id = ?").bind(id).first()
}

const stageOut = s => s && ({ id: s.id, name: s.name, rally: s.rally, lengthM: s.length_m })

// Each player's best ok run on a stage's board, worked out again (after a run is hidden or a player banned).
async function rebest(db, stageId, board, playerId) {
  const r = await db.prepare(
    "SELECT id, time_ms FROM runs WHERE stage_id = ? AND board = ? AND player_id = ? AND status = 'ok' " +
    "ORDER BY time_ms, id LIMIT 1",
  ).bind(stageId, board, playerId).first()
  if (r) {
    await db.prepare(
      "INSERT INTO best (stage_id, board, player_id, run_id, time_ms) VALUES (?, ?, ?, ?, ?) " +
      "ON CONFLICT (stage_id, board, player_id) DO UPDATE SET run_id = excluded.run_id, time_ms = excluded.time_ms",
    ).bind(stageId, board, playerId, r.id, r.time_ms).run()
  } else {
    await db.prepare("DELETE FROM best WHERE stage_id = ? AND board = ? AND player_id = ?")
      .bind(stageId, board, playerId).run()
  }
}

const LIVE = "FROM best b JOIN players p ON p.id = b.player_id JOIN runs r ON r.id = b.run_id " +
  "WHERE b.stage_id = ? AND b.board = ? AND p.banned = 0"

async function placeOf(db, stageId, board, timeMs) {
  const r = await db.prepare(`SELECT COUNT(*) AS n ${LIVE} AND b.time_ms < ?`).bind(stageId, board, timeMs).first()
  return (r ? r.n : 0) + 1
}

// A board: the top rows, and the rows either side of `around` (a player id) when it is placed below them.
async function boardOf(db, stage, board, top, around, n) {
  const ofRow = await db.prepare(`SELECT COUNT(*) AS n ${LIVE}`).bind(stage.id, board).first()
  const of = ofRow ? ofRow.n : 0
  const cols = "SELECT b.time_ms AS timeMs, b.player_id AS pid, p.name AS name, r.car AS car, r.id AS runId"
  const { results: topRows } = await db.prepare(`${cols} ${LIVE} ORDER BY b.time_ms, b.run_id LIMIT ?`)
    .bind(stage.id, board, top).all()
  const rows = []
  for (const r of topRows || []) rows.push({ ...r, pos: await placeOf(db, stage.id, board, r.timeMs) })
  let you = null
  if (around) {
    const mine = await db.prepare(`${cols} ${LIVE} AND b.player_id = ?`).bind(stage.id, board, around).first()
    if (mine) {
      you = { pos: await placeOf(db, stage.id, board, mine.timeMs), timeMs: mine.timeMs, runId: mine.runId }
      if (!rows.some(r => r.pid === around)) {
        const { results: before } = await db.prepare(
          `${cols} ${LIVE} AND (b.time_ms < ? OR (b.time_ms = ? AND b.run_id < ?)) ORDER BY b.time_ms DESC, b.run_id DESC LIMIT ?`,
        ).bind(stage.id, board, mine.timeMs, mine.timeMs, mine.runId, n).all()
        const { results: after } = await db.prepare(
          `${cols} ${LIVE} AND (b.time_ms > ? OR (b.time_ms = ? AND b.run_id > ?)) ORDER BY b.time_ms, b.run_id LIMIT ?`,
        ).bind(stage.id, board, mine.timeMs, mine.timeMs, mine.runId, n).all()
        const near = [...(before || []).reverse(), mine, ...(after || [])].filter(r => !rows.some(x => x.runId === r.runId))
        let skipped = true
        for (const r of near) {
          rows.push({ ...r, pos: await placeOf(db, stage.id, board, r.timeMs), skipped: skipped || undefined })
          skipped = false
        }
      }
    }
  }
  const leader = rows.length ? rows[0].timeMs : null
  return {
    stage: stageOut(stage), board, of, you,
    rows: rows.map(r => ({ pos: r.pos, name: r.name, car: r.car, timeMs: r.timeMs, gapMs: leader === null ? 0 : r.timeMs - leader,
      runId: r.runId, you: r.pid === around || undefined, skipped: r.skipped })),
  }
}

async function route(req, env) {
  const url = new URL(req.url)
  const path = url.pathname.replace(/\/+$/, "")
  const now = Date.now()
  const db = env.DB
  const ip = req.headers.get("cf-connecting-ip") || "local"

  if (req.method === "GET" && path === "/v1/health") return json({ ok: true, version: VERSION })

  if (req.method === "POST" && path === "/v1/players") {
    await rateLimit(db, "ip:" + ip, RATE.register, now)
    const b = await body(req)
    const n = cleanName(b.name)
    if (n.error) fail(400, n.error)
    const taken = await db.prepare("SELECT 1 FROM players WHERE name = ? COLLATE NOCASE").bind(n.name).first()
    if (taken) fail(409, "that name is taken")
    const id = randomHex(12), secret = randomHex(24)
    await db.prepare("INSERT INTO players (id, secret_hash, name, created_at) VALUES (?, ?, ?, ?)")
      .bind(id, await sha256(secret), n.name, now).run()
    return json({ id, secret, name: n.name })
  }

  if (req.method === "POST" && path === "/v1/players/me") {
    const p = await player(env, req, now)
    const n = cleanName((await body(req)).name)
    if (n.error) fail(400, n.error)
    const taken = await db.prepare("SELECT id FROM players WHERE name = ? COLLATE NOCASE").bind(n.name).first()
    if (taken && taken.id !== p.id) fail(409, "that name is taken")
    await db.prepare("UPDATE players SET name = ? WHERE id = ?").bind(n.name, p.id).run()
    return json({ name: n.name })
  }

  if (req.method === "POST" && path === "/v1/runs/start") {
    const p = await player(env, req, now)
    const s = cleanStage((await body(req)).stage)
    if (s.error) fail(400, s.error)
    const stage = await findOrMakeStage(db, s.stage, now)
    const token = randomHex(16)
    await db.prepare("INSERT INTO tokens (token, player_id, stage_id, issued_at) VALUES (?, ?, ?, ?)")
      .bind(token, p.id, stage.id, now).run()
    return json({ token, stageId: stage.id })
  }

  if (req.method === "POST" && path === "/v1/runs") {
    const p = await player(env, req, now)
    await rateLimit(db, "s:" + p.id, RATE.submit, now)
    const b = await body(req)
    if (!BOARDS.has(b.board)) fail(400, "board is stock or open")
    const t = typeof b.token === "string" &&
      await db.prepare("SELECT * FROM tokens WHERE token = ?").bind(b.token).first()
    if (!t || t.player_id !== p.id) fail(400, "unknown run token")
    if (t.used) fail(409, "this run was sent already")
    if (now - t.issued_at > LIMITS.TOKEN_MAX_AGE_MS) fail(400, "the run token is too old")
    // (used before anything else can fail, so a run is never counted twice)
    const claim = await db.prepare("UPDATE tokens SET used = 1 WHERE token = ? AND used = 0").bind(b.token).run()
    if (claim.meta && claim.meta.changes === 0) fail(409, "this run was sent already")
    const stage = await db.prepare("SELECT * FROM stages WHERE id = ?").bind(t.stage_id).first()
    if (!stage) fail(400, "unknown stage")
    const run = { timeMs: b.timeMs, penaltyMs: b.penaltyMs ?? 0, trace: b.trace }
    const c = checkRun(run, stage, now - t.issued_at)
    if (c.reject) fail(422, c.reject)
    const flags = [...c.flags]
    // (a time well ahead of the board's best, on a board with a few times: looked at before it shows)
    const rec = await db.prepare(`SELECT MIN(b.time_ms) AS t, COUNT(*) AS n ${LIVE}`).bind(stage.id, b.board).first()
    if (rec && rec.n >= 3 && rec.t && run.timeMs < rec.t * 0.95) flags.push("record")
    const status = hardFlags(flags).length ? "flagged" : "ok"
    const car = typeof b.car === "string" ? b.car.slice(0, LIMITS.TEXT_MAX) : null
    const ver = typeof b.modVersion === "string" ? b.modVersion.slice(0, 32) : null
    const ins = await db.prepare(
      "INSERT INTO runs (stage_id, board, player_id, car, time_ms, penalty_ms, trace, mod_version, submitted_at, " +
      "wall_ratio, status, flags) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id",
    ).bind(stage.id, b.board, p.id, car, run.timeMs, run.penaltyMs, JSON.stringify(run.trace), ver, now,
      c.wallRatio, status, flags.join(",") || null).first()
    if (status === "ok") await rebest(db, stage.id, b.board, p.id)
    const mine = await db.prepare("SELECT time_ms FROM best WHERE stage_id = ? AND board = ? AND player_id = ?")
      .bind(stage.id, b.board, p.id).first()
    const of = await db.prepare(`SELECT COUNT(*) AS n ${LIVE}`).bind(stage.id, b.board).first()
    return json({
      runId: ins.id, status, flags, stage: stageOut(stage), board: b.board,
      best: mine ? mine.time_ms : null, pos: mine ? await placeOf(db, stage.id, b.board, mine.time_ms) : null,
      of: of ? of.n : 0,
    })
  }

  if (req.method === "POST" && path === "/v1/boards") {
    const b = await body(req)
    const auth = bearer(req)
    const p = auth ? await player(env, req, now) : null
    if (!p) await rateLimit(db, "ip:" + ip, RATE.any, now)
    const s = cleanStage(b.stage)
    if (s.error) fail(400, s.error)
    const board = BOARDS.has(b.board) ? b.board : "stock"
    const top = Math.max(1, Math.min(50, Number.isInteger(b.top) ? b.top : 10))
    const n = Math.max(0, Math.min(5, Number.isInteger(b.n) ? b.n : 2))
    const stage = await findStage(db, s.stage)
    if (!stage) return json({ stage: null, board, of: 0, rows: [], you: null })
    return json(await boardOf(db, stage, board, top, p ? p.id : null, n))
  }

  if (req.method === "POST" && path === "/v1/reports") {
    const p = await player(env, req, now)
    const b = await body(req)
    if (!Number.isInteger(b.runId)) fail(400, "runId is needed")
    const r = await db.prepare("SELECT id FROM runs WHERE id = ?").bind(b.runId).first()
    if (!r) fail(404, "no such run")
    const why = typeof b.why === "string" ? b.why.slice(0, 200) : null
    await db.prepare("INSERT OR IGNORE INTO reports (run_id, player_id, why, at) VALUES (?, ?, ?, ?)")
      .bind(b.runId, p.id, why, now).run()
    return json({ ok: true })
  }

  let m
  if (req.method === "POST" && (m = /^\/v1\/admin\/runs\/(\d+)$/.exec(path))) {
    admin(env, req)
    const status = (await body(req)).status
    if (!["ok", "hidden", "flagged"].includes(status)) fail(400, "status is ok, hidden or flagged")
    const r = await db.prepare("SELECT * FROM runs WHERE id = ?").bind(Number(m[1])).first()
    if (!r) fail(404, "no such run")
    await db.prepare("UPDATE runs SET status = ? WHERE id = ?").bind(status, r.id).run()
    await rebest(db, r.stage_id, r.board, r.player_id)
    return json({ ok: true, runId: r.id, status })
  }
  if (req.method === "POST" && (m = /^\/v1\/admin\/players\/([0-9a-f]+)$/.exec(path))) {
    admin(env, req)
    const banned = (await body(req)).banned === true ? 1 : 0
    const r = await db.prepare("UPDATE players SET banned = ? WHERE id = ?").bind(banned, m[1]).run()
    if (r.meta && r.meta.changes === 0) fail(404, "no such player")
    return json({ ok: true, banned: banned === 1 })
  }
  if (req.method === "GET" && path === "/v1/admin/flagged") {
    admin(env, req)
    const { results } = await db.prepare(
      "SELECT r.id, r.stage_id AS stageId, s.name AS stage, r.board, p.name AS player, r.player_id AS playerId, " +
      "r.car, r.time_ms AS timeMs, r.flags, r.wall_ratio AS wallRatio, r.submitted_at AS at, " +
      "(SELECT COUNT(*) FROM reports x WHERE x.run_id = r.id) AS reports " +
      "FROM runs r JOIN players p ON p.id = r.player_id JOIN stages s ON s.id = r.stage_id " +
      "WHERE r.status = 'flagged' OR r.id IN (SELECT run_id FROM reports) ORDER BY r.submitted_at DESC LIMIT 200",
    ).all()
    return json({ runs: results || [] })
  }

  fail(404, "not found")
}

export default {
  async fetch(req, env) {
    try {
      return await route(req, env)
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status)
      console.error(e && e.stack || e)
      return json({ error: "server error" }, 500)
    }
  },
}
