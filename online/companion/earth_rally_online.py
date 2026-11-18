"""Earth Rally online board: the companion beside the game (docs/research-online-leaderboards.md, section 1).

BeamNG's Lua cannot reach the internet (its sockets only reach this computer and the LAN, and it has no HTTPS), so the
mod talks to this program on 127.0.0.1 and this program talks to the board's server over HTTPS. One file, Python's
standard library only, so BeamNG.Earth's add-ons page can run it with its own Python (add-on kind "companion").

    python earth_rally_online.py [--port 47820] [--server https://earth-rally-board.example.workers.dev] [--data DIR]

The mod's side is earthRally/online.lua. Each line it sends is one JSON request, {"id": n, "op": ..., ...}, and each
line back is the answer, {"id": n, "ok": true | false, ...}, in whatever order they finish. Ops:

    hello                               -> {version, server, player: {name} | null, queued}
    register {name}                     -> {player: {name}}         (a new player, or a new name for this one)
    start {stage}                       -> {token, stageId}
    submit {run}                        -> the server's answer; {queued: true} when the server cannot be reached
    board {stage, board, top, n}        -> the server's answer
    report {runId, why}                 -> {}

The player's id and secret are kept in DATA/player.json, and runs that could not be sent in DATA/queue.json (sent again
every RETRY_S while this runs). DATA is ~/.earth_rally_online by default: not beside this file, which BeamNG.Earth
replaces when the add-on is updated. A player the server no longer knows (its database was reset) is forgotten, so
the next name picked makes a new one.
"""
import argparse
import json
import logging
import os
import socketserver
import sys
import threading
import time
import urllib.error
import urllib.request

VERSION = "0.1.0"
DEFAULT_PORT = 47820
# The board's address once it is deployed (online/worker); --server or EARTH_RALLY_BOARD overrides it.
DEFAULT_SERVER = os.environ.get("EARTH_RALLY_BOARD", "")
HTTP_TIMEOUT_S = 15
RETRY_S = 60
LINE_MAX = 4 << 20
QUEUE_MAX = 200

log = logging.getLogger("earth_rally_online")


class Board:
    """The server, the player's identity and the queue of runs not sent yet."""

    def __init__(self, server, data_dir, opener=None, legacy_dir=None):
        self.server = server.rstrip("/")
        self.data = data_dir
        self.lock = threading.RLock()
        self.open = opener or urllib.request.urlopen
        os.makedirs(self.data, exist_ok=True)
        self.player = self._read("player.json", None)
        if self.player is None and legacy_dir:
            # (the first prototype kept the player beside this file: brought over once)
            old = os.path.join(legacy_dir, "player.json")
            try:
                with open(old, encoding="utf-8") as f:
                    self.player = json.load(f)
                self._write("player.json", self.player)
            except (OSError, ValueError):
                pass
        if self.player and self.player.get("server") != self.server:
            self.player = None          # (an identity on another server is not this one's)
        self.queue = self._read("queue.json", [])
        self.tries = {}
        if not isinstance(self.queue, list):
            self.queue = []

    # ---- files
    def _path(self, name):
        return os.path.join(self.data, name)

    def _read(self, name, default):
        try:
            with open(self._path(name), encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return default

    def _write(self, name, value):
        tmp = self._path(name + ".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(value, f)
        os.replace(tmp, self._path(name))

    # ---- HTTP
    def call(self, method, path, body=None, auth=True):
        """(status, answer): status 0 when the server could not be reached."""
        if not self.server:
            return 0, {"error": "no board server is set (--server)"}
        headers = {"content-type": "application/json", "user-agent": "earth-rally-online/" + VERSION}
        if auth and self.player:
            headers["authorization"] = "Bearer %s:%s" % (self.player["id"], self.player["secret"])
        data = None if body is None else json.dumps(body).encode("utf-8")
        req = urllib.request.Request(self.server + path, data=data, method=method, headers=headers)
        try:
            with self.open(req, timeout=HTTP_TIMEOUT_S) as r:
                return r.status, json.loads(r.read().decode("utf-8") or "{}")
        except urllib.error.HTTPError as e:
            try:
                answer = json.loads(e.read().decode("utf-8") or "{}")
            except ValueError:
                answer = {}
            return e.code, {"error": answer.get("error") or "server answered %d" % e.code}
        except (urllib.error.URLError, OSError, ValueError) as e:
            return 0, {"error": "the board cannot be reached (%s)" % getattr(e, "reason", e)}

    # ---- ops
    def hello(self, _req):
        return {"ok": True, "version": VERSION, "server": self.server or None,
                "player": {"name": self.player["name"]} if self.player else None, "queued": len(self.queue)}

    def register(self, req):
        name = req.get("name")
        with self.lock:
            if self.player:
                st, a = self.call("POST", "/v1/players/me", {"name": name})
                if st == 200:
                    self.player["name"] = a["name"]
                    self._write("player.json", self.player)
                elif self._forget_if_unknown(st, a):
                    return self.register(req)
            else:
                st, a = self.call("POST", "/v1/players", {"name": name}, auth=False)
                if st == 200:
                    self.player = {"id": a["id"], "secret": a["secret"], "name": a["name"], "server": self.server}
                    self._write("player.json", self.player)
        if st != 200:
            return {"ok": False, "error": a.get("error"), "offline": st == 0}
        return {"ok": True, "player": {"name": self.player["name"]}}

    def _forget_if_unknown(self, st, a):
        """The server no longer knows this player (401): forgotten, so a name picked next makes a new one."""
        if st == 401 and self.player:
            with self.lock:
                log.warning("the board does not know this player (%s): forgotten", a.get("error"))
                self.player = None
                try:
                    os.replace(self._path("player.json"), self._path("player.json.%d.old" % time.time()))
                except OSError:
                    pass
            return True
        return False

    def _need_player(self):
        return None if self.player else {"ok": False, "error": "pick a name for the online board first", "noPlayer": True}

    def start(self, req):
        miss = self._need_player()
        if miss:
            return miss
        st, a = self.call("POST", "/v1/runs/start", {"stage": req.get("stage")})
        if self._forget_if_unknown(st, a):
            return {"ok": False, "error": "the board no longer knows you: pick a name again", "noPlayer": True}
        return self._answer(st, a)

    def submit(self, req):
        miss = self._need_player()
        if miss:
            return miss
        run = req.get("run")
        st, a = self.call("POST", "/v1/runs", run)
        if st == 0 or st >= 500 or st == 429:
            with self.lock:
                if len(self.queue) < QUEUE_MAX:
                    self.queue.append(run)
                    self._write("queue.json", self.queue)
            return {"ok": False, "queued": True, "error": a.get("error")}
        return self._answer(st, a)

    def board(self, req):
        body = {k: req.get(k) for k in ("stage", "board", "top", "n") if req.get(k) is not None}
        return self._answer(*self.call("POST", "/v1/boards", body))

    def report(self, req):
        return self._need_player() or self._answer(
            *self.call("POST", "/v1/reports", {"runId": req.get("runId"), "why": req.get("why")}))

    @staticmethod
    def _answer(st, a):
        if st == 200:
            a = dict(a)
            a["ok"] = True
            return a
        return {"ok": False, "error": a.get("error"), "status": st or None, "offline": st == 0}

    def flush_queue(self):
        """Send the runs that could not be sent: kept while the server cannot be reached, dropped once it answers.
        Each run stays in the queue (and its file) until it is answered, so a run queued meanwhile, or the companion
        stopping half way, loses none."""
        with self.lock:
            todo = list(self.queue)
        done = 0
        for run in todo:
            if not self.player:
                break
            st, a = self.call("POST", "/v1/runs", run)
            if st == 0 or st == 429:
                break                       # (still unreachable, or too soon: the rest wait too)
            if st >= 500:
                # (the server failing on this one run: the others still go; tried MAX_TRIES times, then dropped)
                key = json.dumps(run, sort_keys=True)[:200]
                self.tries[key] = self.tries.get(key, 0) + 1
                if self.tries[key] < self.MAX_TRIES:
                    continue
                log.warning("a queued run failed %d times on the server: dropped (%s)", self.MAX_TRIES, a.get("error"))
            elif st != 200:
                log.warning("a queued run was refused: %s", a.get("error"))
            with self.lock:
                if run in self.queue:
                    self.queue.remove(run)
                self._write("queue.json", self.queue)
            done += 1
        return done

    MAX_TRIES = 10

    OPS = ("hello", "register", "start", "submit", "board", "report")

    def handle(self, req):
        op = req.get("op") if isinstance(req, dict) else None
        if op not in self.OPS:
            return {"ok": False, "error": "unknown op %r" % (op,)}
        try:
            return getattr(self, op)(req)
        except Exception as e:      # (one bad request never stops the companion)
            log.exception("op %s failed", op)
            return {"ok": False, "error": "companion error: %s" % e}


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        board = self.server.board
        wlock = threading.Lock()

        def answer(req):
            out = board.handle(req)
            out["id"] = req.get("id") if isinstance(req, dict) else None
            line = (json.dumps(out) + "\n").encode("utf-8")
            with wlock:
                try:
                    self.wfile.write(line)
                    self.wfile.flush()
                except (OSError, ValueError):     # (the connection closed while the answer was on its way)
                    pass

        while True:
            line = self.rfile.readline(LINE_MAX + 1)
            if not line:
                return
            if len(line) > LINE_MAX:
                answer({"op": None})
                return
            try:
                req = json.loads(line.decode("utf-8"))
            except ValueError:
                continue
            # (each request on its own thread: a slow board answer never holds up the next request)
            threading.Thread(target=answer, args=(req,), daemon=True).start()


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    # (not on Windows: there SO_REUSEADDR lets a second companion share the port, each taking some connections)
    allow_reuse_address = os.name != "nt"


def serve(board, port):
    srv = Server(("127.0.0.1", port), Handler)
    srv.board = board

    def retry():
        while True:
            time.sleep(RETRY_S)
            if board.queue:
                sent = board.flush_queue()
                if sent:
                    log.info("sent %d queued run(s)", sent)
    threading.Thread(target=retry, daemon=True).start()
    return srv


def main(argv=None):
    ap = argparse.ArgumentParser(description="Earth Rally's online board, beside the game")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--server", default=DEFAULT_SERVER)
    ap.add_argument("--data", default=os.path.join(os.path.expanduser("~"), ".earth_rally_online"))
    a = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    board = Board(a.server, a.data, legacy_dir=os.path.dirname(os.path.abspath(__file__)))
    srv = serve(board, a.port)
    log.info("Earth Rally online %s on 127.0.0.1:%d, board %s, player %s", VERSION, a.port, board.server or "(none)",
             board.player["name"] if board.player else "(none yet)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
