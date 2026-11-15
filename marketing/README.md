# Earth Rally 1.6.0: launch package

Everything for announcing 1.6.0, the first supported release. Shot in game on 2026-11-14 (1.6.0 on BeamNG.drive
0.40.5, BeamNG.Earth fork with modding API 1.9).

| What | Where |
|---|---|
| Posts for Reddit, the BeamNG forum, X / Bluesky, Discord, Instagram, YouTube | [`posts.md`](posts.md) |
| Social images: 16:9 posts, 1:1 and 4:5 feed, 9:16 story, GitHub social preview | `../Earth Rally 1.6.0 marketing/social/` (beside the repo folder, outside git) |
| Raw PNGs and the export script (`python export.py <repo> <social folder>`) | `../Earth Rally 1.6.0 marketing/raw/` |
| Screenshots (1600x900) used by the README and wiki | [`../docs/media/`](../docs/media/) |
| Wiki pages (source) and how to publish them | [`../docs/wiki/`](../docs/wiki/), `python tools/publish_wiki.py` |

## Launch order

1. `/release 1.6.0`: tag, zip, GitHub release marked Latest.
2. Make the wiki's first page on the web once, then `python tools/publish_wiki.py`.
3. **Settings > General > Social preview** on GitHub: upload `github-social-preview.jpg` from that folder (328 KB, under the 1 MB limit).
4. Repo **About**: description "Real rally stages on the real roads of BeamNG.Earth", website = the wiki, topics
   `beamng`, `beamng-drive`, `rally`, `mod`, `simracing`.
5. Post, in this order: BeamNG forum, r/BeamNG, Discord, X / Bluesky, Instagram.

## Image notes

* Leaderboards show real crews' names from the ARA 2026 results pack (shipped with the 1.6.0-alpha release).
* The import folder path in `menu-rallies.jpg` is blurred (it named the Windows user).
* Menu times are the owner's own drives. The on-stage shots and the 6:33.1 results card are from a script-AI run on
  Weaver Bend for the shoot; that run was removed from the save afterwards.
