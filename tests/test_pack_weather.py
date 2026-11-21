#!/usr/bin/env python3
"""tools/pack_weather.py, offline: a made-up pack (a made-up map and event file in a temporary folder) and a made-up
Open-Meteo archive response, no network."""
import datetime as dt
import json
import os
import sys
import tempfile
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))

KML = """<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
<Placemark><name>Alpha</name><LineString><coordinates>
10.000,50.000,0 10.010,50.000,0 10.020,50.000,0
</coordinates></LineString></Placemark>
<Placemark><name>Start Alpha</name><Point><coordinates>10.020,50.000,0</coordinates></Point></Placemark>
<Placemark><name>Beta</name><LineString><coordinates>
11.000,51.000,0 11.010,51.000,0
</coordinates></LineString></Placemark>
</Document></kml>
"""


def made_up_day(date, code=3, temp=10.0, elev=200.0):
    hours = [f'{date}T{h:02d}:00' for h in range(24)]

    def col(v):
        return [v] * 24
    return {'latitude': 50.0, 'longitude': 10.0, 'elevation': elev, 'timezone': 'Europe/Berlin',
            'hourly': {'time': hours, 'temperature_2m': [temp + h for h in range(24)], 'dew_point_2m': col(temp - 2),
                       'is_day': [1 if 7 <= h < 17 else 0 for h in range(24)], 'precipitation': col(0.0),
                       'rain': col(0.0), 'showers': col(None), 'snowfall': col(0.0), 'weather_code': col(code),
                       'cloud_cover': col(90.0), 'cloud_cover_low': col(80.0), 'cloud_cover_mid': col(40.0),
                       'cloud_cover_high': col(10.0), 'surface_pressure': col(1000.0), 'wind_speed_10m': col(4.0),
                       'wind_direction_10m': col(250.0), 'wind_gusts_10m': col(9.0), 'visibility': col(None)}}


def main():
    import pack_weather as pw
    failed = 0

    def check(ok, what):
        nonlocal failed
        print(('ok    ' if ok else 'FAIL  ') + what)
        if not ok:
            failed += 1

    # derive: the message BeamNG.Earth's weather.lua reads
    m = pw.derive(made_up_day('2026-01-10', code=63), 14)
    check(m['code'] == 63 and m['rainMmH'] == 1.0, 'a rain code with no rain sum: the floor, as BeamNG.Earth does')
    check(m['tempC'] == 24.0 and m['slTempC'] == round(24.0 + 0.0065 * 200, 2), 'the temperature, and at sea level')
    check(m['cover'] == {'total': 90.0, 'low': 80.0, 'mid': 40.0, 'high': 10.0}, 'the cloud cover')
    check(m['wind'] == {'ms': 4.0, 'fromDeg': 250.0, 'gustMs': 9.0}, 'the wind')
    check('visM' not in m and m['fog'] is False and m['isDay'] is True, 'no visibility in the archive: left out')
    check(pw.derive(made_up_day('2026-01-10'), 20)['isDay'] is False, 'night')
    fog = pw.derive(made_up_day('2026-01-10', code=45), 8)
    check(fog['fog'] and fog['visM'] == 800.0, 'a fog code: fog, visibility at most 800 m')
    day = made_up_day('2026-01-10')
    day['hourly']['weather_code'][5] = None
    check(pw.derive(day, 5) is None, 'an hour with no data: none')

    # the pack
    calls = []

    def fake(u):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(u).query)
        calls.append((u.split('?')[0], q))
        return made_up_day(q['start_date'][0])

    with tempfile.TemporaryDirectory() as tmp:
        pack = Path(tmp) / 'Made Up Pack'
        (pack / 'events').mkdir(parents=True)
        (pack / 'map.kml').write_text(KML, encoding='utf-8')
        (pack / 'season.json').write_text(json.dumps({'format': 1, 'name': 'Made Up', 'rounds': [
            {'round': 1, 'name': 'Made Up Rally', 'map': 'map.kml', 'event': 'events/e.json'},
            {'round': 2, 'name': 'Future Rally', 'map': 'map.kml', 'event': 'events/f.json'}]}), encoding='utf-8')
        ev = {'format': 1, 'event': {'name': 'Made Up Rally', 'timezone': 'Europe/Berlin'}, 'itinerary': [
            {'type': 'MTC_OUT', 'control': 'TC0', 'date': '2026-01-10', 'first_car': '08:00'},
            {'type': 'SS', 'control': 'SS1', 'stage': 'Alpha', 'date': '2026-01-10', 'first_car': '09:35'},
            {'type': 'SS', 'control': 'SS2', 'stage': 'alpha', 'date': '2026-01-10', 'first_car': '09:50'},
            {'type': 'SS', 'control': 'SS3', 'stage': 'Beta', 'date': '2026-01-10', 'first_car': '14:05'},
            {'type': 'SS', 'control': 'SS4', 'stage': 'Gamma', 'date': '2026-01-10', 'first_car': '15:00'},
            {'type': 'SS', 'control': 'SS5', 'stage': 'Alpha', 'date': '2026-01-11', 'first_car': '10:00',
             'weather': {'code': 0}}]}
        (pack / 'events' / 'e.json').write_text(json.dumps(ev, indent=2) + '\n', encoding='utf-8')
        fut = {'format': 1, 'event': {'timezone': 'Europe/Berlin'}, 'itinerary': [
            {'type': 'SS', 'control': 'SS1', 'stage': 'Alpha', 'date': '2026-12-01', 'first_car': '09:00'}]}
        (pack / 'events' / 'f.json').write_text(json.dumps(fut), encoding='utf-8')

        said = []
        fetcher = pw.Fetcher(get_json=fake, pause_s=0)
        counts = pw.run(str(pack), fetcher=fetcher, today=dt.date(2026, 11, 19), say=said.append)
        out = json.loads((pack / 'events' / 'e.json').read_text(encoding='utf-8'))
        rows = {r['control']: r for r in out['itinerary']}
        check(counts == {'Made Up Rally': 3, 'Future Rally': 0}, 'three stages given weather, none in the future')
        check(rows['SS1']['weather']['tempC'] == 19.0, "the hour of the start (09:35 -> 09:00's)")
        check(rows['SS3']['weather']['tempC'] == 24.0, 'and the next stage its own')
        check('weather' not in rows['SS4'] and any('SS4 Gamma' in s for s in said), 'no line of that name: none, said')
        check(rows['SS5']['weather'] == {'code': 0}, 'a row with weather left alone')
        check('weather' not in rows['TC0'], 'only SS rows')
        check(out['weather_source'].startswith('Open-Meteo.com, archive, fetched 2026-11-19'), 'the source on the event')
        check(len(calls) == 2, 'one request per cell and day (two stages in the same cell share one)')
        base, q = calls[0]
        check(base == pw.ARCHIVE and q['timezone'] == ['Europe/Berlin'] and q['start_date'] == ['2026-01-10'],
              "the archive, the event's zone, the day")
        check(abs(float(q['latitude'][0]) - 50.0) < 1e-6 and abs(float(q['longitude'][0]) - 10.0) < 1e-6,
              "the stage's start point's cell (Alpha's start control)")
        check(any('future' in s for s in said), 'a future rally: said so')
        check('weather' not in json.loads((pack / 'events' / 'f.json').read_text())['itinerary'][0],
              'and nothing written')
        check((pack / 'events' / 'e.json').read_text(encoding='utf-8').endswith('}\n'), 'its trailing newline kept')

        # again: nothing fetched; --force: fetched again
        calls.clear()
        again = pw.run(str(pack), fetcher=pw.Fetcher(get_json=fake, pause_s=0), today=dt.date(2026, 11, 19),
                       say=lambda s: None)
        check(again['Made Up Rally'] == 0 and calls == [], 'a second run: rows with weather left alone')
        pw.run(str(pack), force=True, fetcher=pw.Fetcher(get_json=fake, pause_s=0), today=dt.date(2026, 11, 19),
               say=lambda s: None)
        check(len(calls) == 3, '--force: fetched again (SS5 too)')

        # a recent day: the historical forecast first
        calls.clear()
        f2 = pw.Fetcher(get_json=fake, pause_s=0)
        f2.hour(50.0, 10.0, '2026-11-17', 9, 'Europe/Berlin', dt.date(2026, 11, 19))
        check(calls[0][0] == pw.RECENT, 'a day two days ago: the historical forecast')

        # the archive down: the other one
        calls.clear()

        def down(u):
            calls.append(u)
            if u.startswith(pw.ARCHIVE):
                raise OSError('down')
            return made_up_day(urllib.parse.parse_qs(urllib.parse.urlparse(u).query)['start_date'][0])
        msg, api = pw.Fetcher(get_json=down, pause_s=0).hour(50.0, 10.0, '2026-01-10', 9, None, dt.date(2026, 11, 19))
        check(msg and api == 'historical forecast' and 'timezone=auto' in calls[0], 'the archive down: the other API')

    print(f'{failed} failed' if failed else 'all ok')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
