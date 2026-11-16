-- earthRally/report: "Report a problem" (docs/mockups-telemetry/telemetry.html, #reportweb). Nothing leaves the game
-- by itself: the player's browser opens a new GitHub issue with the versions and what they wrote filled in, and, if
-- they ticked it, the game log is saved cleaned (clean() below) to REPORT_DIR, whose folder opens beside it so they
-- can drag the file in. Works with stats on or off.
local M = {}

M.ISSUE_URL = 'https://github.com/DeRamp/BeamNG.Earth.Rally/issues/new'
M.LOG_FILE = '/beamng.log'
M.REPORT_DIR = '/earthRally/reports/'
M.TAIL_LINES = 400          -- the log's last lines kept whole; before them only Earth Rally's own lines
M.MAX_BYTES = 900 * 1024
M.TEXT_MAX = 1500           -- what the player wrote, in the address (browsers cut very long ones)

local function lines(text)
  local out = {}
  for l in (text .. '\n'):gmatch('(.-)\r?\n') do out[#out + 1] = l end
  if out[#out] == '' then out[#out] = nil end
  return out
end

-- (a dotted quad whose parts are all 0..255, and that is not part of a longer dotted number such as a version)
local function scrubIps(l)
  return (l:gsub('()(%d+)%.(%d+)%.(%d+)%.(%d+)()', function(s, a, b, c, d, e)
    local before, after = l:sub(s - 1, s - 1), l:sub(e, e + 1)
    if before == '.' or before:match('%d') or after:match('^%.%d') or after:match('^%d') then return nil end
    for _, p in ipairs({ a, b, c, d }) do if tonumber(p) > 255 then return nil end end
    return '<removed>'
  end))
end

-- (an IPv6 address: hex groups and colons, with a '::' or a hex letter, so a clock time like 12:34:56 is kept)
local function scrubIp6(l)
  return (l:gsub('[%x:][%x:][%x:]+', function(m)
    local _, colons = m:gsub(':', '')
    if colons < 2 or #m < 6 then return nil end
    if not (m:find('::', 1, true) or m:find('%a')) then return nil end
    if m:find('[^:]%x%x%x%x%x') then return nil end         -- (a group longer than 4: a hash, not an address)
    return '<removed>'
  end))
end

-- a pattern matching s in any letter case
local function anyCase(s)
  return (s:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%0'):gsub('%a', function(c) return '[' .. c:lower() .. c:upper() .. ']' end))
end

-- The log with the player's details taken out: the user name (in Windows, Mac and Linux paths and anywhere else,
-- any letter case), a OneDrive organisation name, Steam IDs and Steam names, email addresses, IP addresses (v4 and
-- v6), the hardware hash line. user: the user name, if known.
function M.clean(text, user)
  local out = {}
  local userPat = (type(user) == 'string' and #user >= 3) and anyCase(user) or nil
  for _, l in ipairs(lines(text or '')) do
    local low = l:lower()
    if low:find('%f[%w]h2%f[%W]') or low:find('hardware hash') or low:find('hwid')
      or (low:find('steam') and (low:find('name') or low:find('persona') or low:find('user'))) then
      l = '<line removed>'
    else
      l = l:gsub('([A-Za-z]:[\\/][Uu][Ss][Ee][Rr][Ss][\\/])[^\\/\r\n"\']+', '%1<you>')
      l = l:gsub('(/[Uu]sers/)[^/\r\n"\']+', '%1<you>')
      l = l:gsub('(/home/)[^/\r\n"\']+', '%1<you>')
      l = l:gsub('([Oo]ne[Dd]rive ?%- ?)[^\\/\r\n"\']+', '%1<removed>')
      l = l:gsub('7656119%d%d%d%d%d%d%d%d%d%d', '<removed>')
      l = l:gsub('[%w%.%-_+]+@[%w%-]+%.[%w%.%-]+', '<removed>')
      l = scrubIps(l)
      l = scrubIp6(l)
      if userPat then l = l:gsub(userPat, '<you>') end
    end
    out[#out + 1] = l
  end
  return out
end

-- Which lines go in the report: Earth Rally's own lines from anywhere, then the last TAIL_LINES whole, under
-- MAX_BYTES (the oldest dropped first).
function M.pick(ls)
  local out, n = {}, #ls
  local tailFrom = math.max(1, n - M.TAIL_LINES + 1)
  for i = 1, tailFrom - 1 do
    if ls[i]:find('earthRally', 1, true) or ls[i]:find('earth_rally', 1, true) then out[#out + 1] = ls[i] end
  end
  if tailFrom > 1 then out[#out + 1] = '... (the rest of the log before here left out) ...' end
  for i = tailFrom, n do out[#out + 1] = ls[i] end
  local text = table.concat(out, '\n')
  while #text > M.MAX_BYTES and #out > 1 do table.remove(out, 1) text = table.concat(out, '\n') end
  return text
end

local function urlEncode(s)
  return (tostring(s):gsub('[^%w%-_%.~]', function(c) return string.format('%%%02X', c:byte()) end))
end

-- The issue's address. info: { mod, game, earth, stage, text, logFile }
function M.issueUrl(info)
  local text = tostring(info.text or ''):sub(1, M.TEXT_MAX)
  local first = text:match('^%s*([^\r\n]+)') or ''
  local title = first ~= '' and first:sub(1, 80) or 'Bug report'
  local body = table.concat({
    '**What happened**', '', text ~= '' and text or '(describe it here)', '',
    '**Versions**', '',
    '- Earth Rally: ' .. tostring(info.mod or '?'),
    '- BeamNG.drive: ' .. tostring(info.game or '?'),
    '- BeamNG.Earth API: ' .. tostring(info.earth or '?'),
    info.stage and ('- Stage: ' .. info.stage) or '- Stage: none',
    '',
    info.logFile and ('**Log**: drag `' .. info.logFile .. '` from the folder that opened into this box ' ..
      '(personal details already removed; read it first if you like).') or '**Log**: not attached.',
  }, '\n')
  return M.ISSUE_URL .. '?labels=bug&title=' .. urlEncode(title) .. '&body=' .. urlEncode(body)
end

local function readLog()
  local okF, f = pcall(io.open, M.LOG_FILE, 'r')
  if okF and f then local t = f:read('*a') f:close() return t end
  local rf = rawget(_G, 'readFile')
  if rf then local ok, t = pcall(rf, M.LOG_FILE) if ok then return t end end
  return nil
end

-- Save the cleaned log. Returns the file's name in the user folder, or nil and why.
function M.saveLog()
  local text = readLog()
  if not text or text == '' then return nil, 'the game log could not be read' end
  local user = os.getenv and (os.getenv('USERNAME') or os.getenv('USER')) or nil
  -- (picked first, then cleaned: a long log is mostly left out, no need to clean it all)
  local out = table.concat(M.clean(M.pick(lines(text)), user), '\n')
  local name = M.REPORT_DIR .. 'log-' .. os.date('%Y%m%d-%H%M%S') .. '.txt'
  local wf = rawget(_G, 'writeFile')
  local ok = false
  if wf then local okW, r = pcall(wf, name, out) ok = okW and r ~= false end
  if not ok then
    local okF, f = pcall(io.open, name, 'w')
    if okF and f then f:write(out) f:close() ok = true end
  end
  if not ok then return nil, 'the log could not be saved' end
  return name
end

-- The button: text (what the player wrote), withLog, info { mod, game, earth, stage }. Returns { ok, message, logFile }
function M.open(text, withLog, info)
  info = info or {}
  info.text = text
  local logFile, why = nil, nil
  if withLog then logFile, why = M.saveLog() end
  info.logFile = logFile and ('earthRally/reports/' .. logFile:match('[^/]+$')) or nil
  local plat = rawget(_G, 'Engine') and Engine.Platform
  if logFile and plat and plat.exploreFolder then pcall(plat.exploreFolder, M.REPORT_DIR) end
  local web = rawget(_G, 'openWebBrowser')
  if not web then return { ok = false, message = 'the browser could not be opened' } end
  pcall(web, M.issueUrl(info))
  return { ok = true, logFile = info.logFile,
    message = why and ('Opened GitHub; ' .. why .. '.') or 'Opened GitHub in your browser.' }
end

return M
