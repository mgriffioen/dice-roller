-- Small drawing helpers shared by every scene.

local gfx <const> = playdate.graphics

Util = {}

-- The Playdate system font tops out around 16px tall, which is too small for a
-- headline number. There is no vector text on the Playdate, so the trick is to
-- render the string into an offscreen image once and blit it back up-scaled.
-- It looks chunky and pixelated on purpose -- that reads as "retro" on a 1-bit
-- screen, and it costs nothing at runtime.
local bigTextCache = {}
local bigTextCacheCount = 0

function Util.drawBigText(text, x, y, scale, alignment)
    alignment = alignment or kTextAlignment.left
    local key = text .. "@" .. scale
    local img = bigTextCache[key]
    if img == nil then
        local w, h = gfx.getTextSize(text)
        img = gfx.image.new(w, h, gfx.kColorClear)
        gfx.pushContext(img)
            gfx.drawText(text, 0, 0)
        gfx.popContext()
        -- The cache is keyed by string, and the set of totals/values we draw is
        -- small, but reset it if it ever grows unreasonably so we don't leak.
        if bigTextCacheCount > 250 then
            bigTextCache = {}
            bigTextCacheCount = 0
        end
        bigTextCache[key] = img
        bigTextCacheCount += 1
    end

    local w = img.width * scale
    if alignment == kTextAlignment.center then
        x = x - w / 2
    elseif alignment == kTextAlignment.right then
        x = x - w
    end
    img:drawScaled(x, y, scale)
    return w, img.height * scale
end

function Util.bigTextSize(text, scale)
    local w, h = gfx.getTextSize(text)
    return w * scale, h * scale
end

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
