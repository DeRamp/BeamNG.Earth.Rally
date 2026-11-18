// Earth Rally online board: the checks on what a client sends. Pure (no database, no network), so they test in Node.
// The client is open source, so none of this proves a time is honest: it stops edited times, teleports, shortcuts
// and resent submissions, and flags the rest for a person to look at (docs/research-online-leaderboards.md, s. 3).

export const LIMITS = {
  NAME_MIN: 2, NAME_MAX: 24,
  TEXT_MAX: 80,                 // a stage's or rally's name
  STAGE_MIN_M: 300, STAGE_MAX_M: 120000,
  SAME_STAGE_M: 100,            // start and flying finish within this of a known stage's: the same stage
  SAME_STAGE_LEN: 0.03,         // and its length within this share
  MAX_AVG_KMH: 200,             // no stage is driven faster than this on average: refused
  MAX_SPEED_MS: 100,            // between two trace points faster than this (360 km/h) over JUMP_M: a jump
  JUMP_M: 60,
  TRACE_MAX_POINTS: 20000,
  TRACE_GAP_MS: 5000,           // trace points further apart than this: a gap (noted, not flagged)
  END_M: 150,                   // the trace's first point this near the start, its last this near the finish
  SHORT_SHARE: 0.9,             // the trace this much shorter than the stage: a shortcut
  CLOCK_MS: 3000,               // the trace's last time this near the stage time (without penalties)
  WALL_SLACK_MS: 2000,          // the server's clock may run this much under the stage time (latency)
  TOKEN_MAX_AGE_MS: 24 * 3600 * 1000,
}

// Notes that do not take a run off the board.
export const SOFT_FLAGS = new Set(["trace-gap"])

// Words a name may not hold (matched after folding case and common look-alike characters). Short on purpose: the
// report button and the admin page catch the rest. Extend as needed.
const BLOCKED = ["fuck", "shit", "cunt", "nigg", "fag", "rape", "nazi", "hitler", "admin", "moderator", "earthrally"]
const FOLD = { 0: "o", 1: "i", 3: "e", 4: "a", 5: "s", 7: "t", "@": "a", $: "s", "!": "i" }

export function metres(lat1, lon1, lat2, lon2) {
  const R = 6371008.8, r = Math.PI / 180
  const dLat = (lat2 - lat1) * r, dLon = (lon2 - lon1) * r
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin(dLon / 2) ** 2
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)))
}

const isNum = x => typeof x === "number" && Number.isFinite(x)
const isLatLon = p => Array.isArray(p) && p.length >= 2 && isNum(p[0]) && isNum(p[1]) &&
  Math.abs(p[0]) <= 90 && Math.abs(p[1]) <= 180

// A display name, tidied, or { error }.
export function cleanName(raw) {
  if (typeof raw !== "string") return { error: "a name is needed" }
  const name = raw.normalize("NFC").replace(/\s+/g, " ").trim()
  if (name.length < LIMITS.NAME_MIN || name.length > LIMITS.NAME_MAX) {
    return { error: `a name is ${LIMITS.NAME_MIN} to ${LIMITS.NAME_MAX} characters` }
  }
  if (!/^[\p{L}\p{N}][\p{L}\p{N} ._'-]*$/u.test(name)) return { error: "letters, numbers, spaces and . _ ' - only" }
  const folded = [...name.toLowerCase()].map(c => FOLD[c] || c).join("").replace(/[^a-z\p{L}]/gu, "")
  if (BLOCKED.some(w => folded.includes(w))) return { error: "that name is not allowed" }
  return { name }
}

function cleanText(s, max) {
  if (s === undefined || s === null) return null
  if (typeof s !== "string") return undefined
  const t = s.replace(/[\u0000-\u001f]/g, "").replace(/\s+/g, " ").trim()
  return t.length ? t.slice(0, max) : null
}

// A stage as the client describes it: { name, rally, start: [lat, lon], finish: [lat, lon], lengthM }, tidied, or
// { error }.
export function cleanStage(s) {
  if (!s || typeof s !== "object") return { error: "no stage" }
  const name = cleanText(s.name, LIMITS.TEXT_MAX)
  const rally = cleanText(s.rally, LIMITS.TEXT_MAX)
  if (!name) return { error: "the stage has no name" }
  if (rally === undefined) return { error: "bad rally name" }
  if (!isLatLon(s.start) || !isLatLon(s.finish)) return { error: "bad start or finish" }
  if (!isNum(s.lengthM) || s.lengthM < LIMITS.STAGE_MIN_M || s.lengthM > LIMITS.STAGE_MAX_M) {
    return { error: "bad stage length" }
  }
  return { stage: { name, rally, start: [s.start[0], s.start[1]], finish: [s.finish[0], s.finish[1]], lengthM: s.lengthM } }
}

// How far a known stage row is from a described stage, or null when it is not the same stage.
export function stageDistance(row, st) {
  const ds = metres(row.start_lat, row.start_lon, st.start[0], st.start[1])
  const df = metres(row.finish_lat, row.finish_lon, st.finish[0], st.finish[1])
  const dl = Math.abs(row.length_m - st.lengthM) / row.length_m
  if (ds > LIMITS.SAME_STAGE_M || df > LIMITS.SAME_STAGE_M || dl > LIMITS.SAME_STAGE_LEN) return null
  return ds + df
}

// The box a stage's start is looked for in (degrees), wide enough for SAME_STAGE_M at any latitude a road is on.
export function startBox(st) {
  const dLat = 0.002
  const dLon = Math.min(1, 0.002 / Math.max(0.05, Math.cos(st.start[0] * Math.PI / 180)))
  return [st.start[0] - dLat, st.start[0] + dLat, st.start[1] - dLon, st.start[1] + dLon]
}

// A run's checks. run: { timeMs, penaltyMs, trace: [[ms, lat, lon]...] }, stage: a stage row (start_lat ...,
// length_m), wallMs: the server's clock from the run's token to now. Returns { reject } (refused outright) or
// { flags: [...], wallRatio } (empty flags: on the board).
export function checkRun(run, stage, wallMs) {
  const { timeMs, penaltyMs } = run
  if (!Number.isInteger(timeMs) || timeMs <= 0 || timeMs > 6 * 3600 * 1000) return { reject: "bad time" }
  if (!Number.isInteger(penaltyMs) || penaltyMs < 0 || penaltyMs > timeMs) return { reject: "bad penalty" }
  const driveMs = timeMs - penaltyMs
  const avgKmh = stage.length_m / 1000 / (driveMs / 3600000)
  if (avgKmh > LIMITS.MAX_AVG_KMH) return { reject: `faster than ${LIMITS.MAX_AVG_KMH} km/h on average` }
  if (isNum(wallMs) && wallMs < driveMs - LIMITS.WALL_SLACK_MS) return { reject: "the run took less time than it says" }

  const tr = run.trace
  if (!Array.isArray(tr) || tr.length < 2) return { reject: "no trace" }
  if (tr.length > LIMITS.TRACE_MAX_POINTS) return { reject: "trace too long" }
  for (const p of tr) {
    if (!Array.isArray(p) || !isNum(p[0]) || !isLatLon([p[1], p[2]])) return { reject: "bad trace point" }
  }
  const flags = new Set()
  let pathM = 0
  for (let i = 1; i < tr.length; i++) {
    const dt = tr[i][0] - tr[i - 1][0]
    if (dt < 0) return { reject: "trace goes back in time" }
    const d = metres(tr[i - 1][1], tr[i - 1][2], tr[i][1], tr[i][2])
    pathM += d
    if (dt > LIMITS.TRACE_GAP_MS) flags.add("trace-gap")
    if (d > LIMITS.JUMP_M && d / Math.max(dt, 1) * 1000 > LIMITS.MAX_SPEED_MS) flags.add("jump")
  }
  const first = tr[0], last = tr[tr.length - 1]
  if (metres(first[1], first[2], stage.start_lat, stage.start_lon) > LIMITS.END_M) flags.add("start")
  if (metres(last[1], last[2], stage.finish_lat, stage.finish_lon) > LIMITS.END_M) flags.add("finish")
  if (pathM < stage.length_m * LIMITS.SHORT_SHARE) flags.add("short")
  if (Math.abs(last[0] - driveMs) > LIMITS.CLOCK_MS) flags.add("clock")
  return { flags: [...flags], wallRatio: isNum(wallMs) ? wallMs / driveMs : null }
}

// Whether flags take a run off the board.
export const hardFlags = flags => flags.filter(f => !SOFT_FLAGS.has(f))
