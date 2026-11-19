"""The online board end to end, on this computer: the mod's client (online.lua, under LuaJIT with a real TCP socket
standing in for luasocket) -> the companion (online/companion/earth_rally_online.py) -> the board's server (the
Worker under Node, online/worker/dev/server.mjs). About 15 s: the server checks a run took as long as it says.
Needs Node 22+ (skipped without it) and lupa.

    python tests/test_online_e2e.py
"""
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LUA = ROOT / "mod" / "earth_rally" / "lua" / "ge" / "extensions"
SERVER = ROOT / "online" / "worker" / "dev" / "server.mjs"
COMPANION = ROOT / "online" / "companion" / "earth_rally_online.py"

fails = []


def check(cond, name):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fails.append(name)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def wait_port(port, timeout=15):
    end = time.time() + timeout
    while time.time() < end:
        try:
            socket.create_connection(("127.0.0.1", port), 0.5).close()
            return True
        except OSError:
            time.sleep(0.1)
    return False


class Sock:
    """What online.lua uses of a luasocket tcp object, over a real socket (the Lua side wraps it: lua_sock below)."""

    def __init__(self):
        self.s = None

    def connect(self, host, port):
        try:
            self.s = socket.create_connection((host, int(port)), 2)
            self.s.setblocking(False)
            return ""
        except OSError as e:
            return str(e) or "refused"

    def send(self, data):
        self.s.setblocking(True)
        self.s.sendall(data if isinstance(data, bytes) else data.encode("utf-8"))
        self.s.setblocking(False)
        return len(data)

    def recv(self):
        try:
            d = self.s.recv(65536)
        except BlockingIOError:
            return ""
        except OSError:
            return None
        return d.decode("utf-8") if d else None

    def close(self):
        if self.s:
            self.s.close()


LUA_SOCK = r"""
local py = ...
local function tcp()
  local s = py()
  local o = {}
  function o:settimeout() end
  function o:setoption() end
  function o:connect(h, p) local e = s.connect(h, p) if e == '' then return 1 end return nil, e end
  function o:getpeername() return '127.0.0.1' end
  function o:send(d) return s.send(d) end
  function o:receive() local d = s.recv() if d == nil then return nil, 'closed', '' end return nil, 'timeout', d end
  function o:close() s.close() end
  return o
end
return { tcp = tcp }
"""


def main():
    node = shutil.which("node")
    if not node:
        print("test_online_e2e: skipped (no Node)")
        return 0
    try:
        import lupa.luajit21 as lj
    except ImportError:
        print("test_online_e2e: skipped (pip install lupa)")
        return 0
    tmp = tempfile.mkdtemp(prefix="er_online_")
    sport, cport = free_port(), free_port()
    procs = []
    try:
        # (EARTH_RALLY_TEST_BOARD: a board already running, e.g. `npx wrangler dev`, instead of the Node stand-in)
        url = os.environ.get("EARTH_RALLY_TEST_BOARD")
        if not url:
            procs.append(subprocess.Popen([node, "--no-warnings", str(SERVER), "--port", str(sport), "--admin", "t"],
                                          stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT))
            url = "http://127.0.0.1:%d" % sport
        procs.append(subprocess.Popen([sys.executable, str(COMPANION), "--port", str(cport), "--server", url,
                                       "--data", tmp], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT))
        check((os.environ.get("EARTH_RALLY_TEST_BOARD") or wait_port(sport)) and wait_port(cport),
              "server and companion up")

        lua = lj.LuaRuntime()
        lua.globals().TESTS = (ROOT / "tests").as_posix()
        lua.execute("package.path = '%s/?.lua;' .. package.path" % LUA.as_posix())
        O = lua.eval("require('earthRally/online')")
        T = lua.execute("return dofile(TESTS .. '/testlib.lua')")
        O._jsonEncode, O._jsonDecode = T.jsonEncode, T.jsonDecode
        O._socket = lua.execute(LUA_SOCK, Sock)
        O.PORT = cport
        O.RECONNECT_S = 0.05

        def pump(cond, timeout=10):
            end = time.time() + timeout
            while time.time() < end:
                O.update(0.05)
                if cond():
                    return True
                time.sleep(0.02)
            return False

        O.enable(True)
        check(pump(lambda: O.status().connected), "the mod reaches the companion")
        check(O.status().player is None, "no player yet")

        got = {}
        name = "Ann%d" % (int(time.time()) % 100000) if os.environ.get("EARTH_RALLY_TEST_BOARD") else "Ann"
        O.register(name, lambda r: got.__setitem__("r", r))
        check(pump(lambda: "r" in got) and got["r"].ok and O.status().player.name == name, "a name picked")

        # a 600 m stage driven in 12 s (180 km/h: within the server's average)
        desc = O.stageDesc("Test Rally", "Sprint", lua.table(60.0, 25.0), lua.table(60.0 + 600 / 111195, 25.0), 600)
        h = O.runStart(desc)
        check(pump(lambda: h.token is not None) and h.token, "a run token")
        drive_s = 12.0
        t0 = time.time()
        steps = int(drive_s / 0.25)
        for i in range(steps + 1):
            O.runSample(h, i * 0.25, 60.0 + (600 / 111195) * i / steps, 25.0)
        time.sleep(max(0, drive_s - (time.time() - t0)))
        O.runFinish(h, lua.table_from({"timeS": drive_s + 10, "penaltyS": 10, "driveS": drive_s, "car": "Ibishu Covet",
                                       "board": "stock", "lat": 60.0 + 600 / 111195, "lon": 25.0}))
        check(pump(lambda: O.lastResult is not None), "the run answered")
        r = O.lastResult
        check(r.ok and r.status == "ok" and r.pos == 1 and r.best == 22000,
              "on the board: 1st, 22.0 s (status %s, %s)" % (r.status, r.error))

        O.board(desc, "stock")
        check(pump(lambda: O.board(desc, "stock").data is not None), "the board read back")
        data = O.board(desc, "stock").data
        rows = [data.rows[i] for i in range(1, len(data.rows) + 1)]
        row = next((x for x in rows if x.you), rows[0])
        check(row.name == name and row.timeMs == 22000 and row.car == "Ibishu Covet" and row.you,
              "the row: Ann, 22.0 s, the car, you")
        check(data.stage.name == "Sprint" and data.stage.rally == "Test Rally", "the stage named")
        O.board(desc, "open")
        check(pump(lambda: O.board(desc, "open").data is not None), "the open board read")

        # the companion keeps the player
        check((Path(tmp) / "player.json").exists(), "the player kept by the companion")

        # the companion gone: said so, and the mod carries on
        procs[-1].terminate()
        procs[-1].wait(5)
        check(pump(lambda: not O.status().connected), "the companion stopped: seen")
        h2 = O.runStart(desc)
        check(h2 is not None, "a run still starts")
        O.runFinish(h2, lua.table_from({"timeS": 20, "penaltyS": 0, "driveS": 20, "board": "stock",
                                        "lat": 60.0, "lon": 25.0}))
        check(not O.lastResult.ok, "a run with no companion is not sent, and says so")
    finally:
        for p in procs:
            if p.poll() is None:
                p.terminate()
                try:
                    p.wait(5)
                except subprocess.TimeoutExpired:
                    p.kill()
        shutil.rmtree(tmp, ignore_errors=True)
    print("test_online_e2e: %s" % ("FAILED: " + ", ".join(fails) if fails else "all passed"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
