-- earthRally/lineStats: what a stage's line says about itself -- how many corners the co-driver will call on it, and
-- how much height it gains and loses -- from the line's own points, with nothing from the game (the offline tests
-- run it).
--
-- Worked out once, when a line is saved (the end of a recce, the end of an auto recce), and kept in the line's own
-- file. Not worked out when the page asks: the menu re-reads a stage every two seconds while its page is open, and
-- the longest line in the user's set resamples to about 9,800 samples. events.lineFigures reads the kept figures
-- back, and works them out once for a line saved by a version before this one.
--
-- The corner count is the co-driver's own count, not an approximation of it: stageWriter.stageCorners is the
-- function that decides which corners the notebook gets -- one pacenote per corner -- and this calls that one
-- function. The stretch measured is the stage itself, its start control to its flying finish, so all four tiles on
-- the stage page describe the same piece of road.
--
-- What this cannot have that a run has: a run puts the line into the game's coordinates and finds its controls
-- again there (runner.lua project()), while this reads the line as it was stored and uses a flat frame about its
-- first point, as runner.lua's own stageLatLon does. The corner pass reads shape rather than position, so the two
-- agree on the user's lines (measured against the corner counts the game itself recorded), but a corner right on
-- the edge of being called could fall either way between them.
local geo = require('earthRally/geo')
local writer = require('earthRally/stageWriter')

local M = {}

M.CONTROL_OFF_LINE_M = 200  -- a start or finish control further than this from the line is not on it (runner.lua's
                            -- own rule where it cuts a line round a stage: stageLatLon)

-- (a flat frame of metres about lat0, lon0 -- east and north, as runner.lua's stageLatLon makes it)
local function frameAt(lat0, lon0)
  return function(lat, lon)
    return { x = geo.metres(lat0, lon0, lat0, lon) * (lon < lon0 and -1 or 1),
             y = geo.metres(lat0, lon0, lat, lon0) * (lat < lat0 and -1 or 1) }
  end
end

-- The figures for a line as its file holds it.
--   points   { { lat, lon, alt, 1 }... } (the recce and matched files' own shape; a fourth 1 means "no road on the
--            map here", so no notes and no corners counted along there)
--   stage    the event's stage, for its controls. Without it, or with controls that are not on the line, the whole
--            line is taken as the stage -- the same fallback the runner makes.
-- Returns { corners = n, gainM = m, lossM = m }, or nil when there is no line to measure. gainM and lossM are
-- absent when the line carries no height (geo.rise): then the stage page's two height tiles are dashes while its
-- Corners tile is still a number, which is the honest pair of answers.
function M.of(points, stage)
  -- (two points are a line and measure as one: a straight, with no corners on it)
  if type(points) ~= 'table' or #points < 2 then return nil end
  local xy = frameAt(points[1][1], points[1][2])
  local line = {}
  for i, p in ipairs(points) do
    local q = xy(p[1], p[2])
    q.z, q.gap = p[3], p[4] == 1 or nil
    line[i] = q
  end
  local cum = geo.cumulative(line)
  local total = cum[#cum]
  -- A line of no length is the only one with nothing to say. Anything else gets a number, even a 50 m service
  -- route that an organiser's file lists among the stages: it has 0 corners, which is true of it, and the stage
  -- page's dash goes on meaning one thing only -- there is no line here.
  if total <= 0 then return nil end

  -- the stage along the line: its start control to its flying finish, where those lie on the line. A finish that
  -- does not come at least 100 m after the start means neither control was found on this line, and then the stage
  -- is the whole of it (runner.lua stageLatLon, the same rule).
  local ctl = (stage and stage.controls) or {}
  local function at(c, default)
    if not c or not c.lat then return default end
    local _, _, s, off = geo.locate(line, cum, xy(c.lat, c.lon))
    if off > M.CONTROL_OFF_LINE_M then return default end
    return s
  end
  local startM, finishM = at(ctl.start, 0), at(ctl.ff, total)
  if finishM <= startM + 100 then startM, finishM = 0, total end

  -- the stretches with no road on the map: the run calls no notes along them, so no corners are counted there
  -- either (runner.lua builds these same ranges from these same flags before it builds the stage)
  local mute, from = {}, nil
  for i, p in ipairs(line) do
    if p.gap then from = from or cum[i]
    elseif from then mute[#mute + 1] = { from - writer.MUTE_PAD_M, cum[i] + writer.MUTE_PAD_M } from = nil end
  end
  if from then mute[#mute + 1] = { from - writer.MUTE_PAD_M, total } end

  local corners = writer.stageCorners(line, cum, { startM = startM, finishM = finishM, mute = mute })
  local out = { corners = #corners }
  local gain, loss = geo.rise(geo.slice(line, cum, startM, finishM))
  if gain then
    out.gainM = math.floor(gain * 10 + 0.5) / 10
    out.lossM = math.floor(loss * 10 + 0.5) / 10
  end
  return out
end

return M
