# 1.7.0 notes: the full rally MVP

Branch `full-rally-mvp`, from `main` at 1.6.2. Plan: [`plan-1.7.0.md`](plan-1.7.0.md).

## Revision 2 (issues #23-#33)

The first drive's findings are now issues #23-#33. This revision answers all of them.

| Issue | What changed |
|---|---|
| #23 | The auto recce runs on Start for every stage with no line. Downloads are accepted for you. |
| #24 | The time card is trimmed: no "full repair · game saves" on each row, shorter start screen. |
| #25 | D-pad right is the rally's recovery on an Xbox pad (`xidevice_earthRally.json`). |
| #26 | The rally starts at the event file's start place, at the first service when there is none. |
| #27 | Control hints in the HUD's bottom-left: recover, flip upright, time card, skip the wait. |
| #28 | Leave rally (continue later) and Retire (save deleted), each with a confirm saying what it costs. |
| #29 | Dev panel: jump 500 m or 100 m before the finish; skip the transit. Not in the main UI. |
| #30 | A stage with more than 250 m of its road missing from the map is held out of the rally and listed. |
| #31 | A Realistic recovery takes you to the service you rejoin at; you drive the transit from there. |
| #32 | Logs show the car did go to SS4's stage; the "SS6" was not reproduced. A test now checks SS1 → SS4. |
| #33 | Services are places on the map. Transits are driven: follow the GPS, the stage loads as you arrive. |

## Before driving

- **Re-import happens by itself.** The pack reader is newer again (places), so the first scan imports every pack.
  Your times and ids are kept.
- **The dev panel** (Settings → Developer panel) has the new rally tools under the run tools.
- The mock-ups were skipped for this revision: you asked for it built.

## Open questions for the owner

- **Transit lengths** are not measured. Some ARA transits are 30-50 km. Is a player skip out of service wanted
  after all? (#33 says dev panel only, as built.)
- **No pad button for the time card.** Service out, Leave and Retire need Ctrl+Alt+K.
- **A broken car on a transit in Realistic** can only Leave. Casual's transit recovery repairs it.
- **#32:** where on screen did "SS6" show? The logs say SS4's stage loaded.
- **Saves from the first MVP build** are not continued (the save format changed). Start the rally again.

## Test plan (one rally with an event file, day 1)

1. **Start (Casual):** the start screen lists stages to recce and stages held out. Start: any recces run first,
   then the car goes to the start place and the time card opens.
2. **Transit:** Go on the time card. Follow the GPS arrows to SS1's time control. The Messages app shows the
   transit and distance; the hints show recovery and the time card. The stage loads as you arrive.
3. **Transit recovery:** off the road on a transit, Backspace or D-pad right puts you back on the nearest road.
4. **Dev panel:** on SS1, jump 500 m before the finish. At the end, the card stays until you drive on.
5. **Service:** after the last stage before a service, follow the GPS to the service. On arrival the car is
   repaired, the game saves, the card opens. Service out arms the next transit.
6. **Realistic recovery:** Start again in Realistic. On SS1, Backspace twice. You land at the service you rejoin
   at with the Super Rally card, then drive to the right stage (SS4 in the old SS1 case).
7. **Leave and Continue:** Leave rally from the time card. Its confirm says where you continue from. Continue on
   the rally page brings you back there.
8. **Retire:** from the time card or the rally page. The confirm says the save is deleted. It is.
9. **BeamNG's recovery off** during the rally; back after Leave or Retire.
10. **Finish** (if you get that far): the finish card, then the Results tab.

## Findings

(Logged here while the owner drives, with the diagnosis. Not fixed during the drive.)
