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
  code TEXT, module TEXT
);
CREATE INDEX IF NOT EXISTS events_day ON events (day, event);
CREATE INDEX IF NOT EXISTS events_session ON events (session);

-- rows older than a year, as monthly counts (worker.js prune)
CREATE TABLE IF NOT EXISTS archive (month TEXT, event TEXT, rally TEXT, stage TEXT, result TEXT, n INTEGER);
