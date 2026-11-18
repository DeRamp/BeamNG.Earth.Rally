-- Earth Rally's online leaderboard (docs/research-online-leaderboards.md). Cloudflare D1, which is SQLite.
-- Apply: npx wrangler d1 execute earth-rally --remote --file schema.sql   (and --local for wrangler dev)

-- A player: an id and a secret the companion keeps on the player's computer (only its SHA-256 is stored here).
CREATE TABLE IF NOT EXISTS players (
  id          TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,
  name        TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  banned      INTEGER NOT NULL DEFAULT 0
);
CREATE UNIQUE INDEX IF NOT EXISTS players_name ON players (name COLLATE NOCASE);

-- A stage: the same road whoever drives it. Found by its start, flying finish and length within a tolerance
-- (checks.js sameStage), so two players whose lines differ by a few metres share one board.
CREATE TABLE IF NOT EXISTS stages (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  rally       TEXT,
  start_lat   REAL NOT NULL,
  start_lon   REAL NOT NULL,
  finish_lat  REAL NOT NULL,
  finish_lon  REAL NOT NULL,
  length_m    REAL NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS stages_start ON stages (start_lat, start_lon);

-- A run token: issued as the run starts, used once by its submission (no resent submissions; the server's clock
-- against the stage time).
CREATE TABLE IF NOT EXISTS tokens (
  token       TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL,
  stage_id    TEXT NOT NULL,
  issued_at   INTEGER NOT NULL,
  used        INTEGER NOT NULL DEFAULT 0
);

-- Every run submitted. status: ok (on the board), flagged (kept, off the board until looked at), hidden (removed).
CREATE TABLE IF NOT EXISTS runs (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  stage_id     TEXT NOT NULL,
  board        TEXT NOT NULL,            -- 'stock' | 'open'
  player_id    TEXT NOT NULL,
  car          TEXT,
  time_ms      INTEGER NOT NULL,
  penalty_ms   INTEGER NOT NULL DEFAULT 0,
  trace        TEXT,                     -- JSON [[ms, lat, lon]...], kept for review and ghosts
  mod_version  TEXT,
  submitted_at INTEGER NOT NULL,
  wall_ratio   REAL,                     -- the server's clock from token to submission over the stage time
  status       TEXT NOT NULL DEFAULT 'ok',
  flags        TEXT,                     -- why it was flagged, comma separated
  resets       TEXT,                     -- JSON [ms...]: when the car was reset or recovered
  slow_ms      INTEGER                   -- how long the game's clock ran slow (slow motion)
);
CREATE INDEX IF NOT EXISTS runs_player ON runs (player_id, submitted_at);

-- Each player's best ok run per stage and board: what a board reads.
CREATE TABLE IF NOT EXISTS best (
  stage_id   TEXT NOT NULL,
  board      TEXT NOT NULL,
  player_id  TEXT NOT NULL,
  run_id     INTEGER NOT NULL,
  time_ms    INTEGER NOT NULL,
  PRIMARY KEY (stage_id, board, player_id)
);
CREATE INDEX IF NOT EXISTS best_board ON best (stage_id, board, time_ms);

CREATE TABLE IF NOT EXISTS reports (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id     INTEGER NOT NULL,
  player_id  TEXT NOT NULL,
  why        TEXT,
  at         INTEGER NOT NULL,
  UNIQUE (run_id, player_id)
);

-- Rate limiting: requests per key (a player or an address) per minute.
CREATE TABLE IF NOT EXISTS hits (
  key  TEXT NOT NULL,
  win  INTEGER NOT NULL,
  n    INTEGER NOT NULL,
  PRIMARY KEY (key, win)
);
