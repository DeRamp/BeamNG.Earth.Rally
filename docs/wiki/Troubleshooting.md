# Troubleshooting

## The menu won't open

1. Are you in the BeamNG.Earth level? Try **Rally menu** on the pause menu's **Earth Rally** tab.
2. Press **`~`** and type `earthRally_main.toggleMenu()`.
   * **It opens**: the key isn't reaching the game. On some layouts Ctrl + Alt is AltGr; bind another key.
   * **`attempt to index global 'earthRally_main'`**: the mod isn't loaded. **Mods** in the main menu: switch Earth
     Rally on. The zip must be directly in `…\current\mods\`, still zipped, one copy only.
3. **No styling** (plain text)? Type `reloadUI()` in the console.

## "Recce needed" and Auto recce greyed out

Auto recce needs [the DeRamp fork of BeamNG.Earth](https://github.com/DeRamp/BeamNG.Earth/releases). The note under the
button says so. On official BeamNG.Earth, press **Recce** and drive the stage once.

## My time says "not placed"

Your line is more than 5 % off the official distance, so it can't be compared with the real crews. **Reset** the
stage and run **Auto recce**, or drive a **Recce** that follows the stage.

## Reporting a bug

[Open an issue](https://github.com/DeRamp/BeamNG.Earth.Rally/issues) with:

* Earth Rally, BeamNG.drive and BeamNG.Earth versions.
* What you did and what happened.
* The lines mentioning `earthRally` from `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\beamng.log`.

Report problems with the DeRamp fork here too, not to the BeamNG.Earth team.
