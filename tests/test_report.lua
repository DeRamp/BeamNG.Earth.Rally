-- report (+stats): the log cleaned of the player's details, the lines picked, the GitHub address built.
local T = dofile(TESTS .. '/testlib.lua')
function log() end
local report = require('earthRally/report')

local logText = table.concat({
  '0.012|I|init| Userpath: C:\\Users\\Jane Doe\\AppData\\Local\\BeamNG\\BeamNG.drive\\current',
  '0.020|I|steam| Steam user name: JaneRacer',
  '0.021|I|steam| SteamID 76561198012345678 logged on',
  '0.030|I|net| listening on 192.168.1.20:4444',
  '0.031|I|ver| BeamNG.drive 0.40.5.0.12345 build',
  '0.040|I|hw| H2: 9f8e7d6c5b4a',
  '0.050|I|mail| contact jane.doe@example.com',
  '0.060|I|earthRally| loaded from C:/Users/jdoe/Documents/mods, user jdoe',
}, '\n')

local out = table.concat(report.clean(logText, 'jdoe'), '\n')
T.check(not out:find('Jane Doe', 1, true), 'windows user in a path removed')
T.check(out:find('C:\\Users\\<you>\\AppData', 1, true) ~= nil, 'path kept with <you>')
T.check(not out:find('JaneRacer', 1, true), 'steam name line removed')
T.check(not out:find('76561198012345678', 1, true), 'steam id removed')
T.check(not out:find('192.168.1.20', 1, true), 'ip removed')
T.check(out:find('0.40.5.0.12345', 1, true) ~= nil, 'a long version number is not an ip')
T.check(not out:find('9f8e7d6c5b4a', 1, true), 'H2 line removed')
T.check(not out:find('jane.doe@example.com', 1, true), 'email removed')
T.check(not out:find('jdoe', 1, true), 'user name removed everywhere')

-- picking: our lines from early on, the tail whole
report.TAIL_LINES = 3
local ls = { 'a', 'earthRally: one', 'b', 'c', 'd', 'e' }
local picked = report.pick(ls)
T.check(picked:find('earthRally: one', 1, true) and not picked:find('\na\n', 1, true) and picked:find('c\nd\ne$'), 'ours + the tail')

-- the address
local url = report.issueUrl({ mod = '1.6.2-alpha+stats', game = '0.40.5', text = 'Notes stopped\non SS3 & more', logFile = 'earthRally/reports/log-1.txt' })
T.check(url:match('^https://github%.com/DeRamp/BeamNG%.Earth%.Rally/issues/new%?labels=bug&title=Notes%%20stopped&body=') ~= nil, 'title from the first line')
T.check(not url:find('&', #'https://github.com/DeRamp/BeamNG.Earth.Rally/issues/new?labels=bug&title=Notes%20stopped&body=' + 1, true), 'body encoded (no raw &)')
T.check(url:find('1.6.2-alpha%2Bstats', 1, true) ~= nil, 'version in the body')

T.done('test_report')
