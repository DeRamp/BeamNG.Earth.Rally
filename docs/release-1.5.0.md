# 1.5.0: the co-driver

The pacenotes are rebuilt. The co-driver now calls what the road actually does: hairpins and square corners in place
of a number, corners that tighten or open, chicanes, long sweepers, cautions where a corner comes up faster than it
looks, and crests where you genuinely cannot see the road ahead. Everything is read from the stage's line and its
heights, so it works on every stage the mod can drive, with nothing new to install. The whole list, with the figures
behind each call, is in `docs/pacenotes-1.5.0.md`.

The co-driver was 1.6.0 on the roadmap. It was built alongside on the stage and finished first, so it is released
as 1.5.0, and on the stage is now 1.6.0 (the same as the rally files did for 1.4.0).

---

## Corners

* **Hairpin** and **tight hairpin** for the corners that turn back on themselves, and **square** for a tight
  right-angle, said in place of the corner's number, as the game's own stages do.
* **Tightens**, **opens**, **opens and tightens**, and **tightens down** for a corner that tightens downhill.
* **Chicane left / right**: two tight corners either way in quick succession, one call instead of two.
* **Twisty** for a run of quick flicks, with every corner still called.
* **Long sweepers**: a long bend too open to count as a corner used to go by in silence; it is now a "six long".
* **Care, caution, double caution**: from how much you have to slow for a corner against how fast you arrive, a care
  on a big corner after a long straight, and a caution at least where a corner tightens over a crest.

## Crests, from what the driver can see

A crest is called where the road you are about to reach — 2 seconds ahead at the speed the stage allows — is hidden
behind a rise, and stays hidden. If you can see over it, there is no call, however much the grade changes: a steep
climb easing off, or a descent getting steeper, is not a crest. **Small crest** and **big crest** say how soon the
road disappears.

* **Down** at the top of a downhill from flat road, in place of a crest.
* **Jump** and **big jump** where the car cannot follow the road at speed; **dip** and **bad dip**; **up** and
  **down** on long hills.
* **Into crest**, **over crest** and **tightens / opens over crest** where a crest meets a corner, and **keep left /
  right over crest** at a fork on one.
* **Brake over crest** before a corner with a caution just over a crest.

## Bridges, junctions, the road, the finish

* **Over bridge**, where a stage's line has its bridges. The in-game auto recce cannot see bridges (BeamNG.Earth's
  road graph has no bridge flag), so they come from `tools/auto_recce.py --event <id> --bridges-only`, which adds
  BeamNG.Earth's own bridges to the lines already matched. The heights on a bridge are the valley under it, so no
  crest, jump or dip is read there.
* **Keep left / right** now comes before the corner when the fork is inside it.
* **Narrows** where the road gets markedly narrower, on a line that knows the road's width (tried so far on drawn
  roads only: no line matched before this release has the widths).
* **Over finish** on the last note.

## Every voice

The game's casual co-driver voices say only a dozen or so calls. The mod reads which style your voice uses and
leaves out what it cannot say, so no note goes by in silence: a casual voice hears a crest in a corner as "over
crest" after it, and a chicane as its two corners. The developer panel shows the style it found. A voice changed in
Options during a run is used from the next run.

## Fixed along the way

* A second auto recce of a stage keeps the bridges added to it.
* Crests, jumps and dips are no longer read off bad elevation data (a step in the heights steeper than any road).

## Known

* Very broad hilltops, where a car stays in sight over the top, are not called.
* "Down" at the top of a downhill needs a 6 % average fall over 100 m, gentler than the 8 % a long hill's "down"
  needs, so a stepped descent can call it several times close together.
* `tools/selftest.py` still cannot hear the co-driver (the game only calls notes for a car that is really moving),
  so it exits 1 on every run: read its checks, not its exit code. The real check was the user driving it, four
  times.
* Not in this release, from the co-driver's roadmap: co-driver settings (call timing, detail, voice), and the
  self-test hearing the co-driver.
