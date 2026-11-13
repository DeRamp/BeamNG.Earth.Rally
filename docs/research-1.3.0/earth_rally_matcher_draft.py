#!/usr/bin/env python3
"""DRAFT (research prototype, not the release file): the watch-mode shell of an Earth Rally Matcher companion.

The release file must be ONE .py (BeamNG.Earth installs only the release asset into <data>/addons/<id>/), so the real
companion is tools/match_roads.py with this shell added (a --watch mode); here match_stage is imported from a
match_roads.py given with --match-roads, so the shell can be tried without changing that file.

    # dry run (lists what would be matched; reads the user folder only, imports nothing of BeamNG.Earth's):
    python earth_rally_matcher_draft.py --watch --once --dry-run --match-roads <earth-rally>/tools/match_roads.py
    # as BeamNG.Earth runs it (dev tree):
    python launcher.py --run-addon earth_rally_matcher_draft.py --watch
"""
import argparse
import json
import os
import sys
import time

MATCHER_VERSION = 1         # bump when the matching changes: every stage is matched again
POLL_S = 5.0                # the events folder looked at this often
HEARTBEAT_S = 10.0          # matcher.json rewritten at least this often (the mod: older than ~30 s = not running)
SETTLE_S = 3.0              # an event file changed less than this ago is left until it is complete
RETRY_S = 600.0             # a stage that failed (network) is tried again after this


# --- where things are ------------------------------------------------------------------------------------------

def _server_path():
    """Dev tree: launcher.run_addon does not put server/ on sys.path (the packaged app imports it from its archive)."""
    try:
        import mapdata  # noqa: F401
        return
    except ImportError:
        pass
    for p in list(sys.path):
        s = os.path.join(p, "server")
        if os.path.isfile(os.path.join(s, "mapdata.py")):
            sys.path.insert(0, s)
            return


def user_dirs(given=None):
    """The BeamNG user folders to watch: the given one, BeamNG.Earth's (BNE_USER_DIR when the server passes it; else
    the one the game told BeamNG.Earth, apppaths.saved_user_dir; else install.candidate_user_dirs), those with an
    earthRally folder first."""
    cands = [given, os.environ.get("BNE_USER_DIR")]
    try:
        import apppaths
        cands.append(apppaths.saved_user_dir())
    except Exception:
        pass
    try:
        import install
        cands += install.candidate_user_dirs()
    except Exception:
        base = os.environ.get("LOCALAPPDATA")
        cands.append(os.path.join(base, "BeamNG", "BeamNG.drive", "current") if base
                     else os.path.expanduser("~/.local/share/BeamNG/BeamNG.drive/current"))
    out = []
    for c in cands:
        if c and os.path.isdir(os.path.join(c, "earthRally")) and os.path.normcase(os.path.abspath(c)) not in \
                [os.path.normcase(os.path.abspath(o)) for o in out]:
            out.append(c)
    return out


def cache_dir(given=None):
    """BeamNG.Earth's download cache: BNE_CACHE_DIR when the server passes it, else earthd's own default (the folder
    chosen on the settings page, apppaths.saved_cache_dir, else ~/.cache/beamng-earth: on Windows too)."""
    if given:
        return given
    if os.environ.get("BNE_CACHE_DIR"):
        return os.environ["BNE_CACHE_DIR"]
    try:
        import apppaths
        return apppaths.saved_cache_dir() or apppaths.default_cache_dir()
    except Exception:
        return os.path.join(os.path.expanduser("~"), ".cache", "beamng-earth")


# --- below the game and the world server -------------------------------------------------------------------------

def lower_priority():
    """Idle priority (and background I/O on Windows): the matcher inherits the world server's cores (cpupin) and its
    "below normal" class; it should take only what neither the game nor the server's workers want."""
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        k32.GetCurrentProcess.restype = wintypes.HANDLE
        k32.SetPriorityClass.argtypes = (wintypes.HANDLE, wintypes.DWORD)
        k32.SetPriorityClass.restype = wintypes.BOOL
        ok = k32.SetPriorityClass(k32.GetCurrentProcess(), 0x00000040)       # IDLE_PRIORITY_CLASS
        k32.SetPriorityClass(k32.GetCurrentProcess(), 0x00100000)            # PROCESS_MODE_BACKGROUND_BEGIN (I/O)
        return "idle" if ok else None
    try:
        os.nice(19)
        if hasattr(os, "sched_setscheduler") and hasattr(os, "SCHED_IDLE"):
            os.sched_setscheduler(0, os.SCHED_IDLE, os.sched_param(0))
        return "idle"
    except OSError:
        return None


# --- files -------------------------------------------------------------------------------------------------------

def write_json(path, data):
    """Atomic; retried while the game has the file open (os.replace fails on Windows then)."""
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f)
    for i in range(20):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(0.1 * (i + 1))
    os.remove(tmp)
    raise PermissionError(f"could not replace {path}")


def map_key(line):
    a, b = line[0], line[-1]
    return '%d:%.6f:%.6f:%.6f:%.6f' % (len(line), a[0], a[1], b[0], b[1])


def pending(ud, failed, now):
    """[(event, stage, matched path)] still to match in user folder ud: no matched file, or one made for another map
    line (mapKey) or by an older matcher."""
    ev_dir = os.path.join(ud, "earthRally", "events")
    out_dir = os.path.join(ud, "earthRally", "matched")
    todo = []
    try:
        names = sorted(n for n in os.listdir(ev_dir) if n.endswith(".json"))
    except OSError:
        return todo
    for n in names:
        p = os.path.join(ev_dir, n)
        try:
            if now - os.path.getmtime(p) < SETTLE_S:
                continue
            with open(p, encoding="utf-8") as f:
                ev = json.load(f)
        except (OSError, ValueError):
            continue                    # (being written: next look)
        if not isinstance(ev, dict) or ev.get("format") != 1:
            continue
        eid = ev.get("id") or n[:-5]
        for st in ev.get("stages") or ():
            if not isinstance(st, dict) or not isinstance(st.get("line"), list) or len(st["line"]) < 2:
                continue
            key = f"{eid}__{st['id']}"
            mk = map_key(st["line"])
            mp = os.path.join(out_dir, key + ".json")
            try:
                with open(mp, encoding="utf-8") as f:
                    m = json.load(f)
                if m.get("mapKey") == mk and int(m.get("matcher", 0)) >= MATCHER_VERSION:
                    continue
                # (tools/match_roads.py's files today have no "matcher" field: same mapKey = keep them, so a player's
                # existing matches are not redone; drop this clause to redo them)
                if m.get("mapKey") == mk and "matcher" not in m:
                    continue
            except (OSError, ValueError, AttributeError):
                pass
            f_ = failed.get(key)
            if f_ and f_["mapKey"] == mk and (f_["permanent"] or now - f_["at"] < RETRY_S):
                continue
            todo.append((eid, st, mp, key, mk))
    return todo


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--watch", action="store_true")
    ap.add_argument("--once", action="store_true", help="one look, then end (tests)")
    ap.add_argument("--dry-run", action="store_true", help="list, match nothing, write nothing")
    ap.add_argument("--user-dir")
    ap.add_argument("--cache-dir")
    ap.add_argument("--match-roads", help="(the draft only) the match_roads.py to take match_stage from")
    a = ap.parse_args()
    # (BNE_* variables are build switches in revisit's code key; BNE_FEED, set for companions only, would give this
    # process a key of its own. Gone before any server module is imported)
    os.environ.pop("BNE_FEED", None)
    _server_path()
    print(f"[matcher] priority: {lower_priority() if not a.dry_run else 'unchanged (dry run)'}", flush=True)
    uds = user_dirs(a.user_dir)
    cd = cache_dir(a.cache_dir)
    print(f"[matcher] user folders: {uds}; cache: {cd}", flush=True)
    engine = None
    failed, stats = {}, {}
    last_beat = 0.0
    while True:
        now = time.time()
        for ud in uds:
            todo = pending(ud, failed, now)
            status_p = os.path.join(ud, "earthRally", "matcher.json")
            status = {"format": 1, "matcher": MATCHER_VERSION, "pid": os.getpid(), "heartbeat": round(now),
                      "state": "matching" if todo else "idle", "queued": len(todo), "current": None,
                      "stages": stats}
            if a.dry_run:
                for eid, st, mp, key, mk in todo:
                    print(f"[matcher] would match {key}", flush=True)
                continue
            for i, (eid, st, mp, key, mk) in enumerate(todo):
                if engine is None:
                    import importlib.util
                    import numpy as np
                    import mapdata, mapcells, dem as demmod, roads as roadsmod
                    if a.match_roads:
                        spec = importlib.util.spec_from_file_location("match_roads", a.match_roads)
                        mr = importlib.util.module_from_spec(spec)
                        spec.loader.exec_module(mr)
                    else:
                        mr = sys.modules[__name__]       # (the release file: match_stage lives in this file)
                    engine = (np, mapdata.MapData(cd, threads=2), mapcells, demmod.Dem(cd, fetch_workers=4),
                              roadsmod, mr)
                np, md, mapcells, dem, roadsmod, mr = engine
                status.update(state="matching", queued=len(todo) - i,
                              current={"event": eid, "stage": st["id"], "since": round(time.time())})
                write_json(status_p, status)
                t0 = time.time()
                try:
                    m = mr.match_stage(np, md, mapcells, dem, st, roadsmod)
                    if m:
                        m["matcher"] = MATCHER_VERSION
                        write_json(mp, m)
                        stats[key] = {"state": "done", "seconds": round(time.time() - t0, 1), "at": round(time.time())}
                    else:
                        failed[key] = {"mapKey": mk, "at": time.time(), "permanent": True}
                        stats[key] = {"state": "failed", "error": "no roads found", "at": round(time.time())}
                except Exception as e:      # (a network error: tried again after RETRY_S)
                    failed[key] = {"mapKey": mk, "at": time.time(), "permanent": False}
                    stats[key] = {"state": "failed", "error": f"{type(e).__name__}: {e}"[:300], "at": round(time.time())}
                print(f"[matcher] {key}: {stats[key]}", flush=True)
            if todo or now - last_beat >= HEARTBEAT_S:
                status.update(state="idle", queued=0, current=None, heartbeat=round(time.time()))
                write_json(status_p, status)
                last_beat = now
        if a.once or not a.watch:
            return 0
        time.sleep(POLL_S)


if __name__ == "__main__":
    sys.exit(main())
