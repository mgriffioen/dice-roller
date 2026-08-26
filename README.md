# Dice Roller

A D&D/RPG dice roller for the [Playdate](https://play.date/). Pick a die and a
count, then turn the crank to throw them. The dice tumble, land one by one, and
the total slides up on an overlay.

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
it on hardware, use the Simulator's **Device → Upload Game to Device**, or the
sideload uploader at <https://play.date/account/sideload/>.

The Simulator lets you drive the crank with the mouse: grab the crank in the
right-hand panel, or hold <kbd>⌘</kbd>/<kbd>Ctrl</kbd> and drag.

## Controls

**Setup screen**

| Input | Action |
| --- | --- |
| Left / Right | Change die type (d2, d4, d6, d8, d10, d12, d20, d100) |
| Up / Down | Change how many to roll |
| A | Go to the rolling screen |

**Rolling screen**

| Input | Action |
| --- | --- |
| Crank | Wind up and throw. Keep going until the meter fills, then stop and let the dice land. |
| A (crank docked) | Fallback throw, for a docked crank or a quick test |
| A (on the result) | Roll again with the same dice |
| B | Back to the setup screen |

Sound can be turned off from the Playdate system menu.

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
    dice.lua          dice types, shapes, and the Die class (tumbling + drawing)
    layout.lua        fits N dice into a rectangle at the largest size that works
    util.lua          drawing helpers: scaled text, panels, bars, screen dimming
    sfx.lua           synth blips -- no audio files needed
  scenes/
    setup.lua         choose die type and count
    roll.lua          the crank throw, the settle sequence, the result overlay
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

**Shapes come from `playdate.geometry.polygon`.** Each die shape is stored as
unit-circle points, then rotated, scaled and translated at draw time
(`Die:drawPolygonDie`). One table works at any size and any angle.

**`import` is not `require`.** It's resolved by `pdc` at compile time and can't
return a value, so modules export globals (`Dice`, `Layout`, `Util`, `Sfx`). The
`class()` function from `CoreLibs/object` also defines a global — `class("Die")`
creates `Die`.

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
- the layout solver keeps every die on screen at every supported count
- a full throw — crank, release, settle, result — reaches a valid total, in a
  reasonable number of frames, via both the crank and the button fallback
- natural 20 / natural 1 banners appear only for a single d20

Drawing is stubbed, so this checks behaviour, not pixels — for those, run it.

## Ideas for next

- A modifier (`+3`) and advantage/disadvantage for d20
- Saved roll presets, using `playdate.datastore` to persist them
- Roll history on a second page
- Accelerometer shake as an alternative to the crank
  (`playdate.readAccelerometer()`, after `playdate.startAccelerometer()`)
