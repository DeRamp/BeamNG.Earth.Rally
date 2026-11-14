#!/usr/bin/env python3
"""mod -> server -> mod for BeamNG.Earth's api.roadGraph, with no game: the auto recce's one dependency on
BeamNG.Earth, driven end to end against BeamNG.Earth's own server code.

Why this exists. tests/test_autorecce.lua drives the auto recce against a stand-in BeamNG.Earth, and BeamNG.Earth's
own server tests drive api.roadGraph against a stand-in add-on. Both suites were green while the call was broken
four times over, because every one of those bugs lived in the gap between the two stand-ins (2026-11-13):

  1. the server answered with the name of the file it had written, and the add-on read result.nodes: every window
     looked like "no answer", and nothing anywhere logged a fault;
  2. the cached-only read used a reader meant for the places query, which does not give roads what they need to be
     drivable: a window whose cells were all on disk built 0 nodes and still answered "complete";
  3. the request's lat / lon was converted to the anchor's frame by the handler and the x, y then handed to a worker
     thread, so a re-centred anchor put the window about 19 km from the stage -- complete, with no roads in it;
  4. (ours) a stage with no road in it was still written as the organisers' line end to end, which left the stage
     amber as though the auto recce had achieved something.

So this test stands in for neither side:

  * the add-on is ours, unmodified: earthRally/autoRecce and earthRally/earthAdapter under LuaJIT;
  * BeamNG.Earth's mod half is its own api.lua, unmodified, under the same LuaJIT: M.roadGraph builds the request
    and the game's JSON encoder writes it, M._onRoadGraph is handed the answer and reads the graph file back
    through the game's readFile;
  * the wire is BeamNG.Earth's protocol.py, encoded and decoded both ways, so neither side is handed a Python
    object the other never sent;
  * the server half is BeamNG.Earth's Connection.road_graph and Server.road_graph_data over a real
    mapdata.MapData. Its map cells are written into a temporary cache as the .npz files the app caches, so the
    roads go through the production read path (mapcells.load_cells -> MapData.cells -> decode, tag joins, lane
    sections, smoothing) and a graph with real roads in it comes out of navgraph.build. 0 nodes is a failure here.
    Only the ground heights and the grading are stood in for (flat), as BeamNG.Earth's own tests do.

Reintroducing each of the four, one at a time, and running this (2026-11-13):
  bug 1  18 checks red, among them the whole auto recce ending "1397 m of the stage has no map data on this
         computer yet: nothing written" -- the in-game symptom, word for word;
  bug 2   2 checks red, both of them mechanism (which reader, at which kind). It is NOT caught in behaviour: see
         the note at the foot of this file, which is worth reading before trusting that bug's diagnosis;
  bug 3   2 checks red, "6016 m off" for an anchor moved 6000 m -- and the window still complete, with 96 roads
         in it, which is how it went unnoticed;
  bug 4   3 checks red (ours, in autoRecce.matchAndWrite).

It also found a fifth, which is open: a cached-only window does download map cells, through the roads layer's own
neighbour hooks. The run prints the whole finding; those two checks are reported rather than failed (STRICT below),
so this stays a gate on the four while that one is open upstream.

Where BeamNG.Earth comes from: $BNGE_REPO, else a `beamng.earth` checkout beside this repository. Nothing in it is
written to -- the cells, the session folder and the cache are all in temporary directories, and its fetcher is
replaced by one that refuses, so no run of this touches the network or the player's own map cache. Without the
checkout (or without its Python dependencies, or without lupa) this test prints what is missing and passes, as
tests/test_mapkey.py does when there are no events on the computer.

Note on the interpreter: the server half needs the app's Python dependencies (numpy and the rest). When the
interpreter running this suite has no numpy, this re-runs itself under <BeamNG.Earth>/.venv, which has them.
"""
import asyncio
import importlib
import json
import logging
import math
import os
import site
import subprocess
import sys
import tempfile
import threading
import types
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RALLY_LUA = ROOT / 'mod' / 'earth_rally' / 'lua' / 'ge' / 'extensions'

# --- the fixture ----------------------------------------------------------------------------------
# Fells Point, Baltimore: BeamNG.Earth's own road tests use it, it is on land and in the US, so the graph's road
# rules are the ones the matcher expects. Everything below is in metres east / north of it.
LAT, LON = 39.2834, -76.5934
AID = 3                             # the committed anchor's id
VFS_DIR = '/temp/beamngEarth/test'
RADIUS = 400.0                      # part A's window: small, so a build is a second
ASKED = (1000.0, 0.0)               # the point asked about: not the anchor's origin, so a window built at the
#                                     origin instead of at the point asked for is a failure too
MOVE_N = 6000.0                     # how far the anchor is re-centred mid-request (bug 3)
DECOY = (1000.0, MOVE_N)            # where a window converted in the frame that has gone lands: cells and roads on
#                                     disk there too, so the bug answers "complete" with roads in it
STAGE_FROM, STAGE_TO = 500.0, 1900.0        # part B's stage: 1.4 km east, so it takes more than one window
STAGE_STEP = 200.0
FETCHING_KINDS = ('demand', 'urgent')       # mapdata downloads at these and raises at every other

# A check that fails because of a fault found in BeamNG.Earth rather than in this test (Checks.bug): printed in
# full at the end of every run, and counted as a failure only with BNGE_RG_E2E_STRICT=1. The default keeps this
# suite a gate on OUR four bugs while the fifth one is open upstream -- it is reported every run, never hidden.
STRICT = os.environ.get('BNGE_RG_E2E_STRICT') == '1'


# --------------------------------------------------------------------------------------------------
# finding BeamNG.Earth, and an interpreter that can run its server code
# --------------------------------------------------------------------------------------------------
def is_app(c):
    return (c / 'server' / 'earthd.py').is_file() and (c / 'mod' / 'beamng_earth').is_dir()


def app_repo():
    """The BeamNG.Earth checkout to drive, or None.

    $BNGE_REPO decides when it is set, even if it names nothing: a run that was pointed somewhere should say so
    rather than quietly test a different checkout. Otherwise a sibling of this repository."""
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
    the server's dependencies but not lupa -- tests/run_tests.py's own interpreter has it the other way round.)"""
    for extra in (None, site.getusersitepackages()):
        if extra is not None and extra not in sys.path:
            sys.path.append(extra)
        try:
            return importlib.import_module('lupa.luajit21')
        except ImportError:
            continue
    return None


# --------------------------------------------------------------------------------------------------
# the server's half: BeamNG.Earth's own code over cells written as the app caches them
# --------------------------------------------------------------------------------------------------
READS = []          # (cell, layers, kind) of every map-cell read made anywhere while a request is served
UNKEPT = []         # (cell, layer) of every MapData.layer_unkept read
FETCHED = []        # (url, kind) of every download attempted


def instrument(mapdata, netfetch):
    """Every cell read and every download recorded -- patched on the class, not wrapped round the one object the
    request is given.

    That distinction is the point. A roads layer carries hooks of its own (gradesep.hook and
    gradesep.neighbours_hook, which navgraph runs while it builds) and they read through the MapData the layer was
    decoded with, not through anything the caller passed in. A wrapper round the object therefore sees the
    window's own cells and none of the reads those hooks make -- which is how BeamNG.Earth's own unit test came to
    assert "nothing fetched" for a cached-only window truthfully, against a stand-in that has no such hooks."""
    if getattr(mapdata.MapData, '_e2e_instrumented', False):
        return
    cell, cells, unkept = mapdata.MapData.cell, mapdata.MapData.cells, mapdata.MapData.layer_unkept

    def w_cell(self, key, layers=mapdata.LAYERS, kind='demand'):
        READS.append((str(key), tuple(layers), kind))
        return cell(self, key, layers, kind)

    def w_cells(self, keys, layers=mapdata.LAYERS, kind='demand'):
        keys = list(keys)
        for k in keys:
            READS.append((str(k), tuple(layers), kind))
        return cells(self, keys, layers, kind)

    def w_unkept(self, key, layer, kind='background'):
        UNKEPT.append((str(key), layer))
        return unkept(self, key, layer, kind)

    mapdata.MapData.cell, mapdata.MapData.cells, mapdata.MapData.layer_unkept = w_cell, w_cells, w_unkept
    mapdata.MapData._e2e_instrumented = True

    class NoFetch(netfetch.Fetcher):
        """A fetcher that refuses, and says what was reached for. The cells this test builds from are on disk and a
        road-graph window promises to download nothing, so a download here is either a fault in the fixture or a
        fault in that promise -- and the test can tell which, because it knows what it wrote."""

        def __init__(self):
            super().__init__(offline=True)

        def get(self, url, **kw):
            FETCHED.append((str(url), kw.get('kind')))
            raise RuntimeError('offline: this test downloads nothing')

        def session(self, url, kind='demand', lane=None):
            FETCHED.append((str(url), kind))
            raise RuntimeError('offline: this test downloads nothing')

    mapdata._E2E_NO_FETCH = NoFetch


def fetching_reads():
    return [r for r in READS if r[2] in FETCHING_KINDS]


def layers_read():
    return {lr for _, ls, _ in READS for lr in ls}


class NoChain:
    """Server.chain_view's bridge and tunnel profiles: none, as BeamNG.Earth's own road-graph tests have it."""

    def parts(self, feats, box):
        return []

    def open_parts(self, feats, box):
        return []

    def depth_of(self, fid):
        return None


class App:
    """BeamNG.Earth's server modules, and one Server stand-in holding a real MapData over a temporary cache."""

    def __init__(self, app, tmp):
        sys.path.insert(0, str(app / 'server'))
        self.app = app
        self.np = importlib.import_module('numpy')
        self.geodesy = importlib.import_module('geodesy')
        self.mapcells = importlib.import_module('mapcells')
        self.mapgeom = importlib.import_module('mapgeom')
        self.mapdata = importlib.import_module('mapdata')
        self.navgraph = importlib.import_module('navgraph')
        self.protocol = importlib.import_module('protocol')
        self.earthd = importlib.import_module('earthd')
        self.netfetch = importlib.import_module('netfetch')
        instrument(self.mapdata, self.netfetch)
        # the road rules' country without the airports database or the border downloads (as the app's own
        # road-graph tests do: the fixture is in the United States either way)
        self.navgraph.country_at = lambda *a, **k: 'US'
        self.base = self.geodesy.EnuFrame(LAT, LON, 0.0)
        self.cache = tmp / 'cache'
        self.out = tmp / 'session'
        self.cache.mkdir(parents=True, exist_ok=True)
        self.out.mkdir(parents=True, exist_ok=True)
        self.fetcher = self.mapdata._E2E_NO_FETCH()
        self.md = self.mapdata.MapData(str(self.cache), fetcher=self.fetcher)
        self.server = self._server()

    # --- the fixture's geometry ---------------------------------------------------------------
    def geo(self, spot):
        la, lo, _ = self.base.enu_to_geodetic(spot[0], spot[1], 0.0)
        return float(la), float(lo)

    def frame_at(self, east=0.0, north=0.0):
        la, lo = self.geo((east, north))
        return self.geodesy.EnuFrame(la, lo, 0.0)

    def _empty_rule(self):
        np, mg = self.np, self.mapgeom
        return mg.RuleTable(np.zeros(0, np.int32), np.zeros(0, '<U8'),
                            np.zeros(0, np.float32), np.zeros(0, np.float32))

    def road_features(self, lines, ids, cls='residential'):
        """A roads layer of straight lines, each [(east m, north m), ...] from (LAT, LON), placed through the
        anchor frame so a road is where the assertions say it is to the metre."""
        np, mg = self.np, self.mapgeom
        coords, part_off, ring_off, coord_off = [], [0], [0], [0]
        for ln in lines:
            for e, n in ln:
                la, lo = self.geo((e, n))
                coords.append((lo, la))
            coord_off.append(len(coords))
            ring_off.append(len(coord_off) - 1)
            part_off.append(len(ring_off) - 1)
        n = len(lines)
        return mg.Features(
            layer='roads', ids=np.array(list(ids)), kind=np.full(n, mg.LINE, np.uint8),
            part_off=np.array(part_off, np.int64), ring_off=np.array(ring_off, np.int64),
            coord_off=np.array(coord_off, np.int64),
            lonlat=np.array(coords, np.float64).reshape(len(coords), 2),
            attrs={'class': np.array([cls] * n), 'subtype': np.array(['road'] * n)},
            rules={k: self._empty_rule() for k in ('surface', 'width', 'level', 'flags', 'subclass',
                                                   'connectors', 'oneway', 'max_speed_kmh')})

    def window_keys(self, spot, radius):
        """The map cells Server.road_graph_data reads for a window of this radius around a spot."""
        np = self.np
        w = radius + 200.0
        la, lo, _ = self.base.enu_to_geodetic(np.array([spot[0] - w, spot[0] + w]),
                                              np.array([spot[1] - w, spot[1] + w]), 0.0)
        return self.mapcells.cells_for_bbox(float(la.min()), float(lo.min()),
                                            float(la.max()), float(lo.max()))

    def write_cell(self, key, feats):
        """One cell's roads layer on disk, as the app caches it: the layer's own arrays in an .npz, which
        MapData.has() sees and the production read path decodes. No reader is stood in for."""
        arrays = dict(feats.to_arrays(''))
        arrays['provenance'] = json.dumps({'id': 'test', 'datasets': [
            {'dataset': 'test', 'license': 'test', 'features': int(len(feats))}]})
        path = self.md.path(key, 'roads')
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.np.savez(path, **arrays)
        return path

    def lay_out(self, spots, radius, lines_for):
        """Every cell of each spot's window written, holding that spot's roads. Returns the keys written."""
        done = set()
        for i, spot in enumerate(spots):
            lines = lines_for(spot)
            feats = self.road_features(lines, ['s%d_%03d' % (i, j) for j in range(len(lines))])
            for k in self.window_keys(spot, radius):
                if str(k) in done:
                    continue
                self.write_cell(k, feats)
                done.add(str(k))
        return done

    # --- the server ---------------------------------------------------------------------------
    def _anchor(self, frame, lat=LAT, lon=LON):
        return types.SimpleNamespace(id=AID, lat=lat, lon=lon, frame=frame, zooms=(14,),
                                     bridges=None, tunnels=None)

    def _server(self, traffic=True):
        np = self.np
        s = types.SimpleNamespace(
            anchors={AID: self._anchor(self.base)}, mapdata=self.md, surface=None, road_widths=None,
            dej_on='off', airports_db=None, grader_lock=threading.Lock(), out_dir=str(self.out),
            vfs_dir=VFS_DIR, traffic=traffic, road_pool=None,
            dem=types.SimpleNamespace(sample=lambda la, lo, zoom: np.zeros(np.shape(la))))
        # the real build, bound to this stand-in: Connection.road_graph calls it through the server
        s.road_graph_data = lambda *a, **kw: self.earthd.Server.road_graph_data(s, *a, **kw)
        s.grader_for = lambda a: None
        s.ground = lambda fr, la, lo, z: z
        s.chain_view = lambda *a, **k: NoChain()
        s.country = lambda a: 'US'
        s.left_hand = lambda a: False
        s.mph = lambda a: True
        return s

    def move_anchor(self, east, north):
        """The anchor re-centred: the same id, a new frame. (A worker thread does this in the middle of a request
        in the bug-3 check; the server's own rebase does the same thing.)"""
        la, lo = self.geo((east, north))
        self.server.anchors[AID] = self._anchor(self.frame_at(east, north), la, lo)

    def handle(self, req, move=None):
        """Connection.road_graph over the Server stand-in: the road_graph_result messages it sent, each decoded off
        the wire as the mod's net would decode it.

        `move` = (east, north): the anchor is re-centred on the worker thread just before the build runs, which is
        the gap bug 3 lived in -- the handler had worked out x, y in the frame the request arrived in and the build
        read them in the frame that replaced it."""
        earthd, protocol = self.earthd, self.protocol
        sent, moved = [], []
        app = self

        class MovingPool:
            """api_pool, with the anchor re-centred once on the worker thread before the first job."""

            def __init__(self):
                self.inner = ThreadPoolExecutor(1)

            def submit(self, fn, *a, **kw):
                def run():
                    if move is not None and not moved:
                        moved.append(True)
                        app.move_anchor(*move)
                    return fn(*a, **kw)
                return self.inner.submit(run)

            def shutdown(self, *a, **kw):
                self.inner.shutdown(*a, **kw)

        async def go():
            pool = MovingPool()
            self.server.api_pool = pool
            conn = types.SimpleNamespace(s=self.server, send=sent.append, active=AID)
            conn._sweep_road_graphs = lambda *a: earthd.Connection._sweep_road_graphs(conn, *a)
            try:
                await earthd.Connection.road_graph(conn, req)
            finally:
                pool.shutdown()
        asyncio.run(go())
        if move is not None and not moved:
            raise AssertionError('the anchor was never re-centred: the build never reached the pool')
        out = []
        for m in sent:
            out += protocol.Decoder().feed(protocol.encode(m))
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

    def road_graph_data(self, spot, radius, cached_only=True):
        return self.earthd.Server.road_graph_data(self.server, AID, None, None, radius, cached_only,
                                                  self.geo(spot))


# --------------------------------------------------------------------------------------------------
# the mod's half: BeamNG.Earth's api.lua and our own autoRecce, both unmodified, under LuaJIT
# --------------------------------------------------------------------------------------------------
_BOOT = r"""
package.path = BNGE_LUA .. '/?.lua;' .. RALLY_LUA .. '/?.lua;' .. package.path
dofile(BNGE_TESTS .. '/stubs.lua')            -- BeamNG.Earth's own offline game stubs (vec3, scene objects, files)
local J = dofile(BNGE_TESTS .. '/minijson.lua')   -- ... and its stand-in for the game's JSON
function jsonEncode(v) return J.encode(v) end
function jsonDecode(s) local ok, v = pcall(J.decode, s) if ok then return v end return nil end

LOGS = {}
function log(level, _, msg) LOGS[#LOGS + 1] = tostring(level) .. ' ' .. tostring(msg) end

-- the game's readFile, over the virtual file system: BeamNG.Earth answers with a path in its session folder and
-- api.lua reads the graph back through this
function readFile(path)
  local pre = '^' .. VFS_DIR:gsub('(%W)', '%%%1') .. '/'
  local rel = tostring(path):gsub(pre, '')
  if rel == tostring(path) then return nil end      -- (not our session folder: the game would not find it either)
  local fh = io.open(OUT_DIR .. '/' .. rel, 'rb')
  if not fh then return nil end
  local txt = fh:read('*a')
  fh:close()
  return txt
end

-- the game's user folder, for the file the auto recce writes
FILES = {}
function jsonWriteFile(path, data) FILES[path] = data return true end
function jsonReadFile(path) return FILES[path] end
FS = { fileExists = function(_, path) return FILES[path] ~= nil end, findFiles = function() return {} end }

-- BeamNG.Earth's net: what api.lua puts on the wire comes to the test as the bytes the game would have sent
package.loaded['beamngEarth/net'] = {
  isConnected = function() return true end,
  send = function(m) PY_SEND(jsonEncode(m)) end }

-- BeamNG.Earth's core, as api.lua reads it: our level, a committed anchor, a player standing on it
local geodesy = require('beamngEarth/geodesy')
ANCHOR = geodesy.newAnchor(ANCHOR_LAT, ANCHOR_LON)
local st = { inOurLevel = true, anchor = ANCHOR, player = nil, pending = nil }
beamngEarth_core = {
  _state = function() return st end,
  groundReady = function() return true end,
  serverHello = function() return { appVersion = 'test' } end,
}
function SET_ANCHOR(lat, lon)                 -- (the world's origin moved, as the mod hears it)
  ANCHOR = geodesy.newAnchor(lat, lon)
  st.anchor = ANCHOR
end
-- the mod's own conversion, through the API an add-on uses (api.toGeo): [lat, lon, alt]
function MOD_TO_GEO(x, y, z) return J.encode({ API.toGeo(x, y, z or 0) }) end
function PLAYER_AT(lat, lon)
  local x, y, z = ANCHOR:geodeticToWorld(lat, lon, 0)
  st.player = { x = x, y = y, z = z, vx = 0, vy = 0, vz = 0, lat = lat, lon = lon, speed = 0 }
end

API = require('beamngEarth/api')
beamngEarth_api = API

-- ours, over it, unmodified
local auto = require('earthRally/autoRecce')
local events = require('earthRally/events')
local adapter = require('earthRally/earthAdapter')
AUTO, EVENTS, ADAPTER = auto, events, adapter
auto.clock = function() return 0 end          -- (`seconds` deterministic, as tests/test_autorecce.lua has it)

------------------------------------------------------------------------------------ part A: api.lua alone
local lastDirect = nil

function ASK(lat, lon, radius)
  lastDirect = nil
  return API.roadGraph(lat, lon, { radius = radius }, function(res) lastDirect = res end)
end

function DELIVER(text)
  lastDirect = nil
  API._onRoadGraph(jsonDecode(text))
  if lastDirect == nil then return nil end
  local kinds = {}
  for _, k in ipairs({ 'nodes', 'edges', 'signals', 'rules', 'lines', 'path', 'error', 'complete', 'mph' }) do
    kinds[k] = type(lastDirect[k])
  end
  local n = 0
  if type(lastDirect.nodes) == 'table' then for _ in pairs(lastDirect.nodes) do n = n + 1 end end
  return J.encode({ res = lastDirect, types = kinds, nodeCount = n })
end

------------------------------------------------------------------------------------ part B: the auto recce
local recce = nil

function START_RECCE(eventJson, stageJson)
  recce = nil
  FILES = {}
  events.forget()
  auto.cancel()
  local event, stage = jsonDecode(eventJson), jsonDecode(stageJson)
  STAGE_ID = stage.id
  EVENT_ID = event.id
  local ok, why = auto.start(event, stage, function(o, m, w, how)
    recce = { ok = o, matched = m, why = w, how = how }
  end)
  return J.encode({ started = ok == true, why = why })
end

function RECCE_RESULT()
  if recce == nil then return nil end
  local out = { ok = recce.ok == true, why = recce.why, how = recce.how }
  local m = recce.matched
  if type(m) == 'table' then
    out.matched = { lengthM = m.lengthM, mapLineM = m.mapLineM, gapM = m.gapM,
                    gaps = #(m.gaps or {}), junctions = #(m.junctions or {}),
                    points = #(m.points or m.line or {}) }
  end
  out.file = FILES[events.MATCHED_DIR .. tostring(EVENT_ID) .. '__' .. tostring(STAGE_ID) .. '.json'] ~= nil
  return J.encode(out)
end

-- The matched line's points as lat / lon, from the file the auto recce wrote (whatever key it uses for them).
function MATCHED_POINTS()
  local f = FILES[events.MATCHED_DIR .. tostring(EVENT_ID) .. '__' .. tostring(STAGE_ID) .. '.json']
  if type(f) ~= 'table' then return nil end
  local pts = f.points or f.line or f.pts
  if type(pts) ~= 'table' then return J.encode({ keys = (function()
    local ks = {} for k in pairs(f) do ks[#ks + 1] = tostring(k) end table.sort(ks) return ks end)() })
  end
  return J.encode({ pts = pts })
end

-- the answer through api._onRoadGraph, which hands it on to our own callback (nothing is returned: what came of
-- it is read from RECCE_RESULT once the pump has drained)
function DELIVER_RECCE(text) API._onRoadGraph(jsonDecode(text)) end

function LOG_TEXT() return table.concat(LOGS, '\n') end
"""


class Mod:
    """One LuaJIT state with BeamNG.Earth's api.lua and our auto recce in it."""

    def __init__(self, lupa, app):
        self.sent = []
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.PY_SEND = lambda text: self.sent.append(str(text))
        g.BNGE_LUA = (app.app / 'mod' / 'beamng_earth' / 'lua' / 'ge' / 'extensions').as_posix()
        g.BNGE_TESTS = (app.app / 'mod' / 'tests').as_posix()
        g.RALLY_LUA = RALLY_LUA.as_posix()
        g.OUT_DIR = Path(app.out).as_posix()
        g.VFS_DIR = VFS_DIR
        g.ANCHOR_LAT, g.ANCHOR_LON = LAT, LON
        self.lua.execute(_BOOT)
        self.g = self.lua.globals()

    def take(self):
        """The oldest message the mod has sent, and nothing left behind."""
        if not self.sent:
            raise AssertionError('the mod sent nothing')
        return self.sent.pop(0)


# --------------------------------------------------------------------------------------------------
def metres(lat_a, lon_a, lat_b, lon_b):
    m_lat = 111320.0
    m_lon = 111320.0 * math.cos(math.radians(lat_a))
    return math.hypot((lat_b - lat_a) * m_lat, (lon_b - lon_a) * m_lon)


def cross_roads(spot, reach=350.0):
    """A small grid around a spot: two long roads crossing and four side streets. Enough that a window centred
    there has a connected graph and one centred elsewhere has none of it."""
    e, n = spot
    lines = [[(e - reach, n), (e + reach, n)], [(e, n - reach), (e, n + reach)]]
    for d in (-200.0, 200.0):
        lines.append([(e - reach, n + d), (e + reach, n + d)])
        lines.append([(e + d, n - reach), (e + d, n + reach)])
    return lines


def stage_line(app):
    """The organisers' line: straight east, as an event file's stage.line is ({lat, lon} per point)."""
    out = []
    d = STAGE_FROM
    while d <= STAGE_TO + 1e-9:
        la, lo = app.geo((d, 0.0))
        out.append([la, lo])
        d += STAGE_STEP
    return out


def stage_roads(spot):
    """The roads under part B's stage: one road along the whole of it, a parallel road 250 m north the matcher must
    not prefer, and a side road crossing it (a junction landmark). `spot` is ignored: these are the same roads
    whatever window is being written, which is what makes the windows stitch by node name."""
    del spot
    a, b = STAGE_FROM - 400.0, STAGE_TO + 400.0
    main, north = [], []
    d = a
    while d <= b + 1e-9:
        main.append((d, 0.0))
        north.append((d, 250.0))
        d += 50.0
    side = [((STAGE_FROM + STAGE_TO) / 2, -200.0), ((STAGE_FROM + STAGE_TO) / 2, 200.0)]
    return [main, north, list(side)]


# --------------------------------------------------------------------------------------------------
class Checks:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.bugs = []          # checks that fail because of a fault found in BeamNG.Earth, not in this test

    def ok(self, cond, what):
        if cond:
            self.passed += 1
            print('ok    ' + what)
        else:
            self.failed += 1
            print('FAIL  ' + what)
        return bool(cond)

    def bug(self, cond, what):
        """A check whose failure is a fault in BeamNG.Earth, not in this test. Listed again in full at the end so a
        red line here cannot be mistaken for a flaky one, and counted as a failure only under BNGE_RG_E2E_STRICT."""
        if cond:
            self.passed += 1
            print('ok    ' + what)
            return True
        self.bugs.append(what)
        if STRICT:
            self.failed += 1
        print(('FAIL  ' if STRICT else 'BUG   ') + what)
        return False

    def near(self, got, want, tol, what):
        return self.ok(abs(got - want) <= tol, '%s (got %.3f, want %.3f +- %g)' % (what, got, want, tol))


def nodes_geodetic(frame, nodes):
    """(lat, lon) of each graph node, read as an add-on reads them: x, y in the frame the anchor has now."""
    pts = [(float(v[0]), float(v[1])) for v in nodes.values()]
    return [tuple(float(c) for c in frame.enu_to_geodetic(x, y, 0.0)[:2]) for x, y in pts]


def centre_of(pts):
    if not pts:
        return 0.0, 0.0
    las = [p[0] for p in pts]
    los = [p[1] for p in pts]
    return (min(las) + max(las)) / 2, (min(los) + max(los)) / 2


# --- part A: the wire contract, a real build, and where the window lands ---------------------------
def part_a(c, app, lupa):
    print('\n-- api.roadGraph itself (BeamNG.Earth api.lua <-> its server) --')
    app.lay_out((ASKED, DECOY), RADIUS, cross_roads)
    mod = Mod(lupa, app)
    lat, lon = app.geo(ASKED)

    # the frames on the two sides agree: the mod's anchor and the server's are the same world, or every node the
    # add-on converts lands somewhere else
    ml, mo = json.loads(str(mod.g.MOD_TO_GEO(ASKED[0], ASKED[1], 0.0)))[:2]
    apart = metres(lat, lon, float(ml), float(mo))
    c.ok(apart < 1.0, "the mod's frame (api.toGeo) and the server's agree (%.2f m apart 1 km out)" % apart)

    # 1: the request as api.lua really sends it
    rid = mod.g.ASK(lat, lon, RADIUS)
    c.ok(rid is not None, 'api.roadGraph took the call')
    req = app.wire_in(mod.take())
    c.ok(req.get('type') == 'road_graph', 'the request is a road_graph message')
    c.ok(req.get('cachedOnly') is True, 'asked cached-only: there is no fetching form of the request')
    c.near(float(req['radius']), RADIUS, 1e-6, 'the radius it was given')
    c.near(float(req['lat']), lat, 1e-9, 'the latitude it was given')
    c.near(float(req['lon']), lon, 1e-9, 'the longitude it was given')
    c.ok(isinstance(req['id'], int) and not isinstance(req['id'], bool),
         'the request id survived the game\'s JSON as a whole number')

    # 2: the answer, and what the add-on is actually given (bug 1)
    del READS[:], UNKEPT[:], FETCHED[:]         # (the reads from here on are this request's)
    answers = app.handle(req)
    c.ok(len(answers) == 1, 'one answer a request')
    ans = answers[0]
    c.ok(ans.get('type') == 'road_graph_result', 'the answer is a road_graph_result')
    c.ok(ans.get('complete') is True, 'every cell of the window was on disk, so the window is complete')
    c.ok(str(ans.get('path', '')).find('roadgraph_%d_' % AID) >= 0,
         'written under its own name, never the player\'s navgraph (%r)' % (ans.get('path'),))
    got = mod.g.DELIVER(app.wire_out(ans))
    c.ok(got is not None, "the add-on's callback was called")
    got = json.loads(str(got))
    res, kinds = got['res'], got['types']
    c.ok(res.get('error') is None, 'no error in the answer')
    c.ok(kinds['nodes'] == 'table', 'BUG 1: the add-on was handed a nodes table (got %r)' % (kinds['nodes'],))
    c.ok(kinds['edges'] == 'table', 'BUG 1: ... and an edges table (got %r)' % (kinds['edges'],))
    c.ok(got['nodeCount'] > 0, 'BUG 2: the cells on disk produced a graph with roads in it (%d nodes)'
         % got['nodeCount'])
    c.ok(len(res.get('edges') or []) > 0, '... and edges (%d)' % len(res.get('edges') or []))
    node = next(iter(res['nodes'].values())) if res.get('nodes') else None
    c.ok(node is not None and len(node) == 4, 'a node is [x, y, z, radius] (%r)' % (node,))
    c.ok(kinds['rules'] == 'table', 'the road rules came over with it')
    c.ok(res.get('anchorId') == AID and res.get('serial') == ans.get('serial'),
         'the answer names the anchor and the serial it was built for')
    c.ok(kinds['path'] == 'string', 'and the file is still named, for an add-on that would rather read it itself')

    # the graph the add-on read is the graph the server built
    built, _ = app.road_graph_data(ASKED, RADIUS)
    built = app.navgraph.short_ids(built) if app.navgraph.SHORT_IDS else built
    mine = res.get('nodes') or {}
    c.ok(sorted(mine) == sorted(built['nodes']),
         "the add-on's node names are the server's own (%d / %d)" % (len(mine), len(built['nodes'])))

    # 3: how the window's cells were read (bug 2), and that nothing was fetched for them
    c.ok('roads' in layers_read(), 'the roads layer of the window was read at all')
    c.ok(UNKEPT == [],
         "BUG 2: the window was read through the call the player's own graph uses, not through the "
         "places query's reader (MapData.layer_unkept: %d read(s))" % len(UNKEPT))
    c.ok(any(lr == 'roads' and kind == 'background' for _, ls, kind in READS for lr in ls),
         'BUG 2: ... and at a kind that cannot download')
    # and the same thing said in behaviour rather than in mechanism: over cells that are all on disk, the
    # cached-only read and the read the player's own graph does must produce the same graph. (This is the check
    # that would catch a divergence between the two readers if one ever appeared. Reintroducing bug 2 does not
    # make it fail: see the note at the foot of this file.)
    cached, cmissing = app.road_graph_data(ASKED, RADIUS, cached_only=True)
    player, _ = app.road_graph_data(ASKED, RADIUS, cached_only=False)
    c.ok(cmissing == 0 and len(cached['nodes']) > 0
         and sorted(cached['nodes']) == sorted(player['nodes'])
         and len(cached['edges']) == len(player['edges']),
         "BUG 2: the cached-only graph is the graph the player's own path builds from the same cells "
         '(%d / %d nodes, %d / %d edges)' % (len(cached['nodes']), len(player['nodes']),
                                             len(cached['edges']), len(player['edges'])))
    bad = fetching_reads()
    c.bug(not bad,
          'nothing of the window was read at a kind that downloads '
          '(%d cell-read(s) at demand/urgent: %s)'
          % (len(bad), sorted({k for k, _, _ in bad})[:6]))
    c.bug(not FETCHED, 'nothing was downloaded for a cached-only window (%d attempt(s): %s)'
          % (len(FETCHED), [u for u, _ in FETCHED[:3]]))

    # 4: where the window landed (bug 3), the anchor standing still
    frame = app.server.anchors[AID].frame
    pts = nodes_geodetic(frame, res.get('nodes') or {})
    far = max([metres(lat, lon, a, o) for a, o in pts] or [1e9])
    c.ok(far < RADIUS * math.sqrt(2.0) + 100.0,
         'every node is inside the window asked for (furthest %.0f m, window %.0f m)' % (far, RADIUS))
    mid = centre_of(pts) if pts else (0.0, 0.0)
    off = metres(lat, lon, *mid) if pts else 1e9
    c.ok(off < 100.0, 'the window is centred where the add-on asked (%.0f m off)' % off)

    # the decoy really is a complete window with roads in it, or the check below would pass for the wrong reason
    keep = app.server.anchors[AID]
    app.server.anchors[AID] = app._anchor(app.frame_at(0.0, MOVE_N), *app.geo((0.0, MOVE_N)))
    dgraph, dmissing = app.road_graph_data(DECOY, RADIUS)
    app.server.anchors[AID] = keep
    c.ok(dmissing == 0 and len(dgraph['nodes']) > 0,
         'the ground the bug lands on is a complete window with roads in it (%d nodes, %d cells unread)'
         % (len(dgraph['nodes']), dmissing))

    # 5: the same, with the anchor re-centred between the request arriving and the build running -- bug 3 itself
    rid = mod.g.ASK(lat, lon, RADIUS)
    c.ok(rid is not None, 'a second request accepted')
    req = app.wire_in(mod.take())
    answers = app.handle(req, move=(0.0, MOVE_N))
    ans = answers[0]
    got = json.loads(str(mod.g.DELIVER(app.wire_out(ans))))
    res = got['res']
    c.ok(res.get('error') is None, 'the re-centred anchor did not break the request (%r)' % (res.get('error'),))
    c.ok(ans.get('complete') is True, 'the window it built was complete')
    c.ok(got['nodeCount'] > 0, '... and had roads in it (%d nodes)' % got['nodeCount'])
    frame = app.server.anchors[AID].frame       # the frame the build used, which is the one the nodes are in
    pts = nodes_geodetic(frame, res.get('nodes') or {})
    mid = centre_of(pts) if pts else (0.0, 0.0)
    off = metres(lat, lon, *mid) if pts else 1e9
    c.ok(off < 100.0,
         'BUG 3: the window is still centred where the add-on asked after the anchor moved %.0f m (%.0f m off)'
         % (MOVE_N, off))
    far = max([metres(lat, lon, a, o) for a, o in pts] or [1e9])
    c.ok(far < RADIUS * math.sqrt(2.0) + 100.0,
         'BUG 3: and no node of it is outside that window (furthest %.0f m)' % far)

    # 6: a window over roadless ground is visible as such (the facts our own refusal keys on)
    app2 = App(app.app, Path(tempfile.mkdtemp(prefix='rg_e2e_bare_')))
    app2.lay_out((ASKED,), RADIUS, lambda spot: [])
    mod2 = Mod(lupa, app2)
    mod2.g.ASK(lat, lon, RADIUS)
    bare = app2.handle(app2.wire_in(mod2.take()))[0]
    got = json.loads(str(mod2.g.DELIVER(app2.wire_out(bare))))
    c.ok(bare.get('complete') is True and got['res'].get('error') is None,
         'a window with no roads is served, complete and without an error')
    c.ok(got['types']['nodes'] == 'table' and got['nodeCount'] == 0,
         'and reaches the add-on as an empty graph, not as a missing field')

    # 7: the refusals reach the add-on in words
    app.server.traffic = False
    mod.g.ASK(lat, lon, RADIUS)
    refused = app.handle(app.wire_in(mod.take()))[0]
    got = json.loads(str(mod.g.DELIVER(app.wire_out(refused))))
    app.server.traffic = True
    c.ok('--traffic off' in str(refused.get('error')), 'a server without roads says so (%r)' % refused.get('error'))
    c.ok(got['types']['error'] == 'string' and got['types']['nodes'] == 'nil',
         'and the add-on gets the reason and no graph to mistake for one')
    return mod


# --- part B: our own auto recce over the real call -------------------------------------------------
def part_b(c, app_dir, lupa, roads=True, label='with roads'):
    print('\n-- the auto recce (earthRally/autoRecce <-> api.lua <-> its server), %s --' % label)
    app = App(app_dir, Path(tempfile.mkdtemp(prefix='rg_e2e_recce_')))
    line = stage_line(app)
    # every window of the plan written, so the stage is covered and the coverage record is satisfied
    plan_spots = [(STAGE_FROM + d, 0.0) for d in (0.0, 700.0, 1400.0)]
    app.lay_out(plan_spots, 1000.0, stage_roads if roads else (lambda spot: []))
    mod = Mod(lupa, app)
    mid = line[len(line) // 2]
    mod.g.PLAYER_AT(mid[0], mid[1])

    event = {'id': 'e2e-event', 'name': 'End to End Rally'}
    stage = {'id': 'e2e-stage', 'name': 'End to End Stage', 'line': line}
    started = json.loads(str(mod.g.START_RECCE(json.dumps(event), json.dumps(stage))))
    c.ok(started.get('started') is True, 'the auto recce started (%r)' % (started.get('why'),))

    windows = 0
    while mod.sent:
        windows += 1
        if windows > 24:
            raise AssertionError('the auto recce asked for more than 24 windows: it is not finishing')
        answers = app.handle(app.wire_in(mod.take()))
        if len(answers) != 1:
            raise AssertionError('one answer a request: %r' % (answers,))
        mod.g.DELIVER_RECCE(app.wire_out(answers[0]))
    c.ok(windows >= 2, 'the stage took more than one window, so the windows had to stitch (%d)' % windows)

    res = mod.g.RECCE_RESULT()
    c.ok(res is not None, 'the auto recce finished and called back once')
    res = json.loads(str(res))
    if roads:
        c.ok(res['ok'] is True, 'BUG 1/3: a matched line was written (%r)' % (res.get('why'),))
        c.ok(res.get('file') is True, 'the file is in the game\'s user folder')
        m = res.get('matched') or {}
        length = float(m.get('lengthM') or 0.0)
        gap = float(m.get('gapM') or 0.0)
        c.ok(length > (STAGE_TO - STAGE_FROM) * 0.8,
             'the matched line covers the stage (%.0f m of %.0f m)' % (length, STAGE_TO - STAGE_FROM))
        c.ok(gap < length * 0.1,
             'and ran on roads rather than on the organisers\' line (%.0f m of %.0f m is gap)' % (gap, length))
        pts = json.loads(str(mod.g.MATCHED_POINTS() or '{}')).get('pts')
        c.ok(isinstance(pts, list) and len(pts) > 10, 'the written line has points in it (%s)'
             % (len(pts) if isinstance(pts, list) else pts))
        if isinstance(pts, list) and pts:
            worst = 0.0
            for p in pts:
                pl, po = (p[0], p[1]) if isinstance(p, list) else (p.get('lat'), p.get('lon'))
                e, n, _ = app.base.geodetic_to_enu(float(pl), float(po), 0.0)
                worst = max(worst, abs(float(n)))
            c.ok(worst < 25.0,
                 'every point of it is on the road under the stage, not on the road 250 m north '
                 '(worst %.1f m off the stage line)' % worst)
    else:
        c.ok(res['ok'] is False, 'BUG 4: a stage with no road in it wrote nothing')
        c.ok(res.get('file') is not True, '... and left no file behind')
        c.ok('no roads' in str(res.get('why') or '').lower() or 'no map data' in str(res.get('why') or '').lower(),
             '... and said why in words a player can act on (%r)' % (res.get('why'),))
        c.ok(str((res.get('how') or {}).get('kind') or '') != '', 'the ending is named for the menu (%r)'
             % ((res.get('how') or {}).get('kind'),))
    return res


# --------------------------------------------------------------------------------------------------
def main():
    app_dir = app_repo()
    if app_dir is None:
        print('test_roadgraph_e2e: no BeamNG.Earth checkout at %s: skipped'
              % (os.environ.get('BNGE_REPO') or ('%s/beamng.earth' % ROOT.parent)))
        return 0
    if not have_numpy():
        if os.environ.get('BNGE_RG_E2E_CHILD'):
            print("test_roadgraph_e2e: %s has no numpy either: skipped" % sys.executable)
            return 0
        vp = venv_python(app_dir)
        if vp is None:
            print('test_roadgraph_e2e: this interpreter has no numpy and %s has no .venv: skipped' % app_dir)
            return 0
        env = dict(os.environ, BNGE_RG_E2E_CHILD='1', BNGE_REPO=str(app_dir))
        return subprocess.run([str(vp), str(Path(__file__).resolve())], env=env).returncode
    lupa = lupa_runtime()
    if lupa is None:
        print('test_roadgraph_e2e: lupa (LuaJIT) is not installed for %s: skipped' % sys.executable)
        return 0
    print('test_roadgraph_e2e: BeamNG.Earth at %s, %s' % (app_dir, sys.executable))

    c = Checks()
    # the app's own warnings, at volume: a refused download is this test working as intended (every cell it builds
    # from is one it wrote), and the roads layers' neighbour reads produce one per cell
    logging.getLogger('earthd').setLevel(logging.ERROR)
    tmp = Path(tempfile.mkdtemp(prefix='rg_e2e_'))
    app = App(app_dir, tmp)
    part_a(c, app, lupa)
    part_b(c, app_dir, lupa, roads=True, label='with roads')
    part_b(c, app_dir, lupa, roads=False, label='over roadless ground')
    print('\ntest_roadgraph_e2e: %d passed, %d failed' % (c.passed, c.failed))
    if c.bugs:
        print("""
================================================================================
A FIFTH BUG, found by this test: a cached-only road-graph window does fetch.

A decoded roads layer carries hooks of its own -- gradesep.hook and
gradesep.neighbours_hook, attached in MapData._decoded_layer -- and navgraph.build
runs them while it builds. gradesep._neighbours (server/gradesep.py) reads each of
the eight cells round a cell with

    md.cell(k, layers=("roads",), kind="demand")

which is the highest download priority there is, ahead of the world's own
streaming. Nothing the cachedOnly flag controls touches it: Server.road_graph_data
reads the window's own cells at kind="background", and then the build reaches past
them. In this run a 2-cell window read 17 more cells at demand and attempted ~40
downloads; against the real cache at Maryhill a 6-cell window reached for 35 more
(no download only because the player had already driven there).

docs/ADDONS.md promises "No map cell is downloaded for it", and BeamNG.Earth's own
test_road_graph_api cannot see this, because its stand-in map data has no such
hooks -- the same gap between stand-ins that hid the other four.

Not fixed here: the fix belongs in BeamNG.Earth, beside road_graph_data.
Run with BNGE_RG_E2E_STRICT=1 to have these count as failures.
================================================================================""")
        for b in c.bugs:
            print('  ' + b)
    return 1 if c.failed else 0


# --------------------------------------------------------------------------------------------------
# A note on bug 2, which this test does not catch.
#
# The fix (BeamNG.Earth 3ce9d2dd) swapped MapData.layer_unkept for mapcells.load_cells at kind="background",
# because layer_unkept "skips the neighbour discovery and tag joins roads need for drivability", and a window whose
# cells were all on disk built 0 nodes in a game while the player's own graph of the same anchor had 489.
#
# That divergence could not be reproduced here. For a cell on disk the two readers run the same decode:
# layer_unkept calls MapData._decoded_layer(remember=False), which applies _rails and _lanes and attaches the same
# hooks; only a cell already in the MEM_MB cache is answered without re-running the joins. Tried against this
# fixture and against the real cached cells of the place the bug was found at (Maryhill, 45.70719 -120.79373, six
# z14 cells), with the tag sources present, with them absent, and with the memory cache warmed by the player's
# path first and then the tags restored, the two readers gave the same 546 nodes every time. Reintroducing the old
# reader leaves all 53 checks here green.
#
# So what is held down above is the fix's content (the reader, and the kind) and its invariant (the two readers
# agree), not the symptom. Worth noting too: bug 3's own symptom -- a complete window with no roads in it, at an
# anchor that had moved -- is exactly bug 2's reported symptom, and bug 3 explains the intermittency (a fresh
# anchor has no drift; the next one does) better than a memory-cache story does. The two may well have been one
# bug.
if __name__ == '__main__':
    sys.exit(main())
