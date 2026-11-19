-- Earth Rally stats (+stats): the D1 database. Apply with
--   npx wrangler d1 execute earth-rally-stats --remote --file=schema.sql
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY,
  day TEXT NOT NULL,            -- YYYY-MM-DD, no time of day
  event TEXT NOT NULL,
  session TEXT NOT NULL,        -- random, new each time the game starts, never reused
  mod TEXT, game TEXT, earth TEXT,
  rally TEXT, stage TEXT, pass INTEGER, result TEXT, time_s INTEGER, resets INTEGER, line TEXT,
  stages_done INTEGER, stages_total INTEGER,
  code TEXT, module TEXT,
  message TEXT, car TEXT, cls TEXT,  -- added 2026-11-18 (migrate-2026-11-18.sql for the live table)
  install TEXT                  -- unused since 2026-11-19 (install_seen goes to installs); added by migrate-2026-11-18b.sql
);
CREATE INDEX IF NOT EXISTS events_day ON events (day, event);
CREATE INDEX IF NOT EXISTS events_session ON events (session);
CREATE INDEX IF NOT EXISTS events_err ON events (event, code, module, mod, day);   -- errors: first seen, cheaply

-- players: one row per install number and day, from install_seen. A table of its own, with no row number, so an
-- install cannot be matched to the session rows sent alongside it (added 2026-11-19, migrate-2026-11-19.sql)
CREATE TABLE IF NOT EXISTS installs (
  install TEXT NOT NULL, day TEXT NOT NULL, mod TEXT, game TEXT, earth TEXT,
  PRIMARY KEY (install, day)
) WITHOUT ROWID;

-- rows older than a year, as monthly counts (worker.js prune)
CREATE TABLE IF NOT EXISTS archive (month TEXT, event TEXT, rally TEXT, stage TEXT, result TEXT, n INTEGER);
