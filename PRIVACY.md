# Earth Rally: privacy

Earth Rally can send anonymous stats. It asks the first time the rally menu opens and sends nothing until you
answer. Closing the question counts as No. Change it any time in **Settings › Privacy**.

Owner and contact for this data: **DeRamp**, through
[GitHub issues](https://github.com/DeRamp/BeamNG.Earth.Rally/issues).

## What is sent, with Yes

- The event: a session started, a stage or rally started or finished, a recce done, an error code.
- A random install number made on your PC. It is tied to nothing else.
- The Earth Rally, BeamNG.drive and BeamNG.Earth versions.
- The day, with no time of day.
- For a stage: the rally and stage name, the result, the stage time in whole seconds and the number of resets.
  Stages from your own imported maps are sent as `custom`, never by name.
- For an error: a short code and the part of the mod it came from. Never the error text.

## What is never sent

- Your name, or your Steam or BeamNG account.
- Your IP address. The server never reads or stores it.
- Your location or where you drive.
- Your PC, hardware or other mods.
- Logs. A log only leaves your PC if you attach it to a bug report yourself.

## Where it goes and how long it stays

- Sent over plain HTTP, because the game's Lua cannot do HTTPS. That is why nothing personal is in it.
- Stored in a Cloudflare database run by DeRamp. Request logs are off.
- Kept 12 months. After that, only monthly totals are kept, with no install numbers.

## Your controls

- **See what was sent:** every message is also saved word for word in `earthRally/telemetry/sent.jsonl` in your
  BeamNG user folder.
- **Delete my stats:** removes everything sent from your PC from the server and starts a new install number.
- **Turn it off:** Settings › Privacy › Off. Nothing more is sent.

## Bug reports

**Report a problem** opens a new GitHub issue in your browser with the versions filled in. You can attach your game
log: Earth Rally saves a copy to `earthRally/reports/` with your Windows user name, Steam details, emails and IP
addresses removed, and you drag it into the issue yourself. GitHub issues are public.
