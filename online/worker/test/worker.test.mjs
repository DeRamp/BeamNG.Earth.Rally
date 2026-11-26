// The online board's Worker, end to end over the D1 stand-in: node --test online/worker/test/
import { test } from "node:test"
import assert from "node:assert/strict"
import worker from "../src/index.js"
import { makeD1 } from "../dev/d1.mjs"
import { cleanName, checkRun, metres } from "../src/checks.js"

const DEG_PER_M = 1 / 111195
const STAGE = { name: "Test Road", rally: "Test Rally", start: [60, 25], finish: [60 + 10000 * DEG_PER_M, 25], lengthM: 10000 }

// A trace up the stage at an even speed: [[ms, lat, lon]...], every stepMs.
function trace(stage, ms, stepMs = 500, jumpAt = null) {
  const out = []
  for (let t = 0; t <= ms; t += stepMs) {
    let f = t / ms
    if (jumpAt !== null && f > jumpAt && f < jumpAt + 0.1) f += 0.1
    out.push([t, stage.start[0] + (stage.finish[0] - stage.start[0]) * f, stage.start[1]])
  }
  if (out[out.length - 1][0] !== ms) out.push([ms, stage.finish[0], stage.finish[1]])
  return out
}

function setup() {
  const env = { DB: makeD1(), ADMIN_TOKEN: "letmein" }
  let clock = 1_800_000_000_000
  const realNow = Date.now
  Date.now = () => clock
  const call = async (method, path, body, auth) => {
    const headers = { "content-type": "application/json" }
    if (auth) headers.authorization = `Bearer ${auth}`
    const r = await worker.fetch(new Request("http://x" + path, {
      method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    }), env)
    return { status: r.status, body: await r.json() }
  }
  const register = async name => {
    const r = await call("POST", "/v1/players", { name })
    assert.equal(r.status, 200, JSON.stringify(r.body))
    return `${r.body.id}:${r.body.secret}`
  }
  // A whole run: token, the clock moved on by the run's time, the submission.
  const drive = async (auth, ms, opts = {}) => {
    const st = opts.stage || STAGE
    const s = await call("POST", "/v1/runs/start", { stage: st }, auth)
    assert.equal(s.status, 200, JSON.stringify(s.body))
    clock += opts.wallMs ?? ms + 30000
    return call("POST", "/v1/runs", {
      token: s.body.token, board: opts.board || "stock", car: "Sunburst RS", timeMs: ms + (opts.penaltyMs || 0),
      penaltyMs: opts.penaltyMs || 0, trace: opts.trace || trace(st, ms), modVersion: "test",
    }, auth)
  }
  return { env, call, register, drive, done: () => { Date.now = realNow }, tick: ms => { clock += ms } }
}

test("names", () => {
  assert.equal(cleanName("  Ann   Driver ").name, "Ann Driver")
  assert.ok(cleanName("a").error)
  assert.ok(cleanName("x".repeat(25)).error)
  assert.ok(cleanName("<script>").error)
  assert.ok(cleanName("Sh1t driver").error)
  assert.ok(cleanName("BigShitDriver").error, "camel case split")
  assert.ok(cleanName("EarthRallyAdmin").error)
  for (const ok of ["Nazir", "Draper", "Scunthorpe", "Yoshitaka", "Grapefruit"]) assert.equal(cleanName(ok).name, ok)
  assert.equal(cleanName("Kalle Rovanperä").name, "Kalle Rovanperä")
})

test("checks on a run", () => {
  const row = { start_lat: STAGE.start[0], start_lon: STAGE.start[1], finish_lat: STAGE.finish[0], finish_lon: STAGE.finish[1], length_m: 10000 }
  const ok = checkRun({ timeMs: 360000, penaltyMs: 0, trace: trace(STAGE, 360000) }, row, 400000)
  assert.deepEqual(ok.flags, [])
  assert.ok(checkRun({ timeMs: 100000, penaltyMs: 0, trace: trace(STAGE, 100000) }, row, 400000).reject, "360 km/h average")
  assert.ok(checkRun({ timeMs: 360000, penaltyMs: 0, trace: trace(STAGE, 360000) }, row, 200000).reject, "faster than the server's clock")
  assert.ok(checkRun({ timeMs: 360000, penaltyMs: 0, trace: [] }, row, 400000).reject, "no trace")
  assert.ok(checkRun({ timeMs: 360000, penaltyMs: 0, trace: trace(STAGE, 360000, 500, 0.4) }, row, 400000).flags.includes("jump"))
  const half = { ...STAGE, finish: [STAGE.start[0] + 5000 * DEG_PER_M, 25] }
  const short = checkRun({ timeMs: 360000, penaltyMs: 0, trace: trace(half, 360000) }, row, 400000).flags
  assert.ok(short.includes("short") && short.includes("finish"))
  assert.ok(checkRun({ timeMs: 370000, penaltyMs: 0, trace: trace(STAGE, 360000) }, row, 400000).flags.includes("clock"))
  assert.deepEqual(checkRun({ timeMs: 370000, penaltyMs: 10000, trace: trace(STAGE, 360000) }, row, 400000).flags, [], "a penalty is not driving time")
  assert.ok(Math.abs(metres(...STAGE.start, ...STAGE.finish) - 10000) < 20)
  // a reset the client reported: its jump is not a teleport
  const jumpy = trace(STAGE, 360000, 500, 0.4)
  const at = jumpy.filter((p, i) => i && metres(jumpy[i - 1][1], jumpy[i - 1][2], p[1], p[2]) > 500).map(p => p[0])
  assert.equal(at.length, 2)
  assert.ok(!checkRun({ timeMs: 360000, penaltyMs: 0, trace: jumpy, resets: at.map(x => x - 200) }, row, 400000).flags.includes("jump"))
  assert.ok(checkRun({ timeMs: 360000, penaltyMs: 0, trace: jumpy, resets: [at[0] - 200] }, row, 400000).flags.includes("jump"), "a reset covers its own jump only")
  assert.ok(checkRun({ timeMs: 360000, penaltyMs: 0, trace: jumpy, resets: at.map(x => x - 60000) }, row, 400000).flags.includes("jump"))
  // resets on Stock must be paid for
  assert.ok(checkRun({ timeMs: 360000, penaltyMs: 0, trace: jumpy, resets: at.map(x => x - 200), board: "stock" }, row, 400000).flags.includes("resets"))
  assert.ok(!checkRun({ timeMs: 380000, penaltyMs: 20000, trace: jumpy, resets: at.map(x => x - 200), board: "stock" }, row, 400000).flags.includes("resets"))
  // slow motion: noted (soft until tuned in game)
  assert.ok(checkRun({ timeMs: 360000, penaltyMs: 0, trace: trace(STAGE, 360000), slowMs: 60000 }, row, 400000).flags.includes("slow"))
  assert.deepEqual(checkRun({ timeMs: 360000, penaltyMs: 0, trace: trace(STAGE, 360000), slowMs: 2000 }, row, 400000).flags, [])
})

test("register, drive, board", async () => {
  const t = setup()
  try {
    const ann = await t.register("Ann")
    assert.equal((await t.call("POST", "/v1/players", { name: "ann" })).status, 409, "names are unique, any case")
    const bob = await t.register("Bob")
    const cara = await t.register("Cara")

    const r1 = await t.drive(ann, 360000)
    assert.equal(r1.status, 200, JSON.stringify(r1.body))
    assert.equal(r1.body.status, "ok")
    assert.equal(r1.body.pos, 1)
    await t.drive(bob, 350000)
    await t.drive(cara, 370000)
    const slower = await t.drive(ann, 380000)
    assert.equal(slower.body.best, 360000, "the best stays")
    assert.equal(slower.body.pos, 2)

    // a line a few metres off finds the same stage
    const near = { ...STAGE, name: "Test Road (my pack)", start: [STAGE.start[0] + 15 * DEG_PER_M, 25.0001], lengthM: 10100 }
    const b = await t.call("POST", "/v1/boards", { stage: near, board: "stock" }, ann)
    assert.equal(b.status, 200)
    assert.equal(b.body.stage.name, "Test Road", "the first name kept")
    assert.equal(b.body.of, 3)
    assert.deepEqual(b.body.rows.map(r => r.name), ["Bob", "Ann", "Cara"])
    assert.deepEqual(b.body.rows.map(r => r.gapMs), [0, 10000, 20000])
    assert.equal(b.body.you.pos, 2)
    assert.ok(b.body.rows[1].you)

    // the open board is its own
    const o = await t.call("POST", "/v1/boards", { stage: STAGE, board: "open" })
    assert.equal(o.body.of, 0)
    await t.drive(cara, 300000, { board: "open" })
    assert.equal((await t.call("POST", "/v1/boards", { stage: STAGE, board: "open" })).body.of, 1)

    // another road: no board
    const other = { ...STAGE, start: [61, 25], finish: [61 + 10000 * DEG_PER_M, 25] }
    const none = await t.call("POST", "/v1/boards", { stage: other, board: "stock" })
    assert.equal(none.body.stage, null)
    // the same ends, another route (3 % longer): a board of its own
    const longer = await t.call("POST", "/v1/boards", { stage: { ...STAGE, lengthM: 10300 }, board: "stock" })
    assert.equal(longer.body.stage, null)
    // a stage named rudely is renamed, not refused
    const rude = await t.call("POST", "/v1/runs/start", { stage: { ...other, name: "Shit Road" } }, ann)
    assert.equal(rude.status, 200)
    assert.equal((await t.call("POST", "/v1/boards", { stage: other, board: "stock" })).body.stage.name, "Unnamed stage")
  } finally { t.done() }
})

test("you below the top rows, with your neighbours", async () => {
  const t = setup()
  try {
    let me = null
    for (let i = 0; i < 16; i++) {
      const a = await t.register(`Driver ${i}`)
      await t.drive(a, 300000 + i * 1000)
      if (i === 13) me = a
      t.tick(61000)    // (the rate limit is per minute)
    }
    const b = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock", top: 10, n: 2 }, me)
    assert.equal(b.body.you.pos, 14)
    assert.deepEqual(b.body.rows.map(r => r.pos), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16])
    assert.ok(b.body.rows[10].skipped, "a gap before your neighbours")
    assert.ok(b.body.rows[12].you)
    assert.equal(b.body.rows.filter(r => r.skipped).length, 1)
    // 11th: straight on from the top ten, no gap
    const eleventh = await t.register("Eleven")
    t.tick(61000)
    await t.drive(eleventh, 309500)
    const b11 = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock", top: 10, n: 2 }, eleventh)
    assert.equal(b11.body.you.pos, 11)
    assert.ok(!b11.body.rows.some(r => r.skipped), "no gap between 10th and 11th")
  } finally { t.done() }
})

test("cheats", async () => {
  const t = setup()
  try {
    const ann = await t.register("Ann")
    // resent
    const s = await t.call("POST", "/v1/runs/start", { stage: STAGE }, ann)
    t.tick(400000)
    const run = { token: s.body.token, board: "stock", timeMs: 360000, penaltyMs: 0, trace: trace(STAGE, 360000) }
    assert.equal((await t.call("POST", "/v1/runs", run, ann)).status, 200)
    assert.equal((await t.call("POST", "/v1/runs", run, ann)).status, 409, "one submission per token")
    // someone else's token
    const bob = await t.register("Bob")
    const s2 = await t.call("POST", "/v1/runs/start", { stage: STAGE }, ann)
    t.tick(400000)
    assert.equal((await t.call("POST", "/v1/runs", { ...run, token: s2.body.token }, bob)).status, 400)
    // a time shorter than the server saw pass
    const fast = await t.drive(bob, 360000, { wallMs: 100000 })
    assert.equal(fast.status, 422)
    t.tick(61000)
    // a teleport: kept, off the board
    const jump = await t.drive(bob, 340000, { trace: trace(STAGE, 340000, 500, 0.5) })
    assert.equal(jump.body.status, "flagged")
    assert.ok(jump.body.flags.includes("jump"))
    const b = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock" })
    assert.deepEqual(b.body.rows.map(r => r.name), ["Ann"])
    // a bad secret
    assert.equal((await t.call("POST", "/v1/runs/start", { stage: STAGE }, ann.split(":")[0] + ":nope")).status, 401)
    assert.equal((await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock" }, "gone:nope")).status, 200,
      "a board read with stale credentials is read as anyone")
    // the database failing after the token is claimed: the token given back, the retry taken
    const s3 = await t.call("POST", "/v1/runs/start", { stage: STAGE }, ann)
    t.tick(400000)
    t.tick(61000)
    const real = t.env.DB.prepare
    t.env.DB.prepare = sql => (sql.startsWith("INSERT INTO runs") ? { bind: () => ({ first: async () => { throw new Error("D1 down") } }) } : real(sql))
    assert.equal((await t.call("POST", "/v1/runs", { ...run, token: s3.body.token }, ann)).status, 500)
    t.env.DB.prepare = real
    assert.equal((await t.call("POST", "/v1/runs", { ...run, token: s3.body.token }, ann)).status, 200)
    // a failure after the run is stored: the token kept, so a retry cannot store it twice
    const s4 = await t.call("POST", "/v1/runs/start", { stage: STAGE }, ann)
    t.tick(400000)
    t.tick(61000)
    t.env.DB.prepare = sql => (sql.startsWith("SELECT time_ms FROM best") ? { bind: () => ({ first: async () => { throw new Error("D1 down") } }) } : real(sql))
    assert.equal((await t.call("POST", "/v1/runs", { ...run, token: s4.body.token }, ann)).status, 500)
    t.env.DB.prepare = real
    assert.equal((await t.call("POST", "/v1/runs", { ...run, token: s4.body.token }, ann)).status, 409)
  } finally { t.done() }
})

test("moderation", async () => {
  const t = setup()
  try {
    const ann = await t.register("Ann")
    const bob = await t.register("Bob")
    const a = await t.drive(ann, 360000)
    const b = await t.drive(bob, 350000)
    assert.equal((await t.call("POST", "/v1/reports", { runId: b.body.runId, why: "too quick" }, ann)).status, 200)
    assert.equal((await t.call("GET", "/v1/admin/flagged", undefined, "admin:wrong")).status, 401)
    const f = await t.call("GET", "/v1/admin/flagged", undefined, "admin:letmein")
    assert.deepEqual(f.body.runs.map(r => [r.id, r.reports]), [[b.body.runId, 1]])
    // hidden: off the board, Ann leads
    assert.equal((await t.call("POST", `/v1/admin/runs/${b.body.runId}`, { status: "hidden" }, "admin:letmein")).status, 200)
    let board = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock" })
    assert.deepEqual(board.body.rows.map(r => r.name), ["Ann"])
    // and dealt with: off the Flagged list and out of the stage's flagged and reported counts, its report kept
    assert.equal((await t.call("GET", "/v1/admin/flagged", undefined, "admin:letmein")).body.runs.length, 0)
    const hs = (await t.call("GET", "/v1/admin/stages", undefined, "admin:letmein")).body.stages[0]
    assert.deepEqual([hs.runs, hs.flagged, hs.reported], [2, 0, 0])
    const hr = (await t.call("GET", `/v1/admin/stages/${hs.id}/runs`, undefined, "admin:letmein")).body.runs
    assert.deepEqual(hr.filter(r => r.status === "hidden").map(r => r.reports), [1])
    // banned: off every board
    const pid = ann.split(":")[0]
    await t.call("POST", `/v1/admin/players/${pid}`, { banned: true }, "admin:letmein")
    board = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock" })
    assert.equal(board.body.of, 0)
    assert.equal((await t.call("POST", "/v1/runs/start", { stage: STAGE }, ann)).status, 403)
    assert.ok(a.body.runId)
  } finally { t.done() }
})

test("admin: stages, runs, move, approve, ban", async () => {
  const t = setup()
  const A = "admin:letmein"
  try {
    const ann = await t.register("Ann")
    const bob = await t.register("Bob")
    const a1 = await t.drive(ann, 360000)
    t.tick(61000)
    const a2 = await t.drive(ann, 355000, { board: "open" })
    const b1 = await t.drive(bob, 350000)
    await t.call("POST", "/v1/reports", { runId: b1.body.runId, why: "too quick" }, ann)
    assert.equal((await t.call("GET", "/v1/admin/stages", undefined, "admin:wrong")).status, 401)
    const st = await t.call("GET", "/v1/admin/stages", undefined, A)
    assert.equal(st.body.stages.length, 1)
    assert.deepEqual([st.body.stages[0].runs, st.body.stages[0].flagged, st.body.stages[0].reported], [3, 0, 1])
    const sid = st.body.stages[0].id
    let runs = (await t.call("GET", `/v1/admin/stages/${sid}/runs`, undefined, A)).body
    assert.equal(runs.stage.name, "Test Road")
    assert.equal(runs.runs.length, 3)
    const bob1 = runs.runs.find(r => r.id === b1.body.runId)
    assert.deepEqual([bob1.player, bob1.board, bob1.reports, bob1.reasons, bob1.isBest, bob1.banned, bob1.modVersion],
      ["Bob", "stock", 1, "too quick", true, false, "test"])
    assert.equal((await t.call("GET", "/v1/admin/stages/ffff/runs", undefined, A)).status, 404)

    // move Ann's stock run to open: stock loses her, open keeps her faster run as best
    let m = await t.call("POST", `/v1/admin/runs/${a1.body.runId}/move`, undefined, A)
    assert.deepEqual([m.status, m.body.board], [200, "open"])
    let stock = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock" })
    assert.deepEqual(stock.body.rows.map(r => r.name), ["Bob"])
    let open = await t.call("POST", "/v1/boards", { stage: STAGE, board: "open" })
    assert.deepEqual(open.body.rows.map(r => [r.name, r.runId]), [["Ann", a2.body.runId]])
    // and the open run back to stock: both boards worked out again
    await t.call("POST", `/v1/admin/runs/${a2.body.runId}/move`, undefined, A)
    stock = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock" })
    assert.deepEqual(stock.body.rows.map(r => [r.name, r.timeMs]), [["Bob", 350000], ["Ann", 355000]])
    open = await t.call("POST", "/v1/boards", { stage: STAGE, board: "open" })
    assert.deepEqual(open.body.rows.map(r => [r.name, r.runId]), [["Ann", a1.body.runId]])

    // approve a reported run: still ok, its reports gone
    await t.call("POST", `/v1/admin/runs/${b1.body.runId}`, { status: "flagged" }, A)
    stock = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock" })
    assert.deepEqual(stock.body.rows.map(r => r.name), ["Ann"])
    assert.equal((await t.call("POST", `/v1/admin/runs/${b1.body.runId}/approve`, undefined, A)).status, 200)
    stock = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock" })
    assert.deepEqual(stock.body.rows.map(r => r.name), ["Bob", "Ann"])
    assert.equal((await t.call("GET", "/v1/admin/flagged", undefined, A)).body.runs.length, 0)
    runs = (await t.call("GET", `/v1/admin/stages/${sid}/runs`, undefined, A)).body
    assert.equal(runs.runs.find(r => r.id === b1.body.runId).reports, 0)
    assert.equal((await t.call("POST", "/v1/admin/runs/99999/approve", undefined, A)).status, 404)
    assert.equal((await t.call("POST", `/v1/admin/runs/${b1.body.runId}/move`, undefined, "admin:wrong")).status, 401)

    // ban and unban: off every board, then back with the best intact
    const bid = bob.split(":")[0]
    await t.call("POST", `/v1/admin/players/${bid}`, { banned: true }, A)
    stock = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock" })
    assert.deepEqual(stock.body.rows.map(r => r.name), ["Ann"])
    runs = (await t.call("GET", `/v1/admin/stages/${sid}/runs`, undefined, A)).body
    assert.equal(runs.runs.find(r => r.id === b1.body.runId).banned, true)
    await t.call("POST", `/v1/admin/players/${bid}`, { banned: false }, A)
    stock = await t.call("POST", "/v1/boards", { stage: STAGE, board: "stock" })
    assert.deepEqual(stock.body.rows.map(r => r.name), ["Bob", "Ann"])
    assert.equal((await t.call("GET", "/v1/health")).body.version, "0.2.0")
  } finally { t.done() }
})

test("new stages a day", async () => {
  const t = setup()
  try {
    const ann = await t.register("Ann")
    let last = null
    for (let i = 0; i < 21; i++) {
      const st = { ...STAGE, start: [50 + i * 0.1, 10], finish: [50 + i * 0.1 + 10000 * DEG_PER_M, 10] }
      last = await t.call("POST", "/v1/runs/start", { stage: st }, ann)
      if (i < 20) assert.equal(last.status, 200)
      if (i % 50 === 49) t.tick(61000)
    }
    assert.equal(last.status, 429)
    assert.equal((await t.call("POST", "/v1/runs/start", { stage: STAGE.start && { ...STAGE, start: [50, 10], finish: [50 + 10000 * DEG_PER_M, 10] } }, ann)).status, 200, "a known stage still starts")
  } finally { t.done() }
})

test("rename and rate limits", async () => {
  const t = setup()
  try {
    const ann = await t.register("Ann")
    await t.register("Bob")
    assert.equal((await t.call("POST", "/v1/players/me", { name: "BOB" }, ann)).status, 409)
    assert.equal((await t.call("POST", "/v1/players/me", { name: "Annie" }, ann)).body.name, "Annie")
    for (let i = 0; i < 3; i++) await t.register(`P${i}x`)
    assert.equal((await t.call("POST", "/v1/players", { name: "Sixth" })).status, 429, "five sign-ups a minute per address")
    assert.equal((await t.call("GET", "/v1/health")).body.ok, true)
    assert.equal((await t.call("GET", "/v1/nothing")).status, 404)
  } finally { t.done() }
})

test("admin: board stats", async () => {
  const t = setup()
  const A = "admin:letmein"
  const STAGE2 = { name: "Second Road", rally: "Other Rally", start: [61, 25], finish: [61 + 8000 * DEG_PER_M, 25], lengthM: 8000 }
  try {
    const ann = await t.register("Ann"), bob = await t.register("Bob"), cid = await t.register("Cid")
    const dan = await t.register("Dan"), eve = await t.register("Eve")
    assert.ok(eve)
    await t.drive(ann, 360000)
    t.tick(61000)
    await t.drive(ann, 355000, { board: "open" })
    await t.drive(bob, 350000)
    t.tick(61000)
    await t.drive(bob, 400000, { stage: STAGE2 })
    const c = await t.drive(cid, 340000)
    await t.drive(dan, 330000)
    // Cid's only run hidden, Dan banned: neither counts anywhere
    await t.call("POST", `/v1/admin/runs/${c.body.runId}`, { status: "hidden" }, A)
    await t.call("POST", `/v1/admin/players/${dan.split(":")[0]}`, { banned: true }, A)

    assert.equal((await t.call("GET", "/v1/admin/stats")).status, 401)
    assert.equal((await t.call("GET", "/v1/admin/stats", undefined, "admin:wrong")).status, 401)
    assert.equal((await t.call("GET", "/v1/admin/stats", undefined, ann)).status, 401)
    for (const d of ["0", "366", "abc", "7.5", "-3", "1e2"]) {
      assert.equal((await t.call("GET", "/v1/admin/stats?days=" + d, undefined, A)).status, 400, d)
    }
    const s = (await t.call("GET", "/v1/admin/stats?days=7", undefined, A)).body
    assert.equal(s.days, 7)
    assert.deepEqual(s.totals, { players: 4, drivers: 2, active7: 2, new7: 2, runs: 4, stages: 2, rallies: 2, km: 38,
      timeMs: 360000 + 355000 + 350000 + 400000, stock: 3, open: 1, flagged: 0, resetsPerRun: 0 })
    assert.deepEqual(s.daily.map(d => [d.runs, d.players]), [[4, 2]])
    assert.deepEqual(s.growth.map(g => g.players), [2])
    const p = Object.fromEntries(s.players.map(x => [x.name, [x.runs, x.stages, x.records, x.podiums]]))
    // (Bob: P1 on Stock on both stages; Ann: P2 on Stock and P1 on Open; Cid's hidden run and Dan's ban leave no mark)
    assert.deepEqual(p, { Bob: [2, 2, 2, 2], Ann: [2, 1, 1, 2], Cid: [0, 0, 0, 0], Eve: [0, 0, 0, 0] })
    const st = s.stages[0]
    assert.deepEqual([st.name, st.rally, st.runs, st.players, st.recordMs], ["Test Road", "Test Rally", 3, 2, 350000])
    assert.ok(Math.abs(st.recordKmh - 10000 / 350000 * 3600) < 1e-9)
    assert.deepEqual(s.rallies, [{ rally: "Test Rally", runs: 3 }, { rally: "Other Rally", runs: 1 }])
    assert.deepEqual(s.cars, [{ car: "Sunburst RS", runs: 4 }])
    assert.deepEqual(s.mods, [{ v: "test", runs: 4 }])
    assert.equal(s.times.length, 4)
    // 40 days on: out of the range, still in the totals
    t.tick(40 * 86400000)
    const later = (await t.call("GET", "/v1/admin/stats", undefined, A)).body
    assert.equal(later.days, 30)
    assert.deepEqual([later.daily.length, later.mods.length, later.times.length, later.totals.runs, later.totals.active7, later.totals.new7],
      [0, 0, 0, 4, 0, 0])
  } finally { t.done() }
})
