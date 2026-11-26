-- earthRally/importReport: what an import found, for the person who made the file (docs/plan-hand-files.md). Each
-- import of a map or pack is written as "import report.txt" in the pack's folder (or "<file> - import report.txt"
-- beside a zip or a loose map), and the same report is shown in game from the Rallies page's Last import lines.
--
-- M.build(d) takes one entry of importer.scan's list and gives the report as data:
--   { name, verdict = 'ok' | 'problems' | 'failed', headline, sub, problems = { { n, where, text, what, fix } },
--     unused = { same }, found = { { title, rows = { { label, value, warn } } } } }
-- M.text(rep) gives it as the text file; M.write(d) writes it and returns the data.
local M = {}

local function str(v) return v == nil and '' or tostring(v) end

-- (a problem as the report shows it: from pack.lua / textPack.lua's tables, or a plain string)
local function item(p)
  if type(p) ~= 'table' then return { what = str(p) } end
  local where = p.file and (p.file .. (p.line and (', line ' .. p.line) or '')) or (p.line and ('line ' .. p.line))
  return { where = where, text = p.text, what = str(p.what), fix = p.fix, level = p.level }
end

local MONTHS = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
local function day(iso)
  local y, m, d = tostring(iso or ''):match('^(%d+)-(%d+)-(%d+)$')
  if not y then return str(iso) end
  return string.format('%d %s %s', tonumber(d), MONTHS[tonumber(m)] or m, y)
end
local function dates(ds)
  if type(ds) ~= 'table' or not ds.from then return nil end
  if not ds.to or ds.to == ds.from then return day(ds.from) end
  return day(ds.from) .. ' - ' .. day(ds.to)
end

local function rulesLine(r)
  if type(r) ~= 'table' then return nil end
  local out = {}
  if type(r.falseStartS) == 'table' then
    local t = {}
    for i, v in ipairs(r.falseStartS) do t[i] = str(v) end
    out[#out + 1] = 'false start ' .. table.concat(t, ' / ') .. ' s'
  end
  if r.lateSPerMin then out[#out + 1] = 'late ' .. r.lateSPerMin .. ' s per minute' end
  if r.earlySPerMin then out[#out + 1] = 'early ' .. r.earlySPerMin .. ' s per minute' end
  if r.maxLatenessMin then out[#out + 1] = 'max lateness ' .. r.maxLatenessMin .. ' min' end
  if r.startIntervalMin then out[#out + 1] = 'start interval ' .. r.startIntervalMin .. ' min' end
  if #out == 0 then return nil end
  local s = table.concat(out, ', ')
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- (one rally's "What the game found" rows)
local function rallyFound(ev, rep, title)
  local rows = {}
  local function row(label, value, warn) if value and value ~= '' then rows[#rows + 1] = { label = label, value = value,
    warn = warn } end end
  row('Dates', dates(ev.dates))
  row('Town', ev.place)
  local src = type(ev.source) == 'table' and ev.source.file or nil
  row('Map', src and string.format('%s: %d stage line%s', src:match('([^/]+)$') or src, #ev.stages,
    #ev.stages == 1 and '' or 's'))
  -- stages: each with its length and the passes that run it
  local passesOf = {}
  for _, p in ipairs(ev.itinerary or {}) do
    passesOf[p.stage] = passesOf[p.stage] or {}
    local t = p.ss .. (p.powerStage and ' (power stage)' or '') .. (p.cancelled and ' (cancelled)' or '')
    table.insert(passesOf[p.stage], t)
  end
  local lines = {}
  for _, st in ipairs(ev.stages or {}) do
    local ps = passesOf[st.id]
    lines[#lines + 1] = string.format('%s  %.1f km  %s', st.name, (st.lengthM or 0) / 1000,
      ps and table.concat(ps, ', ') or 'not in the running order')
  end
  row('Stages', table.concat(lines, '\n'))
  -- the running order, a line a day
  if ev.rallyStops then
    local after = {}
    for _, s in ipairs(ev.rallyStops) do after[s.after] = s end
    local days, cur, curDay = {}, nil, nil
    for i, p in ipairs(ev.itinerary or {}) do
      if not cur or (p.day and p.day ~= curDay) then
        cur = {}
        days[#days + 1] = { day = p.day, items = cur }
        curDay = p.day
      end
      cur[#cur + 1] = p.ss
      local s = after[i]
      if s and s.kind == 'service' then
        cur[#cur + 1] = s.label .. (s.name and (' (' .. s.name .. ')') or '') .. (s.place and '' or ' - no position')
      end
    end
    local out = {}
    for _, dd in ipairs(days) do
      out[#out + 1] = (dd.day and ('Day ' .. dd.day .. '   ') or '') .. table.concat(dd.items, ' · ')
    end
    if ev.rallyStart then table.insert(out, 1, 'Start at ' .. str(ev.rallyStart.name)) end
    row('Running order', table.concat(out, '\n'))
  else
    row('Running order', 'None: the stages run once each, in map order. No full rally.')
  end
  if ev.timing and ev.timing.start then
    row('Timed', string.format('Yes: from %s %s%s', day(ev.timing.start.date), str(ev.timing.start.time),
      ev.timing.timezone and (' (' .. ev.timing.timezone .. ')') or ''))
  elseif ev.rallyStops then
    row('Timed', 'No: road sections are not timed')
  end
  local f = rep and rep.found
  row('Results', f and string.format('%d crews on %d stage%s', f.crews, f.resultPasses, f.resultPasses == 1 and '' or 's')
    or 'None')
  local wx = 0
  for _, p in ipairs(ev.itinerary or {}) do if p.weather then wx = wx + 1 end end
  row('Weather', wx > 0 and string.format('%d stage%s', wx, wx == 1 and '' or 's') or 'None: the player\'s own')
  local pics = {}
  for _, k in ipairs({ 'cover', 'logo', 'photo' }) do if ev.media and ev.media[k] then pics[#pics + 1] = k end end
  row('Pictures', #pics > 0 and table.concat(pics, ', ') or 'None')
  row('Rules', rulesLine(ev.rules))
  return { title = title, rows = rows }
end

-- The report of one import (an entry of importer.scan's list).
function M.build(d)
  local rep = { name = str(d.name or d.file), file = d.file, problems = {}, unused = {}, found = {} }
  local function add(p)
    local it = item(p)
    if it.level == 'unused' then rep.unused[#rep.unused + 1] = it else rep.problems[#rep.problems + 1] = it end
  end
  if not d.ok then
    rep.verdict = 'failed'
    for _, p in ipairs(d.problems or {}) do add(p) end
    local main = item(d.problem or d.why)
    main.main = true
    table.insert(rep.problems, 1, main)
  else
    for _, p in ipairs(d.warnings or {}) do add(p) end
    -- the map's own: a stage's controls far off its line, a line in pieces, points that match no stage
    for _, r in ipairs(d.results or {}) do
      local br = r.report or {}
      local mapFile = r.event and type(r.event.source) == 'table' and r.event.source.file and
        r.event.source.file:match('([^/]+)$') or nil
      for _, st in ipairs(br.stages or {}) do
        for _, w in ipairs(st.warnings or {}) do
          add({ file = mapFile, what = string.format('%s: %s.', st.name, w), fix = 'Check the stage in your map.' })
        end
      end
      for _, u in ipairs(br.unmatched or {}) do
        if u.suggest then
          add({ file = mapFile, what = string.format('The point "%s" matches no stage. Did you mean %s?', u.name,
            u.suggest), fix = 'Name a control point after its stage: "Kilo Hill Start".' })
        end
      end
    end
    rep.verdict = #rep.problems > 0 and 'problems' or 'ok'
    local many = #(d.results or {}) > 1 or d.kind == 'season'
    for _, r in ipairs(d.results or {}) do
      if r.event then
        local title = many and string.format('%s%s', r.round and ('Round ' .. r.round .. ': ') or '', r.event.name)
          or r.event.name
        rep.found[#rep.found + 1] = rallyFound(r.event, r.report, title)
      end
    end
  end
  for i, p in ipairs(rep.problems) do p.n = i end
  local n = #rep.problems
  if rep.verdict == 'failed' then
    rep.headline = string.format('%s: not imported', rep.name)
    rep.sub = 'Fix the problem below and the game reads it again by itself.'
  elseif rep.verdict == 'problems' then
    rep.headline = string.format('%s: imported with %d problem%s', rep.name, n, n == 1 and '' or 's')
    rep.sub = "It's in the menu. Fix these and the game reads it again by itself."
  else
    rep.headline = string.format('%s: imported', rep.name)
    rep.sub = "It's in the menu."
  end
  rep.at = os.date('%d %b %Y, %H:%M')
  return rep
end

-- The report as the text file.
function M.text(rep, d)
  local out = {}
  local function w(s) out[#out + 1] = s or '' end
  local function wrap(s, indent)
    -- (long lines broken at spaces, for Notepad)
    local width, lines = 96 - #indent, {}
    for para in (str(s) .. '\n'):gmatch('([^\n]*)\n') do
      local cur = ''
      for word in para:gmatch('%S+') do
        if #cur + #word + 1 > width and cur ~= '' then lines[#lines + 1] = indent .. cur cur = word
        else cur = cur == '' and word or (cur .. ' ' .. word) end
      end
      lines[#lines + 1] = indent .. cur
    end
    return table.concat(lines, '\n')
  end
  local rule = string.rep('=', 96)
  local thin = string.rep('-', 96)
  w('EARTH RALLY - IMPORT REPORT')
  local kind = d and (d.packKind == 'zip' and ' (zip)' or d.packKind == 'folder' and ' (folder)' or ' (map)') or ''
  w(string.format('%s%s  ·  read %s', str(d and d.file or rep.file), kind, rep.at))
  w('The game writes this file each time it reads this. Editing it changes nothing.')
  w()
  w(rule)
  local n = #rep.problems
  if rep.verdict == 'failed' then w('NOT IMPORTED')
  elseif rep.verdict == 'problems' then w(string.format('IMPORTED WITH %d PROBLEM%s', n, n == 1 and '' or 'S'))
  else w('IMPORTED') end
  w(rep.verdict == 'failed' and 'Fix the problem below and the game reads it again by itself.'
    or rep.verdict == 'problems' and "It's in the menu. Fix the problems below and the game reads it again by itself."
    or "It's in the menu. Nothing to fix.")
  w(rule)
  local function list(title, items)
    if #items == 0 then return end
    w() w() w(title) w(thin) w()
    for i, p in ipairs(items) do
      local head = string.format('%d. ', i)
      local pad = string.rep(' ', #head)
      if p.where then
        w(head .. p.where .. (p.text and p.text ~= '' and (':  ' .. p.text) or ''))
        w(wrap(p.what, pad))
      else
        w(wrap(p.what, pad):gsub('^' .. pad, head, 1))
      end
      if p.fix then w(wrap(p.fix, pad)) end
      w()
    end
  end
  list('PROBLEMS', rep.problems)
  if #rep.found > 0 then
    w() w() w('WHAT THE GAME FOUND') w(thin)
    for _, f in ipairs(rep.found) do
      w()
      w(f.title)
      for _, r in ipairs(f.rows) do
        local first = true
        for line in (r.value .. '\n'):gmatch('([^\n]*)\n') do
          local wrapped = wrap(line, string.rep(' ', 17))
          w(string.format('  %-15s%s', first and r.label or '', (wrapped:gsub('^%s+', ''))))
          first = false
        end
      end
    end
  end
  list('READ BUT NOT USED', rep.unused)
  return table.concat(out, '\r\n') .. '\r\n'
end

-- Writes d's report where it goes (d.reportPath), and returns it as data (for the menu). Nothing written without a
-- path; a write that fails is logged, never an error.
function M.write(d)
  local rep = M.build(d)
  if d.reportPath then
    local s = M.text(rep, d)
    local ok = pcall(function()
      if writeFile then writeFile(d.reportPath, s)
      else
        local f = io.open(d.reportPath, 'wb')
        if f then f:write(s) f:close() end
      end
    end)
    if not ok and log then log('W', 'earthRally', 'could not write ' .. tostring(d.reportPath)) end
  end
  return rep
end

return M
