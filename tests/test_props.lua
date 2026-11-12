-- The roadside boards' facing, against a copy of the game's own quatFromDir (lua/common/mathlib.lua,
-- LuaQuat:setFromDir), on roads running every way: a mirrored turn looks right only on a road running north-south.
local T = dofile(TESTS .. '/testlib.lua')
function log() end
local props = require('earthRally/props')

-- the game's setFromDir(dir, up = +Z), for a level direction
local function gameQuat(dx, dy)
  local l = math.sqrt(dx * dx + dy * dy)
  local d = { dx / l, dy / l, 0 }
  local u = { 0, 0, 1 }
  local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end
  local m = {}
  m[1] = d
  m[0] = cross(d, u)
  m[2] = cross(m[0], d)
  local function at(i, j) return m[i][j + 1] end
  local tr = at(0, 0) + at(1, 1) + at(2, 2)
  if tr > 0 then
    local s = math.sqrt(tr + 1)
    local w = s * 0.5
    s = 0.5 / s
    return { (at(2, 1) - at(1, 2)) * s, (at(0, 2) - at(2, 0)) * s, (at(1, 0) - at(0, 1)) * s, w }
  end
  local i = 0
  if at(1, 1) > at(0, 0) then i = 1 end
  if at(2, 2) > at(i, i) then i = 2 end
  local j, k = (i + 1) % 3, (i + 2) % 3
  local q = { [0] = 0, 0, 0 }
  local s = math.sqrt((at(i, i) - at(j, j)) - (at(k, k) - 1))
  q[i] = s * 0.5
  s = 0.5 / s
  q[j] = (at(j, i) + at(i, j)) * s
  q[k] = (at(k, i) + at(i, k)) * s
  local w = (at(k, j) - at(j, k)) * s
  return { q[0], q[1], q[2], w }
end

local worst = 0
for deg = 0, 345, 15 do
  local h = math.rad(deg)
  local dx, dy = math.sin(h), math.cos(h)       -- (clockwise from north)
  local q, g = props._yawQuat(dx, dy), gameQuat(dx, dy)
  -- the same rotation: q and -q are one
  local dot = math.abs(q[1] * g[1] + q[2] * g[2] + q[3] * g[3] + q[4] * g[4])
  worst = math.max(worst, 1 - dot)
end
T.check(worst < 1e-6, 'a board turned as the game turns it, on roads running every way (worst ' .. string.format('%.2g', worst) .. ')')

-- a road running east: the board's front (+Y) turned to +X, not to -X
local q = props._yawQuat(1, 0)
local x, y, z, w = q[1], q[2], q[3], q[4]
-- +Y rotated by q (the game's convention, as gameQuat: rows): column of the rotation matrix, conjugated
local gx = gameQuat(1, 0)
T.check(math.abs(z - gx[3]) < 1e-9 and math.abs(w - gx[4]) < 1e-9, 'east: the same quaternion as the game\'s')
T.done('test_props')
