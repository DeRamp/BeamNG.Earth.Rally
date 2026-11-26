-- earthRally/textRead: the forgiving pieces of the hand-made rally files (docs/rally-file.md, "Hand-made files";
-- textPack.lua puts them together). Everything here takes what a person might type and gives back the value, or nil
-- and a short reason a person can act on. Pure Lua: no game calls.
local M = {}

local floor, abs = math.floor, math.abs

------------------------------------------------------------------------------------------ bytes to text

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + floor(cp / 64), 0x80 + cp % 64) end
  if cp < 0x10000 then
    return string.char(0xE0 + floor(cp / 4096), 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + floor(cp / 262144), 0x80 + floor(cp / 4096) % 64, 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
end
M._utf8char = utf8char

local function fromUtf16(s, little)
  local out, i, n = {}, 1, #s
  while i + 1 <= n do
    local a, b = s:byte(i, i + 1)
    local u = little and (a + b * 256) or (a * 256 + b)
    i = i + 2
    if u >= 0xD800 and u <= 0xDBFF and i + 1 <= n then
      local c, d = s:byte(i, i + 1)
      local lo = little and (c + d * 256) or (c * 256 + d)
      if lo >= 0xDC00 and lo <= 0xDFFF then
        u = 0x10000 + (u - 0xD800) * 1024 + (lo - 0xDC00)
        i = i + 2
      end
    end
    out[#out + 1] = utf8char(u)
  end
  return table.concat(out)
end

local function validUtf8(s)
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local len = c < 0x80 and 1 or (c >= 0xC2 and c <= 0xDF) and 2 or (c >= 0xE0 and c <= 0xEF) and 3
      or (c >= 0xF0 and c <= 0xF4) and 4 or nil
    if not len then return false end
    for k = 1, len - 1 do
      local d = s:byte(i + k)
      if not d or d < 0x80 or d > 0xBF then return false end
    end
    i = i + len
  end
  return true
end

-- (Windows-1252's 0x80-0x9F; above that it is Latin-1)
local CP1252 = { [0x80] = 0x20AC, [0x82] = 0x201A, [0x83] = 0x0192, [0x84] = 0x201E, [0x85] = 0x2026, [0x86] = 0x2020,
  [0x87] = 0x2021, [0x88] = 0x02C6, [0x89] = 0x2030, [0x8A] = 0x0160, [0x8B] = 0x2039, [0x8C] = 0x0152, [0x8E] = 0x017D,
  [0x91] = 0x2018, [0x92] = 0x2019, [0x93] = 0x201C, [0x94] = 0x201D, [0x95] = 0x2022, [0x96] = 0x2013, [0x97] = 0x2014,
  [0x98] = 0x02DC, [0x99] = 0x2122, [0x9A] = 0x0161, [0x9B] = 0x203A, [0x9C] = 0x0153, [0x9E] = 0x017E, [0x9F] = 0x0178 }

local function fromCp1252(s)
  return (s:gsub('[\128-\255]', function(ch)
    local b = ch:byte()
    return utf8char(CP1252[b] or b)
  end))
end

-- (the typographers' characters Word and phones put in, as plain ones)
local PLAIN = {
  ['\226\128\156'] = '"', ['\226\128\157'] = '"', ['\226\128\158'] = '"', ['\194\171'] = '"', ['\194\187'] = '"',
  ['\226\128\152'] = "'", ['\226\128\153'] = "'", ['\226\128\154'] = "'", ['\226\128\178'] = "'", ['\226\128\179'] = '"',
  ['\226\128\147'] = '-', ['\226\128\148'] = '-', ['\226\136\146'] = '-', ['\226\128\144'] = '-', ['\226\128\145'] = '-',
  ['\194\160'] = ' ', ['\226\128\175'] = ' ', ['\226\128\137'] = ' ', ['\226\128\138'] = ' ', ['\226\128\139'] = '',
  ['\239\187\191'] = '', ['\226\128\166'] = '...',
}

-- A file's bytes as UTF-8 text with plain quotes, dashes and spaces and \n line ends, whatever wrote it: UTF-8 with
-- or without a BOM, UTF-16 either way round (Notepad's "Unicode"), or Windows-1252. Second answer: what it was read
-- as, when not plain UTF-8 (for the report, never a problem).
function M.text(s)
  if type(s) ~= 'string' then return nil end
  local how = nil
  local b1, b2 = s:byte(1, 2)
  if b1 == 0xFF and b2 == 0xFE then s, how = fromUtf16(s:sub(3), true), 'UTF-16'
  elseif b1 == 0xFE and b2 == 0xFF then s, how = fromUtf16(s:sub(3), false), 'UTF-16'
  elseif #s >= 4 and s:sub(2, 2) == '\0' and s:sub(4, 4) == '\0' then s, how = fromUtf16(s, true), 'UTF-16'
  elseif #s >= 4 and s:sub(1, 1) == '\0' and s:sub(3, 3) == '\0' then s, how = fromUtf16(s, false), 'UTF-16'
  else
    if s:sub(1, 3) == '\239\187\191' then s = s:sub(4) end
    if not validUtf8(s) then s, how = fromCp1252(s), 'Windows-1252' end
  end
  s = s:gsub('\r\n?', '\n'):gsub('%z', '')
  for k, v in pairs(PLAIN) do
    if s:find(k, 1, true) then s = s:gsub(k:gsub('%p', '%%%0'), v) end
  end
  return s, how
end

------------------------------------------------------------------------------------------ words and names

local ACCENTS = {}
do
  local groups = {
    a = 'àáâãäåāăą', c = 'çćč', d = 'ďđ', e = 'èéêëēėęě', g = 'ğ', i = 'ìíîïīį', l = 'łľ', n = 'ñńň', o = 'òóôõöøō',
    r = 'ř', s = 'śšş', t = 'ťţ', u = 'ùúûüūůű', y = 'ýÿ', z = 'źżž', ss = 'ß', ae = 'æ', oe = 'œ',
  }
  for plain, list in pairs(groups) do
    for ch in list:gmatch('[\192-\255][\128-\191]*') do ACCENTS[ch] = plain end
  end
end

-- The plain lower-case letters of s: accents off (é -> e), everything not a letter or digit gone. Two names are the
-- same name when their folds are equal ("Kilo Hill", "kilo-hill", "KILO HILL!").
function M.fold(s)
  if type(s) ~= 'string' then return '' end
  local out = {}
  for ch in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
    local b1 = ch:byte(1)
    if b1 < 128 then
      if ch:match('%w') then out[#out + 1] = ch:lower() end
    elseif ACCENTS[ch] then
      out[#out + 1] = ACCENTS[ch]
    elseif #ch == 2 then
      -- (two-byte letters: Latin-1 and Extended-A, Greek, Cyrillic; upper case made lower, punctuation dropped)
      local cp = (b1 - 0xC0) * 64 + (ch:byte(2) - 0x80)
      if cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then cp = cp + 32
      elseif cp >= 0x100 and cp <= 0x17F and cp ~= 0x130 and cp ~= 0x138 and cp ~= 0x149 and cp ~= 0x17F then
        local oddUpper = (cp >= 0x139 and cp <= 0x148) or (cp >= 0x179 and cp <= 0x17E)
        if (oddUpper and cp % 2 == 1) or (not oddUpper and cp % 2 == 0) then cp = cp + 1 end
      elseif cp >= 0x391 and cp <= 0x3AB then cp = cp + 32
      elseif cp >= 0x410 and cp <= 0x42F then cp = cp + 32
      elseif cp >= 0x400 and cp <= 0x40F then cp = cp + 80 end
      local c = utf8char(cp)
      if ACCENTS[c] then out[#out + 1] = ACCENTS[c]
      elseif cp >= 0xC0 and cp ~= 0xD7 and cp ~= 0xF7 then out[#out + 1] = c end
    elseif #ch == 3 and b1 == 0xE2 then
      -- (dashes, quotes and spaces: dropped)
    else
      out[#out + 1] = ch                 -- (other scripts as they are: two such names stay two)
    end
  end
  return table.concat(out)
end

-- (the number of single-letter edits from a to b, nil once it passes `most`)
function M.distance(a, b, most)
  most = most or 99
  if abs(#a - #b) > most then return nil end
  -- (two letters the wrong way round is one slip: "Prak" for "Park")
  local prev2, prev = nil, {}
  for j = 0, #b do prev[j] = j end
  for i = 1, #a do
    local cur, lowest = { [0] = i }, i
    local ai = a:byte(i)
    for j = 1, #b do
      local cost = ai == b:byte(j) and 0 or 1
      local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      if prev2 and i > 1 and j > 1 and ai == b:byte(j - 1) and a:byte(i - 1) == b:byte(j) then
        v = math.min(v, prev2[j - 2] + 1)
      end
      cur[j] = v
      if v < lowest then lowest = v end
    end
    if lowest > most then return nil end
    prev2, prev = prev, cur
  end
  return prev[#b] <= most and prev[#b] or nil
end

-- The one name in `names` that `want` is a slip of: within a quarter of its letters (one at least, three at most) and
-- nearer than any other. nil when none is, or two are as near.
function M.closest(want, names)
  local w = M.fold(want)
  if w == '' then return nil end
  local best, bestD, tie = nil, nil, false
  for _, name in ipairs(names) do
    local f = M.fold(name)
    local most = math.max(1, math.min(3, floor(#f / 4)))
    local d = f ~= '' and M.distance(w, f, most) or nil
    -- (a name cut short: "Kilo" for "Kilo Hill"; never the other way, "Kilo Hill North" is not Kilo Hill)
    if not d and f ~= '' and #w >= 4 and #w < #f and f:sub(1, #w) == w then d = most end
    if d then
      if not bestD or d < bestD then best, bestD, tie = name, d, false
      elseif d == bestD and name ~= best then tie = true end
    end
  end
  if tie then return nil end
  return best, bestD
end

function M.trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- (a value in quotes, as some people write one: "Fernvale Forest Rally")
function M.unquote(s)
  s = M.trim(s)
  local inner = s:match('^"(.*)"$') or s:match("^'(.*)'$")
  return inner and M.trim(inner) or s
end

------------------------------------------------------------------------------------------ the lines of a text file

-- Every line of a text file: { n, raw (as written), text (notes taken off, trimmed), indent }. A note is `#` or `//`
-- at the start of a line or after a space; ` # ` in a value is a note too ("cover.jpg   # the card").
function M.lines(s)
  local out, n = {}, 0
  for raw in (s .. '\n'):gmatch('([^\n]*)\n') do
    n = n + 1
    local t = raw:gsub('\t', '    ')
    local indent = #(t:match('^ *'))
    t = t:gsub('^%s*#.*$', ''):gsub('^%s*//.*$', ''):gsub('%s+#.*$', ''):gsub('%s+//.*$', '')
    out[#out + 1] = { n = n, raw = M.trim(raw), text = M.trim(t), indent = indent }
  end
  return out
end

-- A line's key and value, when it is `Key: value`, `Key = value` or `Key  value` for one of `keys` (canonical name
-- -> list of the ways people write it, each as M.fold gives it). Returns canonical, value, the key as written; or nil,
-- the key as written when it looks like a key nobody knows ("Organiser: X").
function M.keyValue(text, keys)
  local k, v = text:match('^([^:=]-)%s*[:=]%s*(.*)$')
  local function canon(written)
    local f = M.fold(written)
    if f == '' then return nil end
    for name, aliases in pairs(keys) do
      for _, a in ipairs(aliases) do if a == f then return name end end
    end
    return nil
  end
  if k and k ~= '' and not k:find('^%d') then
    local c = canon(k)
    if c then return c, M.trim(v), M.trim(k) end
  end
  -- (no ":": the longest run of words at the start that is a key, then the rest)
  local words = {}
  for w in text:gmatch('%S+') do words[#words + 1] = w end
  for take = math.min(4, #words), 1, -1 do
    local head = table.concat(words, ' ', 1, take)
    local c = canon(head)
    if c then
      -- (where those words end in the line as written: "Start  interval 2 min")
      local pat = '^%s*'
      for i = 1, take do pat = pat .. words[i]:gsub('%p', '%%%0') .. (i < take and '%s+' or '') end
      local _, e = text:find(pat)
      local rest = text:sub((e or #head) + 1):gsub('^%s*[:=]?%s*', '')
      return c, M.trim(rest), head
    end
  end
  if k and k ~= '' and #k <= 30 and not k:find('^%d') and not k:find('[/\\]') then return nil, M.trim(k) end
  return nil
end

-- The key a line's head before its colon is, exactly (no word-by-word fallback), or nil: inside a list only such a
-- line ends it ("Rally start: Fernvale Park" is a stop, not the Rally setting).
function M.exactKey(text, keys)
  local k = text:match('^([^:=]-)%s*[:=]')
  if not k or k == '' then return nil end
  local f = M.fold(k)
  for name, aliases in pairs(keys) do
    for _, a in ipairs(aliases) do if a == f then return name end end
  end
  return nil
end

-- The key `written` is a slip of, among `keys` (as M.keyValue takes them), or nil.
function M.closestKey(written, keys)
  local w = M.fold(written)
  if w == '' then return nil end
  local best, bestD, tie = nil, nil, false
  for name, aliases in pairs(keys) do
    for _, a in ipairs(aliases) do
      local d = M.distance(w, a, math.max(1, math.min(3, floor(#a / 4))))
      if d then
        if not bestD or d < bestD then best, bestD, tie = name, d, false
        elseif d == bestD and name ~= best then tie = true end
      end
    end
  end
  return not tie and best or nil
end

------------------------------------------------------------------------------------------ numbers, times, dates

-- A number as written: "10.46", "10,46" (a decimal comma), "+5", "1 234". nil for anything else.
function M.number(s)
  s = M.trim(s):gsub('^%+', '')
  if s == '' then return nil end
  if s:match('^%-?%d+,%d+$') then s = s:gsub(',', '.') end
  if s:match('^%-?%d[%d ]*%d$') then s = s:gsub(' ', '') end
  return tonumber(s)
end

-- Every number in s, in order ("10, 60, 180 s" -> { 10, 60, 180 }).
function M.numbers(s)
  local out = {}
  for n in tostring(s or ''):gsub('(%d),(%d%d?%f[^%d])', '%1.%2'):gmatch('%-?%d+%.?%d*') do out[#out + 1] = tonumber(n) end
  return out
end

-- A length of time in minutes: "30", "30 min", "30m", "0:30", "1h", "1 h 30", "1h30", "1.5 h", "90 mins". nil, why.
function M.minutes(s)
  local t = M.trim(s):lower():gsub(',', '.')
  if t == '' then return nil, 'empty' end
  local n = tonumber(t)
  if n then return n end
  local h, m = t:match('^(%d+):(%d%d)$')
  if h then return tonumber(h) * 60 + tonumber(m) end
  h, m = t:match('^(%d+%.?%d*)%s*h%a*%s*(%d+)%s*m?%a*$')
  if h then return tonumber(h) * 60 + tonumber(m) end
  h = t:match('^(%d+%.?%d*)%s*h%a*$') or t:match('^(%d+%.?%d*)%s*hours?$')
  if h then return tonumber(h) * 60 end
  m = t:match('^(%d+%.?%d*)%s*m%a*$') or t:match("^(%d+%.?%d*)%s*'$")
  if m then return tonumber(m) end
  return nil, string.format('"%s" is not a length of time: write it as 30 min, or 1 h 30', M.trim(s))
end

-- A time of day as 'HH:MM': "8:23", "08:23", "8.23", "8h23", "08:23:00", "8:23 am", "8:23pm", "0823". nil, why.
function M.clock(s)
  local t = M.trim(s):lower():gsub('%s+', ' ')
  local h, m, rest = t:match('^(%d%d?)[:%.h](%d%d)(.*)$')
  if not h then h, m, rest = t:match('^(%d%d)(%d%d)(.*)$') end
  if not h then
    h, rest = t:match('^(%d%d?)%s*([ap]%.?m%.?)$')
    m = h and '00'
  end
  if not h then return nil, string.format('"%s" is not a time of day: write it as 08:23', M.trim(s)) end
  h, m = tonumber(h), tonumber(m)
  rest = M.trim(rest):gsub(':%d%d$', '')
  rest = M.trim(rest)
  if rest:match('^p%.?m%.?$') then if h < 12 then h = h + 12 end
  elseif rest:match('^a%.?m%.?$') then if h == 12 then h = 0 end
  elseif rest ~= '' then return nil, string.format('"%s" is not a time of day: write it as 08:23', M.trim(s)) end
  if h > 23 or m > 59 then return nil, string.format('"%s" is not a time of day', M.trim(s)) end
  return string.format('%02d:%02d', h, m)
end

-- A stage time in seconds: "6:39.4", "399.4", "0:06:39.4", "6'39.4\"", "6m39.4s", "6:39,4", "1:02:03.4". A time
-- marked N (or "notional") was given, not driven: second answer true. nil, why for anything else.
function M.stageTime(s)
  local t = M.trim(s)
  local notional = false
  local lower = t:lower()
  if lower:match('%s*notional$') then notional, t = true, M.trim(t:sub(1, #t - 8))
  elseif t:match('^.-%d%.?%d*%s*[nN]$') or t:match('^.-["s]%s*[nN]$') then notional, t = true, M.trim(t:sub(1, -2))
  elseif t:match('^[nN]%s+%d') then notional, t = true, M.trim(t:sub(2)) end
  t = t:gsub('(%d),(%d)', '%1.%2')
  local function sec(x) return tonumber(x) end
  local n = tonumber(t)
  if n then return n, notional end
  local h, m, sx = t:match('^(%d+):(%d%d?):(%d%d?%.?%d*)$')
  if h then return tonumber(h) * 3600 + tonumber(m) * 60 + sec(sx), notional end
  m, sx = t:match('^(%d+):(%d%d?%.?%d*)$')
  if m then return tonumber(m) * 60 + sec(sx), notional end
  m, sx = t:match("^(%d+)%s*'%s*(%d%d?%.?%d*)%s*\"?$")
  if m then return tonumber(m) * 60 + sec(sx), notional end
  m, sx = t:match('^(%d+)%s*m%s*(%d%d?%.?%d*)%s*s?$')
  if m then return tonumber(m) * 60 + sec(sx), notional end
  h, m, sx = t:match('^(%d+)%.(%d%d)%.(%d%d?)$')        -- 5.20.3 is not taken: a dot is a decimal point
  if h then return nil, string.format('"%s" is not a time. Write it as %s:%s.%s (minutes:seconds) or seconds',
    M.trim(s), h, m, sx) end
  return nil, string.format('"%s" is not a time. Write it as 6:39.4 (minutes:seconds) or 399.4 (seconds)', M.trim(s))
end

local MONTHS = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11,
  dec = 12 }
local MONTH_WORDS = { january = 1, february = 2, march = 3, april = 4, june = 6, july = 7, august = 8,
  september = 9, sept = 9, october = 10, november = 11, december = 12,
  -- (German, French, Spanish, Italian)
  januar = 1, februar = 2, marz = 3, juni = 6, juli = 7, oktober = 10, dezember = 12,
  janvier = 1, fevrier = 2, mars = 3, avril = 4, mai = 5, juin = 6, juillet = 7, aout = 8, septembre = 9,
  octobre = 10, novembre = 11, decembre = 12,
  enero = 1, febrero = 2, marzo = 3, abril = 4, mayo = 5, junio = 6, julio = 7, agosto = 8, septiembre = 9,
  octubre = 10, noviembre = 11, diciembre = 12,
  gennaio = 1, febbraio = 2, aprile = 4, maggio = 5, giugno = 6, luglio = 7, settembre = 9, ottobre = 10,
  dicembre = 12 }
-- (a month's name or its short form, the whole word: "Mayfield" is not May)
local function month(w)
  w = w and M.fold(w) or ''
  if #w == 3 and MONTHS[w] then return MONTHS[w] end
  return MONTH_WORDS[w]
end
local WEEKDAYS = { mon = true, tue = true, wed = true, thu = true, fri = true, sat = true, sun = true }
local DAYS_IN = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function iso(y, m, d)
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if not (y and m and d) or m < 1 or m > 12 or d < 1 or d > DAYS_IN[m] then return nil end
  if y < 100 then y = y + 2000 end
  return string.format('%04d-%02d-%02d', y, m, d)
end

-- One date as 'YYYY-MM-DD': "2031-02-07", "7 Feb 2031", "7th February 2031", "Feb 7, 2031", "Sat 7 Feb 2031",
-- "7/2/2031", "7.2.2031". `year` fills one left out ("7 Feb"). Returns the date, or nil and why; a third answer when
-- day and month could be either way round (read day first).
function M.date(s, year)
  local t = M.trim(s):gsub(',', ' '):gsub('(%d)%a%a%f[%A]', '%1'):gsub('%s+', ' ')
  local wd = t:match('^(%a+)%.? %d')                      -- ("Sat 7 Feb": the weekday off)
  if wd and WEEKDAYS[wd:lower():sub(1, 3)] then t = t:gsub('^%a+%.? ', '') end
  local y, m, d = t:match('^(%d%d%d%d)[%-/%.](%d%d?)[%-/%.](%d%d?)$')
  if y then
    local r = iso(y, m, d)
    if r then return r end
  end
  local dd, mon, yy = t:match('^(%d%d?) ([%a\128-\255]+)%.? ?(%d*)$')
  if dd and month(mon) then
    local r = iso(yy ~= '' and yy or year, month(mon), dd)
    if r then return r end
    if yy == '' and not year then return nil, string.format('"%s" has no year', M.trim(s)) end
  end
  mon, dd, yy = t:match('^([%a\128-\255]+)%.? (%d%d?) ?(%d*)$')
  if mon and month(mon) then
    local r = iso(yy ~= '' and yy or year, month(mon), dd)
    if r then return r end
    if yy == '' and not year then return nil, string.format('"%s" has no year', M.trim(s)) end
  end
  local a, b, c = t:match('^(%d%d?)[/%.%-](%d%d?)[/%.%-](%d%d%d?%d?)$')
  if a then
    a, b = tonumber(a), tonumber(b)
    local r, either
    if a > 12 then r = iso(c, b, a)
    elseif b > 12 then r = iso(c, a, b)
    else r, either = iso(c, b, a), a ~= b end
    if r then return r, nil, either end
    return nil, string.format('"%s" is not a day of the year: check the day and the month', M.trim(s))
  end
  if y or (mon and month(mon)) or (dd and month(select(2, t:match('^(%d%d?) ([%a\128-\255]+)')))) then
    return nil, string.format('"%s" is not a day of the year: check the day and the month', M.trim(s))
  end
  return nil, string.format('"%s" is not a date: write it as 7 Feb 2031 or 2031-02-07', M.trim(s))
end

-- A rally's dates: { from, to } from "7-8 Feb 2031", "7 - 8 February 2031", "Feb 7-8, 2031", "2031-02-07 to
-- 2031-02-08", "7 Feb 2031 - 8 Feb 2031", or one day. nil, why; third answer as M.date's.
function M.dates(s)
  local t = M.trim(s):gsub('%s+', ' ')
  local one, why, either = M.date(t)
  if one then return { from = one, to = one }, nil, either end
  local d1, d2, rest = t:match('^(%d%d?)%a*%s*%-%s*(%d%d?)%a*%s+(%a.*)$')
  if d1 then
    local a = M.date(d1 .. ' ' .. rest)
    local b = M.date(d2 .. ' ' .. rest)
    if a and b then return { from = a, to = b } end
  end
  local mon, e1, e2, yy = t:match('^(%a+)%.? (%d%d?)%a*%s*%-%s*(%d%d?)%a*,? (%d%d%d%d)$')
  if mon then
    local a, b = M.date(mon .. ' ' .. e1 .. ' ' .. yy), M.date(mon .. ' ' .. e2 .. ' ' .. yy)
    if a and b then return { from = a, to = b } end
  end
  local left, right = t:match('^(.-)%s+to%s+(.+)$')
  if not left then left, right = t:match('^(.-)%s+%-%s+(.+)$') end
  if not left then left, right = t:match('^(.-)%s+until%s+(.+)$') end
  if left then
    local b, whyB, eB = M.date(right)
    local yr = b and b:sub(1, 4) or right:match('(%d%d%d%d)')
    local a, whyA, eA = M.date(left, yr)
    if a and b then return { from = a, to = b }, nil, eA or eB end
    return nil, whyA or whyB or string.format('"%s" is not a date', t)
  end
  return nil, why or string.format('"%s" is not a date', t)
end

-- (the day after a 'YYYY-MM-DD', n days on)
function M.addDays(dateIso, n)
  local y, m, d = dateIso:match('^(%d+)-(%d+)-(%d+)$')
  if not y then return nil end
  local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
  return os.date('%Y-%m-%d', t + n * 86400)
end

------------------------------------------------------------------------------------------ positions

local function dms(deg, min, sec, hemi)
  local v = tonumber(deg) + (tonumber(min) or 0) / 60 + (tonumber(sec) or 0) / 3600
  if hemi == 'S' or hemi == 'W' then v = -v end
  return v
end

-- A position as lat, lon from what a person pastes or types: "60.0102, -10.0451", "60.0102 -10.0451", a decimal comma
-- ("60,0102 -10,0451"), degrees minutes seconds (60°00'36.7"N 10°02'42.4"W), "N 60.0102 W 10.0451",
-- "60.0102N 10.0451W", or a Google Maps link. Third answer: 'swapped' when it was plainly longitude first (a first
-- number over 90). nil, why for anything else.
local position
function M.position(s)
  local lat, lon, note = position(s)
  if lat then return lat, lon, note end
  return nil, lon or string.format('"%s" is not a position on Earth', M.trim(s))
end
function position(s)
  local t = M.trim(s)
  local function ok(lat, lon, note)
    if not (lat and lon) then return nil end
    if abs(lat) > 90 and abs(lon) <= 90 then lat, lon, note = lon, lat, 'swapped' end
    if abs(lat) > 90 or abs(lon) > 180 then return nil end
    return lat, lon, note
  end
  -- (a Google Maps link: the place's own !3d!4d, else @lat,lon, else q= / ll=)
  local a, b = t:match('!3d(%-?%d+%.?%d*)!4d(%-?%d+%.?%d*)')
  if not a then a, b = t:match('@(%-?%d+%.?%d*),(%-?%d+%.?%d*)') end
  if not a then a, b = t:match('[?&]q=(%-?%d+%.?%d*),%s*(%-?%d+%.?%d*)') end
  if not a then a, b = t:match('[?&]ll=(%-?%d+%.?%d*),(%-?%d+%.?%d*)') end
  if a then
    local lat, lon, note = ok(tonumber(a), tonumber(b))
    if lat then return lat, lon, note end
  end
  local u = t:upper():gsub('º', '°')
  -- degrees, minutes, seconds, hemisphere after
  local p = {}
  for deg, rest in u:gmatch('(%d+%.?%d*)%s*°([^NSEW]*)%s*([NSEW])') do p[#p + 1] = { deg, rest } end
  local hemis = {}
  for h in u:gmatch('°[^NSEW]*([NSEW])') do hemis[#hemis + 1] = h end
  if #p == 2 then
    local vals = {}
    for i, q in ipairs(p) do
      local mi, se = q[2]:match("(%d+%.?%d*)%s*'%s*(%d*%.?%d*)")
      vals[i] = { v = dms(q[1], mi, se ~= '' and se or nil, hemis[i]), h = hemis[i] }
    end
    local lat, lon
    for _, v in ipairs(vals) do
      if v.h == 'N' or v.h == 'S' then lat = v.v else lon = v.v end
    end
    if lat and lon then return ok(lat, lon) end
  end
  -- hemisphere letters with decimal degrees, before or after: "N 60.01 W 10.04", "60.01N 10.04W"
  local h1, n1, h2, n2 = u:match('^([NS])%s*(%d+%.?%d*)[,;%s]+([EW])%s*(%d+%.?%d*)$')
  if h1 then return ok(dms(n1, 0, 0, h1), dms(n2, 0, 0, h2)) end
  n1, h1, n2, h2 = u:match('^(%d+%.?%d*)%s*([NS])[,;%s]+(%d+%.?%d*)%s*([EW])$')
  if n1 then return ok(dms(n1, 0, 0, h1), dms(n2, 0, 0, h2)) end
  -- two plain numbers
  local x, y = t:match('^%(?%s*(%-?%d+,%d+)%s+(%-?%d+,%d+)%s*%)?$')      -- (decimal commas, a space between)
  if x then return ok(tonumber((x:gsub(',', '.'))), tonumber((y:gsub(',', '.')))) end
  x, y = t:match('^%(?%s*(%-?%d+%.?%d*)%s*[,;%s]%s*(%-?%d+%.?%d*)%s*%)?$')
  if x then
    local lat, lon, note = ok(tonumber(x), tonumber(y))
    if lat then return lat, lon, note end
    return nil, string.format('"%s" is not a position on Earth', t)
  end
  return nil, string.format('"%s" is not a position: paste it from Google Maps, or write it as 60.0102, -10.0451', t)
end

------------------------------------------------------------------------------------------ CSV

-- A CSV file's rows as Excel and Sheets write them: `,`, `;` (Excel in much of Europe) or tab between cells, cells
-- in quotes with "" inside, blank rows, rows of nothing but commas, and `#` notes skipped. Returns the header row
-- ({ cells, n }) and the rows after it ({ { cells, n, raw }... }), or nil and why.
function M.csv(s)
  local rows, n = {}, 0
  local delim = nil
  for raw in (s .. '\n'):gmatch('([^\n]*)\n') do
    n = n + 1
    local trimmed = M.trim(raw)
    if trimmed ~= '' and not trimmed:match('^#') and not trimmed:match('^"#') then
      if not delim then
        local counts = {}
        for _, d in ipairs({ ',', ';', '\t' }) do
          local c = 0
          local inQ = false
          for i = 1, #raw do
            local ch = raw:sub(i, i)
            if ch == '"' then inQ = not inQ elseif ch == d and not inQ then c = c + 1 end
          end
          counts[#counts + 1] = { d = d, c = c }
        end
        table.sort(counts, function(a, b) return a.c > b.c end)
        delim = counts[1].c > 0 and counts[1].d or ','
      end
      local cells, cur, inQ, i = {}, {}, false, 1
      while i <= #raw do
        local ch = raw:sub(i, i)
        if inQ then
          if ch == '"' and raw:sub(i + 1, i + 1) == '"' then cur[#cur + 1] = '"' i = i + 1
          elseif ch == '"' then inQ = false
          else cur[#cur + 1] = ch end
        elseif ch == '"' then inQ = true
        elseif ch == delim then cells[#cells + 1] = M.trim(table.concat(cur)) cur = {}
        else cur[#cur + 1] = ch end
        i = i + 1
      end
      cells[#cells + 1] = M.trim(table.concat(cur))
      local any = false
      for _, c in ipairs(cells) do if c ~= '' then any = true break end end
      if any then rows[#rows + 1] = { cells = cells, n = n, raw = trimmed } end
    end
  end
  if #rows == 0 then return nil, 'it is empty' end
  local header = table.remove(rows, 1)
  return header, rows, delim
end

-- The column of `header` that is one of `aliases` (folded), or nil.
function M.column(header, aliases)
  for i, c in ipairs(header.cells) do
    local f = M.fold(c)
    for _, a in ipairs(aliases) do if f == a then return i end end
  end
  return nil
end

return M
