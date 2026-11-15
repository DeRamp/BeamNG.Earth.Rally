-- A tiny test helper: T.check(cond, name), T.near(a, b, eps, name), T.done(file) (exits 1 on any failure).
local T = { passed = 0, failed = 0 }

function T.check(cond, name)
  if cond then T.passed = T.passed + 1
  else T.failed = T.failed + 1 print('FAIL: ' .. tostring(name)) end
end

function T.near(a, b, eps, name)
  local ok = type(a) == 'number' and type(b) == 'number' and math.abs(a - b) <= eps
  T.check(ok, string.format('%s (%s vs %s)', name, tostring(a), tostring(b)))
end

-- A small JSON reader and writer, for tests that stand in the game's jsonDecode (pack.lua reads JSON from text: a
-- zip's entries have no path to jsonReadFile). null reads as nil, as the game's does.
function T.jsonDecode(s)
  local pos = 1
  local function ws() pos = s:find('[^ \t\r\n]', pos) or #s + 1 end
  local val
  local function str()
    local out = {}
    pos = pos + 1
    while true do
      local c = s:sub(pos, pos)
      if c == '"' then pos = pos + 1 break end
      if c == '' then error('unterminated string') end
      if c == '\\' then
        local e = s:sub(pos + 1, pos + 1)
        if e == 'u' then
          local cp = tonumber(s:sub(pos + 2, pos + 5), 16)
          if cp < 0x80 then out[#out + 1] = string.char(cp)
          elseif cp < 0x800 then out[#out + 1] = string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
          else out[#out + 1] = string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64) end
          pos = pos + 6
        else
          out[#out + 1] = ({ n = '\n', t = '\t', r = '\r', b = '\b', f = '\f' })[e] or e
          pos = pos + 2
        end
      else
        out[#out + 1] = c
        pos = pos + 1
      end
    end
    return table.concat(out)
  end
  val = function()
    ws()
    local c = s:sub(pos, pos)
    if c == '{' then
      local t = {}
      pos = pos + 1
      ws()
      if s:sub(pos, pos) == '}' then pos = pos + 1 return t end
      while true do
        ws()
        local k = str()
        ws()
        pos = pos + 1          -- (the colon)
        t[k] = val()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == '}' then return t end
      end
    elseif c == '[' then
      local t, n = {}, 0
      pos = pos + 1
      ws()
      if s:sub(pos, pos) == ']' then pos = pos + 1 return t end
      while true do
        n = n + 1
        t[n] = val()
        ws()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == ']' then return t end
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true
    elseif s:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false
    elseif s:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil
    else
      local num = s:match('^-?[%d.eE+-]+', pos)
      if not num then error('bad JSON at ' .. pos) end
      pos = pos + #num
      return tonumber(num)
    end
  end
  return val()
end

function T.jsonEncode(v)
  local t = type(v)
  if t == 'table' then
    if next(v) == nil or v[1] ~= nil then
      local out = {}
      for i, x in ipairs(v) do out[i] = T.jsonEncode(x) end
      return '[' .. table.concat(out, ',') .. ']'
    end
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do out[#out + 1] = T.jsonEncode(k) .. ':' .. T.jsonEncode(v[k]) end
    return '{' .. table.concat(out, ',') .. '}'
  elseif t == 'string' then
    return '"' .. (v:gsub('[%c"\\]', function(c) return string.format('\\u%04x', c:byte()) end)) .. '"'
  end
  return tostring(v)
end

function T.done(file)
  print(string.format('%s: %d passed, %d failed', file, T.passed, T.failed))
  if T.failed > 0 then os.exit(1) end
end

return T
