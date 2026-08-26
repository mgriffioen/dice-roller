dofile(DIR .. "/stub.lua")

-- Extra stubs the roll scene needs.
local noop = function() end
setmetatable(Util, { __index = function() return noop end })
Sfx = setmetatable({}, { __index = function() return noop end })
Game = { switchTo = function(scene, ...) Game.current = scene end }
playdate.easingFunctions = { outCubic = function(t, b, c, d) return b + c * (t / d) end }
playdate.kButtonA, playdate.kButtonB = "a", "b"
playdate.kButtonUp, playdate.kButtonDown = "u", "d"
playdate.kButtonLeft, playdate.kButtonRight = "l", "r"

local Input = { crank = 0, docked = false, justPressed = {}, held = {} }
playdate.getCrankChange = function() return Input.crank, Input.crank end
playdate.isCrankDocked = function() return Input.docked end
playdate.buttonJustPressed = function(b) return Input.justPressed[b] == true end
playdate.buttonIsPressed = function(b) return Input.held[b] == true end

dofile(OUT .. "/dice.lua")
dofile(OUT .. "/layout.lua")
dofile(OUT .. "/roll.lua")

local failures = 0
local function check(ok, msg)
    if not ok then failures = failures + 1; print("FAIL: " .. msg) end
end

math.randomseed(99)

-- Drive a whole roll: crank hard, then stop, and see that it lands.
local function playThrough(spec, count, useButton)
    RollScene:enter(spec, count)
    Input.docked = useButton or false
    Input.crank = 0
    Input.held = {}

    local frames = 0
    -- Phase 1: crank (or hold A) until the meter is full.
    while RollScene.cranked < 540 and frames < 600 do
        if useButton then Input.held[playdate.kButtonA] = true else Input.crank = 22 end
        RollScene:update(); frames = frames + 1
    end
    check(RollScene.state == "tumbling",
        spec.key .. ": expected tumbling after cranking, got " .. RollScene.state)

    -- Phase 2: let go and wait for the result.
    Input.crank = 0
    Input.held = {}
    while RollScene.state ~= "result" and frames < 900 do
        RollScene:update(); frames = frames + 1
    end
    check(RollScene.state == "result",
        spec.key .. " x" .. count .. ": never reached the result state (" ..
        RollScene.state .. " after " .. frames .. " frames)")
    return RollScene.result, frames
end

for _, spec in ipairs(DiceTypes) do
    for _, count in ipairs({ 1, 2, spec.maxCount }) do
        local r, frames = playThrough(spec, count)
        check(r ~= nil, spec.key .. " x" .. count .. ": no result")
        if r then
            check(r.total >= count and r.total <= count * spec.sides,
                spec.key .. " x" .. count .. ": total " .. r.total .. " out of range")
            check(#r.parts == count,
                spec.key .. " x" .. count .. ": expected " .. count .. " parts, got " .. #r.parts)
            check(r.high >= r.low, "high/low inverted")
            check(Game.lastResult == r, "lastResult not published")
            -- Every die must be settled and stationary once the overlay is up.
            for _, d in ipairs(RollScene.dice) do
                check(d.settled, spec.key .. ": a die is still tumbling on the result screen")
            end
        end
        check(frames < 260, spec.key .. " x" .. count .. ": took " .. frames ..
            " frames, that feels too slow")
    end
end

-- The docked-crank fallback (hold A) must work too.
local r = playThrough(DiceTypes[3], 3, true)
check(r ~= nil and r.total >= 3 and r.total <= 18, "A-button fallback produced " .. tostring(r and r.total))

-- Natural 20 / natural 1 banners, single d20 only.
local d20 = nil
for _, s in ipairs(DiceTypes) do if s.key == "d20" then d20 = s end end
RollScene:enter(d20, 1)
RollScene.dice[1].value = 20
RollScene:computeResult()
check(RollScene.result.banner == "NATURAL 20!", "missing nat 20 banner")
RollScene.dice[1].value = 1
RollScene:computeResult()
check(RollScene.result.banner == "NATURAL 1", "missing nat 1 banner")
RollScene.dice[1].value = 13
RollScene:computeResult()
check(RollScene.result.banner == nil, "banner shown for a plain roll")
RollScene:enter(d20, 2)
RollScene.dice[1].value, RollScene.dice[2].value = 20, 20
RollScene:computeResult()
check(RollScene.result.banner == nil, "banner should not appear for multiple d20s")
check(RollScene.result.total == 40, "2d20 total wrong")

-- A: reroll from the result screen; B: back to setup.
SetupScene = { enter = noop }
RollScene:enter(d20, 1)
RollScene.state = "result"
Input.justPressed = { [playdate.kButtonA] = true }
RollScene:update()
check(RollScene.state == "ready", "A on the result screen should start a fresh throw")
Input.justPressed = { [playdate.kButtonB] = true }
RollScene:update()
check(Game.current == SetupScene, "B should return to the setup scene")

-- Rolls must actually vary.
Input.justPressed = {}
local totals = {}
for _ = 1, 40 do
    local res = playThrough(d20, 1)
    totals[res.total] = true
end
local distinct = 0
for _ in pairs(totals) do distinct = distinct + 1 end
check(distinct > 5, "40 d20 rolls only produced " .. distinct .. " distinct totals")

if failures == 0 then print("all roll-scene checks passed")
else print(failures .. " check(s) failed"); os.exit(1) end
