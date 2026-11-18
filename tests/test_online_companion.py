"""The online board's companion (online/companion/earth_rally_online.py) with a fake server: its player kept, runs
queued while the board cannot be reached and sent when it can, refused ones dropped. No network."""
import io
import json
import shutil
import sys
import tempfile
import urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "online" / "companion"))
import earth_rally_online as c  # noqa: E402

fails = []


def check(cond, name):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        fails.append(name)


class Fake:
    """urlopen: answers by path, or raises as an unreachable server (down = True)."""

    def __init__(self):
        self.down = False
        self.calls = []
        self.answers = {}

    def __call__(self, req, timeout=None):
        path = req.full_url.split("//", 1)[1].split("/", 1)[1]
        body = json.loads(req.data.decode()) if req.data else None
        self.calls.append(("/" + path, body, req.headers.get("Authorization")))
        if self.down:
            raise urllib.error.URLError("down")
        ans = self.answers.get("/" + path, (200, {}))
        st, a = ans(body) if callable(ans) else ans
        if st != 200:
            raise urllib.error.HTTPError(req.full_url, st, "x", {}, io.BytesIO(json.dumps(a).encode()))
        return Resp(io.BytesIO(json.dumps(a).encode()))


class Resp:
    def __init__(self, r):
        self.r, self.status = r, 200

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self):
        return self.r.getvalue()


def main():
    tmp = tempfile.mkdtemp(prefix="er_comp_")
    try:
        f = Fake()
        f.answers["/v1/players"] = (200, {"id": "p1", "secret": "s1", "name": "Ann"})
        f.answers["/v1/runs"] = (200, {"runId": 1, "status": "ok", "pos": 1, "of": 1})
        b = c.Board("https://board", tmp, opener=f)
        check(b.handle({"op": "hello"})["player"] is None, "no player at first")
        check(b.handle({"op": "submit", "run": {}}).get("noPlayer"), "no run before a name")
        r = b.handle({"op": "register", "name": "Ann"})
        check(r["ok"] and r["player"]["name"] == "Ann", "registered")
        check(json.loads((Path(tmp) / "player.json").read_text())["secret"] == "s1", "the player kept")
        b2 = c.Board("https://board", tmp, opener=f)
        check(b2.player and b2.player["id"] == "p1", "the player read back")
        check(c.Board("https://other", tmp, opener=f).player is None, "not on another server")

        r = b.handle({"op": "submit", "run": {"token": "t"}})
        check(r["ok"] and r["pos"] == 1 and f.calls[-1][2] == "Bearer p1:s1", "a run sent, as the player")

        f.down = True
        r = b.handle({"op": "submit", "run": {"token": "t2"}})
        check(not r["ok"] and r["queued"] and len(b.queue) == 1, "server down: the run queued")
        check(b.handle({"op": "hello"})["queued"] == 1, "hello says one is waiting")
        check(b.flush_queue() == 0 and len(b.queue) == 1, "still down: kept")
        check(json.loads((Path(tmp) / "queue.json").read_text())[0]["token"] == "t2", "the queue on disk")
        f.down = False
        check(b.flush_queue() == 1 and not b.queue, "back up: sent")

        f.down = True
        b.handle({"op": "submit", "run": {"token": "t3"}})
        f.down = False
        f.answers["/v1/runs"] = (409, {"error": "this run was sent already"})
        check(b.flush_queue() == 1 and not b.queue, "refused by the server: dropped, not kept for ever")

        # one run the server always fails on: the others behind it still go; it is dropped after MAX_TRIES
        f.down = True
        b.handle({"op": "submit", "run": {"token": "bad"}})
        b.handle({"op": "submit", "run": {"token": "good"}})
        f.down = False
        f.answers["/v1/runs"] = lambda body: (500, {"error": "server error"}) if body["token"] == "bad" else (200, {})
        check(b.flush_queue() == 1 and [r["token"] for r in b.queue] == ["bad"], "a failing run does not hold up the rest")
        for _ in range(c.Board.MAX_TRIES):
            b.flush_queue()
        check(not b.queue, "dropped after MAX_TRIES")

        # a server whose database was reset: the player forgotten, a new name makes a new one
        f.answers["/v1/runs/start"] = (401, {"error": "unknown player"})
        r = b.handle({"op": "start", "stage": {}})
        check(not r["ok"] and r.get("noPlayer") and b.player is None, "unknown to the server: forgotten")
        f.answers["/v1/players"] = (200, {"id": "p2", "secret": "s2", "name": "Ann"})
        check(b.handle({"op": "register", "name": "Ann"})["ok"] and b.player["id"] == "p2", "a name again: a new player")

        f.answers["/v1/boards"] = (400, {"error": "bad stage length"})
        r = b.handle({"op": "board", "stage": {}})
        check(not r["ok"] and r["error"] == "bad stage length" and r["status"] == 400, "the server's error passed on")
        check(not b.handle({"op": "nope"})["ok"], "an unknown op answered")
        check(not c.Board("", tmp, opener=f).handle({"op": "board"})["ok"], "no server set: said so")

        # stats (#76): to the stats server, never with the player's id; refused or not set: said so
        sb = c.Board("https://board", tmp, opener=f, stats_server="https://stats")
        sb.player = {"id": "p9", "secret": "s", "name": "Ann", "server": "https://board"}
        f.calls.clear()
        r = sb.handle({"op": "stats", "events": [{"event": "session_start"}]})
        check(r["ok"] and f.calls[-1][0] == "/v1/events" and f.calls[-1][2] is None, "stats sent with no player id")
        check(sb.handle({"op": "hello"})["stats"] is True, "hello says stats can go")
        f.answers["/v1/events"] = (400, {"error": "bad"})
        r = sb.handle({"op": "stats", "events": [{"event": "x"}]})
        check(not r["ok"] and r["status"] == 400, "a refused batch: its status passed on")
        check(not sb.handle({"op": "stats", "events": []})["ok"], "no events: refused")
        r = c.Board("https://board", tmp, opener=f).handle({"op": "stats", "events": [{"event": "x"}]})
        check(not r["ok"] and r.get("offline"), "no stats server: kept for later")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("test_online_companion: %s" % ("FAILED: " + ", ".join(fails) if fails else "all passed"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
