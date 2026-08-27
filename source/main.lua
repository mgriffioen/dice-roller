-- Dice Roller for Playdate
--
-- Three scenes: pick your dice (scenes/setup.lua), throw them with the crank
-- (scenes/roll.lua), and browse what you rolled before (scenes/history.lua).
-- Everything is drawn immediately each frame -- no sprites --
-- because at 30fps with a dozen shapes that is both fast enough and much easier
-- to follow than a sprite/z-order system.

import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/easing"

-- The alignment constants are a global in the SDK, but alias defensively so the
-- code reads the same either way.
kTextAlignment = kTextAlignment or playdate.graphics.kTextAlignment

import "lib/util"
import "lib/numerals"
import "lib/dice"
import "lib/layout"
import "lib/sfx"
import "lib/settings"
import "lib/history"
import "scenes/setup"
import "scenes/roll"
import "scenes/history"

local gfx <const> = playdate.graphics

-- Shared state. Scenes are plain tables with :enter() and :update(); the only
-- thing they need from each other is here.
Game = {
    scene = nil,
}

function Game.switchTo(scene, ...)
    Game.scene = scene
    scene:enter(...)
end

local function bootstrap()
    -- Lua's generator is deterministic unless we seed it, which would mean the
    -- same "random" sequence of rolls after every launch.
    local seconds, milliseconds = playdate.getSecondsSinceEpoch()
    math.randomseed(seconds * 1000 + milliseconds)

    playdate.display.setRefreshRate(30)
    gfx.setFont(gfx.getSystemFont())

    Sfx.init()
    Settings.load()
    History.load()

    -- Whichever way the dice were last thrown, that is how they are thrown now.
    -- setStyle ignores anything it does not recognise, so a settings file from
    -- another version cannot leave the dice in a style nothing can draw.
    Dice.setStyle(Settings.get("rollStyle", Dice.SCATTER))

    -- Three is the most the system menu takes, and this is the third. Anything
    -- else that wants to be configurable from here will have to displace one of
    -- them or move onto the setup screen as a field.
    local menu = playdate.getSystemMenu()
    menu:addCheckmarkMenuItem("sound", true, function(on)
        Sfx.enabled = on
    end)
    menu:addOptionsMenuItem("roll", Dice.STYLES, Dice.style, function(style)
        Settings.set("rollStyle", Dice.setStyle(style))
    end)
    menu:addMenuItem("clear history", function()
        History.clear()
    end)

    Game.switchTo(SetupScene)
end

bootstrap()

function playdate.update()
    Game.scene:update()
end
