-- 2026-11-18: error message, car and class. For the live D1, which already has the old events table:
--   npx wrangler d1 execute earth-rally-stats --remote --file=migrate-2026-11-18.sql
-- (run it once; a second run fails with "duplicate column name", harmlessly)
ALTER TABLE events ADD COLUMN message TEXT;
ALTER TABLE events ADD COLUMN car TEXT;
ALTER TABLE events ADD COLUMN cls TEXT;
