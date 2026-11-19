# Earth Rally Leaderboards

The helper that connects [Earth Rally](https://github.com/DeRamp/BeamNG.Earth.Rally) to its online leaderboards.
BeamNG.drive's mods cannot reach the internet, so the mod talks to this program on your PC, and it talks to the
leaderboard over HTTPS.

**Alpha · one Python file, standard library only · runs beside the game through BeamNG.Earth's Add-ons page**

## Install

1. Install Earth Rally first: in BeamNG.Earth, open **Add-ons** > **Add from GitHub**, paste
   `DeRamp/BeamNG.Earth.Rally` and press **Install**.
2. Paste `DeRamp/earth-rally-leaderboards` the same way and press **Install**.
3. Press **Start**, and tick **Start with BeamNG.Earth** so it runs every time.
4. In game, turn on **Settings > Leaderboards** in the Earth Rally menu (**Ctrl + Alt + K**) and pick a name.

Updates come through the same **Add-ons** page.

## What it sends

* **Leaderboard runs:** your leaderboard name, the stage, your time and penalties, the car and its class, and the
  car's position on the stage twice a second with its resets, so the leaderboard can check the run. A random player
  id and secret, kept in `~/.earth_rally_online/`, say the runs are yours.
* **Stats and error reports**, only if you said yes to them in game. They carry no name or id.
* Nothing at all while Leaderboards are off in the game.

The full list: [Earth Rally privacy](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/PRIVACY.md).

## Running it by hand

For testing, without BeamNG.Earth:

```
python earth_rally_online.py [--port 47820] [--server URL] [--stats-server URL] [--data DIR]
```

It listens on `127.0.0.1:47820`, where the mod looks for it. `--server` points it at another leaderboard, such as a
local test server.

## For the maintainer

The source lives in the Earth Rally repository, `online/companion/earth_rally_online.py`. This repository holds this
README, `beamngEarth_addon.json` (how BeamNG.Earth runs it) and the licence. Each release has exactly one asset,
`earth_rally_online.py`, copied from the Earth Rally repository at release time. Releases are full releases, not
pre-releases: BeamNG.Earth's Add-ons page installs only the newest full release.

## License

MIT, see [LICENSE](LICENSE).
