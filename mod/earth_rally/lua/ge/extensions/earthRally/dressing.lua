-- earthRally/dressing: where the stage dressing stands (1.6.0, docs/plan-1.6.0-stage-dressing.md): course tape across
-- the side roads the stage does not take, direction boards before its turns and forks, junction marshals, radio and
-- medical points, marshal posts and spectator areas, each one of the game's own rally props. Pure: nothing from the
-- game (tests/test_dressing.lua runs it offline); props.lua puts the result down.
--
-- The rules are the mock-up's (docs/mockups-1.6.0/stage.html, agreed with the user 2026-11-14): its script is the
-- reference, and the constants below carry its names. Where this goes past what the mock-up drew (the spectators'
-- gazebo and chairs on a corner of any shape, a marshal post from the map away from a junction), it says so.
--
-- dressing.plan(input) -> a list of sites, in order along the stage:
--   { kind = 'tape' | 'board' | 'marshal' | 'radio' | 'medical' | 'spectators', source = 'rule' | 'map', name,
--     shared (a radio point whose post a medical point shares),
--     along (m along the line: the junction, the point), from, to (m along the line the site's objects span),
--     objects = { { shape (full path), x, y, z (or nil), dx, dy, foot (its reach, FOOT), [ex, ey, eo, eh, grp: set
--       from the road's edge, edged below] }, ... } }
-- every object in game coordinates of the moment: (x, y) is where the model's origin goes and (dx, dy) the way its +Y
-- points, as props.lua's yawQuat takes it. The models' own quirks (which way a tape runs from its origin, which side
-- of a board is its face) are dealt with here, in one place (shapeDir below), so props.lua only puts them down.
local M = {}

local geo = require('earthRally/geo')

local sqrt, abs, max, min, huge = math.sqrt, math.abs, math.max, math.min, math.huge

-- A compass bearing (degrees clockwise from north) as a direction in game coordinates (+x east, +y north: test_props
-- turns its boards with dx = sin, dy = cos). junctions.lua has the shared one; this is the same, for when it is not
-- there (tests run without it).
local function bearingToDirLocal(deg)
  local h = math.rad(deg)
  return math.sin(h), math.cos(h)
end
local okJ, J = pcall(require, 'earthRally/junctions')
local bearingToDir = (okJ and type(J) == 'table' and J.bearingToDir) or bearingToDirLocal
M._bearingToDir = bearingToDir

------------------------------------------------------------------------------------------ the rules

M.HALF = 3.0              -- the stage road's half width when nothing says (props.DEFAULT_HALF_WIDTH_M)
-- a radio / medical board and its warning this far beyond the road's edge (until 1.6.0's notes 0.3 m inside it, as
-- props.BOARD_OUT_M's control boards, where a car stops beside them; the user, 2026-11-15: "too close to the road")
M.BOARD_OUT = 1.0
M.DIR_BOARD_OUT = 1.0     -- a direction (tulip) board this far beyond the road's edge (the user, 2026-11-14: "a bit
                          -- further off the road")
M.TENT_OUT = 1.5          -- props.TENT_OUT_M: the gazebo's centre beyond the edge
M.ROADSIDE_MARSHAL_OUT = 2.5  -- a roadside marshal's table this far beyond the edge (1.6.0's note 10, the user: "an
                              -- additional meter off" the TENT_OUT it had)
M.TAPE_IN = 8             -- tape this far into a side road from the junction ...
M.TAPE_PAST = 0.75        -- ... each end this far past the side road's edge (the user, 2026-11-14: "just past")
M.TAPE_CLEAR = 1.0        -- ... moved farther in until both its ends clear the stage's road by this much
M.TAPE_IN_MAX = 30        -- (and no farther: a tape that never clears is left out -- the side road is the stage's
                          -- own later pass, or runs beside it -- and said so once in the log)
M.TAPE_SY_MAX = 1.25      -- a tape model stretched along its length by at most this (review round 2) ...
M.TAPE_OVERLAP = 0.5      -- ... beyond it two pieces of the longest model, overlapping by at least this
M.TAPE_LEN_MAX = 2 * 1.25 * 10 - 0.5  -- (so no tape is longer than two of them: 24.5 m)
M.TAPE_GROW_STEP = 0.25   -- (a tape's maxLen, the longest that still clears the stage's road, found in these steps)
-- A side road leaving within this of the stage's own road (the way on, or the way back: an acute junction, a fork)
-- gets its tape parallel with the stage road, TAPE_CLEAR off its edge, across the side road's mouth (1.6.2, issue #9,
-- the user: "the fence should always run parallel with the stage road"). Square to such a side road the tape stood at
-- 50-75 degrees to the stage and had to be walked far in before both ends cleared it: an awkward angle. Its length
-- is the side road's width along the stage's way (2 x half width / sin of the angle) plus TAPE_PAST each end.
M.TAPE_PARALLEL_DEG = 45
M.CLEAR_CELL_M = 50       -- (the whole line's clearance looked up in cells of this size)
M.BOARD_BEFORE = 75       -- direction board before a turn / fork
M.WARN_BEFORE = 100       -- radio / medical warning board
M.POST_AFTER = 6          -- the post just after a radio / medical board
M.MEDICAL_AFTER = 8       -- a shared post's medical boards this far after the radio ones
M.SHARE_M = 50            -- a medical point this close to a radio point shares its post
M.SPEC_OFF = 5            -- spectator tape off the road's edge
M.FENCE_BEHIND = 2.5      -- the mesh fence behind the tape
M.BALE_OFF = 1.5          -- the spectators' hay bales (their centres) this far off the road's edge, clear of it by
                          -- their FOOT (props.lua pushes one further out where the game's road is wider) ...
M.BALE_CLEAR = 0.7        -- ... and left out where that is less than this clear of every road there
M.MARSHAL_BEHIND = 5      -- a junction marshal stands on the closed road this far behind its tape ...
M.MARSHAL_SIDE = 1.5      -- ... this far off that road's centre
-- (a marshal from the map at a turn whose only closed road is in the overrun: behind that road's tape all the same,
-- MARSHAL_BEHIND behind it and this far past the road's edge, on the side away from the stage's way out -- clear of
-- the overrun path; 1.6.0's note 11, lite review)
M.MARSHAL_OVERRUN_SIDE = 4
-- ... and none at all where that road is within this of the way in: the stage turns off a through road and the only
-- closed road is straight on, where a car that overshoots goes (the user: marshals never where an overshooting car
-- goes)
M.MARSHAL_OVERRUN_DEG = 45
M.LOOK_M = 15             -- the way in / out of a junction: the line this far either side of it

-- the automatic fill (the mock-up's section 7), for each kind the rally's map marks none of on any stage (1.6.0's
-- note 5: a kind marked on another stage only is none here, not by chance; plan's mapKinds). By chance within these
-- bounds (the user, 2026-11-15: "if they don't have them, you can randomize them"), the chance seeded from the stage
-- (input.seed: runner passes "<event id>/<stage id>"), so a stage dresses the same on every run and two stages differ.
M.RADIO_EVERY_M = 5000    -- a radio point every ~5 km: each the next RADIO_GAP_MIN_M .. RADIO_GAP_MAX_M on ...
M.RADIO_GAP_MIN_M, M.RADIO_GAP_MAX_M = 4000, 6000
M.RADIO_NOT_LAST_M = 1000 -- ... none in the last 1 km before the finish
M.RADIO_CLEAR_M = 40      -- (an automatic one moved along until its post is this clear of a junction)
M.SPEC_EVERY_M = 4000     -- spectator areas at most one per ~4 km ...
M.SPEC_NOT_FIRST_M = 500  -- ... none in the first 500 m
M.SPEC_MAX_RADIUS_M = 40  -- a corner counts as a hairpin for spectators this tight ...
M.SPEC_MIN_ANGLE = 90     -- ... and turning this much
M.SPEC_MIN_TURN = 60      -- a junction turn counts this sharp
M.SPEC_LEAD_M = 28        -- the spectators' tape runs this far up each leg of the corner (the mock-up's hairpin) ...
M.SPEC_SPAN_MAX_M = 120   -- ... along at most this much road in all
M.SPEC_POINT_M = 20       -- a spectator point from the map: tape this far either side of it
M.MARSHAL_EVERY_M = 1000  -- junction marshals at every turn that can have one, but at most one per ~1 km
M.MARKS_SPAN_PAD_M = 100  -- the map's points kept from this far before the start to this far past the finish
M.MARSHAL_AT_JUNCTION_M = 40  -- a marshal from the map this near a taped junction (turn, straight or fork) on the
                              -- ground (its point to the junction's) stands behind its tape (1.6.0's note 11)
-- Points right by each other merged before anything is placed (the user, 2026-11-15: "if two points are right by each
-- other please merge them, this applies to all things"): points of one kind this close along the line (spectators
-- and marshals: on one side) are one -- spectators one area over their combined span, a radio, medical or marshal
-- post one post at the first -- and a roadside marshal post this close to a radio / medical point is left out (that
-- post has its own table and chair). A radio and a medical point within SHARE_M still share one post.
M.MERGE_M = 100
M.MARSHAL_NEAR_POST_M = 50
-- (review round 4) ... and points of one kind this close on the ground are one whatever lies between along the line
-- (a hairpin's two legs); a chain merged along the line stops growing at SPEC_SPAN_MAX_M from its first point to its
-- last (the next starts a group of its own); and a radio / medical post whose tent would stand within POST_NEAR_SPEC_M
-- of a spectator area on its side (the right) keeps its boards and flag but not its gazebo, table and chair (the
-- spectators' camp is there)
M.MERGE_GROUND_M = 50
M.POST_NEAR_SPEC_M = 50

-- How far each object reaches round its origin (m, in plan): props.lua holds it this clear of every road the game has
-- there, pushing it out with its group (or leaving the group out) where it is not
M.FOOT = { gazeboFrame = 1.1, gazeboCover = 1.1, table = 0.5, chair = 0.3, flag = 0.2, bale = 0.75,
           radio = 0.3, radioWarn = 0.3, medical = 0.3, medicalWarn = 0.3,
           dirLeft = 0.3, dirRight = 0.3, dirStraight = 0.3, dir45Left = 0.3, dir45Right = 0.3, dir135Right = 0.3,
           dir225Left = 0.3 }

-- each site's object budget (props.lua holds every site to its own DRESS_MAX_OBJS as well)
M.BUDGET = { tape = 8, board = 1, marshal = 3, radio = 9, medical = 6, spectators = 64 }
M.SPEC_TAPE_MAX, M.SPEC_FENCE_MAX = 16, 32

local A = '/art/shapes/race/rally/rally_assets/'
M.SHAPES = {
  tape6 = A .. 's_tape_road_closure_6m.dae', tape8 = A .. 's_tape_road_closure_8m.dae',
  tape10 = A .. 's_tape_road_closure_10m.dae',
  dirLeft = A .. 's_corner_dir_left.dae', dirRight = A .. 's_corner_dir_right.dae',
  dirStraight = A .. 's_corner_dir_straight.dae',
  dir45Left = A .. 's_corner_dir45_left.dae', dir45Right = A .. 's_corner_dir45_right.dae',
  dir135Right = A .. 's_corner_dir135_right.dae', dir225Left = A .. 's_corner_dir225_left.dae',
  radio = A .. 's_rally_signboard_radio_point.dae', radioWarn = A .. 's_rally_signboard_radio_point_warning.dae',
  medical = A .. 's_rally_signboard_medical_point.dae', medicalWarn = A .. 's_rally_signboard_medical_warning.dae',
  specTape = A .. 's_spectator_tape_5m.dae', fence = A .. 's_spectator_grid_a_2m.dae',
  tarp = A .. 's_spectator_tarp_4m.dae',
  gazeboFrame = A .. 's_rally_gazebo_mod_frame_3x3.dae', gazeboCover = A .. 's_rally_gazebo_mod_cover_dkblue_3x3.dae',
  table = A .. 's_rally_fold_table_01.dae', chair = A .. 's_rally_fold_chair_01.dae',
  bale = '/assets/meshes/props/race_event/equipment/s_haybaleround_alt_01.dae',
  flag = '/art/shapes/race/flagMarker.dae',
}
M.LINEAR_M = { tape6 = 6, tape8 = 8, tape10 = 10, specTape = 5, fence = 2, tarp = 4 }

------------------------------------------------------------------------------------------ geometry

local function norm(x, y)
  local l = sqrt(x * x + y * y)
  if l < 1e-9 then return 0, 1 end
  return x / l, y / l
end
local function rightOf(tx, ty) return ty, -tx end          -- the right-hand normal of a direction

-- The signed angle from u to v, degrees, + to the left (autoRecce.angle).
local function angle(ux, uy, vx, vy)
  return math.deg(math.atan2(ux * vy - uy * vx, ux * vx + uy * vy))
end

-- The model's origin and +Y for an object of `key`, from where it should stand:
--   - tape, fence and tarp (s_tape_road_closure_*, s_spectator_tape_5m, _grid_a_2m, _tarp_4m) run from their origin
--     along the model's -Y (read from the models in content/art_shapes.zip: y from -L to 0). Laid from a to b, the
--     origin goes at b and +Y points from a to b.
--   - the signboards (radio / medical) as props.lua's control boards: +Y along the driving direction, the face on -Y
--     towards the car (the models' normals: most face -Y).
--   - the corner arrow boards are the other way round: flat in the model's YZ plane, their face on -X (most normals
--     -X; the arrows' tips reach out to the side they point, +Y for left, as seen from -X). So +X along the driving
--     direction faces the car, and +Y is the road's left.
local function linear(key, ax, ay, bx, by, z)
  local dx, dy = norm(bx - ax, by - ay)
  return { key = key, shape = M.SHAPES[key], x = bx, y = by, z = z, dx = dx, dy = dy }
end
local function upright(key, x, y, z, dx, dy)
  dx, dy = norm(dx, dy)
  return { key = key, shape = M.SHAPES[key], x = x, y = y, z = z, dx = dx, dy = dy, foot = M.FOOT[key] }
end
local function arrowBoard(key, x, y, z, tx, ty)
  tx, ty = norm(tx, ty)
  return { key = key, shape = M.SHAPES[key], x = x, y = y, z = z, dx = -ty, dy = tx, foot = M.FOOT[key] }
end
M._linear, M._arrowBoard = linear, arrowBoard

-- An object set out from the stage road's edge (a board, a post, the spectators' tape): which way is out from the
-- road (ex, ey: the unit normal, pointing away from the centre), how far out from the centre it is (eo) and the half
-- width it was planned against (eh). props.lua sets it the same distance from the edge of the road the game has there
-- when it puts it down, then pushes it further out until it is clear of every road (with the rest of its group, grp:
-- a post's gazebo, table, chair and flag go together), or leaves the group out where it cannot be cleared. Junction
-- tape and junction marshals carry none: they are set from the junction.
local function edged(o, nx, ny, out, h, grp)
  o.ex, o.ey, o.eo, o.eh, o.grp = nx, ny, out, h, grp
  return o
end
-- (the outward normal on side 1 (right) / -1 (left) of a direction of travel)
local function outward(tx, ty, side)
  local rx, ry = rightOf(tx, ty)
  return rx * side, ry * side
end

-- The stage's line, with the questions the rules ask of it.
local function Line(line, cum, half)
  local L = { pts = line, cum = cum, half = half, total = cum[#cum] }
  -- the point s m along (clamped) and the direction of travel there
  function L.at(s)
    local p, d = geo.pointAt(line, cum, s)
    return p.x, p.y, p.z, d.x, d.y
  end
  -- the point s along, `out` m to the right (side 1) or left (-1) of the centre; and the direction there
  function L.off(s, out, side)
    local x, y, z, tx, ty = L.at(s)
    local rx, ry = rightOf(tx, ty)
    return x + rx * out * side, y + ry * out * side, z, tx, ty
  end
  -- how far (x, y) is clear of the stage's road (its centre line, less its half width: `h`, else the stage's), over
  -- the WHOLE line -- a later pass of the stage through the same place is road too (until 1.6.0's review only the
  -- line +-70 m along was looked at, and a crossroads the stage came back through had its later pass taped). The
  -- segments are kept in a grid of CLEAR_CELL_M cells, so a look reads the 3 x 3 cells round the point, not the
  -- thousands of points of a stage line; nothing farther than CLEAR_CELL_M is looked for (clear by that much is clear).
  local C = M.CLEAR_CELL_M
  local grid = nil
  local function cellKey(cx, cy) return cx * 1000003 + cy end
  local function build()
    grid = {}
    for i = 1, #line - 1 do
      local a, b = line[i], line[i + 1]
      for cx = math.floor(min(a.x, b.x) / C), math.floor(max(a.x, b.x) / C) do
        for cy = math.floor(min(a.y, b.y) / C), math.floor(max(a.y, b.y) / C) do
          local k = cellKey(cx, cy)
          local g = grid[k]
          if not g then g = {} grid[k] = g end
          g[#g + 1] = i
        end
      end
    end
  end
  function L.clear(x, y, h)
    if not grid then build() end
    local best = C
    local cx0, cy0 = math.floor(x / C), math.floor(y / C)
    for cx = cx0 - 1, cx0 + 1 do
      for cy = cy0 - 1, cy0 + 1 do
        for _, i in ipairs(grid[cellKey(cx, cy)] or {}) do
          local a, b = line[i], line[i + 1]
          local abx, aby = b.x - a.x, b.y - a.y
          local l2 = abx * abx + aby * aby
          local k = l2 > 1e-12 and max(0, min(1, ((x - a.x) * abx + (y - a.y) * aby) / l2)) or 0
          local ex, ey = x - (a.x + abx * k), y - (a.y + aby * k)
          local d = sqrt(ex * ex + ey * ey)
          if d < best then best = d end
        end
      end
    end
    return best - (h or half)
  end
  return L
end

------------------------------------------------------------------------------------------ junctions

-- The board for a turn of turnDeg (+ left, - right) between the way in and the way out (a fork: always the 45 degree
-- one toward the kept side), or nil for straight on. Returns key, side ('left' / 'right').
function M.dirBoard(turnDeg, kind, keepSide)
  local a = abs(turnDeg)
  local side = turnDeg > 0 and 'left' or 'right'
  if kind == 'fork' then
    side = (keepSide == 'left' or keepSide == 'right') and keepSide or side
    return side == 'left' and 'dir45Left' or 'dir45Right', side
  end
  if kind == 'straight' or a < 30 then return nil end
  if a < 60 then return side == 'left' and 'dir45Left' or 'dir45Right', side end
  if a <= 120 then return side == 'left' and 'dirLeft' or 'dirRight', side end
  return side == 'left' and 'dir225Left' or 'dir135Right', side
end

-- The tape for a side road of half width halfW (HALF when not known: nil or 0), each end TAPE_PAST beyond its edge:
-- the shortest of the 6 / 8 / 10 m models that reaches, else the 10 m one stretched along its length (no longer than
-- TAPE_LEN_MAX). Returns key, the length laid (m) and that length over the model's (1 for a model at its own length;
-- over TAPE_SY_MAX the plan lays it as two pieces: tapePieces).
M.TAPES = { { 'tape6', 6 }, { 'tape8', 8 }, { 'tape10', 10 } }
-- sinA (optional): the sine of the angle between the tape and the side road, for a tape laid parallel with the stage
-- (TAPE_PARALLEL_DEG): the road is 2 x halfW / sinA wide along it.
function M.tapeFor(halfW, sinA)
  local h = (type(halfW) == 'number' and halfW > 0) and halfW or M.HALF
  local need = 2 * h / ((sinA and sinA > 0 and sinA < 1) and sinA or 1) + 2 * M.TAPE_PAST
  for _, t in ipairs(M.TAPES) do
    if need <= t[2] + 1e-9 then return t[1], t[2], 1 end
  end
  local top = M.TAPES[#M.TAPES]
  need = min(need, M.TAPE_LEN_MAX)
  return top[1], need, need / top[2]
end
-- A tape of `len` m of the model `top` m long from (ax, ay) to (bx, by), as pieces { ax, ay, bx, by, sy }: one, its
-- scale len / top, while that is at most TAPE_SY_MAX; else two, one from each end, each at most TAPE_SY_MAX x top
-- and overlapping by TAPE_OVERLAP or more (props.lua's refitTape lays its tapes the same way).
function M.tapePieces(ax, ay, bx, by, len, top)
  if len / top <= M.TAPE_SY_MAX + 1e-9 then return { { ax, ay, bx, by, len / top } } end
  local p = min(top * M.TAPE_SY_MAX, max(top, (len + M.TAPE_OVERLAP) / 2))
  local ux, uy = norm(bx - ax, by - ay)
  return { { ax, ay, ax + ux * p, ay + uy * p, p / top }, { bx - ux * p, by - uy * p, bx, by, p / top } }
end
-- (what props.lua needs to fit a tape of unknown width to the road it finds there when it puts it down)
-- (sinA: a tape parallel with the stage, at that sine to its side road -- props.lua looks for the side road that far
-- off square and lays the tape as long as the road is wide along it)
local function refit(len, sinA)
  local models = {}
  for _, t in ipairs(M.TAPES) do models[#models + 1] = { t[2], M.SHAPES[t[1]] } end
  return { len = len, past = M.TAPE_PAST, models = models, sin = sinA }
end

-- A direction at a junction: given as a bearing, else from the line; turned round when it runs against the line
-- (a guard on the convention: inDeg / outDeg are the driving direction arriving and leaving).
local function wayAt(L, deg, s0, s1)
  local ax, ay = L.at(s0)
  local bx, by = L.at(s1)
  local lx, ly = norm(bx - ax, by - ay)
  if deg == nil then return lx, ly end
  local dx, dy = bearingToDir(deg)
  dx, dy = norm(dx, dy)
  if dx * lx + dy * ly < 0 then dx, dy = -dx, -dy end
  return dx, dy
end

-- One junction: { turnDeg, tapes = { { key, L, s (m in), dx, dy (the side road's way), ax, ay, bx, by } }, jx, jy, jz,
-- tin = { x, y } }.
-- (each tape left out said once in the log, not at every plan of the same junction)
local dropSaid = {}
local function sayDropped(along, deg)
  local k = string.format('%.0f/%.0f', along, deg or -1)
  if dropSaid[k] then return end
  dropSaid[k] = true
  local lg = rawget(_G, 'log')
  if lg then
    pcall(lg, 'I', 'earthRally', string.format('stage dressing: no tape across the side road at %.0f m (bearing %s):'
      .. ' it never clears the stage\'s road within %d m (the stage\'s own later pass, or a road beside it)', along,
      deg and string.format('%.0f', deg) or '?', M.TAPE_IN_MAX))
  end
end
M._dropSaid = dropSaid

local function solveJunction(L, j)
  local along = j.along
  local px, py, pz = L.at(along)
  local jx, jy = j.x or px, j.y or py
  -- (the stage road's half width here: the junction's own -- the file's eighth entry -- else
  -- the stage's)
  local jh = (type(j.half) == 'number' and j.half > 0) and j.half or L.half
  local inx, iny = wayAt(L, j.inDeg, along - M.LOOK_M, along)
  local outx, outy = wayAt(L, j.outDeg, along, along + M.LOOK_M)
  local res = { along = along, kind = j.kind, side = j.side, jx = jx, jy = jy, jz = pz, tapes = {}, half = jh,
                tinx = inx, tiny = iny, toutx = outx, touty = outy, turnDeg = angle(inx, iny, outx, outy) }
  for _, sr in ipairs(j.sides or {}) do
    local dx, dy
    if sr.deg ~= nil then dx, dy = bearingToDir(sr.deg) elseif sr.dx then dx, dy = sr.dx, sr.dy end
    if dx then
      dx, dy = norm(dx, dy)
      -- (the tape's way: square across the side road; at an acute junction along the stage leg nearest the side road,
      -- the way back or the way on -- TAPE_PARALLEL_DEG -- and then it starts where its line runs TAPE_CLEAR off the
      -- stage road's edge, the side road's centre crossing it s = (jh + TAPE_CLEAR) / sinA in)
      local rx, ry = rightOf(dx, dy)
      local cb, ca = -(dx * inx + dy * iny), dx * outx + dy * outy
      local lx, ly, cosL = -inx, -iny, cb
      if ca > cb then lx, ly, cosL = outx, outy, ca end
      local sinA, s0, sMax = nil, M.TAPE_IN, M.TAPE_IN_MAX
      if cosL > math.cos(math.rad(M.TAPE_PARALLEL_DEG)) then
        sinA = sqrt(max(0, 1 - cosL * cosL))
        if sinA > 1e-3 then
          rx, ry = lx, ly
          s0 = (jh + M.TAPE_CLEAR) / sinA + 1e-6      -- (a hair in: exactly TAPE_CLEAR off a straight stage)
          sMax = max(M.TAPE_IN_MAX, s0 + 10)
        else
          sinA = nil
        end
      end
      local key, len, sy = M.tapeFor(sr.halfW, sinA)
      local known = type(sr.halfW) == 'number' and sr.halfW > 0
      local s, ax, ay, bx, by = s0
      local clear = false
      -- farther in until both ends and the middle clear the stage's road, the whole line (a narrow fork's branches
      -- overlap at 8 m)
      while s <= sMax do
        local cx, cy = jx + dx * s, jy + dy * s
        ax, ay = cx + rx * len / 2, cy + ry * len / 2
        bx, by = cx - rx * len / 2, cy - ry * len / 2
        -- (its middle too: a tape longer than the stage road is wide clears it at both ends when the "side road" is
        -- the stage's own other pass, the tape lying across it)
        if L.clear(ax, ay, jh) >= M.TAPE_CLEAR and L.clear(bx, by, jh) >= M.TAPE_CLEAR and
          L.clear(cx, cy, jh) >= M.TAPE_CLEAR then clear = true break end
        s = s + 0.5
      end
      -- (a side road of unknown width: the longest tape there that still clears the stage's road at both ends --
      -- its middle is where it was -- grown in TAPE_GROW_STEP steps, each step's ends checked: props.lua's refitTape
      -- holds the tape it fits to the road map to this, so a wide side road at a fork does not take it onto the stage)
      local maxLen = len
      if clear and not known then
        local cx, cy = jx + dx * s, jy + dy * s
        while maxLen + M.TAPE_GROW_STEP <= M.TAPE_LEN_MAX + 1e-9 do
          local h2 = (maxLen + M.TAPE_GROW_STEP) / 2
          if L.clear(cx + rx * h2, cy + ry * h2, jh) >= M.TAPE_CLEAR and
            L.clear(cx - rx * h2, cy - ry * h2, jh) >= M.TAPE_CLEAR then maxLen = maxLen + M.TAPE_GROW_STEP
          else break end
        end
      end
      if clear then
        res.tapes[#res.tapes + 1] = { key = key, L = len, sy = sy, known = known, s = s, dx = dx, dy = dy, ax = ax,
                                      ay = ay, bx = bx, by = by, halfW = known and sr.halfW or M.HALF, maxLen = maxLen,
                                      sinA = sinA }
      else
        sayDropped(along, sr.deg or J and J.dirToBearing and J.dirToBearing(dx, dy))
      end
    end
  end
  return res
end

-- A junction marshal's table, chair and flag: on the closed road furthest from where a car that misses the turn would
-- go (the one least in line with the way in), MARSHAL_BEHIND m behind its tape, MARSHAL_SIDE off its centre, facing
-- back to the junction (the user, 2026-11-14). At a straight or a fork (a map marshal's: 1.6.0's note 11) the overrun
-- is the stage road itself: the closed road furthest from the way out, the marshal MARSHAL_SIDE past its edge on the
-- side away from the way out. fromMap: at a turn whose only closed road is in the overrun, behind that road's tape all
-- the same, MARSHAL_BEHIND back and MARSHAL_OVERRUN_SIDE past its edge on the side away from the way out (the rule's
-- marshals: none there).
local function junctionMarshal(r, fromMap)
  if #r.tapes == 0 then return nil end
  local turn = r.kind == 'turn'
  local wx, wy = r.tinx, r.tiny
  if not turn then wx, wy = r.toutx, r.touty end
  local tp = r.tapes[1]
  for _, x in ipairs(r.tapes) do
    if x.dx * wx + x.dy * wy < tp.dx * wx + tp.dy * wy then tp = x end
  end
  local rx, ry = rightOf(tp.dx, tp.dy)
  -- (behind a tape laid parallel with the stage -- an acute junction -- MARSHAL_BEHIND square to the tape, which is
  -- farther along its side road: at most twice as far)
  local behind = tp.sinA and min(2 * M.MARSHAL_BEHIND, M.MARSHAL_BEHIND / tp.sinA) or M.MARSHAL_BEHIND
  local d, side = tp.s + behind, M.MARSHAL_SIDE
  local away = rx * r.toutx + ry * r.touty > 0 and -1 or 1   -- (the side of the closed road away from the way out)
  if not turn then side = away * (tp.halfW + M.MARSHAL_SIDE) end
  -- (even the least in line is in the overrun: no rule marshal at this junction)
  if turn and tp.dx * wx + tp.dy * wy > math.cos(math.rad(M.MARSHAL_OVERRUN_DEG)) then
    if not fromMap then return nil end
    side = away * (tp.halfW + M.MARSHAL_OVERRUN_SIDE)
  end
  local cx, cy = r.jx + tp.dx * d + rx * side, r.jy + tp.dy * d + ry * side
  local tx, ty = -tp.dx, -tp.dy
  local qx, qy = rightOf(tx, ty)
  -- (table and chair turned 90 degrees to the right of the way they face, as props.lua's TENT: the user, 2026-11-14)
  return {
    upright('table', cx, cy, r.jz, qx, qy),
    upright('chair', cx + qx * 0.9, cy + qy * 0.9, r.jz, qx, qy),
    upright('flag', cx + tx * 1.6, cy + ty * 1.6, r.jz, tx, ty),
  }, tp
end
M._junctionMarshal = junctionMarshal

------------------------------------------------------------------------------------------ posts

-- A radio point (withMedical: and a medical point sharing its post), or a medical point alone (radio false): the
-- warning board(s) WARN_BEFORE m before, the board(s) at the point, the post POST_AFTER m after, all on the right.
local function post(L, along, radio, medical, nearSpec)
  local objs = {}
  local function board(key, s)
    local x, y, z, tx, ty = L.off(s, L.half + M.BOARD_OUT, 1)
    local nx, ny = outward(tx, ty, 1)
    objs[#objs + 1] = edged(upright(key, x, y, z, tx, ty), nx, ny, L.half + M.BOARD_OUT, L.half)
  end
  local w = along - M.WARN_BEFORE
  local medAt = 0
  if radio then
    board('radioWarn', w)
    board('radio', along)
    if medical then medAt = M.MEDICAL_AFTER end
  end
  if medical then
    board('medicalWarn', w + medAt)
    board('medical', along + medAt)
  end
  -- the gazebo with its near side on the road's edge, a table and a chair under it (as props.lua's TENT), a flag
  local pa = along + M.POST_AFTER + medAt
  local function at(fwd, out, yaw, key)
    local x, y, z, tx, ty = L.off(pa + fwd, L.half + out, 1)
    local dx, dy = tx, ty
    if yaw == 90 then dx, dy = rightOf(tx, ty) end
    local nx, ny = outward(tx, ty, 1)
    objs[#objs + 1] = edged(upright(key, x, y, z, dx, dy), nx, ny, L.half + out, L.half, 'post')
  end
  -- (nearSpec(along) true: a spectator area on the right within POST_NEAR_SPEC_M of the tent -- its camp is the
  -- tent there; the boards and the flag stay)
  if not (nearSpec and nearSpec(pa)) then
    at(0, M.TENT_OUT, 0, 'gazeboFrame')
    at(0, M.TENT_OUT, 0, 'gazeboCover')
    at(-0.3, M.TENT_OUT - 0.6, 90, 'table')
    at(-0.3, M.TENT_OUT + 0.3, 90, 'chair')
  end
  if radio then at(2.4, M.TENT_OUT, 0, 'flag') end
  return objs, w, pa + 3
end

-- A marshal post from the map away from any junction: a table, a chair and a flag off the road's edge (side 1 right,
-- -1 left). The table's long edge along the road, ROADSIDE_MARSHAL_OUT past the edge; the chair 0.9 m behind it on the
-- far side from the road, facing the road. Review round 4 (the user, 2026-11-15, of the build that set both with +Y out from
-- the road: "needs to rotate"): turned 90 degrees from that, the table's +Y along the road (tx, ty) on either side.
-- The models' axes taken (as the junction marshal's turn the user approved in note 2 implies: +Y to the right of the
-- way the marshal faces): the table's long edge along its Y, the chair's seat facing its -X. So the chair faces the
-- road with its -X towards it -- +Y along (tx, ty) on the right, (-tx, -ty) on the left -- and the table, the same
-- either way round, takes (tx, ty) on both sides. 1.6.0's note 10 (the user, of that build: "the chair needs to flip
-- 180"): the chair turned round from that on both sides -- +Y against (tx, ty) on the right, along it on the left, its
-- +X towards the road -- and the group 1 m further out.
local function roadsideMarshal(L, along, side)
  local o = L.half + M.ROADSIDE_MARSHAL_OUT
  local x, y, z, tx, ty = L.off(along, o, side)
  local nx, ny = outward(tx, ty, side)
  -- (the chair's +Y: its +X towards the road -- +X = (-nx, -ny) -- so +Y = (ny, -nx))
  local cx, cy = ny, -nx
  return {
    edged(upright('table', x, y, z, tx, ty), nx, ny, o, L.half, 'marshal'),
    edged(upright('chair', x + nx * 0.9, y + ny * 0.9, z, cx, cy), nx, ny, o + 0.9, L.half, 'marshal'),
    edged(upright('flag', x + tx * 1.6, y + ty * 1.6, z, tx, ty), nx, ny, o, L.half, 'marshal'),
  }
end

------------------------------------------------------------------------------------------ spectators

-- A spectator area on the inside of a corner (side 1 right, -1 left) from s0 to s1 along, its apex at sApex: a run of
-- 5 m tape SPEC_OFF off the road's edge, the 2 m mesh fence FENCE_BEHIND behind it, hay bales at the inside edge
-- around the apex, and behind the fence a gazebo, a row of chairs and two tarps (the mock-up drew these by hand for
-- its hairpin; here they go on the line in from the apex, as far in as it takes to be clear of the whole road).
-- clearOf(x, y): how far a point is clear of every road there (the stage and the junctions' side roads).
local function spectators(L, s0, s1, sApex, side, clearOf)
  local objs = {}
  local half = L.half
  local function run(off, chord, key, cap)
    local n = 0
    local s = s0
    while s < s1 - 0.1 and n < cap do
      local ax, ay, az = L.off(s, half + off, side)
      local e = s + 0.5
      local bx, by, _, btx, bty = L.off(e, half + off, side)
      while e < s1 and (bx - ax) ^ 2 + (by - ay) ^ 2 < chord * chord do
        e = e + 0.25
        bx, by, _, btx, bty = L.off(e, half + off, side)
      end
      local l = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
      if l < chord * 0.8 then break end           -- (a short end left bare: the model is its own length)
      -- (not over another part of the road: the far leg of a tight hairpin, a side road -- its middle too)
      if clearOf(ax, ay) >= off - 1 and clearOf(bx, by) >= off - 1 and clearOf((ax + bx) / 2, (ay + by) / 2) >= off - 1
      then
        local nx, ny = outward(btx, bty, side)
        local o = edged(linear(key, ax, ay, bx, by, az), nx, ny, half + off, half)
        o.offRoad = true      -- (props.lua leaves it out where the road map has a road under it: a branch not planned)
        objs[#objs + 1] = o
        n = n + 1
      end
      s = e
    end
    return n
  end
  run(M.SPEC_OFF, 5, 'specTape', M.SPEC_TAPE_MAX)
  run(M.SPEC_OFF + M.FENCE_BEHIND, 2, 'fence', M.SPEC_FENCE_MAX)
  -- hay bales at the inside edge, at the apex and 12 m either side; one that would stand on a road (at a Y-shaped
  -- hairpin the inside of the turn is another road, or the hairpin's other leg) left out. The three one group
  -- (review round 4): props.lua sets each off the game's road edge and pushes the row out together until all of it
  -- is clear of every road (or leaves the row out), so they stay in line
  for _, ds in ipairs({ -12, 0, 12 }) do
    local s = sApex + ds
    local x, y, z, tx, ty = L.off(s, half + M.BALE_OFF, side)
    if s >= s0 and s <= s1 and clearOf(x, y) >= M.BALE_CLEAR then
      local nx, ny = outward(tx, ty, side)
      objs[#objs + 1] = edged(upright('bale', x, y, z, tx, ty), nx, ny, half + M.BALE_OFF, half, 'bales')
    end
  end
  -- the camp: in from the apex until clear of the road by the fence and a little more
  local px, py, pz, tx, ty = L.at(sApex)
  local nx, ny = rightOf(tx, ty)
  nx, ny = nx * side, ny * side
  local need = M.SPEC_OFF + M.FENCE_BEHIND + 2
  for d = half + need + 1, half + need + 40, 1 do
    local gx, gy = px + nx * d, py + ny * d
    if clearOf(gx, gy) >= need then
      -- facing the road (its +Y away from the apex: chairs and tarps as the gazebo's)
      local fx, fy = -nx, -ny
      local ex, ey = tx, ty
      objs[#objs + 1] = edged(upright('gazeboFrame', gx, gy, pz, fx, fy), nx, ny, d, half, 'camp')
      objs[#objs + 1] = edged(upright('gazeboCover', gx, gy, pz, fx, fy), nx, ny, d, half, 'camp')
      -- (the chairs turned 90 degrees to the right of the way the camp faces, as props.lua's TENT)
      local cx, cy = rightOf(fx, fy)
      for k = 0, 3 do
        local o = -2 + k * 1.3
        objs[#objs + 1] = edged(upright('chair', gx - nx * 3.5 + ex * o, gy - ny * 3.5 + ey * o, pz, cx, cy),
          nx, ny, d - 3.5, half, 'camp')
      end
      for _, sgn in ipairs({ -1, 1 }) do
        local ax, ay = gx + nx * 4 + ex * 6 * sgn, gy + ny * 4 + ey * 6 * sgn
        objs[#objs + 1] = edged(linear('tarp', ax, ay, ax + nx * 4, ay + ny * 4, pz), nx, ny, d + 8, half, 'camp')
      end
      break
    end
  end
  return objs
end

------------------------------------------------------------------------------------------ the showcase

-- A developer's look at every dressing shape in the game, the models' turns being read from their mesh data and never
-- seen standing (runner.dressShowcase puts it down). One of each in a row across the way the car faces, AHEAD_M in
-- front of it, left to right as the driver sees them, each turned by the same code a real site's is, as if the car
-- were driving up a road towards them: the boards' faces towards the car, the arrows pointing their own way, each
-- tape, fence and tarp laid across the road from left to right. Returns { { label, key, object }... } in that order.
M.SHOWCASE_AHEAD_M = 15
M.SHOWCASE_GAP_M = 1.5
M.SHOWCASE = {
  'tape6', 'tape8', 'tape10', 'dirLeft', 'dirRight', 'dirStraight', 'dir45Left', 'dir45Right', 'dir135Right',
  'dir225Left', 'radioWarn', 'radio', 'medicalWarn', 'medical', 'specTape', 'fence', 'tarp', 'gazeboFrame',
  'gazeboCover', 'table', 'chair', 'bale', 'flag',
}
local WIDE = { gazeboFrame = 3, gazeboCover = 3, table = 1.2, chair = 0.6, bale = 1.5, flag = 0.5 }
function M.showcase(x, y, z, hx, hy)
  hx, hy = norm(hx, hy)
  local rx, ry = rightOf(hx, hy)
  local cx, cy = x + hx * M.SHOWCASE_AHEAD_M, y + hy * M.SHOWCASE_AHEAD_M
  local widths, total = {}, 0
  for i, key in ipairs(M.SHOWCASE) do
    widths[i] = M.LINEAR_M[key] or WIDE[key] or 1
    if key ~= 'gazeboCover' then total = total + widths[i] + M.SHOWCASE_GAP_M end
  end
  local out = {}
  local at = -total / 2
  for i, key in ipairs(M.SHOWCASE) do
    -- (the gazebo's cover goes on its frame: the same spot)
    if key == 'gazeboCover' then at = at - widths[i - 1] - M.SHOWCASE_GAP_M end
    local w = widths[i]
    local ax, ay = cx + rx * at, cy + ry * at
    local bx, by = cx + rx * (at + w), cy + ry * (at + w)
    local mx, my = (ax + bx) / 2, (ay + by) / 2
    local o
    if M.LINEAR_M[key] then o = linear(key, ax, ay, bx, by, z)
    elseif key:find('^dir') then o = arrowBoard(key, mx, my, z, hx, hy)
    else o = upright(key, mx, my, z, hx, hy) end
    out[#out + 1] = { label = string.format('%d %s (%s)', #out + 1, key, M.SHAPES[key]:match('([^/]+)$')), key = key,
                      object = o }
    at = at + w + M.SHOWCASE_GAP_M
  end
  return out
end

------------------------------------------------------------------------------------------ the plan

-- A small seeded random number generator of its own (not math.random's one shared state): a seed (a string or a
-- number) and a stream name give the same numbers every time. Park-Miller (multiplier 48271, modulus 2^31 - 1), its
-- state from a djb2 hash of "<seed>|<stream>", stirred a few times so seeds alike do not start alike. rng() a number
-- in [0, 1); rng(a, b) one in [a, b).
local PM_M = 2147483647
function M.rng(seed, stream)
  local s = tostring(seed or '') .. '|' .. tostring(stream or '')
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % PM_M end
  if h == 0 then h = 1 end
  local function nxt() h = (h * 48271) % PM_M return h end
  for _ = 1, 8 do nxt() end
  return function(a, b)
    local u = (nxt() - 1) / (PM_M - 1)
    if a then return a + (b - a) * u end
    return u
  end
end

-- (a copy of list in an order by chance: Fisher-Yates with rnd)
local function shuffled(list, rnd)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  for i = #out, 2, -1 do
    local j = math.floor(rnd() * i) + 1
    if j > i then j = i end
    out[i], out[j] = out[j], out[i]
  end
  return out
end
M._shuffled = shuffled

local function capped(objs, kind)
  local b = M.BUDGET[kind] or 16
  if #objs <= b then return objs end
  local out = {}
  for i = 1, b do out[i] = objs[i] end
  return out
end

-- Points of one kind (sorted along the line) merged: each joins a group on the same side (with sideOf(m) given: -1 /
-- 1) whose last point is within MERGE_M of it along the line -- while that keeps the group's first to last within
-- SPEC_SPAN_MAX_M (a chain stops growing there; the next point starts a group) -- or, with posOf(m) -> x, y given,
-- any of whose points is within MERGE_GROUND_M of it on the ground when it is further than MERGE_M along (a
-- hairpin's other leg). Returns the groups, in
-- order: { along (the first point's), first, last, side, name (the first's), offLineM (the first's), n }.
local function merged(list, sideOf, posOf)
  local out = {}
  for _, m in ipairs(list) do
    local side = sideOf and sideOf(m) or 1
    local px, py
    if posOf then px, py = posOf(m) end
    local hit = nil
    for k = #out, 1, -1 do
      local g = out[k]
      if g.side == side then
        local alongOk = m.along - g.last <= M.MERGE_M and
          max(g.last, m.along) - min(g.first, m.along) <= M.SPEC_SPAN_MAX_M + 1e-9
        local groundOk = false
        -- (on the ground only for a point beyond MERGE_M along: one nearer is the chain's, and held to its span)
        if px and m.along - g.last > M.MERGE_M then
          for _, q in ipairs(g.pts) do
            if (q[1] - px) ^ 2 + (q[2] - py) ^ 2 <= M.MERGE_GROUND_M ^ 2 then groundOk = true break end
          end
        end
        if alongOk or groundOk then hit = g break end
      end
    end
    if hit then
      hit.first, hit.last, hit.n = min(hit.first, m.along), max(hit.last, m.along), hit.n + 1
      if px then hit.pts[#hit.pts + 1] = { px, py } end
    else
      out[#out + 1] = { along = m.along, first = m.along, last = m.along, side = side, name = m.name,
                        offLineM = m.offLineM, n = 1, pts = px and { { px, py } } or {} }
    end
  end
  return out
end
M._merged = merged
local function sideOfMark(m) return (m.offLineM or 0) < 0 and -1 or 1 end

-- input: { line = { {x, y, z}... } (game coordinates, the stage line), cum (or nil: worked out), startM, finishM,
--   junctions = { { along, x, y, kind = 'turn' | 'straight' | 'fork', side (a fork's kept side), inDeg, outDeg (the
--     driving direction arriving and leaving, compass degrees; nil: from the line), sides = { { deg (from the junction
--     out along the side road), halfW }... } }... },
--   marks = { { kind = 'radio' | 'medical' | 'spectator' | 'marshal', along, offLineM (signed: < 0 left), name }... },
--   corners = (stageWriter.stageCorners' list: { i0, i1, dir, angleDeg, minRadius }, its indices samples every
--     cornerStepM (default 5, stageWriter.NOTE_STEP_M) from cornerStartM (default startM); or corners carrying their
--     own `from` / `to` along the line),
--   halfWidth (default 3),
--   seed (the automatic fill's chance: the same seed, the same dressing; default ''),
--   mapKinds = { radio = true, spectator = true, ... } (the kinds the rally's map marks on ANY of its stages:
--     events.markedKinds, counting only the marks some stage would use; a kind marked there, or in `marks` within this
--     stage's span, is never filled in by chance on this stage) }
function M.plan(input)
  local line = input.line
  if not line or #line < 2 then return {} end
  local cum = input.cum or geo.cumulative(line)
  local half = input.halfWidth or M.HALF
  local L = Line(line, cum, half)
  local startM = input.startM or 0
  local finishM = input.finishM or L.total
  local sites = {}
  local function add(kind, source, along, from, to, objs, name)
    objs = capped(objs, kind)
    if #objs == 0 then return end
    sites[#sites + 1] = { kind = kind, source = source, along = along, from = min(from, to), to = max(from, to),
                          objects = objs, name = name }
  end

  -- marks from the map, by kind, on the stage (the runner has already dropped those too far off the line driven),
  -- from MARKS_SPAN_PAD_M before the start to as far past the finish (events.stageMarks counts with the same span).
  -- Per kind and per rally (1.6.0's note 5, the user: "if a rally event has spots marked on a map for at least one
  -- stage, don't assume random on the others, assume zero"): a kind the rally's map marks where a stage uses it -- on
  -- another stage, or on this one -- is the map's alone, and a stage without one of them gets none (review round 4:
  -- a mark no stage uses, outside every span or too far off every line, no longer counts); only a
  -- kind the rally marks nowhere is filled in by chance (medical never is; the junction marshals at taped turns are
  -- dressing, not map points, and stay either way).
  local marks = { radio = {}, medical = {}, spectator = {}, marshal = {} }
  local rallyMarks = {}
  for k, v in pairs(input.mapKinds or {}) do if v then rallyMarks[k] = true end end
  local pad = M.MARKS_SPAN_PAD_M
  for _, m in ipairs(input.marks or {}) do
    if marks[m.kind] and m.along and m.along >= startM - pad and m.along <= finishM + pad then
      marks[m.kind][#marks[m.kind] + 1] = m
      rallyMarks[m.kind] = true
    end
  end
  for _, list in pairs(marks) do table.sort(list, function(a, b) return a.along < b.along end) end

  -- junctions: tape and boards at every one, from either source
  local solved = {}
  local js = {}
  for _, j in ipairs(input.junctions or {}) do
    if j.along and j.along >= startM and j.along <= finishM then js[#js + 1] = j end
  end
  table.sort(js, function(a, b) return a.along < b.along end)
  for _, j in ipairs(js) do
    local r = solveJunction(L, j)
    solved[#solved + 1] = r
    local objs = {}
    for _, tp in ipairs(r.tapes) do
      if not tp.known then
        -- (a side road of unknown width: ONE object, the whole tape, which props.lua refits about its own middle to
        -- the road map's side road where it goes down -- no longer than maxLen -- and lays as one or two pieces
        -- there. Until 1.6.0's note 8 a tape planned as two pieces was refit piece by piece, each about a middle of
        -- its own, so the two came out off the side road's centre.)
        local o = linear(tp.key, tp.ax, tp.ay, tp.bx, tp.by, r.jz)
        if abs(tp.sy - 1) > 1e-9 then o.sy = tp.sy end
        o.refit, o.maxLen = refit(tp.L, tp.sinA), tp.maxLen
        objs[#objs + 1] = o
      else
        for _, pc in ipairs(M.tapePieces(tp.ax, tp.ay, tp.bx, tp.by, tp.L, tp.L / tp.sy)) do
          local o = linear(tp.key, pc[1], pc[2], pc[3], pc[4], r.jz)
          if abs(pc[5] - 1) > 1e-9 then o.sy = pc[5] end
          objs[#objs + 1] = o
        end
      end
    end
    add('tape', 'rule', j.along, j.along, j.along, objs, j.kind)
    local key, side = M.dirBoard(r.turnDeg, j.kind, j.side)
    -- (none before the start line: a junction just after it is not called from the start area)
    if key and j.along - M.BOARD_BEFORE >= startM then
      local s = j.along - M.BOARD_BEFORE
      local sg = side == 'right' and 1 or -1
      local x, y, z, tx, ty = L.off(s, r.half + M.DIR_BOARD_OUT, sg)
      local nx, ny = outward(tx, ty, sg)
      add('board', 'rule', j.along, s, s, { edged(arrowBoard(key, x, y, z, tx, ty), nx, ny, r.half + M.DIR_BOARD_OUT,
        r.half) }, key)
    end
  end
  -- (every side road there, for keeping spectators off them)
  local function clearOf(x, y, s)
    local c = L.clear(x, y)
    for _, r in ipairs(solved) do
      if abs(r.along - s) < 250 then
        for _, tp in ipairs(r.tapes) do
          local k = max(0, min(60, (x - r.jx) * tp.dx + (y - r.jy) * tp.dy))
          local ex, ey = x - (r.jx + tp.dx * k), y - (r.jy + tp.dy * k)
          c = min(c, sqrt(ex * ex + ey * ey) - tp.halfW)
        end
      end
    end
    return c
  end

  -- (a map point's place on the ground: offLineM to its side of the line at its distance along)
  local function posOfMark(m)
    local off = m.offLineM or 0
    local x, y = L.off(m.along, abs(off), off < 0 and -1 or 1)
    return x, y
  end
  -- (the spectator areas placed, { s0, s1, side }: a radio / medical post near one on its side has no tent of its
  -- own)
  local specAreas = {}
  local function nearSpec(along)
    for _, a in ipairs(specAreas) do
      if a.side == 1 and along >= a.s0 - M.POST_NEAR_SPEC_M and along <= a.s1 + M.POST_NEAR_SPEC_M then return true end
    end
    return false
  end

  -- spectator areas first (a radio / medical post by one has no tent: below): the map's (points on one side within
  -- MERGE_M of each other one area), else -- where the rally's
  -- map marks no spectator point anywhere -- at most one per SPEC_EVERY_M at the stage's hairpins and big junction
  -- turns (picked by chance among them), none in the first SPEC_NOT_FIRST_M
  local cStep = input.cornerStepM or 5
  local cStart = input.cornerStartM or startM
  local corners = {}
  for _, c in ipairs(input.corners or {}) do
    local from = c.from or (c.i0 and cStart + (c.i0 - 1) * cStep)
    local to = c.to or (c.i1 and cStart + (c.i1 - 1) * cStep)
    if from and to then
      corners[#corners + 1] = { from = from, to = to, side = c.dir == 'left' and -1 or 1, angle = c.angleDeg or 0,
                                radius = c.minRadius or huge }
    end
  end
  local function spectatorSite(s0, s1, apex, side, source, name)
    s0, s1 = max(s0, apex - M.SPEC_SPAN_MAX_M / 2), min(s1, apex + M.SPEC_SPAN_MAX_M / 2)
    local objs = spectators(L, s0, s1, apex, side, function(x, y) return clearOf(x, y, apex) end)
    local n = #sites
    add('spectators', source, apex, s0, s1, objs, name)
    if #sites > n then specAreas[#specAreas + 1] = { s0 = s0, s1 = s1, side = side } end
  end
  if #marks.spectator > 0 then
    -- each on the inside of the corner it is at, else the side the map put it; those on one side within MERGE_M of
    -- each other one area, from SPEC_POINT_M before the first to as far past the last, its apex in the middle (and
    -- held to SPEC_SPAN_MAX_M round it: spectatorSite). (Until 1.6.0's note 7 each point was an area of its own: two
    -- gazebos one after the other where the map put two points for one area.)
    local function sideOf(m)
      for _, c in ipairs(corners) do
        if m.along >= c.from - 60 and m.along <= c.to + 60 then return c.side end
      end
      return sideOfMark(m)
    end
    for _, g in ipairs(merged(marks.spectator, sideOf, posOfMark)) do
      spectatorSite(g.first - M.SPEC_POINT_M, g.last + M.SPEC_POINT_M, (g.first + g.last) / 2, g.side, 'map', g.name)
    end
  elseif not rallyMarks.spectator then
    local cand = {}
    for _, c in ipairs(corners) do
      if c.radius <= M.SPEC_MAX_RADIUS_M and c.angle >= M.SPEC_MIN_ANGLE then
        cand[#cand + 1] = { apex = (c.from + c.to) / 2, s0 = c.from - M.SPEC_LEAD_M, s1 = c.to + M.SPEC_LEAD_M,
                            side = c.side, score = c.angle, radius = c.radius }
      end
    end
    for _, r in ipairs(solved) do
      if r.kind == 'turn' and abs(r.turnDeg) >= M.SPEC_MIN_TURN then
        cand[#cand + 1] = { apex = r.along, s0 = r.along - M.SPEC_LEAD_M, s1 = r.along + M.SPEC_LEAD_M,
                            side = r.turnDeg > 0 and -1 or 1, score = abs(r.turnDeg), radius = huge }
      end
    end
    -- (which of them by chance: the qualifying corners in an order by chance, each kept unless one already kept is
    -- within SPEC_EVERY_M; sorted along the stage first, so the chance alone decides)
    table.sort(cand, function(a, b)
      if a.apex ~= b.apex then return a.apex < b.apex end
      return a.score > b.score
    end)
    local kept = {}
    for _, c in ipairs(shuffled(cand, M.rng(input.seed, 'spectator'))) do
      local ok = c.apex >= startM + M.SPEC_NOT_FIRST_M and c.apex <= finishM
      for _, k in ipairs(kept) do if abs(k.apex - c.apex) < M.SPEC_EVERY_M then ok = false end end
      if ok then kept[#kept + 1] = c end
    end
    for _, c in ipairs(kept) do spectatorSite(c.s0, c.s1, c.apex, c.side, 'rule') end
  end

  -- radio and medical points first (a roadside marshal post near one is left out, below). Radio: the map's, merged
  -- where within MERGE_M of each other (one post at the first); else, where the rally's map marks no radio point
  -- anywhere, every ~RADIO_EVERY_M (none in the last RADIO_NOT_LAST_M), each moved along until its post is clear of
  -- the junctions
  local radios = {}
  if #marks.radio > 0 then
    for _, g in ipairs(merged(marks.radio, nil, posOfMark)) do radios[#radios + 1] = { along = g.along, source = 'map', name = g.name } end
  elseif not rallyMarks.radio then
    local function clearOfJunctions(s)
      for _, r in ipairs(solved) do
        if r.along >= s - M.RADIO_CLEAR_M and r.along <= s + M.POST_AFTER + M.MEDICAL_AFTER + M.RADIO_CLEAR_M then
          return false
        end
      end
      return true
    end
    -- (each the next RADIO_GAP_MIN_M .. RADIO_GAP_MAX_M on from the last, by chance)
    local rnd = M.rng(input.seed, 'radio')
    local s = startM + rnd(M.RADIO_GAP_MIN_M, M.RADIO_GAP_MAX_M)
    while s <= finishM - M.RADIO_NOT_LAST_M do
      local at = s
      for k = 0, 12 do
        local cand = s + (k % 2 == 0 and 1 or -1) * math.ceil(k / 2) * 25
        if cand <= finishM - M.RADIO_NOT_LAST_M and clearOfJunctions(cand) then at = cand break end
      end
      radios[#radios + 1] = { along = at, source = 'rule' }
      s = at + rnd(M.RADIO_GAP_MIN_M, M.RADIO_GAP_MAX_M)
    end
  end
  -- medical points: only the map's, merged as the radio points; one within SHARE_M of a radio point shares its post
  local medicals = {}
  for _, m in ipairs(merged(marks.medical, nil, posOfMark)) do
    local best, bd = nil, M.SHARE_M
    for _, r in ipairs(radios) do
      if not r.medical and abs(r.along - m.along) <= bd then best, bd = r, abs(r.along - m.along) end
    end
    if best then best.medical = m
    else medicals[#medicals + 1] = m end
  end
  for _, m in ipairs(medicals) do
    local objs, from, to = post(L, m.along, false, true, nearSpec)
    add('medical', 'map', m.along, from, to, objs, m.name)
  end
  for _, r in ipairs(radios) do
    local objs, from, to = post(L, r.along, true, r.medical ~= nil, nearSpec)
    add('radio', r.source, r.along, from, to, objs, r.name or (r.medical and r.medical.name))
    if r.medical then sites[#sites].shared = true end
  end
  local function nearPost(along)
    for _, r in ipairs(radios) do if abs(r.along - along) <= M.MARSHAL_NEAR_POST_M then return true end end
    for _, m in ipairs(medicals) do if abs(m.along - along) <= M.MARSHAL_NEAR_POST_M then return true end end
    return false
  end

  -- marshals: from the map where it marks any on the stage (merged within MERGE_M on one side; behind a taped
  -- junction's tape when near one, else by the road -- and none by the road within MARSHAL_NEAR_POST_M of a radio /
  -- medical post); else at junction turns, at most one per MARSHAL_EVERY_M
  -- (the nearest taped junction within that of the mark's point on the ground: so a second mark is the same junction's
  -- only when it too is within the window of it)
  local function tapedNear(m, within)
    local mx, my = posOfMark(m)
    local best, bd = nil, within
    for _, r in ipairs(solved) do
      local d = sqrt((mx - r.jx) ^ 2 + (my - r.jy) ^ 2)
      if #r.tapes > 0 and d <= bd then best, bd = r, d end
    end
    return best
  end
  if #marks.marshal > 0 then
    -- (each of the map's marshals first to the taped junction it is at, if any -- one marshal behind its tape however
    -- many marks are by it -- and only those left by the road merged: review round 4; until then the marks were merged
    -- first, so a turn's mark could be merged into a roadside one before it, or the other way round)
    local used, roadside = {}, {}
    for _, m in ipairs(marks.marshal) do
      local r = tapedNear(m, M.MARSHAL_AT_JUNCTION_M)
      if r and used[r] then
        -- (that junction's marshal stands already: this mark is the same one)
      else
        -- (a turn whose only closed road is in the overrun: still behind that road's tape, well to its side)
        local jm = r and junctionMarshal(r, true)
        if jm then
          used[r] = true
          add('marshal', 'map', r.along, r.along, r.along, jm, m.name)
        else
          roadside[#roadside + 1] = m
        end
      end
    end
    for _, m in ipairs(merged(roadside, sideOfMark, posOfMark)) do
      if not nearPost(m.along) then
        add('marshal', 'map', m.along, m.along, m.along, roadsideMarshal(L, m.along, m.side), m.name)
      end
    end
  else
    -- (every turn that can have one, but none within MARSHAL_EVERY_M of another: where two are that close, which
    -- one keeps its marshal is by chance -- the turns taken in an order by chance, each kept unless one already kept
    -- is too near)
    local rnd = M.rng(input.seed, 'marshal')
    local eligible = {}
    for _, r in ipairs(solved) do
      if r.kind == 'turn' and #r.tapes > 0 then
        local jm = junctionMarshal(r)
        if jm then eligible[#eligible + 1] = { r = r, jm = jm } end
      end
    end
    local standing = {}
    for _, e in ipairs(shuffled(eligible, rnd)) do
      local ok = true
      for _, a in ipairs(standing) do if abs(e.r.along - a) < M.MARSHAL_EVERY_M then ok = false break end end
      if ok then
        add('marshal', 'rule', e.r.along, e.r.along, e.r.along, e.jm)
        standing[#standing + 1] = e.r.along
      end
    end
  end

  table.sort(sites, function(a, b) if a.from ~= b.from then return a.from < b.from end return a.along < b.along end)
  return sites
end

return M
