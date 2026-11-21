-- earthRally/worldTime: dates, local clocks and the sun for the timed rally (docs/plan-rally-loop.md, items 1 and 2).
-- Pure: no game calls, no os.time (the rally's clock is the itinerary's, never the machine's), so all of it tests
-- offline (tests/test_rally.lua).
--
-- A "local time" here is seconds since 1970-01-01 00:00 as the wall clock of the rally's place reads it, as if that
-- clock were UTC: the itinerary's dates and HH:MM add up with plain arithmetic, and only the sun's height needs the
-- real instant, utc = local - offset.
local M = {}

local floor = math.floor

-- (Howard Hinnant's days_from_civil / civil_from_days: proleptic Gregorian, any year)
function M.daysFromCivil(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = floor(y / 400)
  local yoe = y - era * 400
  local doy = floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end
function M.civilFromDays(z)
  z = z + 719468
  local era = floor(z / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  local d = doy - floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return m <= 2 and y + 1 or y, m, d
end
-- 0 = Sunday
function M.weekday(days) return (days + 4) % 7 end

-- 'YYYY-MM-DD' and 'HH:MM' (the event file's) -> local time, or nil when either is not one.
function M.parse(date, hm)
  if type(date) ~= 'string' or type(hm) ~= 'string' then return nil end
  local y, mo, d = date:match('^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$')
  local h, mi = hm:match('^(%d%d?):(%d%d)$')
  if not (y and h) then return nil end
  y, mo, d, h, mi = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
  if mo < 1 or mo > 12 or d < 1 or d > 31 or h > 24 or mi > 59 then return nil end
  return M.daysFromCivil(y, mo, d) * 86400 + h * 3600 + mi * 60
end

-- local time -> y, mo, d, hours (0-24, fractional)
function M.parts(t)
  local days = floor(t / 86400)
  local y, mo, d = M.civilFromDays(days)
  return y, mo, d, (t - days * 86400) / 3600, days
end

function M.hm(t)
  if type(t) ~= 'number' then return nil end
  local s = floor(t) % 86400
  return string.format('%02d:%02d', floor(s / 3600), floor(s / 60) % 60)
end
-- 'HH:MM:SS' (a time in at a control, to the second)
function M.hms(t)
  if type(t) ~= 'number' then return nil end
  return M.hm(t) .. string.format(':%02d', floor(t) % 60)
end
M.DAYS = { 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' }
M.MONTHS = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
-- 'Fri 6 Feb'
function M.dateText(t)
  if type(t) ~= 'number' then return nil end
  local y, mo, d, _, days = M.parts(t)
  return string.format('%s %d %s', M.DAYS[M.weekday(days) + 1], d, M.MONTHS[mo])
end
-- 'Fri 6 Feb 2026, 18:00 local'
function M.startText(t)
  if type(t) ~= 'number' then return nil end
  local y = M.parts(t)
  return string.format('%s %d, %s local', M.dateText(t), y, M.hm(t))
end

------------------------------------------------------------------------------------------ time zones
-- The event file names its zone the IANA way ('America/Detroit'). The game has no zone database, so the zones rallies
-- are run in are listed here with their standard offset (hours) and their summer-time rule; any other is put at its
-- longitude's hour, no summer time (wrong by an hour at worst, and only the sky's sun moves by it: the clock on the
-- time card is the itinerary's own).
local Z = {}
local function zones(off, rule, list) for _, n in ipairs(list) do Z[n] = { off, rule } end end
zones(-5, 'us', { 'America/New_York', 'America/Detroit', 'America/Toronto', 'America/Montreal',
  'America/Indiana/Indianapolis', 'America/Kentucky/Louisville', 'US/Eastern' })
zones(-4, 'us', { 'America/Halifax' })
zones(-3.5, 'us', { 'America/St_Johns' })
zones(-6, 'us', { 'America/Chicago', 'America/Winnipeg', 'America/Menominee', 'US/Central' })
zones(-6, nil, { 'America/Regina', 'America/Mexico_City' })
zones(-7, 'us', { 'America/Denver', 'America/Edmonton', 'America/Boise', 'US/Mountain' })
zones(-7, nil, { 'America/Phoenix' })
zones(-8, 'us', { 'America/Los_Angeles', 'America/Vancouver', 'US/Pacific' })
zones(-9, 'us', { 'America/Anchorage', 'America/Juneau' })
zones(-10, nil, { 'Pacific/Honolulu' })
zones(0, 'eu', { 'Europe/London', 'Europe/Dublin', 'Europe/Lisbon', 'Atlantic/Canary' })
zones(1, 'eu', { 'Europe/Paris', 'Europe/Berlin', 'Europe/Madrid', 'Europe/Rome', 'Europe/Brussels',
  'Europe/Amsterdam', 'Europe/Vienna', 'Europe/Stockholm', 'Europe/Oslo', 'Europe/Copenhagen', 'Europe/Warsaw',
  'Europe/Prague', 'Europe/Zurich', 'Europe/Budapest', 'Europe/Luxembourg' })
zones(2, 'eu', { 'Europe/Helsinki', 'Europe/Athens', 'Europe/Tallinn', 'Europe/Riga', 'Europe/Vilnius',
  'Europe/Bucharest', 'Europe/Sofia', 'Europe/Kyiv', 'Europe/Kiev' })
zones(10, 'au', { 'Australia/Sydney', 'Australia/Melbourne', 'Australia/Canberra', 'Australia/Hobart' })
zones(9.5, 'au', { 'Australia/Adelaide' })
zones(10, nil, { 'Australia/Brisbane' })
zones(9.5, nil, { 'Australia/Darwin' })
zones(8, nil, { 'Australia/Perth' })
zones(12, 'nz', { 'Pacific/Auckland' })
zones(9, nil, { 'Asia/Tokyo' })
zones(2, nil, { 'Africa/Johannesburg' })
zones(0, nil, { 'UTC', 'Etc/UTC', 'GMT' })
M.ZONES = Z

local function nthSunday(y, mo, n)      -- (n = 1, 2...; -1 = the last)
  local first = M.daysFromCivil(y, mo, 1)
  local d1 = 1 + (7 - M.weekday(first)) % 7
  if n > 0 then return d1 + 7 * (n - 1) end
  local nextM = mo == 12 and M.daysFromCivil(y + 1, 1, 1) or M.daysFromCivil(y, mo + 1, 1)
  local last = nextM - first
  local d = d1
  while d + 7 <= last do d = d + 7 end
  return d
end
local function at(y, mo, d, h) return M.daysFromCivil(y, mo, d) * 86400 + h * 3600 end

-- (std: the local standard time, s. Each rule's switch at its own hour, in standard time)
local function summer(rule, std, offH)
  local y = M.parts(std)
  if rule == 'us' then
    return std >= at(y, 3, nthSunday(y, 3, 2), 2) and std < at(y, 11, nthSunday(y, 11, 1), 1)
  elseif rule == 'eu' then
    local utc = std - offH * 3600
    return utc >= at(y, 3, nthSunday(y, 3, -1), 1) and utc < at(y, 10, nthSunday(y, 10, -1), 1)
  elseif rule == 'au' then
    return not (std >= at(y, 4, nthSunday(y, 4, 1), 2) and std < at(y, 10, nthSunday(y, 10, 1), 2))
  elseif rule == 'nz' then
    return not (std >= at(y, 4, nthSunday(y, 4, 1), 2) and std < at(y, 9, nthSunday(y, 9, -1), 2))
  end
  return false
end

-- The zone's offset from UTC (seconds) at local time t; lon: the place's longitude, for a zone not listed. Second
-- answer: whether the zone was known.
function M.utcOffset(tz, t, lon)
  local z = type(tz) == 'string' and Z[tz] or nil
  if not z then
    return floor((tonumber(lon) or 0) / 15 + 0.5) * 3600, false
  end
  local off = z[1] * 3600
  -- (t is the wall clock; the rules switch at a standard-time hour. Summer time when t read as summer time -- an
  -- hour on from standard -- falls inside it: the hour the clocks go back reads as summer time, its first pass, and
  -- the hour skipped in spring as standard)
  if z[2] and type(t) == 'number' and summer(z[2], t - 3600, z[1]) then off = off + 3600 end
  return off, true
end

-- Local time t in zone tz -> the UTC instant (os.time's epoch).
function M.toUtc(t, tz, lon)
  if type(t) ~= 'number' then return nil end
  return t - M.utcOffset(tz, t, lon)
end

------------------------------------------------------------------------------------------ the sun
-- The sun's elevation (degrees above the horizon, refraction left out) at local date y-mo-d, localHours (0-24) in a zone
-- utcOffset hours from UTC, at lat / lon: NOAA's low-precision formulas, within about a degree. BeamNG.Earth's own
-- (fork sky.lua, sunElevationDeg), ported as it is so the two agree.
function M.sunElevationDeg(y, mo, d, localHours, utcOffset, lat, lon)
  local rad = math.pi / 180
  local utc = (tonumber(localHours) or 0) - (tonumber(utcOffset) or 0)
  y, mo, d = tonumber(y) or 2000, tonumber(mo) or 1, tonumber(d) or 1
  local leap = (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
  local before = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }
  local doy = (before[mo] or 0) + d + ((leap and mo > 2) and 1 or 0) + utc / 24
  local g = 2 * math.pi / (leap and 366 or 365) * (doy - 1)
  local eqt = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g)
    - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
  local decl = 0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g)
    + 0.000907 * math.sin(2 * g) - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g)
  local solarMin = utc * 60 + eqt + 4 * (tonumber(lon) or 0)
  local ha = (solarMin / 4 - 180) * rad
  local phi = (tonumber(lat) or 0) * rad
  local s = math.sin(phi) * math.sin(decl) + math.cos(phi) * math.cos(decl) * math.cos(ha)
  return math.asin(math.max(-1, math.min(1, s))) / rad
end

-- The light at local time t in zone tz at lat / lon: 'day' (the sun 6 degrees up or more), 'night' (more than 6
-- under: civil twilight over), else 'dawn' before noon and 'dusk' after it. nil without a place.
M.TWILIGHT_DEG = 6
function M.light(t, tz, lat, lon)
  if type(t) ~= 'number' or type(lat) ~= 'number' or type(lon) ~= 'number' then return nil end
  local y, mo, d, h = M.parts(t)
  local e = M.sunElevationDeg(y, mo, d, h, M.utcOffset(tz, t, lon) / 3600, lat, lon)
  if e >= M.TWILIGHT_DEG then return 'day' end
  if e < -M.TWILIGHT_DEG then return 'night' end
  return h < 12 and 'dawn' or 'dusk'
end

return M
