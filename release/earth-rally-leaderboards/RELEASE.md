<!-- Draft for the first release of DeRamp/earth-rally-leaderboards.
Tag: v0.2.0 (the companion's VERSION). Title: Earth Rally Leaderboards 0.2.0: the first release.
Full release: leave the pre-release box unticked (BeamNG.Earth's Add-ons page installs only the newest full release).
Asset: exactly one file, earth_rally_online.py, copied from the Earth Rally repository's online/companion/ at the
commit Earth Rally 1.8.0-alpha is released from. Body: everything below this comment. -->

The helper that connects Earth Rally 1.8.0-alpha and later to its online leaderboards.

Works with [Earth Rally](https://github.com/DeRamp/BeamNG.Earth.Rally) 1.8.0-alpha+ · [BeamNG.Earth, DeRamp fork](https://github.com/DeRamp/BeamNG.Earth/releases)

### New
* Sends your stage runs to the Earth Rally leaderboards and fetches the boards for the game.
* A run it cannot send waits in a queue and is sent again later.
* Passes on Earth Rally's opt-in stats and error reports, only when you said yes in game.
* One Python file, standard library only, run by BeamNG.Earth's **Add-ons** page.

---
**Install:**
1. In BeamNG.Earth, open **Add-ons** > **Add from GitHub**, paste `DeRamp/BeamNG.Earth.Rally` and press **Install**.
2. Paste `DeRamp/earth-rally-leaderboards` the same way, press **Install**, then **Start** (tick
   **Start with BeamNG.Earth**).
3. In game, turn on **Settings > Leaderboards** in the Earth Rally menu (**Ctrl + Alt + K**).

[README](https://github.com/DeRamp/earth-rally-leaderboards/blob/main/README.md) · [Privacy](https://github.com/DeRamp/BeamNG.Earth.Rally/blob/main/PRIVACY.md)
