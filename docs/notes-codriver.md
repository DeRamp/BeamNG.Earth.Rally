# Co-driver settings: test notes

Built on 1.9.2 (`1.9.2-alpha+codriver`, branch `feature/codriver-settings`). Findings from the owner's test, logged, not fixed.

## 1. Voice drop-down does not open (main menu, Rally page's Earth Rally menu)

- Seen (2026-11-19): on the Home screen opened from BeamNG's own Rally page, the Voice drop-down does not work.
- Diagnosis (not checked in game): it is a plain HTML `<select>`. BeamNG draws its UI in an off-screen browser,
  which does not show a `<select>`'s pop-up list, so clicking it opens nothing.
- Fix: build the list ourselves in `EarthRallySettings.vue`: a button showing the current voice that opens a list of
  `bng-nav-item` rows under it (scrolls past ~6 voices), closed by a pick, Escape or a click outside. Same look as now.
  Or use the game's own select component if one can be used from a mod page (check `ui/ui-vue` for `BngSelect`).
