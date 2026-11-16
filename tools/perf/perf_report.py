"""Summarise one bench suite and add it to the history (docs/perf-plan-1.6.1.md).

    python tools/perf/perf_report.py <suite folder>      e.g. %LOCALAPPDATA%/BeamNG/BeamNG.drive/current/earthRally/bench/quick-...

Prints each A/B comparison and appends one line per complete capture to perf/history.jsonl (summaries only; the frame
files stay in the user folder), then rebuilds perf/dashboard.html.

The verdict (compare()): within one test and switch, the base is the value whose captures say base=True. For each pair
number, d = (the other value's p99) - (the base's p99). A change is real only when there are at least two pairs, every
pair's d has the same sign, and the median d is larger than the spread of the base's own p99 over its pairs.
Anything else is "no change" (grey on the dashboard), so noise is never read as a win. Captures cut short (a stopped
suite) are left out."""
import csv
import json
import os
import statistics
import subprocess
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
HISTORY = os.path.join(REPO, "perf", "history.jsonl")
SKIP = {"suite.json", "suite-log.json", "progress.json"}


def med(xs):
    xs = [x for x in xs if x is not None]
    return round(statistics.median(xs), 2) if xs else None


def load_captures(folder):
    caps, dropped = [], []
    for f in sorted(os.listdir(folder)):
        if not f.endswith(".json") or f in SKIP or f.startswith("graph-"):
            continue
        with open(os.path.join(folder, f), encoding="utf-8") as fh:
            d = json.load(fh)
        if "frames" not in d or "label" not in d:
            continue
        if not d.get("frames") or d.get("p99") is None or d.get("complete") is False:
            dropped.append(d["label"])
            continue
        caps.append(d)
    return caps, dropped


def _pm_time(r):
    s = r.get("CPUStartDateTime") or r.get("CPUStartTime") or ""
    for fmt in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(s.strip()[:26], fmt).timestamp()
        except ValueError:
            pass
    return None


def presentmon_windows(folder, info):
    """CPUBusy / GPUBusy medians per capture window, when PresentMon ran beside the suite (--date_time rows)."""
    path = os.path.join(folder, "presentmon.csv")
    if not os.path.exists(path):
        return {}
    rows = []
    with open(path, newline="", encoding="utf-8", errors="replace") as fh:
        for r in csv.DictReader(fh):
            t = _pm_time(r)
            try:
                rows.append((t, float(r.get("FrameTime") or r.get("MsBetweenPresents") or "nan"),
                             float(r.get("CPUBusy") or "nan"), float(r.get("GPUBusy") or "nan")))
            except ValueError:
                continue
    rows = [r for r in rows if r[0] is not None]
    out = {}
    for w in info.get("windows", []):
        a, b = w.get("start", 0) + 0.5, (w.get("end") or 0) - 0.5
        sel = [r for r in rows if a <= r[0] <= b]
        if len(sel) > 20:
            out[w["label"]] = {"frames": len(sel), "frameTime": med(r[1] for r in sel),
                               "cpuBusy": med(r[2] for r in sel), "gpuBusy": med(r[3] for r in sel)}
    return out


def summary(cap, info, pm):
    meta = cap.get("meta") or {}
    eng = {k: v.get("mean") for k, v in (cap.get("engine") or {}).items()}
    hooks = {k: {"max": v.get("maxMs"), "perFrame": v.get("perFrameMs")} for k, v in (cap.get("hooks") or {}).items()}
    ft = cap.get("ft") or []
    step = max(1, len(ft) // 300)                       # (a light trace for the dashboard: ~300 points, worst of each)
    trace = [max(ft[i:i + step]) for i in range(0, len(ft), step)]
    return {
        "suite": info.get("suite"), "kind": info.get("kind"), "label": info.get("label"), "date": info.get("date"),
        "commit": info.get("commit"), "branch": info.get("branch"), "dirty": info.get("dirty"),
        "installed": info.get("installed"), "stage": info.get("stage"), "status": info.get("status"),
        "capture": cap["label"], "test": meta.get("test"), "spot": meta.get("spot"), "state": cap.get("state"),
        "switch": meta.get("switch"), "value": meta.get("value"), "pair": meta.get("pair"),
        "base": bool(meta.get("base")), "settleS": meta.get("settleS"), "groundS": meta.get("groundS"),
        "layout": meta.get("layout"), "startClock": meta.get("startClock"), "quality": cap.get("quality"), "display": cap.get("display"), "loading": meta.get("loading"),
        "frames": cap.get("frames"), "mean": cap.get("mean"), "p50": cap.get("p50"),
        "p95": cap.get("p95"), "p99": cap.get("p99"), "max": cap.get("max"), "over33": cap.get("over33"),
        "over50": cap.get("over50"), "seconds": cap.get("seconds"), "gcKBs": cap.get("gcKBs"),
        "counts": cap.get("counts"), "engine": eng, "hooks": hooks, "presentmon": pm.get(cap["label"]),
        "spikes": [{"ms": s.get("ms"), "hooks": s.get("hooks")} for s in (cap.get("spikes") or [])[:20]],
        "trace": trace,
    }


def compare(rows):
    """One result per (suite, test, switch, value != base). See the module docstring for the rule."""
    out = []
    groups = {}
    for r in rows:
        if r.get("p99") is None:
            continue
        groups.setdefault((r.get("suite"), r.get("test"), r.get("switch") or "-"), []).append(r)
    for (suite, test, sw), rs in groups.items():
        base_vals = {json.dumps(r.get("value")) for r in rs if r.get("base")}
        base_key = next(iter(base_vals)) if len(base_vals) == 1 else json.dumps(rs[0].get("value"))
        base = [r for r in rs if json.dumps(r.get("value")) == base_key]
        by_pair_base = {}
        for r in base:
            by_pair_base.setdefault(r.get("pair"), []).append(r["p99"])
        bp99 = med(r["p99"] for r in base)
        bspread = (max(r["p99"] for r in base) - min(r["p99"] for r in base)) if len(base) > 1 else None
        others = {}
        for r in rs:
            k = json.dumps(r.get("value"))
            if k != base_key:
                others.setdefault(k, []).append(r)
        for k, xs in others.items():
            ds = []
            for r in xs:
                b = by_pair_base.get(r.get("pair"))
                if b:
                    ds.append(r["p99"] - statistics.mean(b))
            p99 = med(r["p99"] for r in xs)
            d = med(ds) if ds else (round(p99 - bp99, 2) if p99 is not None and bp99 is not None else None)
            noise = bspread or 0
            if len(ds) < 2:
                verdict = "single"
            elif not (all(x > 0 for x in ds) or all(x < 0 for x in ds)) or abs(d) <= noise:
                verdict = "nochange"
            else:
                verdict = "faster" if d < 0 else "slower"
            out.append({"suite": suite, "label": rs[0].get("label"), "commit": rs[0].get("commit"), "test": test,
                        "switch": sw, "base": json.loads(base_key), "value": json.loads(k), "baseP99": bp99,
                        "p99": p99, "baseP50": med(r["p50"] for r in base), "p50": med(r["p50"] for r in xs),
                        "d": d, "dMin": round(min(ds), 2) if ds else None, "dMax": round(max(ds), 2) if ds else None,
                        "noise": round(noise, 2), "n": len(ds), "verdict": verdict})
    return out


VERDICT = {"faster": "faster", "slower": "slower", "nochange": "no change (pairs disagree or inside spread)",
           "single": "one pair only: indicative"}


def f2(x, w=6):
    return f"{x:{w}.2f}" if isinstance(x, (int, float)) else f"{'-':>{w}}"


def main(folder):
    with open(os.path.join(folder, "suite.json"), encoding="utf-8") as fh:
        info = json.load(fh)
    pm = presentmon_windows(folder, info)
    caps, dropped = load_captures(folder)
    rows = [summary(c, info, pm) for c in caps]
    print(f"\n{info['suite']}  ({info.get('label')}, {info.get('commit')}, {info.get('status')})")
    if dropped:
        print("  left out (cut short):", ", ".join(dropped))
    if not rows:
        print("  no complete captures")
        return 1
    for r in rows:
        pmx = r["presentmon"]
        print(f"  {r['capture']:30} {str(r['state']):9} p50 {f2(r['p50'])} p95 {f2(r['p95'])} p99 {f2(r['p99'])} "
              f"max {f2(r['max'], 7)} over50 {r['over50']:4}  frames {r['frames']}"
              + (f"  cpuBusy {pmx['cpuBusy']} gpuBusy {pmx['gpuBusy']}" if pmx else ""))
    print()
    for c in compare(rows):
        print(f"  {c['test']:14} {c['switch']:10} {str(c['base']):>9} -> {str(c['value']):<9} "
              f"p99 {f2(c['baseP99'])} -> {f2(c['p99'])}  d {f2(c['d'])} [{f2(c['dMin'])}, {f2(c['dMax'])}] "
              f"spread {f2(c['noise'])} n {c['n']}  {VERDICT[c['verdict']]}")
    os.makedirs(os.path.dirname(HISTORY), exist_ok=True)
    seen = set()
    if os.path.exists(HISTORY):
        with open(HISTORY, encoding="utf-8") as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                    seen.add((d.get("suite"), d.get("capture")))
                except ValueError:
                    pass
    added = 0
    with open(HISTORY, "a", encoding="utf-8") as fh:
        for r in rows:
            if (r["suite"], r["capture"]) not in seen:
                fh.write(json.dumps(r, separators=(",", ":")) + "\n")
                added += 1
    print(f"\n{added} captures added to {os.path.relpath(HISTORY, REPO)}")
    subprocess.run([sys.executable, os.path.join(HERE, "perf_dashboard.py")])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
