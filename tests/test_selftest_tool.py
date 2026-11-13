#!/usr/bin/env python3
"""tools/selftest.py without the game: --check-install on stand-in user folders (a fresh install passes; the 1.2.1
fault, an old stage layout without the HUD apps, fails and names the apps; another version, a changed file, two copies,
a saved layout copy, the mod switched off are told), the request and report files, and the full run refusing to
start while the game runs. Never touches the game's own user folder."""
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))


def main():
    import selftest
    failed = 0

    def check(ok, what):
        nonlocal failed
        print(('ok    ' if ok else 'FAIL  ') + what)
        if not ok:
            failed += 1

    def fails(res, pat):
        return any(s == 'FAIL' and pat in t for s, t in res)

    with tempfile.TemporaryDirectory() as tmp:
        user = Path(tmp) / 'current'
        user.mkdir()
        res = selftest.check_install(user)
        check(fails(res, 'not installed'), 'nothing installed: said so')
        r = subprocess.run([sys.executable, str(ROOT / 'tools' / 'install.py'), '--user-dir', str(user)],
                           capture_output=True, text=True)
        check(r.returncode == 0, 'install ran')
        res = selftest.check_install(user)
        check(not any(s == 'FAIL' for s, _ in res), 'a fresh install passes (' + ' | '.join(t for _, t in res) + ')')
        check(any('all 6 stage apps' in t for _, t in res), 'the stage layout\'s apps listed')
        inst = user / 'mods' / 'unpacked' / 'earth_rally'
        lay = inst / 'settings' / 'ui_apps' / 'originalLayouts' / 'default' / 'earthRallyStage.uilayout.json'
        good = lay.read_bytes()
        # 1.2.1 in game: the 1.1.0 layout written over the mod's (BeamNG.Earth's apps and the pacenote cards only)
        lay.write_text(json.dumps({'type': 'earthRallyStage', 'version': 4,
                                   'apps': [{'appName': 'beamngEarthStatus'}, {'appName': 'rallyVisualPacenotes'}]}),
                       encoding='utf-8')
        res = selftest.check_install(user)
        check(fails(res, 'lacks earthRallyHud, earthRallyResults, rallyCountdown, rallyStageTiming, rallyStageProgress'),
              'the 1.2.1 fault: the old layout installed fails, the missing apps named')
        check(fails(res, 'different') and fails(res, 'earthRallyStage.uilayout.json'), '... and the file differs')
        lay.write_bytes(good)
        main_lua = inst / 'lua' / 'ge' / 'extensions' / 'earthRally' / 'main.lua'
        text = main_lua.read_bytes()
        main_lua.write_bytes(text.replace(b"M.VERSION = '", b"M.VERSION = '0.9.", 1))
        res = selftest.check_install(user)
        check(fails(res, 'version: installed 0.9.'), 'another version installed: told')
        main_lua.write_bytes(text)
        (inst / 'stray.lua').write_text('-- left over', encoding='utf-8')
        res = selftest.check_install(user)
        check(fails(res, 'not in the repository (stray.lua)'), 'a file not in the repository: told')
        (inst / 'stray.lua').unlink()
        # a saved copy of the layout (the game's layout editor) without the apps
        saved = user / 'settings' / 'ui_apps' / 'layouts' / 'default'
        saved.mkdir(parents=True)
        (saved / 'earthRallyStage.uilayout.json').write_text(json.dumps({'apps': [{'appName': 'rallyVisualPacenotes'}]}),
                                                              encoding='utf-8')
        res = selftest.check_install(user)
        check(fails(res, 'a saved copy'), 'a saved layout copy without the apps: fails')
        shutil.rmtree(user / 'settings')
        # switched off in the mod list; the log's last loaded version
        (user / 'mods' / 'db.json').write_text(json.dumps({'mods': {'earth_rally': {'active': False}}}), encoding='utf-8')
        (user / 'beamng.log').write_text('1.0|I|GELua.earthRally_main.earthRally| Earth Rally 1.2.1 loaded (Ctrl+Alt+K)\n',
                                         encoding='utf-8')
        res = selftest.check_install(user)
        check(fails(res, 'switched off'), 'switched off in the mod list: fails')
        check(any(s == 'note' and 'Earth Rally 1.2.1 loaded' in t for s, t in res), 'the log\'s last loaded version noted')
        (user / 'mods' / 'db.json').unlink()
        # two copies: a release zip as well
        z = user / 'mods' / 'earth_rally-1.2.2.zip'
        with zipfile.ZipFile(z, 'w') as zf:
            zf.writestr('LICENSE', 'x')
        res = selftest.check_install(user)
        check(fails(res, 'two copies'), 'a zip and the unpacked copy: two copies, fails')
        # only the release zip: its files checked
        shutil.rmtree(user / 'mods' / 'unpacked')
        z.unlink()
        with zipfile.ZipFile(z, 'w') as zf:
            for rel, data in selftest.repo_files().items():
                zf.writestr(rel, data)
            zf.writestr('LICENSE', 'MIT')
        res = selftest.check_install(user)
        check(not any(s == 'FAIL' for s, _ in res), 'the release zip as built: passes (' +
              ' | '.join(t for s, t in res if s == 'FAIL') + ')')

        # the request and the report
        req = selftest.write_request(user, 'otr24', 'maryhill-up', 'abc', True, 900)
        data = json.loads(req.read_text(encoding='utf-8'))
        check(req == user / 'earthRally' / 'selftest' / 'request.json' and data == {
            'event': 'otr24', 'stage': 'maryhill-up', 'token': 'abc', 'quit': True, 'loadLevel': True, 'budgetS': 900},
            'the request file where the mod reads it (selftest.lua REQUEST)')
        d = user / 'earthRally' / 'selftest'
        (d / 'report-20261113-100000.json').write_text(json.dumps({'token': 'old', 'ok': True}), encoding='utf-8')
        check(selftest.find_report(user, 'abc') is None, 'a report of another run is not taken')
        (d / 'report-20261113-110000.json').write_text(json.dumps({'token': 'abc', 'ok': False}), encoding='utf-8')
        found = selftest.find_report(user, 'abc')
        check(found is not None and found[1]['ok'] is False, 'this run\'s report found by its token')

        # the full run refuses while the game is running, and writes no request
        req.unlink()
        selftest.running_exes = lambda: ['BeamNG.drive.x64.exe']
        code = selftest.main(['--user-dir', str(user), '--earth', str(tmp)])
        check(code == 2 and not req.exists(), 'the game running: refused (exit 2), no request written')

    # the mod's Lua and this script agree on where the request goes and what the layout needs
    lua = (ROOT / 'mod' / 'earth_rally' / 'lua' / 'ge' / 'extensions' / 'earthRally' / 'selftest.lua').read_text(
        encoding='utf-8')
    check("M.DIR = '/earthRally/selftest/'" in lua and "M.REQUEST = M.DIR .. 'request.json'" in lua,
          'selftest.lua reads the request where this script writes it')
    print(f'test_selftest_tool: {"all passed" if not failed else str(failed) + " failed"}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
