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
gfx.image = { new = function(w, h)
    return { width = w or 8, height = h or 16, draw = noop, drawScaled = noop }
end }

-- An in-memory stand-in for playdate.datastore. The real one serialises the
-- table to a file; deep-copying here keeps the same property that a stored
-- table is a snapshot rather than a live reference.
local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, item in pairs(v) do out[k] = deepCopy(item) end
    return out
end

local files = {}

playdate = {
    graphics = gfx,
    geometry = { polygon = { new = function(...) return { close = noop } end } },
    datastore = {
        read = function(name) return deepCopy(files[name or "data"]) end,
        write = function(t, name) files[name or "data"] = deepCopy(t) end,
    },
}

-- Test helper: wipe the fake filesystem between cases.
function resetDatastore()
    files = {}
end
kTextAlignment = { left = 0, center = 1, right = 2 }
Util = { clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end }
