-- Minimal stand-ins for the bits of the SDK that dice.lua / layout.lua touch.
function class(name)
    local c = {}
    c.__index = c
    _G[name] = c
    return {
        extends = function(base)
            base = base or { init = function() end }
            c.super = base
            setmetatable(c, {
                __index = base,
                __call = function(cls, ...)
                    local o = setmetatable({}, cls)
                    o:init(...)
                    return o
                end,
            })
            return c
        end,
    }
end

local noop = function() end
local gfx = setmetatable({}, { __index = function() return noop end })
gfx.kColorWhite, gfx.kColorBlack, gfx.kColorClear = 1, 0, 2
gfx.getTextSize = function(s) return #s * 8, 16 end
gfx.image = { new = function() return { width = 8, height = 16, drawScaled = noop } end }

playdate = {
    graphics = gfx,
    geometry = { polygon = { new = function(...) return { close = noop } end } },
}
kTextAlignment = { left = 0, center = 1, right = 2 }
Util = { clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end,
         bigTextSize = function(t, s) return #t * 8 * s, 16 * s end,
         drawBigText = noop }
