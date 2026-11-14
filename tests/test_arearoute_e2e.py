#!/usr/bin/env python3
"""mod -> server -> mod for BeamNG.Earth's api.areaPlan / api.areaAdd / api.areaStatus, with no game: the pre-cache
call the auto recce needs, driven end to end against BeamNG.Earth's own server code.

Why this exists. 1.3.0's auto recce was broken four separate times and every one of those bugs lived in the gap
between two stand-ins -- our Lua suite drove the auto recce against a stand-in BeamNG.Earth, BeamNG.Earth's own
Python suite drove the call against a stand-in add-on, and both were green the whole time (see the long note in
tests/test_roadgraph_e2e.py). So this call gets its cross-boundary test written WITH it rather than after it.

What is real here and what is not:

  * BeamNG.Earth's mod half is its own api.lua, unmodified, under LuaJIT: M.areaPlan / M.areaAdd build the request
    and the game's JSON encoder writes it; M._onAreaPlan / M._onAreaAdd are handed the answer; M.areaStatus reads
    the app's own 'areas' broadcast through core.areasState().
  * the wire is BeamNG.Earth's protocol.py, encoded and decoded both ways, so neither side is handed a Python
    object the other never sent.
  * the server half is BeamNG.Earth's Connection.area_route_plan / Connection.area_route_add over a real
    areas.Areas: the real check_route, the real plan (plan_steps over the native corridor_tiles kernel), the real
    estimate, the real store in a temporary directory, and the real download thread.
  * the add-on is NOT ours yet. The mod half of this feature (earthAdapter's wrapper and the auto recce's
    download offer) is step 3 of docs/plan-1.3.1.md and is not written: what drives api.lua here is the sequence
    the auto recce will run -- plan, show the figure, add, follow the area, then decide from `unavailable` and
    `msg` whether the ground can be trusted -- written in the test's own Lua. When the real one lands it replaces
    the stand-in and these checks are the contract it has to keep.
  * the producers are stood in for (no network): the DEM, the map data and the imagery, exactly as BeamNG.Earth's
    own server/tests/test_areas.py stands them in, and modelled on its stubs.

What each part holds down, and what reintroducing the bug it guards looks like, is listed at the foot of this file.

Where BeamNG.Earth comes from: $BNGE_REPO, else a `beamng.earth` checkout beside this repository. Nothing in it is
written to -- the store and the cache are temporary directories and the producers never reach the network. Without
the checkout (or without its Python dependencies, or without lupa) this prints what is missing and passes, as
tests/test_roadgraph_e2e.py does.

Note on the interpreter: the server half needs the app's Python dependencies (numpy, and its native earthfast
module). When the interpreter running this suite has no numpy, this re-runs itself under <BeamNG.Earth>/.venv,
which has them.
"""
import asyncio
import contextlib
import importlib
import json
import logging
import os
import site
import subprocess
import sys
import tempfile
import time
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# --- the fixture ----------------------------------------------------------------------------------
# A stage line over the Smokies, where this machine's one real saved area is: on land, in the US, and the ground a
# 1.3.1 auto recce would actually ask for. Points every ~400 m, which is what the mod will send after decimation.
LINE = [[35.8939, -83.1537], [35.8975, -83.1480], [35.9010, -83.1420], [35.9048, -83.1365],
        [35.9085, -83.1300], [35.9120, -83.1240], [35.9160, -83.1180], [35.9200, -83.1120],
        [35.9240, -83.1060], [35.9264, -83.0984]]
HALF = 300.0                    # the corridor's half width (m): docs/plan-1.3.1.md's 300 m corridor
RECCE_LAYERS = ['roads']        # what the auto recce needs out of the ten (+ terrain, imagery)


# --------------------------------------------------------------------------------------------------
# finding BeamNG.Earth, and an interpreter that can run its server code
# --------------------------------------------------------------------------------------------------
def is_app(c):
    return (c / 'server' / 'earthd.py').is_file() and (c / 'mod' / 'beamng_earth').is_dir()


def app_repo():
    """The BeamNG.Earth checkout to drive, or None. $BNGE_REPO decides when it is set, even if it names nothing: a
    run that was pointed somewhere should say so rather than quietly test a different checkout."""
    env = os.environ.get('BNGE_REPO')
    if env:
        c = Path(env)
        return c if is_app(c) else None
    for name in ('beamng.earth', 'BeamNG.Earth', 'beamng-earth'):
        c = ROOT.parent / name
        if is_app(c):
            return c
    return None


def have_numpy():
    try:
        importlib.import_module('numpy')
        return True
    except ImportError:
        return False


def venv_python(app):
    for rel in ('.venv/Scripts/python.exe', '.venv/bin/python', '.venv/bin/python3'):
        p = app / rel
        if p.is_file():
            return p
    return None


def lupa_runtime():
    """lupa's LuaJIT 2.1 runtime, or None. (The user site-packages fallback is for the app's virtualenv, which has
    the server's dependencies but not lupa.)"""
    for extra in (None, site.getusersitepackages()):
        if extra is not None and extra not in sys.path:
            sys.path.append(extra)
        try:
            return importlib.import_module('lupa.luajit21')
        except ImportError:
            continue
    return None


# --------------------------------------------------------------------------------------------------
# the server's half: BeamNG.Earth's own areas.py and earthd handlers over stood-in producers
# --------------------------------------------------------------------------------------------------
FETCHED = []            # every download the producers were asked for (kind, what)


class StubDem:
    """The elevation producer, as server/tests/test_areas.py stands it in: it never goes to the network, and every
    tile it is asked for is recorded so a narrowed plan can be shown to have asked for nothing."""

    def __init__(self, fail_at=None):
        self.have, self.fail_at = set(), fail_at

    def has(self, z, x, y):
        return (z, x, y) in self.have

    def predownload(self, z, x, y):
        FETCHED.append(('dem', (z, x, y)))
        if self.fail_at is not None and (z, x, y) == self.fail_at:
            raise OSError('404 from every host')        # (an item no server has: the 11 % case)
        self.have.add((z, x, y))
        return True


class StubMapData:
    def __init__(self):
        self.have = set()

    def has(self, key, layer):
        return (tuple(key), layer) in self.have

    def predownload(self, key, layer):
        FETCHED.append(('cell', (tuple(key), layer)))
        self.have.add((tuple(key), layer))
        return True


class StubCache:
    def __init__(self, cap=20e9):
        self.cap, self.ready, self.pinned, self.pinned_bytes = cap, True, None, None

    def sizes(self, keys=None):
        return []


class StubServer:
    """What areas.Areas reads of an earthd.Server. No imagery (its predownload_sources would want real sources),
    which is why the imagery steps here are counted and not fetched -- the plan is what this test is about."""

    def __init__(self, netfetch, cap=20e9, fail_at=None):
        self.dem = StubDem(fail_at)
        self.mapdata = StubMapData()
        self.imagery = None
        self.net = netfetch.Fetcher(offline=True)
        self.cache = StubCache(cap)
        self.connections = []

    def live_busy(self):
        return False

    def driving(self):
        return False


class App:
    """BeamNG.Earth's server modules, and one Server stand-in holding a real areas.Areas."""

    def __init__(self, app, tmp, cap=20e9, fail_at=None, with_areas=True, patch=()):
        sys.path.insert(0, str(app / 'server'))
        self.app, self.tmp = app, tmp
        self.protocol = importlib.import_module('protocol')
        self.netfetch = importlib.import_module('netfetch')
        self.areasmod = importlib.import_module('areas')
        self.earthd = importlib.import_module('earthd')
        self.undo = []
        # the download thread's own waits, as BeamNG.Earth's test_areas.py shortens them
        for name, v in (('IDLE_WAIT_S', 0.02), ('DEFER_WAIT_S', 0.01), ('STATUS_S', 0.0)) + tuple(patch):
            self.undo.append((name, getattr(self.areasmod, name)))
            setattr(self.areasmod, name, v)
        self.store = tmp / 'store'
        self.store.mkdir(parents=True, exist_ok=True)
        self.producers = StubServer(self.netfetch, cap, fail_at)
        self.broadcast = []            # every 'areas' message the app would have sent every connection
        self.areas = None
        if with_areas:
            self.areas = self.areasmod.Areas(str(self.store), self.producers, notify=self._notify)
        self.server = types.SimpleNamespace(areas=self.areas)
        self.server.areas_message = lambda result=None: self.earthd.Server.areas_message(self.server, result)

    def close(self):
        if self.areas is not None:
            self.areas.close()
        for name, v in self.undo:
            setattr(self.areasmod, name, v)

    def start(self):
        self.areas.start()
        return self

    def _notify(self):
        """earthd's own areas_changed: the 'areas' message to every connection on every change."""
        self.broadcast.append(self.server.areas_message())

    # --- the handlers -------------------------------------------------------------------------
    def handle(self, req):
        """Connection.area_route_plan / area_route_add over the stand-in: the messages it sent, each decoded off
        the wire as the mod's net would decode it."""
        sent = []
        conn = types.SimpleNamespace(s=self.server, send=sent.append, route_points=[])
        conn._area_route = lambda m: self.earthd.Connection._area_route(conn, m)
        conn._area_route_points = lambda m: self.earthd.Connection._area_route_points(conn, m)
        fn = {'area_route_plan': self.earthd.Connection.area_route_plan,
              'area_route_add': self.earthd.Connection.area_route_add,
              'area_plan': self.earthd.Connection.area_plan,
              'area_add': self.earthd.Connection.area_add}[req['type']]
        asyncio.run(fn(conn, req))
        out = []
        for m in sent:
            out += self.protocol.Decoder().feed(self.protocol.encode(m))
        return out

    def wire_in(self, text):
        """A request the mod's JSON encoder wrote, as the server's own decoder makes it off the socket."""
        msgs = self.protocol.Decoder().feed(self.protocol.encode(json.loads(text)))
        if len(msgs) != 1:
            raise AssertionError('one frame expected: %r' % (msgs,))
        return msgs[0]

    def wire_out(self, msg):
        """An answer the server sent, as the bytes the mod's net reads (the frame's payload)."""
        frame = self.protocol.encode(msg)
        return frame[self.protocol.HEADER.size:].decode('utf-8')


# --------------------------------------------------------------------------------------------------
# the mod's half: BeamNG.Earth's api.lua, unmodified, with an add-on over it
# --------------------------------------------------------------------------------------------------
_BOOT = r"""
package.path = BNGE_LUA .. '/?.lua;' .. package.path
dofile(BNGE_TESTS .. '/stubs.lua')            -- BeamNG.Earth's own offline game stubs
local J = dofile(BNGE_TESTS .. '/minijson.lua')   -- ... and its stand-in for the game's JSON
function jsonEncode(v) return J.encode(v) end
function jsonDecode(s) local ok, v = pcall(J.decode, s) if ok then return v end return nil end

LOGS = {}
function log(level, _, msg) LOGS[#LOGS + 1] = tostring(level) .. ' ' .. tostring(msg) end

CONNECTED = true
package.loaded['beamngEarth/net'] = {
  isConnected = function() return CONNECTED end,
  send = function(m) PY_SEND(jsonEncode(m)) end }

-- BeamNG.Earth's core, as api.lua reads it. areasState() is the app's last 'areas' broadcast, which is how
-- api.areaStatus answers: core.lua keeps it in M._areas and this is the same read.
local AREAS = nil
local st = { inOurLevel = true, anchor = nil, player = nil, pending = nil }
beamngEarth_core = {
  _state = function() return st end,
  groundReady = function() return true end,
  serverHello = function() return { appVersion = 'test' } end,
  areasState = function() return AREAS end,
}
function SET_AREAS(text) AREAS = jsonDecode(text) end

API = require('beamngEarth/api')
beamngEarth_api = API

------------------------------------------------------------------------------------------
-- the add-on: the sequence 1.3.1's auto recce will run, nothing more
local recce = { }

function HAS(name) return API.has(name) == true end
function VERSION() local a, b = API.version() return J.encode({ a, b }) end

-- step 1: what would this cost? (the figure the player is shown before being asked)
function ASK_PLAN(pointsJson, half, layersJson)
  recce.plan = nil
  local opts = { half = half, layers = layersJson and jsonDecode(layersJson) or nil }
  local id, why = API.areaPlan(jsonDecode(pointsJson), opts, function(res) recce.plan = res end)
  return J.encode({ id = id, why = why })
end

-- step 2: the player said yes
function ASK_ADD(pointsJson, half, layersJson, name)
  recce.add = nil
  local opts = { half = half, name = name, layers = layersJson and jsonDecode(layersJson) or nil }
  local id, why = API.areaAdd(jsonDecode(pointsJson), opts, function(res) recce.add = res end)
  return J.encode({ id = id, why = why })
end

function DELIVER(text, which)
  local msg = jsonDecode(text)
  if which == 'plan' then API._onAreaPlan(msg) else API._onAreaAdd(msg) end
end

local function typesOf(t, keys)
  local out = {}
  for _, k in ipairs(keys) do out[k] = type(t[k]) end
  return out
end

function PLAN_RESULT()
  if recce.plan == nil then return nil end
  return J.encode({ res = recce.plan,
                    types = typesOf(recce.plan, { 'ok', 'km', 'km2', 'items', 'missing', 'downloadBytes',
                                                  'diskBytes', 'layers', 'error' }) })
end

function ADD_RESULT()
  if recce.add == nil then return nil end
  return J.encode({ res = recce.add, types = typesOf(recce.add, { 'ok', 'id', 'error' }) })
end

-- step 3: follow it, and step 4: decide whether the ground can be trusted. This is the whole reason
-- `unavailable` and `msg` have to come over: "done" is not "the data arrived".
function RECCE_VERDICT(id)
  local a = API.areaStatus(id)
  if a == nil then return J.encode({ gone = true }) end
  local out = { id = a.id, name = a.name, state = a.state, done = a.done, total = a.total,
                unavailable = a.unavailable, msg = a.msg, half = a.half, layers = a.layers,
                types = typesOf(a, { 'state', 'done', 'total', 'unavailable', 'msg' }) }
  if a.state ~= 'done' then
    out.verdict = 'waiting'
    out.telling = (a.state == 'queued' and 'waiting its turn') or a.state
  elseif (a.unavailable or 0) > 0 then
    -- the 1.3.1 rule: a finished download is MAYBE better ground, so re-check rather than trust, and put the
    -- app's own words in front of the player because resuming is an action only they can take
    out.verdict = 'recheck'
    out.tellPlayer = a.msg
  else
    out.verdict = 'ready'
  end
  return J.encode(out)
end

-- the frame pump, for the timeout sweep
function TICK(dt) API.onUpdate(dt) end
function LOG_TEXT() return table.concat(LOGS, '\n') end
"""


class Mod:
    """One LuaJIT state with BeamNG.Earth's api.lua and the add-on sequence in it."""

    def __init__(self, lupa, app):
        self.sent = []
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.PY_SEND = lambda text: self.sent.append(str(text))
        g.BNGE_LUA = (app.app / 'mod' / 'beamng_earth' / 'lua' / 'ge' / 'extensions').as_posix()
        g.BNGE_TESTS = (app.app / 'mod' / 'tests').as_posix()
        self.lua.execute(_BOOT)
        self.g = self.lua.globals()

    def take(self):
        if not self.sent:
            raise AssertionError('the mod sent nothing')
        return self.sent.pop(0)


# --------------------------------------------------------------------------------------------------
class Checks:
    def __init__(self):
        self.passed = self.failed = 0

    def ok(self, cond, what):
        if cond:
            self.passed += 1
            print('ok    ' + what)
        else:
            self.failed += 1
            print('FAIL  ' + what)
        return bool(cond)


def wait_for(cond, timeout=30.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if cond():
            return True
        time.sleep(0.01)
    return False


def jl(v):
    return json.loads(str(v)) if v is not None else None


# --- part A: the request as api.lua really sends it, and the estimate back -------------------------
def part_a(c, app, mod):
    print('\n-- api.areaPlan: the wire, the estimate, and the layers subset --')
    c.ok(mod.g.HAS('areaRoute') is True, "has('areaRoute') is on in this api.lua")
    major, minor = jl(mod.g.VERSION())
    c.ok(major == 1 and minor >= 9, 'the API is 1.%s, a minor with a has() name of its own (%s)' % (minor, major))

    took = jl(mod.g.ASK_PLAN(json.dumps(LINE), HALF, None))
    c.ok(took['id'] is not None, 'api.areaPlan took the call (%r)' % (took.get('why'),))
    req = app.wire_in(mod.take())
    c.ok(req.get('type') == 'area_route_plan', 'the request is an area_route_plan message')
    c.ok(isinstance(req.get('route'), dict), 'the points travel under "route" as the store holds them')
    c.ok(req['route'].get('lat') == [p[0] for p in LINE] and req['route'].get('lon') == [p[1] for p in LINE],
         'every point of the line survived the mod\'s JSON, in order and as two parallel lists')
    c.ok(abs(float(req['half']) - HALF) < 1e-9, 'the half width it was given')
    c.ok(isinstance(req['id'], int) and not isinstance(req['id'], bool),
         "the request id survived the game's JSON as a whole number")
    c.ok('fast' not in req, 'BUG F: no "fast" on the wire, for a plan either (keys: %s)' % sorted(req))
    c.ok('mode' not in req, 'and no "mode": an add-on cannot ask for the world to be built ahead')

    answers = app.handle(req)
    c.ok(len(answers) == 1, 'one answer a request')
    full = answers[0]
    c.ok(full.get('type') == 'area_route_plan_result', 'the answer is an area_route_plan_result')
    c.ok(full.get('ok') is True, 'the estimate was made (%r)' % (full.get('error'),))
    mod.g.DELIVER(app.wire_out(full), 'plan')
    got = jl(mod.g.PLAN_RESULT())
    c.ok(got is not None, "the add-on's callback was called")
    res, kinds = got['res'], got['types']
    c.ok(res.get('error') is None, 'no error in the answer')
    c.ok(kinds['ok'] == 'boolean' and res.get('ok') is True, 'ok came over as a boolean (got %r)' % kinds['ok'])
    for f in ('km', 'km2', 'items', 'missing', 'downloadBytes', 'diskBytes'):
        c.ok(kinds[f] == 'number', '%s reached the add-on as a number (got %r)' % (f, kinds[f]))
    c.ok((res.get('km') or 0) > 2.0, 'the line it measured is the line we sent (%r km)' % (res.get('km'),))
    c.ok((res.get('items') or 0) > 0 and (res.get('missing') or 0) > 0, 'it has items to do (%r of %r missing)'
         % (res.get('missing'), res.get('items')))
    c.ok(kinds['layers'] == 'table' and len(res.get('layers') or []) == 0,
         'BUG L: no subset asked for, so "layers" comes back empty, not absent (%r)' % (res.get('layers'),))
    return full, res


def part_layers(c, app, mod, full):
    print('\n-- the layers subset: what it is for --')
    took = jl(mod.g.ASK_PLAN(json.dumps(LINE), HALF, json.dumps(RECCE_LAYERS)))
    c.ok(took['id'] is not None, 'api.areaPlan with opts.layers took the call (%r)' % (took.get('why'),))
    req = app.wire_in(mod.take())
    c.ok(req.get('layers') == RECCE_LAYERS, 'the subset is on the wire as a list of names (%r)' % (req.get('layers'),))
    narrow = app.handle(req)[0]
    c.ok(narrow.get('ok') is True, 'the narrowed estimate was made (%r)' % (narrow.get('error'),))
    mod.g.DELIVER(app.wire_out(narrow), 'plan')
    got = jl(mod.g.PLAN_RESULT())
    res = got['res']
    c.ok(res.get('layers') == RECCE_LAYERS,
         'BUG L: the app echoes the subset it honoured, so an older app that ignored the field is visible (%r)'
         % (res.get('layers'),))
    # the whole point of writing the subset, measured rather than asserted loosely
    items = (full.get('items') or 0, narrow.get('items') or 0)
    dl = (full.get('downloadBytes') or 0, narrow.get('downloadBytes') or 0)
    c.ok(0 < items[1] < items[0],
         'BUG L: the roads layer alone is a smaller plan (%d items against %d: %.0f%% of it)'
         % (items[1], items[0], 100.0 * items[1] / max(1, items[0])))
    c.ok(0 < dl[1] < dl[0] / 2.0,
         'BUG L: ... and less than half the bytes (%.1f MB against %.1f MB: %.0f%% of it)'
         % (dl[1] / 1e6, dl[0] / 1e6, 100.0 * dl[1] / max(1, dl[0])))
    print('      measured: %d items / %.1f MB for the whole ground, %d items / %.1f MB for roads only'
          % (items[0], dl[0] / 1e6, items[1], dl[1] / 1e6))
    # a subset that names nothing real is refused in words, not with a stack trace
    took = jl(mod.g.ASK_PLAN(json.dumps(LINE), HALF, json.dumps(['tarmac'])))
    bad = app.handle(app.wire_in(mod.take()))[0]
    c.ok(bad.get('ok') is False and 'tarmac' in str(bad.get('error')) and 'roads' in str(bad.get('error')),
         'an unknown layer is refused with the names that would work (%r)' % (bad.get('error'),))
    return narrow


# --- part B: the add, fast out of reach, and the area the player sees ------------------------------
def part_b(c, app, mod):
    print('\n-- api.areaAdd: the area, and fast mode out of reach --')
    took = jl(mod.g.ASK_ADD(json.dumps(LINE), HALF, json.dumps(RECCE_LAYERS), 'Earth Rally: recce'))
    c.ok(took['id'] is not None, 'api.areaAdd took the call (%r)' % (took.get('why'),))
    req = app.wire_in(mod.take())
    c.ok(req.get('type') == 'area_route_add', 'the request is an area_route_add message')
    c.ok('fast' not in req,
         'BUG F: api.areaAdd puts no "fast" on the wire at all (keys: %s)' % sorted(req))
    c.ok(req.get('name') == 'Earth Rally: recce', 'the name the player will see in their own area list')
    c.ok(req.get('layers') == RECCE_LAYERS, 'the subset went with the add, not only with the plan')

    # the hard part of the claim: even a message that DOES carry fast cannot turn it on, because the handler
    # never reads the field. An add-on can send whatever it likes down this socket -- api.lua not sending it is
    # politeness, this is the guarantee.
    forged = dict(req, fast=True)
    answers = app.handle(forged)
    c.ok(len(answers) == 1 and answers[0].get('type') == 'area_route_add_result', 'one area_route_add_result back')
    ans = answers[0]
    c.ok(ans.get('ok') is True, 'the area was added (%r)' % (ans.get('error'),))
    c.ok(app.areas.fast_id is None,
         'BUG F: a forged "fast": true on this message did not start fast mode (fast_id %r)' % (app.areas.fast_id,))
    c.ok(app.server.areas_message().get('fast') == '',
         "BUG F: ... so the 'areas' message names no fast area, and the mod never pauses the player's game")

    mod.g.DELIVER(app.wire_out(ans), 'add')
    got = jl(mod.g.ADD_RESULT())
    c.ok(got is not None, "the add-on's callback was called")
    res, kinds = got['res'], got['types']
    # The one field in this call whose name differs on the two sides: the server answers "area" (as area_add
    # already does) and an add-on reads result.id. That is the shape of 1.3.0's first road-graph bug -- the server
    # sent the name of a file and the add-on read result.nodes -- so it is the one worth a check of its own.
    c.ok(kinds['id'] == 'string' and res.get('id'),
         "BUG N: the add-on was handed the new area's id under the name it reads (%r / %r)"
         % (kinds['id'], res.get('id')))
    c.ok(res.get('ok') is True, 'and ok (%r)' % (res.get('error'),))
    aid = res.get('id')

    # the area as the player's own list has it, which is also what api.areaStatus reads
    c.ok(app.broadcast, "the app broadcast an 'areas' message when the area appeared")
    listed = app.broadcast[-1]['areas'] if app.broadcast else []
    c.ok(len(listed) == 1 and listed[0].get('id') == aid, 'the area is in the player\'s list (%r)' % (listed,))
    a = listed[0] if listed else {}
    c.ok(a.get('name') == 'Earth Rally: recce', 'under the name the add-on gave it')
    c.ok('unavailable' in a, "BUG U: the 'areas' message carries unavailable for every area (keys: %s)"
         % sorted(a))
    c.ok(a.get('layers') == RECCE_LAYERS, 'and the subset, so a restart shows what this area is for')
    c.ok(abs(float(a.get('half', 0)) - HALF) < 1e-9, 'and its width, with the line for the map to draw')

    mod.g.SET_AREAS(json.dumps(app.broadcast[-1] if app.broadcast else {'areas': []}))
    v = jl(mod.g.RECCE_VERDICT(aid)) or {'gone': True}
    v.setdefault('types', {})
    c.ok(v.get('gone') is not True, 'api.areaStatus found the area by the id it was handed')
    c.ok(v['types'].get('done') == 'number' and v['types'].get('total') == 'number',
         'done / total reach the add-on as numbers (%r / %r)'
         % (v['types'].get('done'), v['types'].get('total')))
    c.ok(v['types'].get('unavailable') == 'number',
         'BUG U: ... and so does unavailable (%r)' % (v['types'].get('unavailable'),))
    c.ok((v.get('total') or 0) > 0, 'the area has a plan with items in it (%r)' % (v.get('total'),))
    c.ok(v.get('layers') == RECCE_LAYERS, 'areaStatus gives back the subset, copied (%r)' % (v.get('layers'),))
    return aid


# --- part C: the persistence a resume depends on ---------------------------------------------------
def part_c(c, app_dir, lupa):
    print('\n-- the store: a narrowed area is still narrowed after a restart --')
    tmp = Path(tempfile.mkdtemp(prefix='ar_e2e_store_'))
    app = App(app_dir, tmp)
    try:
        mod = Mod(lupa, app)
        mod.g.ASK_ADD(json.dumps(LINE), HALF, json.dumps(RECCE_LAYERS), 'narrowed')
        ans = app.handle(app.wire_in(mod.take()))[0]
        c.ok(ans.get('ok') is True, 'the narrowed area was added (%r)' % (ans.get('error'),))
        aid = ans.get('area')
        listed = app.areas.message()['areas']
        narrow_total = listed[0]['total'] if listed else 0
        stored = json.loads((app.store / 'areas' / 'areas.json').read_text(encoding='utf-8'))
        kept = (stored.get('areas') or [{}])[0]
        c.ok(kept.get('layers') == RECCE_LAYERS,
             'BUG P: the subset is written into areas.json (%r)' % (kept.get('layers'),))
        c.ok(isinstance(kept.get('route'), dict) and len(kept['route']['lat']) == len(LINE),
             'and the line verbatim beside it (%d points)' % len(kept.get('route', {}).get('lat', [])))
    finally:
        app.close()
    # a second server over the same store: the plan it would walk has to be the plan the area was added with,
    # or a restart silently turns a 1-layer area back into a 12-layer one and downloads the lot
    again = App(app_dir, tmp)
    try:
        back = again.areas.message()['areas']
        c.ok(len(back) == 1 and back[0]['id'] == aid, 'the area came back from the store')
        c.ok(back[0].get('layers') == RECCE_LAYERS,
             'BUG P: ... still narrowed (%r)' % (back[0].get('layers'),))
        a = (again.areas.areas or [{}])[0] or {'s': 0, 'w': 0, 'n': 1, 'e': 1, 'mode': 'data', 'route': None}
        walk = again.areas.steps((a['s'], a['w'], a['n'], a['e']), a['mode'], a['route'], a.get('layers'))
        c.ok(len(walk) == narrow_total,
             'BUG P: and the plan a resume walks is the narrowed one (%d steps against the %d it was added with)'
             % (len(walk), narrow_total))
        wide = again.areas.steps((a['s'], a['w'], a['n'], a['e']), a['mode'], a['route'], None)
        c.ok(len(wide) > len(walk),
             'BUG P: (the un-narrowed plan of the same corridor is %d steps, so this is a real difference)'
             % len(wide))
    finally:
        again.close()


# --- part D: "done" is not "the data arrived" ------------------------------------------------------
def part_d(c, app_dir, lupa):
    print('\n-- the 11 %% case: an area that finishes complete with items unavailable --')
    tmp = Path(tempfile.mkdtemp(prefix='ar_e2e_unavail_'))
    # one DEM tile of the corridor that no host has, as BeamNG.Earth's own test_items_failing_every_pass does it:
    # after MAX_FAILED_PASSES the area is marked done and the rest counted unavailable
    probe = App(app_dir, tmp / 'probe')
    try:
        plan = probe.areas.plan_route([p[0] for p in LINE], [p[1] for p in LINE], HALF)
        bad = next(st[1:] for st in probe.areas.steps(
            probe.areasmod.route_bounds({'lat': [p[0] for p in LINE], 'lon': [p[1] for p in LINE], 'half': HALF}),
            route={'lat': [p[0] for p in LINE], 'lon': [p[1] for p in LINE], 'half': HALF}) if st[0] == 'dem')
        c.ok(plan['ok'] is True and bad is not None, 'the corridor has a DEM tile to make unavailable (%r)' % (bad,))
    finally:
        probe.close()
    app = App(app_dir, tmp / 'run', fail_at=bad, patch=(('PASS_RETRY_S', 0.0),)).start()
    try:
        mod = Mod(lupa, app)
        mod.g.ASK_ADD(json.dumps(LINE), HALF, json.dumps(['roads', 'terrain']), 'Earth Rally: holey')
        ans = app.handle(app.wire_in(mod.take()))[0]
        c.ok(ans.get('ok') is True, 'the area was added (%r)' % (ans.get('error'),))
        aid = ans.get('area')
        done = wait_for(lambda: (app.areas.message()['areas'] or [{}])[0].get('state') == 'done', 60.0)
        c.ok(done, 'the download finished (state %r)'
             % ((app.areas.message()['areas'] or [{}])[0].get('state'),))
        m = (app.areas.message()['areas'] or [{}])[0]
        c.ok((m.get('unavailable') or 0) > 0,
             'BUG U: it finished with items nothing could fetch (%r unavailable of %r)'
             % (m.get('unavailable'), m.get('total')))
        c.ok('unavailable' in str(m.get('msg')) and 'Resume' in str(m.get('msg')),
             "and msg says so in words a player can act on (%r)" % (m.get('msg'),))

        mod.g.SET_AREAS(json.dumps(app.server.areas_message()))
        v = jl(mod.g.RECCE_VERDICT(aid)) or {}
        c.ok(v.get('state') == 'done', 'the add-on sees it as done')
        c.ok(v.get('unavailable') == m.get('unavailable'),
             'BUG U: ... and is told how many items never arrived (%r)' % (v.get('unavailable'),))
        c.ok(v.get('verdict') == 'recheck',
             'BUG U: so the auto recce re-checks the ground rather than trusting it (verdict %r)'
             % (v.get('verdict'),))
        c.ok(v.get('tellPlayer') and 'Resume' in str(v['tellPlayer']),
             'BUG U: and has the app\'s own words to put in front of the player (%r)' % (v.get('tellPlayer'),))
        # the other half of the same contract: an area with nothing missing reads as ready, or the rule above
        # would make every download look suspect
        clean = dict(app.server.areas_message())
        clean['areas'] = [dict(m, unavailable=0, msg='')]
        mod.g.SET_AREAS(json.dumps(clean))
        c.ok((jl(mod.g.RECCE_VERDICT(aid)) or {}).get('verdict') == 'ready',
             'and an area that finished with nothing missing reads as ready')
    finally:
        app.close()


# --- part E: the refusals, in words an add-on can act on -------------------------------------------
def part_e(c, app_dir, lupa):
    print('\n-- the refusals --')
    tmp = Path(tempfile.mkdtemp(prefix='ar_e2e_refuse_'))
    app = App(app_dir, tmp)
    try:
        mod = Mod(lupa, app)
        # THE regression this change exists for: explicit points used to fall through to the box path, and the
        # caller was told to send south, west, north and east -- which an add-on holding a line cannot act on
        probe = {'type': 'area_plan', 'id': 1, 'route': {'lat': [p[0] for p in LINE], 'lon': [p[1] for p in LINE]},
                 'half': HALF}
        res = app.handle(probe)[0]
        c.ok(res.get('ok') is True,
             "BUG R: area_plan takes points named outright instead of falling through to the box path (%r)"
             % (res.get('error'),))
        c.ok('south, west, north and east' not in str(res.get('error') or ''),
             'BUG R: ... so nobody is answered "an area needs south, west, north and east in degrees"')
        # and the same line as an area_add, which used to have no guard at all round _area_route
        res = app.handle({'type': 'area_add', 'id': 2, 'route': {'lat': 'nope', 'lon': []}, 'half': HALF})[0]
        c.ok(res.get('type') == 'areas' and (res.get('result') or {}).get('ok') is False,
             'BUG R: a malformed route on area_add is answered, not dropped on the floor (%r)' % (res.get('result'),))
        c.ok('lat' in str((res.get('result') or {}).get('error')),
             '... and says which field was wrong (%r)' % ((res.get('result') or {}).get('error'),))

        for msg, want, what in (
                ({'type': 'area_route_plan', 'id': 3, 'half': HALF}, 'route',
                 'a plan with no route at all'),
                ({'type': 'area_route_plan', 'id': 4, 'route': {'lat': [35.9], 'lon': [-83.1]}, 'half': HALF},
                 'two points', 'a one-point line'),
                ({'type': 'area_route_plan', 'id': 11, 'route': {'lat': [p[0] for p in LINE], 'lon': [-83.1]},
                  'half': HALF}, 'as many', 'a line with a longitude missing'),
                ({'type': 'area_route_plan', 'id': 5, 'route': {'lat': [p[0] for p in LINE],
                                                                'lon': [p[1] for p in LINE]}, 'half': 5.0},
                 'each side', 'a width under the minimum'),
                ({'type': 'area_route_plan', 'id': 6, 'route': 'current', 'half': HALF}, 'route',
                 "the player's own planned route, which is not an add-on's to ask for")):
            out = app.handle(msg)[0]
            c.ok(out.get('ok') is False and want in str(out.get('error') or ''),
                 '%s: refused in words (%r)' % (what, out.get('error')))
            mod.g.DELIVER(app.wire_out(out), 'plan' if msg['type'] == 'area_route_plan' else 'add')

        # the mod's own refusals: nothing goes on the wire for them
        for call, args, what in (('ASK_PLAN', (json.dumps([LINE[0]]), HALF, None), 'one point'),
                                 ('ASK_PLAN', (json.dumps(LINE), None, None), 'no half width'),
                                 ('ASK_PLAN', (json.dumps([[91.0, 0.0], [0.0, 0.0]]), HALF, None),
                                  'a point off the map'),
                                 ('ASK_PLAN', (json.dumps(LINE), HALF, json.dumps([])), 'an empty layers list')):
            got = jl(getattr(mod.g, call)(*args))
            c.ok(got.get('id') is None and got.get('why'), 'api.areaPlan refuses %s before sending (%r)'
                 % (what, got.get('why')))
        c.ok(not mod.sent, 'and put nothing on the wire for any of them (%d message(s))' % len(mod.sent))
        mod.g.CONNECTED = False
        got = jl(mod.g.ASK_PLAN(json.dumps(LINE), HALF, None))
        c.ok(got.get('id') is None and 'not connected' in str(got.get('why')),
             'with no companion server it says so rather than queueing (%r)' % (got.get('why'),))
        mod.g.CONNECTED = True
    finally:
        app.close()

    # no download cache at all: the add-on is told, not left waiting
    bare = App(app_dir, Path(tempfile.mkdtemp(prefix='ar_e2e_bare_')), with_areas=False)
    try:
        mod = Mod(lupa, bare)
        mod.g.ASK_PLAN(json.dumps(LINE), HALF, None)
        out = bare.handle(bare.wire_in(mod.take()))[0]
        c.ok(out.get('ok') is False and 'download cache' in str(out.get('error')),
             'a server with no download cache says so (%r)' % (out.get('error'),))
        mod.g.DELIVER(bare.wire_out(out), 'plan')
        got = jl(mod.g.PLAN_RESULT())
        c.ok(got and got['types']['error'] == 'string' and got['res'].get('ok') is False,
             'and the add-on gets the reason, with ok false (%r)' % (got and got['res'].get('error'),))
        mod.g.ASK_ADD(json.dumps(LINE), HALF, None, 'x')
        out = bare.handle(bare.wire_in(mod.take()))[0]
        c.ok(out.get('type') == 'area_route_add_result' and out.get('ok') is False,
             'an add against it is answered too, with its own type (%r)' % (out.get('type'),))
    finally:
        bare.close()

    # the pin refusal (areas.PIN_SHARE), which the mod has to surface rather than swallow
    small = App(app_dir, Path(tempfile.mkdtemp(prefix='ar_e2e_pin_')), cap=1e6)
    try:
        mod = Mod(lupa, small)
        mod.g.ASK_ADD(json.dumps(LINE), HALF, None, 'too big')
        out = small.handle(small.wire_in(mod.take()))[0]
        c.ok(out.get('ok') is False and 'cache' in str(out.get('error')),
             'an area that would not fit the cache is refused with the setting to raise (%r)' % (out.get('error'),))
        mod.g.DELIVER(small.wire_out(out), 'add')
        got = jl(mod.g.ADD_RESULT())
        c.ok(got and got['res'].get('ok') is False and got['types']['error'] == 'string',
             'and the add-on is handed that sentence to show (%r)' % (got and got['res'].get('error'),))
    finally:
        small.close()


# --- part F: a request that is never answered ------------------------------------------------------
def part_f(c, app_dir, lupa):
    print('\n-- a request the app never answers --')
    app = App(app_dir, Path(tempfile.mkdtemp(prefix='ar_e2e_timeout_')), with_areas=False)
    try:
        mod = Mod(lupa, app)
        mod.g.ASK_PLAN(json.dumps(LINE), HALF, None)
        mod.take()                                  # (sent, and nothing ever comes back)
        mod.g.TICK(1.0)
        c.ok(jl(mod.g.PLAN_RESULT()) is None, 'nothing is handed to the callback while it is still in flight')
        mod.g.TICK(float(mod.g.API.AREA_TIMEOUT_S) + 1.0)
        got = jl(mod.g.PLAN_RESULT())
        c.ok(got is not None and got['res'].get('error') == 'timed out',
             'after api.AREA_TIMEOUT_S the callback is told it timed out (%r)' % (got and got['res'],))
        before = len(str(mod.g.LOG_TEXT()))
        mod.g.TICK(1000.0)
        c.ok(jl(mod.g.PLAN_RESULT())['res'].get('error') == 'timed out',
         'and heard once: a second sweep hands it nothing new')
        del before
    finally:
        app.close()


# --------------------------------------------------------------------------------------------------
def main():
    app_dir = app_repo()
    if app_dir is None:
        print('test_arearoute_e2e: no BeamNG.Earth checkout at %s: skipped'
              % (os.environ.get('BNGE_REPO') or ('%s/beamng.earth' % ROOT.parent)))
        return 0
    if not have_numpy():
        if os.environ.get('BNGE_AR_E2E_CHILD'):
            print('test_arearoute_e2e: %s has no numpy either: skipped' % sys.executable)
            return 0
        vp = venv_python(app_dir)
        if vp is None:
            print('test_arearoute_e2e: this interpreter has no numpy and %s has no .venv: skipped' % app_dir)
            return 0
        env = dict(os.environ, BNGE_AR_E2E_CHILD='1', BNGE_REPO=str(app_dir))
        return subprocess.run([str(vp), str(Path(__file__).resolve())], env=env).returncode
    lupa = lupa_runtime()
    if lupa is None:
        print('test_arearoute_e2e: lupa (LuaJIT) is not installed for %s: skipped' % sys.executable)
        return 0
    print('test_arearoute_e2e: BeamNG.Earth at %s, %s' % (app_dir, sys.executable))

    c = Checks()
    logging.getLogger('earthd').setLevel(logging.ERROR)
    app = App(app_dir, Path(tempfile.mkdtemp(prefix='ar_e2e_')))
    try:
        mod = Mod(lupa, app)
        full, _ = part_a(c, app, mod)
        part_layers(c, app, mod, full)
        part_b(c, app, mod)
    finally:
        app.close()
    part_c(c, app_dir, lupa)
    part_d(c, app_dir, lupa)
    part_e(c, app_dir, lupa)
    part_f(c, app_dir, lupa)
    print('\ntest_arearoute_e2e: %d passed, %d failed' % (c.passed, c.failed))
    return 1 if c.failed else 0


# --------------------------------------------------------------------------------------------------
# What each lettered check guards, and what reintroducing it looks like. These are the four shapes of
# cross-boundary bug 1.3.0 was broken by, named so a red line here says which one came back.
#
#   BUG N  "the answer carries the thing the add-on reads, not the field the server named it".  1.3.0's first
#          road-graph bug was the server answering with a file path while the add-on read result.nodes. In this
#          call there is exactly one such rename -- the server answers `area` and an add-on reads `result.id` --
#          and part B holds it down. Make _onAreaAdd hand the raw message through and that check goes red.
#          (The plan's own fields are NOT renamed, so handing the raw message through there changes nothing that
#          can be seen from outside; what _onAreaPlan adds is type defence, and that is held down in
#          BeamNG.Earth's own mod/tests/test_api.lua rather than pretended at here.)
#
#   BUG L  the layers subset is honoured AND visible.  A subset that the server quietly ignores is worse than no
#          subset: the add-on shows the player 30 MB and downloads 330. The checks are that the narrowed plan is
#          really smaller (items and bytes, printed), and that the result echoes `layers` so an add-on talking to
#          an older app can tell. Drop `out["layers"]` from plan_route, or the filter in phase_steps, and they go
#          red with the real figures in the line.
#
#   BUG P  the subset is persisted and re-validated.  areas.py plans an area from its stored shape on every pass
#          and after every restart. Leave `layers` out of _save / _load and the area comes back as a 12-layer one
#          and downloads everything the player was never asked about -- silently, because `total` is recomputed
#          at the same moment. Part C fails with the two step counts side by side.
#
#   BUG F  fast mode is not reachable.  In fast mode BeamNG.Earth's own core.lua pauses the player's physics for
#          any client on any fast area (fastAreaPause -> simhold.pause(true)). Part B sends a forged
#          "fast": true on this message type and requires fast_id to stay None: api.lua not sending the field is
#          politeness, the handler not reading it is the guarantee. Add `fast=msg.get("fast") is True` to
#          area_route_add and two checks go red.
#
#   BUG U  "done" is not "the data arrived".  The one saved area on the machine this was written on finished
#          complete with 122 of its 1079 items unavailable -- 11 % -- after three failed passes. If `unavailable`
#          does not reach the add-on it has no way to know, and if `msg` does not, the player never hears the one
#          sentence they can act on. Part D makes a real area end that way and follows the number and the words
#          all the way to the add-on's verdict. Drop "unavailable" from Areas.message() and five checks go red.
#
#   BUG R  the regression this change exists for.  Explicit points fell through _area_route to the box path, and
#          the caller was answered "an area needs south, west, north and east in degrees". Part E asks area_plan
#          for a line and requires an estimate, and asks area_add for a malformed one and requires an answer
#          rather than a task that dies with nothing sent. Measured: 32 checks red, and then the run gives up --
#          reverting this one is reverting the foundation the rest of the feature stands on, so most of the suite
#          has nothing left to test. The other five each go red in place and the run still finishes:
#            U 5 red, P 4 red, L 2 red (+1 more if phase_steps ignores the subset instead), F 2 red, N 7 red.
#
# Not covered here, deliberately:
#   * the mod half of 1.3.1 (earthAdapter's wrapper, the auto recce's download offer): not written yet. The Lua
#     add-on in this file is the sequence it will run, and these checks are the contract.
#   * whether the data a finished area leaves on disk is enough for a road graph. That is the auto recce's own
#     re-check, and the reason part D insists the add-on re-checks rather than trusts.
#   * the imagery steps' byte estimate: this fixture has no imagery provider (StubServer.imagery is None), so
#     the imagery items are planned and counted but contribute no bytes. The layers comparison is therefore
#     CONSERVATIVE -- on a real server, dropping imagery widens the gap the part-L figures show.
if __name__ == '__main__':
    sys.exit(main())
