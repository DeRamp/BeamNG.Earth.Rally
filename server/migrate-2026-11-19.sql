-- 2026-11-19: players move out of events into their own table, installs, so an install number cannot be matched to
-- the session rows stored next to it. For the live D1, after migrate-2026-11-18b.sql:
--   npx wrangler d1 execute earth-rally-stats --remote --file=migrate-2026-11-19.sql
-- (safe to run again)
CREATE TABLE IF NOT EXISTS installs (
  install TEXT NOT NULL, day TEXT NOT NULL, mod TEXT, game TEXT, earth TEXT,
  PRIMARY KEY (install, day)
) WITHOUT ROWID;
INSERT OR IGNORE INTO installs (install, day, mod, game, earth)
  SELECT install, day, mod, game, earth FROM events WHERE event = 'install_seen' AND install IS NOT NULL;
DELETE FROM events WHERE event = 'install_seen';
UPDATE events SET install = NULL WHERE install IS NOT NULL;
DROP INDEX IF EXISTS events_install;
