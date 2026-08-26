-- Small drawing helpers shared by every scene.

local gfx <const> = playdate.graphics

Util = {}

-- 50% checkerboard over the whole screen, used to knock back the dice while the
-- result panel is on top of them.
function Util.dimScreen()
    gfx.setPattern({0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55})
    gfx.fillRect(0, 0, 400, 240)
    gfx.setColor(gfx.kColorBlack)
end

-- A white card with a fat black border: the only "chrome" this app uses.
function Util.drawPanel(x, y, w, h, radius)
    radius = radius or 6
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRoundRect(x, y, w, h, radius)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawRoundRect(x, y, w, h, radius)
    gfx.setLineWidth(1)
end

-- Black bar with white text, for headers and the hint strip along the bottom.
function Util.drawBar(x, y, w, h)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x, y, w, h)
    gfx.setColor(gfx.kColorWhite)
end

function Util.drawInvertedText(text, x, y, alignment)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawTextAligned(text, x, y, alignment or kTextAlignment.left)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function Util.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
