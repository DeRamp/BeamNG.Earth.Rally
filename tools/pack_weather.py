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

A hand-made pack (rally.txt or season.txt, docs/making-rally-packs.md) gets a weather.csv beside each rally.txt
instead, from its running order's times. Its .txt files are read by the mod's own reader (textPack.lua), under
LuaJIT through lupa (pip install lupa), so the tool and the game cannot read them differently.

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
LUA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "mod", "earth_rally", "lua", "ge",
                   "extensions")
# (weather.csv's columns, as textPack.lua reads them back: Sky and the hand-made ones first, then the real weather's)
WX_COLUMNS = ("SS", "Stage", "Sky", "Code", "Daylight", "Cloud %", "Low cloud %", "Mid cloud %", "High cloud %",
              "Wind m/s", "Gust m/s", "Wind from", "Temp C", "Sea level temp C", "Dew C", "Rain mm/h", "Snow cm/h",
              "Fog", "Thunder", "Visibility m", "Cloud base m", "Cloud base above ground m", "Elevation m",
              "Pressure hPa")
SKY_WORDS = ((0, "clear"), (1, "mainly clear"), (2, "partly cloudy"), (3, "overcast"), (45, "fog"), (48, "fog"),
             (51, "drizzle"), (53, "drizzle"), (55, "drizzle"), (56, "drizzle"), (57, "drizzle"), (61, "light rain"),
             (63, "rain"), (65, "heavy rain"), (66, "light rain"), (67, "heavy rain"), (71, "light snow"),
             (73, "snow"), (75, "heavy snow"), (77, "light snow"), (80, "light rain"), (81, "rain"),
             (82, "heavy rain"), (85, "light snow"), (86, "heavy snow"), (95, "thunder"), (96, "thunder"),
             (99, "thunder"))


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


# --------------------------------------------------------------------------------------------------- hand-made packs

def text_root(folder):
    """The folder holding a hand-made pack's season.txt / rally.txt (the folder, or the one folder inside it), else
    None."""
    def has(d):
        for n in os.listdir(d):
            stem = n.lower()
            while stem.endswith(".txt"):
                stem = stem[:-4]
            if stem in ("season", "rally") and os.path.isfile(os.path.join(d, n)):
                return True
        return False
    if has(folder):
        return folder
    inner = [n for n in os.listdir(folder) if not n.startswith(".") and n != "__MACOSX"]
    if len(inner) == 1 and os.path.isdir(os.path.join(folder, inner[0])) and has(os.path.join(folder, inner[0])):
        return os.path.join(folder, inner[0])
    return None


def text_rallies(root):
    """[(name, map path, SS rows, weather.csv path)] of a hand-made pack: read by textPack.lua, as the game reads it."""
    try:
        import lupa.luajit21 as lj
    except ImportError:
        raise SystemExit("reading rally.txt needs lupa: pip install lupa")
    lua = lj.LuaRuntime()
    lua.execute("package.path = ... .. '/?.lua;' .. package.path", LUA.replace("\\", "/"))
    lua.execute("function log() end")
    files = []
    for d, _, names in os.walk(root):
        for n in names:
            files.append(os.path.relpath(os.path.join(d, n), root).replace(os.sep, "/"))
    files.sort()

    def read(rel):
        try:
            with open(os.path.join(root, rel), "rb") as f:
                return f.read()
        except OSError:
            return None
    make = lua.eval("""function(all, read)
      local R = require('earthRally/textRead')
      local imp = require('earthRally/importer')
      local tp = require('earthRally/textPack')
      local list = {}
      for i = 1, #all do list[i] = all[i] end
      local ctx = { all = list,
        readText = function(rel) return R.text(read(rel)) end,
        parseMap = function(rel)
          local s = read(rel)
          if not s then return nil, 'no ' .. rel end
          if rel:lower():match('%.kmz$') then return nil, 'a .kmz: save the map as .kml for this tool' end
          local ok, p = pcall(imp.parse, s, rel:lower():match('%.gpx$') and 'gpx' or 'kml')
          if ok then return p end
          return nil, tostring(p)
        end }
      local m, _, why = tp.read(ctx)
      if not m then return nil, why and why.what or 'no rally.txt or season.txt' end
      local out = {}
      local specs = m.kind == 'season' and m.data.rounds or { m.data }
      for _, spec in ipairs(specs) do
        local ev = spec.event and m.virtual[spec.event]
        if spec.map and ev then
          local rows = {}
          for _, r in ipairs(ev.itinerary or {}) do
            if r.type == 'SS' then rows[#rows + 1] = { control = r.control, stage = r.stage, date = r.date,
              first_car = r.first_car } end
          end
          out[#out + 1] = { name = spec.name or spec.map, map = spec.map, rows = rows,
            dir = spec.event:gsub('#event$', ''):match('^(.*)/[^/]*$') or '',
            timezone = ev.event and ev.event.timezone or nil }
        end
      end
      return out, nil
    end""")
    res, why = make(lua.table_from(files), lambda rel: read(rel))
    if res is None:
        raise SystemExit(f"{root}: {why}")
    out = []
    for i in range(1, len(res) + 1):
        r = res[i]
        rows = []
        for j in range(1, len(r.rows) + 1):
            x = r.rows[j]
            rows.append({"type": "SS", "control": x.control, "stage": x.stage, "date": x.date, "first_car": x.first_car})
        ev = {"event": {"timezone": r.timezone} if r.timezone else {}, "itinerary": rows}
        out.append((r.name, os.path.join(root, r.map), ev, os.path.join(root, r.dir, "weather.csv")))
    return out


def sky_word(code):
    best = None
    for c, w in SKY_WORDS:
        if c == code:
            return w
        if c <= code:
            best = w
    return best or "overcast"


def read_weather_csv(path):
    """(the # lines kept, {SS: the row as written}) of an existing weather.csv, or ([], {})."""
    if not os.path.isfile(path):
        return [], {}
    notes, rows = [], {}
    with open(path, encoding="utf-8-sig", newline="") as f:
        lines = f.read().splitlines()
    import csv
    body = [ln for ln in lines if ln.strip() and not ln.lstrip().startswith("#")]
    notes = [ln for ln in lines if ln.lstrip().startswith("#") and "Open-Meteo" not in ln]
    if not body:
        return notes, rows
    delim = max((",", ";", "\t"), key=lambda d: body[0].count(d))
    reader = csv.reader(body, delimiter=delim)
    header = next(reader)
    for cells in reader:
        row = dict(zip(header, cells))
        ss = (row.get("SS") or "").strip().upper().replace(" ", "")
        if ss:
            rows[ss] = row
    return notes, rows


def weather_row(control, stage, w):
    def n(v):
        return "" if v is None else (f"{v:g}" if isinstance(v, (int, float)) and not isinstance(v, bool) else str(v))
    cover, wind = w.get("cover") or {}, w.get("wind") or {}
    return {"SS": control, "Stage": stage, "Sky": sky_word(int(w.get("code", 3))), "Code": n(w.get("code")),
            "Daylight": "yes" if w.get("isDay", True) else "no", "Cloud %": n(cover.get("total")),
            "Low cloud %": n(cover.get("low")), "Mid cloud %": n(cover.get("mid")), "High cloud %": n(cover.get("high")),
            "Wind m/s": n(wind.get("ms")), "Gust m/s": n(wind.get("gustMs")), "Wind from": n(wind.get("fromDeg")),
            "Temp C": n(w.get("tempC")), "Sea level temp C": n(w.get("slTempC")), "Dew C": n(w.get("dewC")),
            "Rain mm/h": n(w.get("rainMmH")), "Snow cm/h": n(w.get("snowCmH")), "Fog": "yes" if w.get("fog") else "no",
            "Thunder": "yes" if w.get("thunder") else "no", "Visibility m": n(w.get("visM")),
            "Cloud base m": n(w.get("baseM")), "Cloud base above ground m": n(w.get("baseAglM")),
            "Elevation m": n(w.get("elevM")), "Pressure hPa": n(w.get("pressureHpa"))}


def run_text(root, force, fetcher, today, say):
    """A hand-made pack: weather.csv written beside each rally.txt. Returns {rally name: rows given weather}."""
    import csv
    import io
    counts = {}
    for name, map_path, ev, wx_path in text_rallies(root):
        say(f"{name}:")
        notes, old = read_weather_csv(wx_path)
        # (rows already in weather.csv count as had, unless --force)
        for row in ev["itinerary"]:
            if not force and row["control"] in old:
                row["weather"] = {"kept": True}
        got, had, none, future = fill_event(ev, stage_starts(map_path), fetcher, today, force, say)
        if future:
            say("  still in the future: no weather to store yet (the game keeps the player's own)")
        if got:
            by = {}
            for row in ev["itinerary"]:
                w = row.get("weather")
                if w and not w.get("kept"):
                    by[row["control"]] = weather_row(row["control"], row.get("stage") or "", w)
            merged = dict(old)
            merged.update(by)
            order = [r["control"] for r in ev["itinerary"] if r["control"] in merged]
            order += [k for k in merged if k not in order]
            buf = io.StringIO()
            for ln in notes or ["# EARTH RALLY - WEATHER: each stage's weather. A stage that isn't listed has the "
                                "player's own weather."]:
                buf.write(ln + "\n")
            buf.write(f"# Weather data by {ev.get('weather_source', CREDIT)} (CC BY 4.0)\n")
            wr = csv.DictWriter(buf, fieldnames=list(WX_COLUMNS), extrasaction="ignore", lineterminator="\n")
            wr.writeheader()
            for k in order:
                wr.writerow({c: merged[k].get(c, "") for c in WX_COLUMNS})
            with open(wx_path, "w", encoding="utf-8", newline="") as f:
                f.write(buf.getvalue())
        say(f"  {got} stages given weather" + (f", {had} had it already" if had else "")
            + (f", {none} without" if none else ""))
        counts[name] = got
    say(f"{fetcher.requests} requests")
    return counts


def run(folder, force=False, fetcher=None, today=None, say=print):
    """Every event file of the pack given its weather. Returns {rally name: rows given weather}."""
    fetcher = fetcher or Fetcher()
    today = today or dt.date.today()
    troot = text_root(folder)
    if troot:
        return run_text(troot, force, fetcher, today, say)
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
