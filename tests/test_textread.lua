-- The forgiving readers of the hand-made rally files (textRead.lua): every way a person might write a value.
local T = dofile(TESTS .. '/testlib.lua')
local R = require('earthRally/textRead')

-- text: encodings, quotes, line ends
T.check(R.text('\239\187\191Rally: X\r\n') == 'Rally: X\n', 'BOM and CRLF')
T.check(R.text('\255\254R\0a\0l\0l\0y\0') == 'Rally', 'UTF-16 LE with BOM')
T.check(R.text('R\0a\0l\0l\0y\0') == 'Rally', 'UTF-16 LE without BOM')
T.check(R.text('\254\255\0R\0a') == 'Ra', 'UTF-16 BE')
local cp, how = R.text('Caf\233 \147Q\148')
T.check(cp == 'Café "Q"' and how == 'Windows-1252', 'Windows-1252: ' .. tostring(cp))
T.check(R.text('\226\128\156Fernvale\226\128\157 \226\128\147 7') == '"Fernvale" - 7', 'curly quotes and dashes')
T.check(R.text('a\rb') == 'a\nb', 'old Mac line ends')

-- fold and closest
T.check(R.fold('Kilo Hill') == R.fold('kilo-hill') and R.fold('KILO  HILL!') == 'kilohill', 'fold')
T.check(R.fold('Côte Élysée') == 'coteelysee', 'fold accents: ' .. R.fold('Côte Élysée'))
T.check(R.closest('Kilo Hil', { 'Kilo Hill', 'Long Gap' }) == 'Kilo Hill', 'closest: a letter missing')
T.check(R.closest('Klio Hill', { 'Kilo Hill', 'Long Gap' }) == 'Kilo Hill', 'closest: two swapped')
T.check(R.closest('Banana', { 'Kilo Hill', 'Long Gap' }) == nil, 'closest: nothing near')
T.check(R.closest('Gap 1', { 'Gap 2', 'Gap 3' }) == nil, 'closest: two as near is no answer')

-- lines and keys
local L = R.lines('Rally: X   # a note\n  // all a note\n\tAt: 1, 2\n# note')
T.check(L[1].text == 'Rally: X' and L[2].text == '' and L[3].text == 'At: 1, 2' and L[3].indent == 4, 'lines')
local KEYS = { rally = { 'rally', 'name', 'title' }, falseStart = { 'falsestart', 'jumpstart' }, map = { 'map' } }
local k, v = R.keyValue('Rally: Fernvale', KEYS)
T.check(k == 'rally' and v == 'Fernvale', 'key: value')
k, v = R.keyValue('NAME = Fernvale', KEYS)
T.check(k == 'rally' and v == 'Fernvale', 'key = value')
k, v = R.keyValue('Rally   Fernvale', KEYS)
T.check(k == 'rally' and v == 'Fernvale', 'key  value')
k, v = R.keyValue('False start 10, 60', KEYS)
T.check(k == 'falseStart' and v == '10, 60', 'two-word key, no colon')
k, v = R.keyValue('Organiser: Club', KEYS)
T.check(k == nil and v == 'Organiser', 'unknown key')
T.check(R.closestKey('Mapp', KEYS) == 'map', 'closest key')

-- numbers and times
T.check(R.number('10,46') == 10.46 and R.number('+5') == 5 and R.number('x') == nil, 'number')
local ns = R.numbers('10, 60, 180 s')
T.check(#ns == 3 and ns[3] == 180, 'numbers')
T.check(R.minutes('30') == 30 and R.minutes('30 min') == 30 and R.minutes('0:30') == 30 and R.minutes('1h') == 60
  and R.minutes('1 h 30') == 90 and R.minutes('1h30') == 90 and R.minutes('1.5 h') == 90 and R.minutes('90 mins') == 90,
  'minutes')
T.check(R.minutes('soon') == nil, 'minutes: nonsense')
T.check(R.clock('8:23') == '08:23' and R.clock('8.23') == '08:23' and R.clock('8h23') == '08:23'
  and R.clock('08:23:00') == '08:23' and R.clock('8:23 pm') == '20:23' and R.clock('12:05am') == '00:05'
  and R.clock('0823') == '08:23', 'clock')
T.check(R.clock('25:00') == nil, 'clock: no 25th hour')
local s, n = R.stageTime('6:39.4')
T.check(s == 399.4 and not n, 'stage time m:s')
T.check(R.stageTime('399.4') == 399.4 and R.stageTime('0:06:39.4') == 399.4 and R.stageTime("6'39.4\"") == 399.4
  and R.stageTime('6m39.4s') == 399.4 and R.stageTime('6:39,4') == 399.4, 'stage time forms')
s, n = R.stageTime('5:20.3 N')
T.check(s == 320.3 and n == true, 'notional')
local bad, why = R.stageTime('5.20.3')
T.check(bad == nil and why:find('5:20.3', 1, true), 'stage time with dots: ' .. tostring(why))

-- dates
T.check(R.date('2031-02-07') == '2031-02-07' and R.date('7 Feb 2031') == '2031-02-07'
  and R.date('7th February 2031') == '2031-02-07' and R.date('Feb 7, 2031') == '2031-02-07'
  and R.date('Sat 7 Feb 2031') == '2031-02-07' and R.date('7/2/2031') == '2031-02-07'
  and R.date('7 Feb', '2031') == '2031-02-07', 'date forms')
local d1, _, either = R.date('7/2/2031')
T.check(d1 == '2031-02-07' and either, 'day and month either way: day first, said so')
T.check(R.date('2/17/2031') == '2031-02-17', 'month first when it must be')
local ds = R.dates('7-8 Feb 2031')
T.check(ds and ds.from == '2031-02-07' and ds.to == '2031-02-08', 'dates: 7-8 Feb 2031')
ds = R.dates('Feb 7-8, 2031')
T.check(ds and ds.from == '2031-02-07' and ds.to == '2031-02-08', 'dates: Feb 7-8, 2031')
ds = R.dates('2031-02-07 to 2031-02-08')
T.check(ds and ds.to == '2031-02-08', 'dates: to')
ds = R.dates('7 Feb - 8 Feb 2031')
T.check(ds and ds.from == '2031-02-07' and ds.to == '2031-02-08', 'dates: year only on the second')
ds = R.dates('7 Feb 2031')
T.check(ds and ds.from == ds.to, 'dates: one day')
T.check(R.addDays('2031-02-28', 1) == '2031-03-01', 'addDays')

-- positions
local la, lo, note = R.position('60.0102, -10.0451')
T.near(la, 60.0102, 1e-9, 'position lat') T.near(lo, -10.0451, 1e-9, 'position lon')
la, lo = R.position('60.0102 -10.0451')
T.near(lo, -10.0451, 1e-9, 'position, a space')
la, lo = R.position('60,0102 -10,0451')
T.near(la, 60.0102, 1e-9, 'position, decimal commas')
la, lo = R.position([[60°00'36.7"N 10°02'42.4"W]])
T.near(la, 60.010194, 1e-5, 'DMS lat') T.near(lo, -10.045111, 1e-5, 'DMS lon')
la, lo = R.position('N 60.0102 W 10.0451')
T.near(lo, -10.0451, 1e-9, 'hemisphere first')
la, lo = R.position('60.0102N 10.0451W')
T.near(lo, -10.0451, 1e-9, 'hemisphere after')
la, lo = R.position('https://www.google.com/maps/place/X/@60.0100,-10.0400,15z/data=!3d60.0102!4d-10.0451')
T.near(la, 60.0102, 1e-9, 'maps link: the place, not the view')
la, lo, note = R.position('-120.5, 45.2')
T.check(la == 45.2 and lo == -120.5 and note == 'swapped', 'longitude first, plainly')
T.check(R.position('somewhere') == nil, 'not a position')

-- CSV
local h, rows, delim = R.csv('# a note\nSS;Time\n\nSS1;"6:39,4"\n;;\n"SS2";"say ""hi"""\n')
T.check(delim == ';' and h.cells[2] == 'Time' and #rows == 2, 'csv: semicolons, blank rows')
T.check(rows[1].cells[2] == '6:39,4' and rows[2].cells[2] == 'say "hi"' and rows[2].n == 6, 'csv: quotes, line numbers')
T.check(R.column(h, { 'time', 'stagetime' }) == 2, 'column')

-- (handoff review)
T.check(R.fold('Ζάκυνθος') ~= R.fold('Κέρκυρα') and R.fold('Ζάκυνθος') ~= '', 'other scripts: names stay apart')
T.check(R.closest('Kilo Hill', { 'Ζάκυνθος' }) == nil, 'other scripts: nothing matched to them by accident')
T.check(R.closest('Kilo Hill North', { 'Kilo Hill', 'Long Gap' }) == nil, 'a longer name is not a shorter stage')
T.check(R.closest('Kilo', { 'Kilo Hill', 'Long Gap' }) == 'Kilo Hill', 'a name cut short is')
local nd, ndWhy = R.date('30/02/2031')
T.check(nd == nil and type(ndWhy) == 'string', 'an impossible day: a reason, not nothing')
local nds, ndsWhy = R.dates('31/04/2031')
T.check(nds == nil and type(ndsWhy) == 'string', 'dates: an impossible day: a reason')
T.check(R.date('Mayfield 2', '2031') == nil and R.date('Junction 12', '2031') == nil, 'a word starting like a month')
T.check(R.date('2 Sept 2031') == '2031-09-02' and R.date('May 2 2031') == '2031-05-02', 'month words')
local pa, pw = R.position('N 60.01 W 190.04')
T.check(pa == nil and type(pw) == 'string', 'a position off the Earth: a reason')
local k2, v2 = R.keyValue('Start  interval 2 min', { startInterval = { 'startinterval' } })
T.check(k2 == 'startInterval' and v2 == '2 min', 'two spaces inside a key: the value whole (' .. tostring(v2) .. ')')
T.check(R.exactKey('Rally start: Park', { rally = { 'rally' } }) == nil and
  R.exactKey('Rally: X', { rally = { 'rally' } }) == 'rally', 'exactKey')

T.check(R.fold('KRAŠOVO') == R.fold('Krašovo') and R.fold('Krašovo') == 'krasovo', 'capitals of Central Europe')
T.check(R.fold('ŁÓDŹ') == R.fold('Łódź') and R.fold('ΚΈΡΚΥΡΑ') ~= '' and R.fold('МОСКВА') == R.fold('Москва'),
  'capitals of other scripts')
T.check(not R.fold('Ζάκυνθος'):find('[%z\1-\31]'), 'no control bytes in a fold')
T.check(R.date('7 Februar 2031') == '2031-02-07' and R.date('7 février 2031') == '2031-02-07', 'other languages')
local _, why2 = R.date('TBC 2031')
T.check(why2 and not why2:find('day of the year', 1, true), 'not a date: not told to check the day')

T.done('test_textread')
