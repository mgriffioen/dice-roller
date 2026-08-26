# Dice Roller

A D&D/RPG dice roller for the [Playdate](https://play.date/). Set up the throw --
die type, how many, a `+N` modifier, and advantage or disadvantage on a d20 --
then turn the crank. The dice tumble, land one by one, and the total slides up
on an overlay. Past rolls are kept on a second page, and any of them can be
thrown again.

Written in Lua against the Playdate SDK, with comments aimed at someone learning
the platform.

## Building and running

You need the [Playdate SDK](https://play.date/dev/) installed (`pdc` on your
PATH).

```sh
pdc source DiceRoller.pdx     # compile
open DiceRoller.pdx           # macOS: opens in the Playdate Simulator
```

On Linux/Windows, launch the Simulator and open `DiceRoller.pdx` from it. To put
it on hardware, use the Simulator's **Device → Upload Game to Device**, or zip
the built `DiceRoller.pdx` and upload it at
<https://play.date/account/sideload/>. Builds are gitignored — a `.pdx` is
output, not source, so it isn't kept in the repo.

The Simulator has a crank dial in the control panel below the device: drag it
round with the mouse to crank. The **Docked** checkbox beside it folds the crank
away, which is how to exercise the A-button fallback.

## Controls

**Setup screen** — a list of fields: die type, how many, modifier, and (on a
d20) advantage/disadvantage.

| Input | Action |
| --- | --- |
| Up / Down | Choose a field |
| Left / Right | Change the selected field |
| Crank | Change the selected field, faster — `+20` is forty button presses or about half a turn |
| A | Go to the rolling screen |
| B | Open the history page |

Die type and count wrap around; the modifier clamps at ±20. The
advantage/disadvantage row only appears for a d20, and resets to normal if you
switch to another die.

**Rolling screen**

| Input | Action |
| --- | --- |
| Crank | Wind up and throw. Keep going until the meter fills, then stop and let the dice land. |
| A (crank docked) | Fallback throw, for a docked crank or a quick test |
| A (on the result) | Roll again with the same dice |
| B | Back to the setup screen |

**History page** — B from the setup screen. The last 20 rolls, newest first.

| Input | Action |
| --- | --- |
| Up / Down, or crank | Browse |
| A | Throw the selected roll again |
| B | Back to the setup screen |

Sound can be turned off from the Playdate system menu, and the history cleared
from there too.

## Modifiers, advantage and disadvantage

The modifier is applied once to the whole throw, not per die: `3d6+2` rolls three
d6 and adds 2 to the sum, so it spans 5–20. The setup screen shows the notation
and the range it can produce.

Advantage rolls two d20 and keeps the higher; disadvantage keeps the lower. Both
dice are thrown and animated, and the one that didn't count is crossed out where
it lies, so you can see what was discarded. With a count above one it applies per
roll — `3d20 adv` throws three pairs and keeps the best of each.

Two details worth getting right, both covered by the tests:

- **A natural 20 is about the die, not the total.** Rolling 13 with a `+7` is a
  20, but it isn't a critical hit, and the banner doesn't appear. Rolling a 20
  with a `-2` still is one.
- **Under advantage, the banner follows the kept die** — a 20 alongside a 3 is a
  natural 20; under disadvantage that same pair isn't.

Advantage changes which results are *likely*, not which are *possible*, so it
doesn't move the ends of the range.

## Roll history

Every roll is kept — its notation, total, and the individual dice — and the last
20 survive a restart. Picking one and pressing A throws it again: each entry
stores enough to rebuild the throw (die type, count, modifier, mode), so
`2d20+3 dis` comes back exactly as it was.

That file outlives the code that wrote it, which is worth designing for rather
than hoping about. Entries carry a version so a future format change is
discarded instead of half-read into a crash, and anything rebuilt from disk is
re-validated on the way out: a count above the die's current limit is clamped, a
modifier beyond ±20 is clamped, advantage on a die that no longer allows it is
dropped, and an entry naming a die type that no longer exists simply refuses to
load rather than crashing.

## How d100 works

A d100 isn't one die — it's a pair of d10s: a *tens* die reading `00`–`90` and a
*units* die reading `0`–`9`, added together. `00 + 0` reads as 100, not 0. The
app rolls and animates both dice, shows them side by side, and displays each
result as `70+3=73`.

## Project layout

```
source/
  main.lua            entry point: seeds RNG, sets refresh rate, owns the scene switch
  pdxinfo             game metadata (name, bundle ID, version) that pdc bakes in
  lib/
    dice.lua          dice types, shapes, scoring a throw, and the Die class
    layout.lua        fits N dice into a rectangle at the largest size that works
    util.lua          drawing helpers: scaled text, panels, bars, screen dimming
    sfx.lua           synth blips -- no audio files needed
    history.lua       the last 20 rolls, saved with playdate.datastore
  scenes/
    setup.lua         the field list: die type, count, modifier, advantage
    roll.lua          the crank throw, the settle sequence, the result overlay
    history.lua       the second page: browse past rolls, throw one again
  launcher/
    card.png          350x155 launcher tile
    icon.png          32x32 icon
tests/                pure-logic tests that run without the Simulator
```

## Things worth knowing (the notes I'd have wanted on day one)

**`playdate.update()` is the whole loop.** Define it as a global and the SDK
calls it once per frame. `playdate.display.setRefreshRate(30)` sets that rate;
30 is the default and plenty for this.

**This app draws everything every frame** rather than using
`playdate.graphics.sprite`. `gfx.clear()` at the top of the frame, then draw.
Sprites earn their keep when you have many objects with dirty-rect tracking and
z-ordering; a dozen polygons don't need it, and immediate-mode drawing is far
easier to read.

**The crank is polled, not evented.** `playdate.getCrankChange()` returns the
degrees moved since the last call (signed, plus an accelerated variant). There's
also a `playdate.cranked(change, accel)` callback if you prefer. Note that
`playdate.isCrankDocked()` is true when the crank is folded away — always give
players a button fallback, which is what holding A does here.

**The screen is 400×240 and 1-bit.** No greys. "Grey" is a dither pattern:
`gfx.setPattern({0xAA, 0x55, ...})` gives the checkerboard used to knock back
the dice behind the result overlay. Design in black-on-white shapes with fat
outlines and it reads well.

**There is no vector text.** The system font tops out around 16px. To draw a big
number, render the string into an offscreen `gfx.image` once and blit it back
with `image:drawScaled()` — see `Util.drawBigText`. Cache the images; making
them every frame is wasteful.

The catch is that this only scales in whole multiples — 16px or 32px, nothing
between — because a fractional scale doubles some pixel rows and not others,
which looks broken at this resolution. So `Die:faceScale` picks between exactly
two sizes based on how big the die is, with a width check so a two-digit
percentile face doesn't outgrow the die carrying it. Resist deriving that
choice from per-shape geometry: it makes the size jump around between die types
in ways that read as a bug.

**One config table beats threading arguments.** A throw is described by
`{ spec, count, modifier, mode }`, built on the setup screen and handed to the
roll scene. Everything in `Dice` takes that one table, so adding the modifier and
advantage meant changing what goes *in* it rather than changing signatures
everywhere. Advantage also fell out almost free: a d100 was already a *group* of
two dice scored together, and an advantage pair is the same shape with a
different scoring rule.

**Shapes come from `playdate.geometry.polygon`.** Each die shape is stored as
unit-circle points, then rotated, scaled and translated at draw time
(`Die:drawPolygonDie`). One table works at any size and any angle.

**`import` is not `require`.** It's resolved by `pdc` at compile time and can't
return a value, so modules export globals (`Dice`, `Layout`, `Util`, `Sfx`,
`History`). The
`class()` function from `CoreLibs/object` also defines a global — `class("Die")`
creates `Die`.

**Saving is one call.** `playdate.datastore.write(table, filename)` serialises a
plain Lua table into the game's save folder and `read` gives it back — no format
to define, as long as everything in it is a string, number, boolean, or another
such table. Two things that aren't obvious: put a version number in the file so
a later format change can be recognised and discarded, and re-validate whatever
comes back, because a save file outlives the code that wrote it.

**Seed the RNG yourself.** `math.randomseed(playdate.getSecondsSinceEpoch())`,
or every launch replays the same "random" rolls.

**Sound is free.** `playdate.sound.synth.new(playdate.sound.kWaveSquare)` and
`synth:playNote(freq, volume, length)` gets you a full sound set without
shipping a single audio file. Use a small pool of voices so overlapping blips
don't cut each other off.

## Tests

```sh
tests/run.sh          # needs lua5.4 and python3
```

The game rules are plain Lua, so they can be verified without the Simulator. The
script rewrites the SDK's compound assignment operators (`+=`, `*=`) into stock
Lua 5.4, stubs the handful of `playdate.*` calls the logic touches, and checks:

- every die type produces every one of its faces, and nothing out of range
- percentile scoring, including the `00 + 0 = 100` case
- advantage keeps the higher die and disadvantage the lower, exactly one die per
  pair is crossed out, and over many rolls disadvantage < normal < advantage
- totals stay inside the advertised range across every combination of die type,
  count, modifier and mode
- natural 20 / natural 1 is judged on the die rather than the modified total
- the setup screen's field list: wrapping, clamping the modifier at ±20, the
  count clamping when you switch to a die with a lower limit, and the cursor
  never pointing at the d20-only row after leaving the d20
- the layout solver keeps every die on screen at every supported count
- a full throw — crank, release, settle, result — reaches a valid total, in a
  reasonable number of frames, via both the crank and the button fallback
- the history: ordering, the 20-entry cap, surviving a reload, rebuilding a
  throw from an entry, clamping stale values, discarding a corrupt or
  future-versioned file, and browsing/wrapping/scrolling the page — including
  that an empty history is navigable rather than a crash

Drawing is stubbed, so this checks behaviour, not pixels — for those, run it.

## Ideas for next

- Saved roll presets, pinned to the top of the history page
- Accelerometer shake as an alternative to the crank
  (`playdate.readAccelerometer()`, after `playdate.startAccelerometer()`)
