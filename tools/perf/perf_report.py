"""Summarise one bench suite and add it to the history (docs/perf-plan-1.6.1.md).

    python tools/perf/perf_report.py <suite folder>      e.g. %LOCALAPPDATA%/BeamNG/BeamNG.drive/current/earthRally/bench/quick-...

Prints each A/B comparison: the median over pairs, the spread between pairs, and a verdict. A difference inside the
spread is "no change": noise is never read as a win. Appends one line per capture to perf/history.jsonl (summaries only;
the frame files stay in the user folder) and rebuilds perf/dashboard.html."""
import csv
import json
import os
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
HISTORY = os.path.join(REPO, "perf", "history.jsonl")
SKIP = {"suite.json", "suite-log.json", "progress.json"}


def load_captures(folder):
    caps = []
    for f in sorted(os.listdir(folder)):
        if not f.endswith(".json") or f in SKIP or f.startswith("graph-"):
            continue
        with open(os.path.join(folder, f), encoding="utf-8") as fh:
            d = json.load(fh)
        if "frames" in d and "label" in d:
            caps.append(d)
    return caps


def presentmon_windows(folder, info):
    """CPUBusy / GPUBusy medians per capture window, when PresentMon ran beside the suite."""
    path = os.path.join(folder, "presentmon.csv")
    start = info.get("presentmonStart")
    if not (os.path.exists(path) and start):
        return {}
    rows = []
    with open(path, newline="", encoding="utf-8", errors="replace") as fh:
        for r in csv.DictReader(fh):
            try:
                t = float(r.get("CPUStartTime") or r.get("TimeInSeconds") or "nan")
                t = t / 1000 if t > 1e5 else t          # (ms in some builds, s in others)
                rows.append((start + t, float(r.get("FrameTime") or r.get("MsBetweenPresents") or "nan"),
                             float(r.get("CPUBusy") or "nan"), float(r.get("GPUBusy") or "nan")))
            except ValueError:
                continue
    out = {}
    for w in info.get("windows", []):
        a, b = w.get("start", 0) + 0.5, w.get("end", 0) - 0.5
        sel = [r for r in rows if a <= r[0] <= b]
        if len(sel) > 20:
            out[w["label"]] = {"frames": len(sel),
                               "frameTime": round(statistics.median(r[1] for r in sel), 2),
                               "cpuBusy": round(statistics.median(r[2] for r in sel), 2),
                               "gpuBusy": round(statistics.median(r[3] for r in sel), 2)}
    return out


def summary(cap, info, pm):
    meta = cap.get("meta") or {}
    eng = {k: v.get("mean") for k, v in (cap.get("engine") or {}).items()}
    hooks = {k: {"max": v.get("maxMs"), "perFrame": v.get("perFrameMs")} for k, v in (cap.get("hooks") or {}).items()}
    ft = cap.get("ft") or []
    step = max(1, len(ft) // 400)                       # (a light trace for the dashboard: ~400 points)
    trace = [max(ft[i:i + step]) for i in range(0, len(ft), step)]
    return {
        "suite": info.get("suite"), "kind": info.get("kind"), "label": info.get("label"), "date": info.get("date"),
        "commit": info.get("commit"), "branch": info.get("branch"), "dirty": info.get("dirty"),
        "installed": info.get("installed"), "stage": info.get("stage"), "status": info.get("status"),
        "capture": cap["label"], "test": meta.get("test"), "spot": meta.get("spot"), "state": cap.get("state"),
        "switch": meta.get("switch"), "value": meta.get("value"), "pair": meta.get("pair"),
        "settleS": meta.get("settleS"), "frames": cap.get("frames"), "mean": cap.get("mean"), "p50": cap.get("p50"),
        "p95": cap.get("p95"), "p99": cap.get("p99"), "max": cap.get("max"), "over33": cap.get("over33"),
        "over50": cap.get("over50"), "seconds": cap.get("seconds"), "gcKBs": cap.get("gcKBs"),
        "counts": cap.get("counts"), "engine": eng, "hooks": hooks, "presentmon": pm.get(cap["label"]),
        "spikes": [{"ms": s.get("ms"), "hooks": s.get("hooks")} for s in (cap.get("spikes") or [])[:40]],
        "trace": trace,
    }


def compare(rows):
    """Group by (test, switch) and compare each value against the first one seen (the base)."""
    groups = {}
    for r in rows:
        key = (r["test"], r["switch"] or "-")
        groups.setdefault(key, {}).setdefault(json.dumps(r["value"]), []).append(r)
    lines = []
    for (test, sw), vals in groups.items():
        items = list(vals.items())
        base_v, base = items[0]
        bp50 = statistics.median(x["p50"] for x in base if x["p50"] is not None)
        bp99 = statistics.median(x["p99"] for x in base if x["p99"] is not None)
        bspread = max(x["p99"] for x in base) - min(x["p99"] for x in base) if len(base) > 1 else None
        lines.append(f"{test:8} {sw:11} {base_v:>10}  p50 {bp50:6.2f}  p99 {bp99:6.2f}  "
                     f"over50 {statistics.median(x['over50'] for x in base):5.0f}  n {len(base)}"
                     + (f"  spread p99 {bspread:.2f}" if bspread is not None else ""))
        for v, xs in items[1:]:
            p50 = statistics.median(x["p50"] for x in xs)
            p99 = statistics.median(x["p99"] for x in xs)
            spread = max(x["p99"] for x in xs) - min(x["p99"] for x in xs) if len(xs) > 1 else None
            noise = max(s for s in (bspread, spread, 0) if s is not None)
            d = p99 - bp99
            verdict = "no change (inside spread)" if (noise and abs(d) <= noise) else (
                "single pair: indicative only" if len(xs) < 2 else ("faster" if d < 0 else "slower"))
            lines.append(f"{'':8} {'':11} {v:>10}  p50 {p50:6.2f}  p99 {p99:6.2f}  "
                         f"over50 {statistics.median(x['over50'] for x in xs):5.0f}  n {len(xs)}  "
                         f"dp99 {d:+.2f} ms  -> {verdict}")
    return lines


def main(folder):
    with open(os.path.join(folder, "suite.json"), encoding="utf-8") as fh:
        info = json.load(fh)
    pm = presentmon_windows(folder, info)
    rows = [summary(c, info, pm) for c in load_captures(folder)]
    if not rows:
        print("no captures in", folder)
        return 1
    print(f"\n{info['suite']}  ({info.get('label')}, {info.get('commit')}, {info.get('status')})")
    for r in rows:
        pmx = r["presentmon"]
        print(f"  {r['capture']:28} {str(r['state']):9} p50 {r['p50']:6.2f} p95 {r['p95']:6.2f} p99 {r['p99']:6.2f} "
              f"max {r['max']:7.2f} over50 {r['over50']:4}  frames {r['frames']}"
              + (f"  cpuBusy {pmx['cpuBusy']} gpuBusy {pmx['gpuBusy']}" if pmx else ""))
    print()
    for line in compare(rows):
        print(line)
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
