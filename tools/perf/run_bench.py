"""Run a performance suite in the running game (docs/perf-plan-1.6.1.md).

    python tools/perf/run_bench.py <suite> --label "what this build is" [--presentmon PATH] [--no-report]

Suites: smoke, quick, t1, t1b, t2, t3, t4, t5, full (t1 .. t5 in one go).

What it does:
  1. loads tools/perf/bench.lua into the game over MCP and starts the suite there;
  2. watches <user>/earthRally/bench/progress.json (a file, never MCP) with a stall timeout and a total timeout;
  3. optionally runs PresentMon beside it (needs admin, or the "Performance Log Users" group);
  4. writes the capture windows (wall clock) next to the captures, then runs perf_report.py.
The car is never driven: it is placed at fixed spots, and the mod is put straight into the state a capture needs."""
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
EV, ST = "ara26-overmountain", "weaver-bend"     # Overmountain Rally 2026, Weaver Bend (6.8 km)
SPOT1, SPOT2 = 2300, 4600
STALL_S = 90           # progress.json unchanged this long: the game has hung or the bench has died
CAP = {"warm": 5, "seconds": 20}


# ------------------------------------------------------------------------------------------------ the suites
def start():
    return [{"op": "start", "event": EV, "stage": ST}]


def at(spot, state, settle=120):
    return [{"op": "spot", "alongM": spot}, {"op": "state", "name": state}, {"op": "settle", "timeout": settle}]


def cap(label, test, state, spot, **kw):
    d = {"op": "capture", "label": label, "test": test, "state": state, "alongM": spot}
    d.update(CAP)
    d.update(kw)
    return d


def floor_here(test, spot, n, prefix):
    """The run aborted where the car stands, traffic kept off as the run had it: the mod idle, same spot."""
    steps = [{"op": "state", "name": "none"}, {"op": "set", "switch": "traffic", "value": "off"},
             {"op": "settle", "timeout": 90}]
    for i in range(n):
        steps.append(cap(f"{prefix}-none-{i + 1}", test, "none", spot, switch="state", value="none", pair=i + 1))
    return steps


def suite_smoke():
    return start() + at(SPOT1, "running") + [cap("smoke-running", "smoke", "running", SPOT1, seconds=5)] + \
        floor_here("smoke", SPOT1, 1, "smoke")


def suite_quick():
    """After every fix: running vs the mod idle at 2.3 km, 3 pairs; one arrival for the spawn spike."""
    steps = []
    for i in range(3):
        steps += start() + at(SPOT1, "running")
        steps.append(cap(f"q-running-{i + 1}", "quick", "running", SPOT1, switch="state", value="running", pair=i + 1))
        steps += floor_here("quick", SPOT1, 1, f"q-{i + 1}")
    steps += start() + [{"op": "arrival", "label": "q-arrival", "test": "quick-arrival", "alongM": SPOT1}]
    return steps + [{"op": "abort"}]


def suite_t1():
    """World or mod: 2 min from arrival, the mod idle vs running, in the order A B B A."""
    steps = []
    for i, state in enumerate(["none", "running", "running", "none"]):
        steps += start() + [{"op": "spot", "alongM": SPOT1}, {"op": "state", "name": state}]
        if state == "none":
            steps.append({"op": "set", "switch": "traffic", "value": "off"})
        steps.append(cap(f"t1-{state}-{i + 1}", "t1", state, SPOT1, warm=0, seconds=120, switch="state", value=state,
                         pair=i + 1))
    return steps + [{"op": "abort"}]


def suite_t1b():
    """Which state costs: waitStart, running, finished, and the mod idle, at 2.3 km; twice."""
    steps = []
    for i in range(2):
        steps += start() + at(SPOT1, "waitStart")
        steps.append(cap(f"t1b-waitStart-{i + 1}", "t1b", "waitStart", SPOT1, switch="state", value="waitStart",
                         pair=i + 1))
        steps += [{"op": "state", "name": "running"}, {"op": "settle", "timeout": 60}]
        steps.append(cap(f"t1b-running-{i + 1}", "t1b", "running", SPOT1, switch="state", value="running", pair=i + 1))
        steps += [{"op": "state", "name": "finished"}, {"op": "wait", "seconds": 8}, {"op": "settle", "timeout": 60}]
        steps.append(cap(f"t1b-finished-{i + 1}", "t1b", "finished", SPOT1, switch="state", value="finished",
                         pair=i + 1))
        steps += floor_here("t1b", SPOT1, 1, f"t1b-{i + 1}")
    return steps + [{"op": "abort"}]


def suite_t2():
    """Where a slow frame goes: Optick and the Lua sampler, running vs the mod idle, 10 s each."""
    steps = start() + at(SPOT1, "running")
    steps.append(cap("t2-running", "t2", "running", SPOT1, seconds=10, optick=True, profile=True))
    steps += [{"op": "dump", "label": "graph-2300"}]
    steps += [{"op": "state", "name": "none"}, {"op": "set", "switch": "traffic", "value": "off"},
              {"op": "settle", "timeout": 90}]
    steps.append(cap("t2-none", "t2", "none", SPOT1, seconds=10, optick=True, profile=True))
    return steps + [{"op": "abort"}]


T3_SWITCHES = [("streams", 30, 1), ("layout", "stage", "plain"), ("notes", True, False), ("props", "shown", "hidden")]


def suite_t3():
    """What GO switches on: one system taken away at a time, A B A B A B, at 2.3 km in running."""
    steps = start() + at(SPOT1, "running")
    for sw, on, off in T3_SWITCHES:
        for i in range(3):
            steps += [{"op": "set", "switch": sw, "value": on}, {"op": "wait", "seconds": 2}]
            steps.append(cap(f"t3-{sw}-on-{i + 1}", "t3", "running", SPOT1, switch=sw, value=on, pair=i + 1))
            steps += [{"op": "set", "switch": sw, "value": off}, {"op": "wait", "seconds": 2}]
            steps.append(cap(f"t3-{sw}-off-{i + 1}", "t3", "running", SPOT1, switch=sw, value=off, pair=i + 1))
        steps += [{"op": "set", "switch": sw, "value": on}, {"op": "wait", "seconds": 2}]
    # the start clock last: once unloaded it is not put back for this run
    steps.append(cap("t3-startClock-loaded-1", "t3", "running", SPOT1, switch="startClock", value="loaded", pair=1))
    steps += [{"op": "set", "switch": "startClock", "value": "unloaded"}, {"op": "wait", "seconds": 2}]
    steps.append(cap("t3-startClock-unloaded-1", "t3", "running", SPOT1, switch="startClock", value="unloaded",
                     pair=1))
    steps += [{"op": "dump", "label": "graph-2300-t3"}]
    steps += floor_here("t3", SPOT1, 2, "t3")
    return steps + [{"op": "abort"}]


def suite_t4():
    """The spawn spikes: 10 s from arrival, 24 vs 2 objects a frame, over both spots."""
    steps = start() + [{"op": "state", "name": "running"}]
    order = [(SPOT1, 24), (SPOT2, 2), (SPOT1, 2), (SPOT2, 24)]
    for i, (spot, dress) in enumerate(order):
        steps.append({"op": "arrival", "label": f"t4-{spot}-dress{dress}", "test": "t4", "alongM": spot,
                      "dress": dress, "pair": i // 2 + 1})
        steps.append({"op": "settle", "timeout": 90, "required": False})
    steps += [{"op": "dump", "label": "graph-4600"}]
    return steps + [{"op": "abort"}]


def suite_t5():
    """After the run: finished at 4.6 km, traffic back on vs off, twice."""
    steps = start() + at(SPOT2, "running")
    steps += [{"op": "state", "name": "finished"}, {"op": "wait", "seconds": 8}, {"op": "settle", "timeout": 90}]
    for i in range(2):
        steps += [{"op": "set", "switch": "traffic", "value": "on"}, {"op": "wait", "seconds": 5}]
        steps.append(cap(f"t5-traffic-on-{i + 1}", "t5", "finished", SPOT2, switch="traffic", value="on", pair=i + 1))
        steps += [{"op": "set", "switch": "traffic", "value": "off"}, {"op": "wait", "seconds": 5}]
        steps.append(cap(f"t5-traffic-off-{i + 1}", "t5", "finished", SPOT2, switch="traffic", value="off",
                         pair=i + 1))
    return steps + [{"op": "abort"}]


SUITES = {"smoke": suite_smoke, "quick": suite_quick, "t1": suite_t1, "t1b": suite_t1b, "t2": suite_t2,
          "t3": suite_t3, "t4": suite_t4, "t5": suite_t5}
LIMIT_S = {"smoke": 600, "quick": 1500, "t1": 1500, "t1b": 1200, "t2": 600, "t3": 1800, "t4": 900, "t5": 900}


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


def run_suite(kind, label, presentmon=None):
    name = f"{kind}-{time.strftime('%Y%m%d-%H%M%S')}"
    out = os.path.join(BENCH, name)
    os.makedirs(out, exist_ok=True)
    log = os.path.join(out, "runner.log")
    steps = SUITES[kind]()
    info = {"suite": name, "kind": kind, "label": label, "date": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "stage": f"{EV}/{ST}", **build_info()}
    say(log, "suite", name, "-", len(steps), "steps -", label, "-", info["commit"], info["installed"])

    pm = None
    if presentmon:
        pm_csv = os.path.join(out, "presentmon.csv")
        pm = subprocess.Popen([presentmon, "--process_name", "BeamNG.drive.x64.exe", "--output_file", pm_csv,
                               "--no_console_stats", "--stop_existing_session"],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        time.sleep(2)
        if pm.poll() is not None:
            say(log, "PresentMon did not start:", (pm.stdout.read() or "")[-300:].strip())
            pm = None
        else:
            info["presentmonStart"] = time.time()

    pf = os.path.join(BENCH, "progress.json")
    try:
        os.remove(pf)
    except OSError:
        pass
    say(log, "bench:", lua(open(os.path.join(HERE, "bench.lua"), encoding="utf-8").read()))
    cfg = {"name": name, "steps": steps}
    try:
        say(log, "start:", lua(f"return erBench.run({json.dumps(json.dumps(cfg))})", timeout=30))
    except SystemExit as e:
        # (the answer can be lost while the suite did start: its progress file says so)
        time.sleep(5)
        if not os.path.exists(pf):
            raise
        say(log, "start: no answer over MCP (", e, "), but the suite is running")

    windows, cur = [], None
    t0, last, changed, p = time.time(), None, time.time(), None
    status = "finished"
    try:
        while True:
            time.sleep(0.25)
            try:
                with open(pf, encoding="utf-8") as f:
                    p = json.load(f)
            except (OSError, ValueError):
                p = p
            if p:
                k = (p.get("t"), p.get("step"))
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
                if p.get("step") and (p.get("step"), p.get("phase")) != getattr(run_suite, "_shown", None):
                    run_suite._shown = (p.get("step"), p.get("phase"))
                    say(log, f"  step {p.get('step')}/{p.get('of')} {p.get('op')} {p.get('phase')} "
                             f"state {p.get('state')} captures {p.get('captures')}")
                if p.get("done"):
                    status = p.get("why") or "finished"
                    if p.get("err"):
                        say(log, "BENCH ERROR:", p["err"])
                        status = "error"
                    break
            if time.time() - changed > STALL_S:
                say(log, f"STALL: progress unchanged for {STALL_S} s (last {p})")
                status = "stall"
                break
            if time.time() - t0 > LIMIT_S[kind]:
                say(log, f"TIMEOUT: {LIMIT_S[kind]} s")
                status = "timeout"
                try:
                    say(log, "stop:", lua("return erBench.stop('timeout')", timeout=20))
                except SystemExit as e:
                    say(log, "stop failed:", e)
                break
    finally:
        if pm:
            pm.terminate()
            try:
                pm.wait(10)
            except subprocess.TimeoutExpired:
                pm.kill()
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
    kinds = ["t1", "t1b", "t2", "t3", "t4", "t5"] if a.suite == "full" else [a.suite]
    worst = 0
    for kind in kinds:
        out, status = run_suite(kind, a.label, a.presentmon)
        if not a.no_report:
            subprocess.run([sys.executable, os.path.join(HERE, "perf_report.py"), out])
        if status not in ("finished",):
            worst = 1
            if status in ("stall", "error"):
                break
    sys.exit(worst)
