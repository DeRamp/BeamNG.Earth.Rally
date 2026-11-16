# 1.7.0 notes: the full rally MVP

Branch `full-rally-mvp`, from `main` at 1.6.2. Plan: [`plan-1.7.0.md`](plan-1.7.0.md).

## Before driving

- **Re-import happens by itself.** `pack.lua`'s reader is newer, so the first scan imports every pack again and
  the services get read. Your times and ids are kept.
- The rally page of a rally with an event file has a **Full rally** bar: Start the rally, or Continue when one is
  saved.

## Test plan (one rally with an event file and real results, day 1)

1. **Start:** check the car, the class guessed from it, and the stage, day and service counts. Start in **Casual**.
2. **Casual recovery:** on SS1, press Backspace. You go back on the stage line at no cost.
3. **Casual restart:** at the end of SS1, the card shows stage, class and overall places and the crews round you.
   Restart stage runs SS1 again, still damaged.
4. **Damage:** dent the car on SS1. It is still dented at the start of SS2, after the teleport.
5. **Service:** after the last stage before the first service, Continue. The time card shows the service, the
   car is repaired, and "Game saved" appears.
6. **BeamNG's recovery off:** during the rally, R, Insert, Ctrl+R, Home and the vehicle selector do nothing. After
   Quit they work again.
7. **Realistic:** Start again in **Realistic** and press Backspace on SS2. The Recover? card asks first; Keep going
   (or B, or 10 s) takes it down. Press Backspace again to confirm. You land at the first service with the Super
   Rally card. Your missed stages score the class's fastest + 10:00, then + 7:00. Service out goes to the next stage.
8. **Quit and resume (Casual):** after the stage after a service, Quit. On the rally page Continue brings you back
   at the service, not at the stage you quit after.
9. **Quit and resume (Realistic):** Quit halfway through a stage. Continue keeps the stages you finished since the
   service, scores the one you quit under Super Rally, and puts you at the next service.
10. **Finish** (if you get that far): the finish card, then the rally's Results tab shows your total, place and mode.

## Findings

(Logged here while the owner drives, with the diagnosis. Not fixed during the drive.)
