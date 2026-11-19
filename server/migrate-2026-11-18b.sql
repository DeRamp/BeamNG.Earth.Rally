-- 2026-11-18b: the install number, for counting players (install_seen events only). For the live D1:
--   npx wrangler d1 execute earth-rally-stats --remote --file=migrate-2026-11-18b.sql
-- (run it once, after migrate-2026-11-18.sql; a second run fails with "duplicate column name", harmlessly)
ALTER TABLE events ADD COLUMN install TEXT;
CREATE INDEX IF NOT EXISTS events_install ON events (install, day);
