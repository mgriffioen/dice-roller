-- Dice Roller for Playdate
--
-- Two scenes: pick your dice (scenes/setup.lua), then throw them with the crank
-- (scenes/roll.lua). Everything is drawn immediately each frame -- no sprites --
-- because at 30fps with a dozen shapes that is both fast enough and much easier
-- to follow than a sprite/z-order system.

import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/easing"

-- The alignment constants are a global in the SDK, but alias defensively so the
-- code reads the same either way.
kTextAlignment = kTextAlignment or playdate.graphics.kTextAlignment

import "lib/util"
import "lib/dice"
import "lib/layout"
import "lib/sfx"
import "scenes/setup"
import "scenes/roll"

local gfx <const> = playdate.graphics

-- Shared state. Scenes are plain tables with :enter() and :update(); the only
-- thing they need from each other is here.
Game = {
    scene = nil,
    lastResult = nil,
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

    local menu = playdate.getSystemMenu()
    menu:addCheckmarkMenuItem("sound", true, function(on)
        Sfx.enabled = on
    end)

    Game.switchTo(SetupScene)
end

bootstrap()

function playdate.update()
    Game.scene:update()
end
