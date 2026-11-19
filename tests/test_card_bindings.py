#!/usr/bin/env python3
"""The HUD cards' buttons against the installed game's own bindings (cardInput.lua): every game action bound to the
pad's A, B and d-pad (xidevice.json) and to the keyboard's Enter and arrows (keyboard.json) is either filtered while a
card is up (cardInput's BLOCKED), one of our own card actions (our map, pushed first), or in ALLOWED below with the
reason it may stay. A new game version binding something else there fails this. Skipped, with a note, when the game
is not installed where it is looked for (BEAMNG_GAME_DIR, else Steam's default folder)."""
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / 'mod' / 'earth_rally'
GAME = Path(os.environ.get('BEAMNG_GAME_DIR') or 'C:/Program Files (x86)/Steam/steamapps/common/BeamNG.drive')

PAD = {'btn_a', 'btn_b', 'upov', 'dpov', 'lpov', 'rpov'}
KEYS = {'enter', 'numpadenter', 'left', 'right', 'up', 'down'}

# Game actions left on the card's buttons on purpose, with why.
ALLOWED = {
    'steer_left': "the car's driving keys: a finish card can be up with the car still rolling (a flying finish), "
                  'and taking its steering, throttle and brake away there is worse than the pick moving with them',
    'steer_right': 'as steer_left',
    'accelerate': 'as steer_left',
    'brake': 'as steer_left',
    'bigMapMoveForward': "the big map's: only with the big map open, a menu over the HUD (the card gives the keys back)",
    'bigMapMoveBackward': 'as bigMapMoveForward',
    'bigMapMoveLeft': 'as bigMapMoveForward',
    'bigMapMoveRight': 'as bigMapMoveForward',
    'inplaceEdit_up': "the world editor's: only in the editor, never with a card up",
    'inplaceEdit_down': 'as inplaceEdit_up',
    'inplaceEdit_left': 'as inplaceEdit_up',
    'inplaceEdit_right': 'as inplaceEdit_up',
    'jumpAhead': "the replay's seek: only while a replay plays, never with a card up",
    'jumpBack': 'as jumpAhead',
    'jumpFarAhead': 'as jumpAhead',
    'jumpFarBack': 'as jumpAhead',
}


def load_map(path):
    """A BeamNG input map: JSON with // comment lines and trailing commas."""
    s = path.read_text(encoding='utf-8')
    s = re.sub(r'^\s*//.*$', '', s, flags=re.M)
    s = re.sub(r',(\s*[\]}])', r'\1', s)
    return json.loads(s)


def blocked():
    src = (MOD / 'lua' / 'ge' / 'extensions' / 'earthRally' / 'cardInput.lua').read_text(encoding='utf-8')
    m = re.search(r'M\.BLOCKED\s*=\s*\{(.*?)\n\}', src, flags=re.S)
    return set(re.findall(r"'([^']+)'", m.group(1)))


def bound(path, controls):
    return sorted({(b.get('control'), b.get('action')) for b in load_map(path).get('bindings', [])
                   if b.get('control') in controls})


def main():
    maps = GAME / 'settings' / 'inputmaps'
    if not (maps / 'xidevice.json').is_file():
        print(f'test_card_bindings: the game\'s input maps are not at {maps}: skipped (set BEAMNG_GAME_DIR)')
        return 0
    block = blocked()
    ok = bad = 0

    def check(src, control, action):
        nonlocal ok, bad
        if action in block or action.startswith('earthRally_card') or action in ALLOWED:
            ok += 1
            return
        bad += 1
        print(f'FAIL {src}: {control} -> {action}: not filtered on a card (cardInput BLOCKED), not ours, not allowed')

    for f, controls in (('xidevice.json', PAD), ('keyboard.json', KEYS)):
        for control, action in bound(maps / f, controls):
            check('the game ' + f, control, action)
    # our own maps: a card button's other action of ours (the rally's recovery on the d-pad) is filtered too
    for f, controls in (('xidevice_earthRally.json', PAD), ('keyboard_earthRally.json', KEYS)):
        for control, action in bound(MOD / 'settings' / 'inputmaps' / f, controls):
            check('ours ' + f, control, action)
    stale = sorted(a for a in ALLOWED if a in block)
    for a in stale:
        bad += 1
        print(f'FAIL {a}: both filtered and allowed')
    print(f'test_card_bindings: {ok} passed, {bad} failed ({GAME})')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
