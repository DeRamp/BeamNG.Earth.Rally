#!/usr/bin/env python3
"""Store each stage's real weather in a rally pack's event files (docs/plan-rally-loop.md, E).

For every SS row of every event file the pack's manifest names: the hour of its start (`date` + `first_car`, in the
event's `timezone`) at the stage's start point (its line in the pack's map: the start control, else the line's first
point), from Open-Meteo's historical archive (archive-api.open-meteo.com, keyless), or its historical forecast API
for the last few days before today. Written on the row as `weather`, in BeamNG.Earth's own weather message shape
(code, cover, wind, visM, rainMmH, snowCmH, slTempC, fog...), and `weather_source` on the event file. The game never
fetches weather: it uses what is stored here.

    python tools/pack_weather.py "Rally Files/Warden Test Rally V2"
    python tools/pack_weather.py "Rally Files/Warden Test Rally V2" --force     (fetch again rows that have weather)

A rally still in the future gets nothing (the tool says so). Rows that already have weather are left alone unless
--force. Polite: one request per map cell (0.1 degrees) and day, cached for the run, a short timeout, a pause
between requests, User-Agent "EarthRally-pack-weather" and nothing else about you.

derive() follows BeamNG.Earth's server/weather.py derive (MIT License, Copyright (c) 2026 TecnaGamer), changed for
hourly archive data. Weather data by Open-Meteo.com (CC BY 4.0).
"""

import argparse
import datetime as dt
import json
import math
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_kml  # noqa: E402  (the repo's KML reading: the stage lines and their start controls)

ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"
RECENT = "https://historical-forecast-api.open-meteo.com/v1/forecast"
ARCHIVE_LAG_DAYS = 6        # the archive is a few days behind today: newer days come from the historical forecast
HOURLY = ("temperature_2m", "dew_point_2m", "is_day", "precipitation", "rain", "showers", "snowfall", "weather_code",
          "cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high", "surface_pressure",
          "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m", "visibility")
USER_AGENT = "EarthRally-pack-weather"
TIMEOUT_S = 15
PAUSE_S = 1.0               # between two real requests
CELL_DEG = 0.1              # one request per cell and day (BeamNG.Earth's weather cell)
CREDIT = "Open-Meteo.com"

# (from BeamNG.Earth server/weather.py, MIT)
LAPSE = 0.0065
LCL_M_PER_K = 125.0
MID_BASE_M = 3000.0
BASE_MIN_AGL, BASE_MAX_AGL = 200.0, 6000.0
FOG_CODES = (45, 48)
FOG_VIS_M = 800.0
CODE_FLOORS = ((range(51, 58), 0.3, 0.0), (range(61, 68), 1.0, 0.0), (range(80, 83), 1.0, 0.0),
               (range(71, 78), 0.0, 0.5), ((85, 86), 0.0, 0.5), (range(95, 100), 4.0, 0.0))

MANIFESTS = ("season", "rally", "stage")


# --------------------------------------------------------------------------------------------------- weather

def _f(v, default=0.0):
    return float(v) if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) else default


def cloud_base(t, td, low, mid, elev):
    lcl = LCL_M_PER_K * max(0.0, t - td)
    if low >= mid:
        agl = lcl
    else:
        agl = max(elev + lcl, MID_BASE_M) - elev
    agl = min(max(agl, BASE_MIN_AGL), BASE_MAX_AGL)
    return elev + agl, agl


def derive(om, i):
    """BeamNG.Earth's weather message for hour i of an Open-Meteo hourly response (pure), or None when the hour has
    no data. The hourly sums are per hour already (BeamNG.Earth's live data is 15-minutely)."""
    h = om.get("hourly") or {}

    def at(k):
        col = h.get(k)
        return col[i] if isinstance(col, list) and i < len(col) else None

    if at("weather_code") is None or at("temperature_2m") is None:
        return None
    code = int(_f(at("weather_code"), 0))
    t, td = _f(at("temperature_2m"), 15.0), _f(at("dew_point_2m"), 15.0)
    elev = _f(om.get("elevation"), 0.0)
    rain = _f(at("rain")) + _f(at("showers"))
    snow = _f(at("snowfall"))
    if rain == 0 and snow == 0 and _f(at("precipitation")) > 0:
        rain = _f(at("precipitation"))
    for codes, r_min, s_min in CODE_FLOORS:
        if code in codes:
            rain, snow = max(rain, r_min), max(snow, s_min)
    vis = at("visibility")
    vis = _f(vis) if isinstance(vis, (int, float)) and not isinstance(vis, bool) else None
    fog = code in FOG_CODES
    if fog:
        vis = min(vis if vis is not None else FOG_VIS_M, FOG_VIS_M)
    low, mid, high = (_f(at(k)) for k in ("cloud_cover_low", "cloud_cover_mid", "cloud_cover_high"))
    base_asl, base_agl = cloud_base(t, td, low, mid, elev)
    ms = _f(at("wind_speed_10m"))
    msg = {"code": code, "isDay": bool(_f(at("is_day"), 1)),
           "cover": {"total": _f(at("cloud_cover")), "low": low, "mid": mid, "high": high},
           "baseM": round(base_asl, 1), "baseAglM": round(base_agl, 1),
           "rainMmH": round(rain, 3), "snowCmH": round(snow, 3),
           "visM": None if vis is None else round(vis, 1), "fog": fog, "thunder": code >= 95,
           "wind": {"ms": ms, "fromDeg": _f(at("wind_direction_10m")), "gustMs": max(ms, _f(at("wind_gusts_10m"), ms))},
           "tempC": t, "dewC": td, "elevM": elev, "slTempC": round(t + LAPSE * elev, 2),
           "pressureHpa": _f(at("surface_pressure"), 1013.25)}
    if msg["visM"] is None:
        del msg["visM"]           # (no visibility in the archive: BeamNG.Earth's default)
    return msg


def cell(lat, lon):
    return (round(round(lat / CELL_DEG) * CELL_DEG, 4), round(round(lon / CELL_DEG) * CELL_DEG, 4))


def url(api, lat, lon, date, tz):
    q = {"latitude": f"{lat:.4f}", "longitude": f"{lon:.4f}", "start_date": date, "end_date": date,
         "hourly": ",".join(HOURLY), "timezone": tz or "auto", "wind_speed_unit": "ms", "cell_selection": "land"}
    return api + "?" + urllib.parse.urlencode(q, safe=",/")


def http_json(u):
    req = urllib.request.Request(u, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=TIMEOUT_S) as r:
        return json.loads(r.read().decode("utf-8"))


class Fetcher:
    """One request per (api, cell, day, zone), cached for the run. get_json is injectable (the tests: no network)."""

    def __init__(self, get_json=http_json, pause_s=PAUSE_S):
        self.get_json, self.pause_s = get_json, pause_s
        self.cache, self.requests, self.last = {}, 0, 0.0

    def day(self, api, lat, lon, date, tz):
        c = cell(lat, lon)
        k = (api, c, date, tz)
        if k not in self.cache:
            wait = self.pause_s - (time.monotonic() - self.last)
            if self.requests and wait > 0:
                time.sleep(wait)
            self.requests += 1
            try:
                self.cache[k] = self.get_json(url(api, c[0], c[1], date, tz))
            except (urllib.error.URLError, OSError, ValueError) as e:
                self.cache[k] = e
            self.last = time.monotonic()
        v = self.cache[k]
        if isinstance(v, Exception):
            raise v
        return v

    def hour(self, lat, lon, date, hh, tz, today):
        """(message, which api) for the local hour hh of date at (lat, lon): the archive, else (recent days, or
        an hour the archive has no data for yet) the historical forecast."""
        d = dt.date.fromisoformat(date)
        apis = [ARCHIVE, RECENT] if (today - d).days > ARCHIVE_LAG_DAYS else [RECENT, ARCHIVE]
        last_err = None
        for api in apis:
            try:
                om = self.day(api, lat, lon, date, tz)
            except Exception as e:  # noqa: BLE001  (one host down: try the other)
                last_err = e
                continue
            times = (om.get("hourly") or {}).get("time") or []
            key = f"{date}T{hh:02d}:00"
            if key in times:
                msg = derive(om, times.index(key))
                if msg:
                    return msg, ("archive" if api == ARCHIVE else "historical forecast")
        if last_err:
            raise last_err
        return None, None


# --------------------------------------------------------------------------------------------------- the pack

def pack_root(folder):
    """The pack's root (the folder, or the one folder inside it) and its manifest: (root, path, kind, data)."""
    def manifest_in(d):
        found = []
        for n in sorted(os.listdir(d)):
            p = os.path.join(d, n)
            if not (n.lower().endswith(".json") and os.path.isfile(p)):
                continue
            try:
                with open(p, encoding="utf-8") as f:
                    data = json.load(f)
            except (OSError, ValueError):
                continue
            kind = data.get("kind") if isinstance(data, dict) else None
            if kind not in MANIFESTS:
                stem = n[:-5].lower()
                kind = stem if stem in MANIFESTS and isinstance(data, dict) and not data.get("kind") else None
            if kind:
                found.append((p, kind, data))
        return found

    found = manifest_in(folder)
    if not found:
        inner = [n for n in os.listdir(folder) if not n.startswith(".") and n != "__MACOSX"]
        if len(inner) == 1 and os.path.isdir(os.path.join(folder, inner[0])):
            folder = os.path.join(folder, inner[0])
            found = manifest_in(folder)
    if len(found) != 1:
        raise SystemExit(f"{folder}: {'no' if not found else 'more than one'} manifest (season / rally / stage)")
    p, kind, data = found[0]
    return folder, p, kind, data


def rallies_of(root, kind, data):
    """[(name, map path, event path)] of every rally in the pack that has an event file."""
    def inside(base, rel):
        if not isinstance(rel, str) or not rel:
            return None
        p = os.path.normpath(os.path.join(base, rel.replace("\\", "/")))
        return p if os.path.commonpath([p, os.path.normpath(root)]) == os.path.normpath(root) else None

    out = []

    def rally(base, spec, name=None):
        if not isinstance(spec, dict):
            return
        if isinstance(spec.get("rally"), str):
            p = inside(base, spec["rally"])
            if p and os.path.isfile(p):
                with open(p, encoding="utf-8") as f:
                    sub = json.load(f)
                rally(os.path.dirname(p), sub, spec.get("name") or name)
            return
        m, e = inside(base, spec.get("map")), inside(base, spec.get("event"))
        if m and e and os.path.isfile(m) and os.path.isfile(e):
            out.append((spec.get("name") or name or os.path.basename(e), m, e))

    if kind == "season":
        for r in data.get("rounds") or []:
            rally(root, r)
    elif kind == "rally":
        rally(root, data)
    return out


def stage_starts(map_path):
    """{line name: (lat, lon)}: each stage's start control, else its line's first point (in driving order)."""
    event, _ = import_kml.build_event(map_path, "pack-weather", "pack-weather")
    out = {}
    for s in event["stages"]:
        c = s["controls"].get("start")
        out.setdefault(s["name"], (c["lat"], c["lon"]) if c else tuple(s["line"][0]))
    return out


def start_of(row):
    """(date, local hour) of an SS row's start, or None."""
    date, fc = row.get("date"), row.get("first_car")
    if not (isinstance(date, str) and isinstance(fc, str)):
        return None
    try:
        dt.date.fromisoformat(date)
        hh = int(fc.split(":")[0])
    except ValueError:
        return None
    return (date, hh) if 0 <= hh <= 23 else None


def fill_event(ev, starts, fetcher, today, force=False, say=print):
    """Weather written on the event's SS rows (in place). Returns (rows given weather, rows that had it, rows left
    without, future: bool)."""
    tz = (ev.get("event") or {}).get("timezone")
    got = had = none = 0
    future = False
    apis = set()
    lower = {k.lower(): v for k, v in starts.items()}
    for row in ev.get("itinerary") or []:
        if not (isinstance(row, dict) and row.get("type") == "SS"):
            continue
        tag = f"{row.get('control')} {row.get('stage')}"
        if isinstance(row.get("weather"), dict) and not force:
            had += 1
            continue
        st = start_of(row)
        pt = starts.get(row.get("stage")) or lower.get(str(row.get("stage") or "").lower())
        if not st:
            say(f"  {tag}: no date or first car time: no weather")
            none += 1
            continue
        if not pt:
            say(f"  {tag}: no line of that name in the map: no weather")
            none += 1
            continue
        if dt.date.fromisoformat(st[0]) >= today:
            future = True
            none += 1
            continue
        try:
            msg, api = fetcher.hour(pt[0], pt[1], st[0], st[1], tz, today)
        except Exception as e:  # noqa: BLE001
            say(f"  {tag}: the weather could not be fetched ({e}): left without")
            none += 1
            continue
        if not msg:
            say(f"  {tag}: no weather for {st[0]} {st[1]:02d}:00: left without")
            none += 1
            continue
        row["weather"] = msg
        apis.add(api)
        got += 1
    if got:
        ev["weather_source"] = f"{CREDIT}, {' and '.join(sorted(apis))}, fetched {today.isoformat()}"
    return got, had, none, future


def run(folder, force=False, fetcher=None, today=None, say=print):
    """Every event file of the pack given its weather. Returns {rally name: rows given weather}."""
    fetcher = fetcher or Fetcher()
    today = today or dt.date.today()
    root, _, kind, data = pack_root(folder)
    counts = {}
    for name, map_path, ev_path in rallies_of(root, kind, data):
        with open(ev_path, encoding="utf-8") as f:
            raw = f.read()
        ev = json.loads(raw)
        say(f"{name}:")
        got, had, none, future = fill_event(ev, stage_starts(map_path), fetcher, today, force, say)
        if future:
            say("  still in the future: no weather to store yet (the game keeps the player's own)")
        if got:
            text = json.dumps(ev, indent=2, ensure_ascii=False) + ("\n" if raw.endswith("\n") else "")
            with open(ev_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
        say(f"  {got} rows given weather" + (f", {had} had it already" if had else "")
            + (f", {none} without" if none else ""))
        counts[name] = got
    say(f"{fetcher.requests} requests")
    return counts


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pack", help="the pack's folder (unzipped)")
    ap.add_argument("--force", action="store_true", help="fetch again the rows that already have weather")
    args = ap.parse_args()
    if not os.path.isdir(args.pack):
        raise SystemExit(f"{args.pack}: not a folder (unzip the pack first)")
    run(args.pack, force=args.force)
    return 0


if __name__ == "__main__":
    sys.exit(main())
