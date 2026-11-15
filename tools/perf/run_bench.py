"""Run a performance suite in the running game (docs/perf-plan-1.6.1.md).

    python tools/perf/run_bench.py <suite> --label "what this build is" [--presentmon PATH] [--no-report]

Suites: smoke, quick, t1, t1b, t2, t3, t4, t5, full (t1b, t1, t2, t3, t4, t5 in one go).

What it does:
  1. loads tools/perf/bench.lua into the game over MCP and starts the suite there;
  2. watches <user>/earthRally/bench/progress.json (a file, never MCP) with a stall timeout and a total timeout;
  3. optionally runs PresentMon beside it (needs admin, or the "Performance Log Users" group);
  4. writes the capture windows (wall clock) next to the captures, then runs perf_report.py.
The car is never driven: it is placed at fixed spots, and the mod is put straight into the state a capture needs.
Every A/B has an explicit base (base=True) and its pairs alternate A B, B A, A B, so a drift over time cancels."""
import argparse
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from mcp import lua  # noqa: E402

BENCH = os.path.join(os.environ.get("LOCALAPPDATA", ""), "BeamNG", "BeamNG.drive", "current", "earthRally", "bench")
EV, ST = "ara26-overmountain", "weaver-bend"     # Overmountain Rally 2026, Weaver Bend (6.8 km), auto recced
LINE = -4                                       # on the start line (just behind it, as a car held there stands)
SPOT1, SPOT2 = 2300, 4600
STALL_S = 90           # progress.json unchanged this long: the game has hung or the bench has died
CAP = {"warm": 5, "seconds": 20}
PM_SESSION = "EarthRallyBench"


# ------------------------------------------------------------------------------------------------ the suites
def start():
    return [{"op": "start", "event": EV, "stage": ST}]


def cap(label, test, state, spot, **kw):
    d = {"op": "capture", "label": label, "test": test, "state": state, "alongM": spot}
    d.update(CAP)
    d.update(kw)
    return d


def floor(test, spot, label, pair, base=False):
    """The run aborted where the car stands, traffic held off as the run holds it: the mod idle (not unloaded)."""
    return [{"op": "state", "name": "none"}, {"op": "set", "switch": "traffic", "value": "off"},
            {"op": "settle", "timeout": 90},
            cap(label, test, "none", spot, switch="state", value="none", pair=pair, base=base)]


def race(test, spot, label, pair, base=False):
    """A fresh run, the car at `spot`, the race active (running), settled."""
    return start() + [{"op": "spot", "alongM": spot}, {"op": "state", "name": "running"},
                      {"op": "settle", "timeout": 120},
                      cap(label, test, "running", spot, switch="state", value="running", pair=pair, base=base)]


def go_at_line(test, label, pair):
    """The start line: waitStart settled (the base), then GO and the 20 s after it recorded from GO (no warm-up, no
    settle: the start clock is fed until the clock reaches 8 s, the start-line prism drawn until 10 s), then the
    race settled on the line."""
    return start() + [
        {"op": "spot", "alongM": LINE}, {"op": "state", "name": "waitStart"}, {"op": "settle", "timeout": 120},
        cap(f"{label}-waitStart", test, "waitStart", LINE, switch="state", value="waitStart", pair=pair, base=True),
        {"op": "state", "name": "running"},
        cap(f"{label}-go", test, "running", LINE, warm=0, seconds=20, switch="state", value="go", pair=pair),
        {"op": "settle", "timeout": 60},
        cap(f"{label}-running", test, "running", LINE, switch="state", value="running", pair=pair),
    ]


def go_suite(test, pairs):
    """GO on the start line against the mod idle on the same spot, A B / B A / A B."""
    steps = []
    for i in range(pairs):
        p = i + 1
        line_first = i % 2 == 0
        run_part = go_at_line(test, f"{test}-{p}", p)
        idle_part = start() + [{"op": "spot", "alongM": LINE}] + floor(test, LINE, f"{test}-{p}-none", p)
        steps += (run_part + floor(test, LINE, f"{test}-{p}-none", p)) if line_first else (idle_part + run_part)
    return steps


def suite_smoke():
    return race("smoke", SPOT1, "smoke-running", 1) + floor("smoke", SPOT1, "smoke-none", 1, base=True)


def suite_quick():
    """After every fix: GO on the line (2 pairs), the race at 2.3 km vs the mod idle (3 pairs, alternated), one
    arrival at 2.3 km in running."""
    steps = go_suite("quick-go", 2)
    for i in range(3):
        p = i + 1
        r = race("quick", SPOT1, f"q-running-{p}", p)
        n = start() + [{"op": "spot", "alongM": SPOT1}] + floor("quick", SPOT1, f"q-none-{p}", p, base=True)
        steps += (r + floor("quick", SPOT1, f"q-none-{p}", p, base=True)) if i % 2 == 0 else (n + r)
    steps += start() + [{"op": "state", "name": "running"},
                        {"op": "arrival", "label": "q-arrival", "test": "quick-arrival", "alongM": SPOT1}]
    return steps + [{"op": "abort"}]


def suite_t1b():
    """Which state costs, on the start line: waitStart, GO, running, the mod idle; 3 pairs alternated."""
    return go_suite("t1b", 3) + [{"op": "abort"}]


def suite_t1():
    """World or mod: 2 min from arrival at 2.3 km, the mod idle vs running, A B B A, no settle on purpose."""
    steps = []
    for i, state in enumerate(["none", "running", "running", "none"]):
        steps += start() + [{"op": "spot", "alongM": SPOT1}, {"op": "state", "name": state}]
        if state == "none":
            steps.append({"op": "set", "switch": "traffic", "value": "off"})
        steps.append(cap(f"t1-{state}-{i + 1}", "t1", state, SPOT1, warm=0, seconds=120, switch="state", value=state,
                         pair=1 if i in (0, 1) else 2, base=state == "none"))
    return steps + [{"op": "abort"}]


def suite_t2():
    """Where a slow frame goes: Optick and the Lua sampler, the race vs the mod idle, 10 s each, at 2.3 km."""
    steps = start() + [{"op": "spot", "alongM": SPOT1}, {"op": "state", "name": "running"},
                       {"op": "settle", "timeout": 120}]
    steps.append(cap("t2-running", "t2", "running", SPOT1, seconds=10, optick=True, profile=True, switch="state",
                     value="running", pair=1))
    steps += [{"op": "dump", "label": "graph-2300"}]
    steps += [{"op": "state", "name": "none"}, {"op": "set", "switch": "traffic", "value": "off"},
              {"op": "settle", "timeout": 90}]
    steps.append(cap("t2-none", "t2", "none", SPOT1, seconds=10, optick=True, profile=True, switch="state",
                     value="none", pair=1, base=True))
    return steps + [{"op": "abort"}]


T3_SWITCHES = [("streams", 30, 1), ("layout", "stage", "plain"), ("notes", True, False), ("props", "shown", "hidden")]


def suite_t3():
    """What GO switches on: one system taken away at a time at 2.3 km in running. Base = as shipped (on).
    Pairs alternate on/off, off/on, on/off."""
    steps = start() + [{"op": "spot", "alongM": SPOT1}, {"op": "state", "name": "running"},
                       {"op": "settle", "timeout": 120}]
    for sw, on, off in T3_SWITCHES:
        for i in range(3):
            order = [(on, True), (off, False)] if i % 2 == 0 else [(off, False), (on, True)]
            for val, is_base in order:
                tag = "on" if is_base else "off"
                steps += [{"op": "set", "switch": sw, "value": val}, {"op": "wait", "seconds": 2}]
                steps.append(cap(f"t3-{sw}-{tag}-{i + 1}", "t3-" + sw, "running", SPOT1, switch=sw, value=val,
                                 pair=i + 1, base=is_base))
        steps += [{"op": "set", "switch": sw, "value": on}, {"op": "wait", "seconds": 2}]
    # the start clock last: once unloaded it is not put back for this run (one pair: indicative only)
    steps.append(cap("t3-startClock-loaded-1", "t3-startClock", "running", SPOT1, switch="startClock",
                     value="loaded", pair=1, base=True))
    steps += [{"op": "set", "switch": "startClock", "value": "unloaded"}, {"op": "wait", "seconds": 2}]
    steps.append(cap("t3-startClock-unloaded-1", "t3-startClock", "running", SPOT1, switch="startClock",
                     value="unloaded", pair=1))
    steps += [{"op": "dump", "label": "graph-2300-t3"}]
    return steps + [{"op": "abort"}]


def suite_t4():
    """The spawn spikes: 10 s from set-down in running, 24 (as shipped, the base) vs 2 objects a frame, each spot its
    own test, two pairs per spot alternated."""
    steps = start() + [{"op": "state", "name": "running"}]
    order = [(SPOT1, 24, 1), (SPOT2, 24, 1), (SPOT1, 2, 1), (SPOT2, 2, 1),
             (SPOT1, 2, 2), (SPOT2, 2, 2), (SPOT1, 24, 2), (SPOT2, 24, 2)]
    for spot, dress, pair in order:
        steps.append({"op": "arrival", "label": f"t4-{spot}-dress{dress}-{pair}", "test": f"t4-{spot}",
                      "alongM": spot, "dress": dress, "pair": pair, "base": dress == 24})
        steps.append({"op": "settle", "timeout": 90, "required": False})
    steps += [{"op": "dump", "label": "graph-4600"}]
    return steps + [{"op": "abort"}]


def suite_t5():
    """After the run: finished at 4.6 km (results card up), traffic back on (base, as the player has it) vs off."""
    steps = start() + [{"op": "spot", "alongM": SPOT2}, {"op": "state", "name": "running"},
                       {"op": "settle", "timeout": 120}]
    steps += [{"op": "state", "name": "finished"}, {"op": "wait", "seconds": 3}, {"op": "settle", "timeout": 90}]
    for i in range(2):
        order = [("on", True), ("off", False)] if i % 2 == 0 else [("off", False), ("on", True)]
        for val, is_base in order:
            steps += [{"op": "set", "switch": "traffic", "value": val}, {"op": "wait", "seconds": 5}]
            steps.append(cap(f"t5-traffic-{val}-{i + 1}", "t5", "finished", SPOT2, switch="traffic", value=val,
                             pair=i + 1, base=is_base))
    return steps + [{"op": "abort"}]


SUITES = {"smoke": suite_smoke, "quick": suite_quick, "t1": suite_t1, "t1b": suite_t1b, "t2": suite_t2,
          "t3": suite_t3, "t4": suite_t4, "t5": suite_t5}
LIMIT_S = {"smoke": 600, "quick": 2400, "t1": 1800, "t1b": 2400, "t2": 900, "t3": 2400, "t4": 1200, "t5": 1200}


# ------------------------------------------------------------------------------------------------ running one
def say(log, *a):
    line = time.strftime("%H:%M:%S ") + " ".join(str(x) for x in a)
    print(line, flush=True)
    with open(log, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def git(*args):
    try:
        return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def build_info():
    mods = os.path.join(os.path.dirname(BENCH), "..", "mods")
    zips = sorted(f for f in os.listdir(mods) if f.startswith("earth_rally")) if os.path.isdir(mods) else []
    return {"commit": git("rev-parse", "--short", "HEAD"), "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
            "dirty": bool(git("status", "--porcelain", "--", "mod")), "installed": zips}


def pm_start(presentmon, out, log):
    pm_csv = os.path.join(out, "presentmon.csv")
    pm_log = open(os.path.join(out, "presentmon.log"), "w", encoding="utf-8")
    pm = subprocess.Popen([presentmon, "--process_name", "BeamNG.drive.x64.exe", "--output_file", pm_csv,
                           "--no_console_stats", "--date_time", "--session_name", PM_SESSION,
                           "--stop_existing_session"], stdout=pm_log, stderr=subprocess.STDOUT)
    time.sleep(2)
    if pm.poll() is not None:
        pm_log.close()
        with open(os.path.join(out, "presentmon.log"), encoding="utf-8", errors="replace") as f:
            say(log, "PresentMon did not start:", f.read()[-300:].strip())
        return None
    return pm


def pm_stop(presentmon, pm):
    # (stopped through its own session, so it flushes the CSV; killed only if that does not end it)
    subprocess.run([presentmon, "--session_name", PM_SESSION, "--terminate_existing_session"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    try:
        pm.wait(15)
    except subprocess.TimeoutExpired:
        pm.kill()


def run_suite(kind, label, presentmon=None):
    name = f"{kind}-{time.strftime('%Y%m%d-%H%M%S')}"
    out = os.path.join(BENCH, name)
    os.makedirs(out, exist_ok=True)
    log = os.path.join(out, "runner.log")
    steps = SUITES[kind]()
    info = {"suite": name, "kind": kind, "label": label, "date": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "stage": f"{EV}/{ST}", **build_info()}
    say(log, "suite", name, "-", len(steps), "steps -", label, "-", info["commit"], info["installed"])

    pm = pm_start(presentmon, out, log) if presentmon else None
    info["presentmon"] = pm is not None

    pf = os.path.join(BENCH, "progress.json")
    say(log, "bench:", lua(open(os.path.join(HERE, "bench.lua"), encoding="utf-8").read()))
    try:
        os.remove(pf)          # (after loading: a reload of the bench must not leave the old suite's file behind)
    except OSError:
        pass
    cfg = {"name": name, "steps": steps}
    try:
        reply = lua(f"return erBench.run({json.dumps(json.dumps(cfg))})", timeout=30)
        say(log, "start:", reply)
        if reply.startswith("ERROR"):
            raise SystemExit("bench refused the suite: " + reply)
    except SystemExit as e:
        # (the answer can be lost while the suite did start: its own progress file says so)
        time.sleep(5)
        try:
            with open(pf, encoding="utf-8") as f:
                started = json.load(f).get("suite") == name
        except (OSError, ValueError):
            started = False
        if not started:
            if pm:
                pm_stop(presentmon, pm)
            raise
        say(log, "start: no answer over MCP (", e, "), but the suite is running")

    windows, cur = [], None
    t0, last, changed, p = time.time(), None, time.time(), None
    status, done = "finished", False
    try:
        while True:
            time.sleep(0.25)
            try:
                with open(pf, encoding="utf-8") as f:
                    q = json.load(f)
                if q.get("suite") == name:
                    p = q
            except (OSError, ValueError):
                pass
            if p:
                k = (p.get("t"), p.get("step"), p.get("capturing"))
                if k != last:
                    last, changed = k, time.time()
                lab = p.get("label") if p.get("capturing") else None
                if lab != cur:
                    now = time.time()
                    if cur:
                        windows[-1]["end"] = now
                    if lab:
                        windows.append({"label": lab, "start": now})
                    cur = lab
                if (p.get("step"), p.get("phase")) != getattr(run_suite, "_shown", None):
                    run_suite._shown = (p.get("step"), p.get("phase"))
                    say(log, f"  step {p.get('step')}/{p.get('of')} {p.get('op')} {p.get('phase')} "
                             f"state {p.get('state')} captures {p.get('captures')}")
                if p.get("done"):
                    done = True
                    status = p.get("why") or "finished"
                    if p.get("err"):
                        say(log, "BENCH ERROR:", p["err"])
                        status = "error"
                    break
            # (5 s progress writes while capturing: the stall clock allows for that)
            if time.time() - changed > STALL_S:
                say(log, f"STALL: progress unchanged for {STALL_S} s (last {p})")
                status = "stall"
                break
            if time.time() - t0 > LIMIT_S[kind]:
                say(log, f"TIMEOUT: {LIMIT_S[kind]} s")
                status = "timeout"
                break
    except KeyboardInterrupt:
        status = "interrupted"
    finally:
        if not done:
            # (anything but a clean end: the game put back, every switch and hook restored)
            try:
                say(log, "stop:", lua(f"return erBench.stop('{status}')", timeout=20))
            except SystemExit as e:
                say(log, "stop failed (put the game back by hand: erBench.stop()):", e)
        if pm:
            pm_stop(presentmon, pm)
        info["status"] = status
        info["windows"] = windows
        info["seconds"] = round(time.time() - t0)
        with open(os.path.join(out, "suite.json"), "w", encoding="utf-8") as f:
            json.dump(info, f, indent=1)
    say(log, "suite", name, status, "in", info["seconds"], "s")
    return out, status


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("suite", choices=list(SUITES) + ["full"])
    ap.add_argument("--label", required=True, help="what this build is, e.g. 'baseline 1.6.0-alpha'")
    ap.add_argument("--presentmon", help="path to PresentMon-*.exe (needs admin or Performance Log Users)")
    ap.add_argument("--no-report", action="store_true")
    a = ap.parse_args()
    kinds = ["t1b", "t1", "t2", "t3", "t4", "t5"] if a.suite == "full" else [a.suite]
    worst = 0
    for kind in kinds:
        out, status = run_suite(kind, a.label, a.presentmon)
        if not a.no_report:
            subprocess.run([sys.executable, os.path.join(HERE, "perf_report.py"), out])
        if status != "finished":
            worst = 1
            if status in ("stall", "error", "interrupted"):
                break
    sys.exit(worst)
