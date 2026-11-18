# Earth Rally: privacy

Earth Rally can send anonymous stats. It asks when you turn on Leaderboards, as its own question, and sends nothing
until you say yes. Closing the question counts as No. The leaderboard works either way. Change it any time in
**Settings › Privacy**.

Owner and contact for this data: **DeRamp**, through
[GitHub issues](https://github.com/DeRamp/BeamNG.Earth.Rally/issues).

## What is sent, with Yes

- The event: a session started, a stage or rally started or finished, a recce done, an error.
- A random session number, made new each time you start the game and never used again, so your sessions cannot
  be linked to each other or to you.
- The Earth Rally, BeamNG.drive and BeamNG.Earth versions.
- The day, with no time of day.
- For a stage: the rally and stage name, the result, the stage time in whole seconds and the number of resets.
  Stages from your own imported maps are sent as `custom`, never by name.
- For a finished stage: the car, and whether it is Stock or Open. A car that is not one of the game's own is sent
  as `custom`.
- For an error in Earth Rally: a short code, the part of the mod, and the error's text (up to 200 letters) with your
  user name, emails, Steam ids and IP addresses removed first.

## What is never sent

- Your name, your leaderboard name, or your Steam or BeamNG account.
- Your location or where you drive.
- Your PC, hardware or other mods.
- Logs. A log only leaves your PC if you attach it to a bug report yourself.

Your IP address reaches the server with each message, as with any internet request. The server never reads or
stores it, and request logs are off.

## Where it goes and how long it stays

- Sent through the Earth Rally Leaderboards add-on on your PC, which passes it on over HTTPS. Only while
  Leaderboards are on.
- Stored in a Cloudflare database run by DeRamp.
- Kept 12 months. After that, only monthly totals are kept, with no session numbers.

## Your controls

- **See what was sent:** every message is also saved word for word in `earthRally/telemetry/sent.jsonl` in your
  BeamNG user folder.
- **Turn it off:** Settings › Privacy › Off. Nothing more is sent, and anything waiting is thrown away.
- There is no "delete my stats": nothing sent can be traced back to you, so there is nothing to find.

## Bug reports

**Report a problem** opens a new GitHub issue in your browser with the versions filled in. You can attach your game
log: Earth Rally saves a copy to `earthRally/reports/` with your user name, OneDrive organisation, Steam details,
emails and IP addresses removed, and you drag it into the issue yourself. Read it first if you like. GitHub issues
are public.
