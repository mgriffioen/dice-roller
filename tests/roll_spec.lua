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

dofile(OUT .. "/numerals.lua")
dofile(OUT .. "/dice.lua")
dofile(OUT .. "/layout.lua")
dofile(OUT .. "/history.lua")
dofile(OUT .. "/roll.lua")
resetDatastore()
History.load()

local failures = 0
local function check(ok, msg)
    if not ok then failures = failures + 1; print("FAIL: " .. msg) end
end

math.randomseed(99)

local d20base
for _, spec in ipairs(DiceTypes) do
    if spec.key == "d20" then d20base = spec end
end

-- Drive a whole roll: crank hard, then stop, and see that it lands.
local function playThrough(config, useButton)
    RollScene:enter(config)
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
        Dice.notation(config) .. ": expected tumbling after cranking, got " .. RollScene.state)

    -- Phase 2: let go and wait for the result.
    Input.crank = 0
    Input.held = {}
    while RollScene.state ~= "result" and frames < 900 do
        RollScene:update(); frames = frames + 1
    end
    check(RollScene.state == "result",
        Dice.notation(config) .. ": never reached the result state (" ..
        RollScene.state .. " after " .. frames .. " frames)")
    return RollScene.result, frames
end

local function config(spec, count, modifier, mode)
    return { spec = spec, count = count or 1, modifier = modifier or 0, mode = mode or "normal" }
end

for _, spec in ipairs(DiceTypes) do
    for _, count in ipairs({ 1, 2, spec.maxCount }) do
        for _, mode in ipairs({ "normal", "advantage", "disadvantage" }) do
            for _, modifier in ipairs({ 0, 4, -3 }) do
                local c = config(spec, count, modifier, mode)
                local r, frames = playThrough(c)
                local name = Dice.notation(c)
                check(r ~= nil, name .. ": no result")
                if r then
                    local lo, hi = Dice.range(c)
                    check(r.total >= lo and r.total <= hi,
                        name .. ": total " .. r.total .. " outside " .. lo .. ".." .. hi)
                    check(r.total == r.diceTotal + modifier,
                        name .. ": total does not equal dice + modifier")
                    check(#r.parts == count,
                        name .. ": expected " .. count .. " parts, got " .. #r.parts)
                    check(r.high >= r.low, "high/low inverted")
                    -- The roll should have landed in the history.
                    local logged = History.latest()
                    check(logged ~= nil and logged.total == r.total and
                          logged.notation == r.notation,
                        name .. ": the roll was not recorded in the history")
                    for _, d in ipairs(RollScene.dice) do
                        check(d.settled, name .. ": a die is still tumbling on the result screen")
                    end
                    -- Exactly one die per pair is crossed out, and only under
                    -- advantage or disadvantage.
                    local dropped = 0
                    for _, d in ipairs(RollScene.dice) do
                        if d.dropped then dropped = dropped + 1 end
                    end
                    check(dropped == (Dice.usesAdvantage(c) and count or 0),
                        name .. ": " .. dropped .. " dice crossed out, expected " ..
                        (Dice.usesAdvantage(c) and count or 0))
                end
                check(frames < 260, name .. ": took " .. frames .. " frames, that feels too slow")
            end
        end
    end
end

-- The throw is a throw: the dice travel, they stay in the tray while they do
-- it, and they are back in their reading positions before the overlay is up.
-- Without this, "rolling" quietly degrades to spinning on the spot again.
local PLAY = { left = 8, top = 28, right = 392, bottom = 192 }

local function watchedThrow(c, rate)
    RollScene:enter(c)
    Input.docked = false
    Input.crank = rate or 22
    Input.held = {}

    local travel, prev = {}, {}
    for i, d in ipairs(RollScene.dice) do
        travel[i] = 0
        prev[i] = { d.x, d.y }
    end

    local frames, strayed, sank, highest = 0, 0, 0, 0
    while RollScene.state ~= "result" and frames < 600 do
        if RollScene.cranked >= 540 then Input.crank = 0 end
        RollScene:update()
        frames = frames + 1
        for i, d in ipairs(RollScene.dice) do
            local dx, dy = d.x - prev[i][1], d.y - prev[i][2]
            travel[i] = travel[i] + math.sqrt(dx * dx + dy * dy)
            prev[i] = { d.x, d.y }
            -- The physics keeps a die's centre inside the tray, and its height
            -- above the table is never negative.
            local r = d.size * 0.45
            if d.x < PLAY.left + r - 0.01 or d.x > PLAY.right - r + 0.01 or
               d.y < PLAY.top + r - 0.01 or d.y > PLAY.bottom - r + 0.01 then
                strayed = strayed + 1
            end
            if d.z < 0 then sank = sank + 1 end
            highest = math.max(highest, d.z)
        end
    end
    return travel, frames, strayed, sank, highest
end

for _, c in ipairs({
    config(DiceTypes[3], 1), config(DiceTypes[3], 6), config(d20base, 12),
    config(DiceTypes[8], 6), config(d20base, 12, 0, "advantage"),
}) do
    local name = Dice.notation(c)
    local travel, frames, strayed, sank, highest = watchedThrow(c)

    check(strayed == 0, name .. ": a die left the tray on " .. strayed .. " frames")
    check(sank == 0, name .. ": a die went below the table on " .. sank .. " frames")
    check(highest > 6, name .. ": the dice never left the table -- no bounce")

    local least = math.huge
    for _, distance in ipairs(travel) do least = math.min(least, distance) end
    -- The tray is 384x164. A die that only jiggled would manage a few dozen
    -- pixels; one that was actually thrown crosses it more than once.
    check(least > 120, name .. ": the least-travelled die covered only " ..
        string.format("%.0f", least) .. "px -- the dice are not really rolling")

    -- No two dice may follow the same path, or a handful reads as one object.
    if #travel > 1 then
        local same = 0
        for i = 2, #travel do
            if math.abs(travel[i] - travel[1]) < 0.5 then same = same + 1 end
        end
        check(same == 0, name .. ": " .. same .. " dice travelled in lockstep")
    end

    -- Run the gather and the landing squash out, then everything is home,
    -- flat on the table and seated square.
    for _ = 1, 40 do RollScene:update() end
    for _, d in ipairs(RollScene.dice) do
        check(math.abs(d.x - d.homeX) < 0.01 and math.abs(d.y - d.homeY) < 0.01,
            name .. ": a die stopped away from its reading position")
        check(d.z == 0 and d.zv == 0, name .. ": a die is still in the air")
        check(d.vx == 0 and d.vy == 0 and d.spin == 0,
            name .. ": a settled die is still moving")
        check(d.landFrames == 0 and d.glideFrames == 0,
            name .. ": a settled die never finished landing")
    end
end

-- However hard the crank is turned, the dice stay on the table. Cranking harder
-- means a bigger shove and a shove lifts the die, so without a ceiling on the
-- hop a violent throw fires the whole handful off the top of the screen.
for _, rate in ipairs({ 22, 60, 120, 400 }) do
    local _, _, strayed, _, highest = watchedThrow(config(d20base, 3), rate)
    check(highest < 32, "cranking at " .. rate ..
        " deg/frame threw the dice " .. string.format("%.0f", highest) ..
        "px into the air -- off the top of the screen")
    check(strayed == 0, "cranking at " .. rate .. " threw a die out of the tray")
end

-- A fresh throw starts from the reading positions again, not from wherever the
-- last one happened to end.
RollScene:enter(config(d20base, 4))
watchedThrow(config(d20base, 4))
RollScene:reset()
for _, d in ipairs(RollScene.dice) do
    check(d.x == d.homeX and d.y == d.homeY and d.z == 0 and not d.settled,
        "reset should put the dice back where the layout wants them")
end

-- Advantage really does bias the result upwards.
local function meanTotal(c, n)
    local sum = 0
    for _ = 1, n do sum = sum + playThrough(c).total end
    return sum / n
end
local plain = meanTotal(config(d20base, 1), 150)
local high  = meanTotal(config(d20base, 1, 0, "advantage"), 150)
local low   = meanTotal(config(d20base, 1, 0, "disadvantage"), 150)
check(high > plain and plain > low,
    "expected disadvantage < normal < advantage, got " ..
    string.format("%.1f / %.1f / %.1f", low, plain, high))

-- The docked-crank fallback (hold A) must work too.
local r = playThrough(config(DiceTypes[3], 3), true)
check(r ~= nil and r.total >= 3 and r.total <= 18, "A-button fallback produced " .. tostring(r and r.total))

-- Natural 20 / natural 1 banners, single d20 only, and judged on the die
-- rather than the total.
local d20 = d20base
RollScene:enter(config(d20, 1))
RollScene.dice[1].value = 20
RollScene:computeResult()
check(RollScene.result.banner == "NATURAL 20!", "missing nat 20 banner")
RollScene.dice[1].value = 1
RollScene:computeResult()
check(RollScene.result.banner == "NATURAL 1", "missing nat 1 banner")
RollScene.dice[1].value = 13
RollScene:computeResult()
check(RollScene.result.banner == nil, "banner shown for a plain roll")

-- A +7 modifier must not turn a 13 into a natural 20, nor a 20 into a non-crit.
RollScene:enter(config(d20, 1, 7))
RollScene.dice[1].value = 13
RollScene:computeResult()
check(RollScene.result.total == 20, "13 + 7 should total 20")
check(RollScene.result.banner == nil, "a modifier must not manufacture a natural 20")
RollScene.dice[1].value = 20
RollScene:computeResult()
check(RollScene.result.banner == "NATURAL 20!", "a modifier must not hide a natural 20")
check(RollScene.result.total == 27, "20 + 7 should total 27")

-- Under advantage the banner follows the kept die.
RollScene:enter(config(d20, 1, 0, "advantage"))
RollScene.dice[1].value, RollScene.dice[2].value = 20, 3
RollScene:computeResult()
check(RollScene.result.banner == "NATURAL 20!", "advantage should keep the natural 20")
check(RollScene.result.total == 20, "advantage total should be the kept die")
RollScene:enter(config(d20, 1, 0, "disadvantage"))
RollScene.dice[1].value, RollScene.dice[2].value = 20, 1
RollScene:computeResult()
check(RollScene.result.banner == "NATURAL 1", "disadvantage should keep the natural 1")

RollScene:enter(config(d20, 2))
RollScene.dice[1].value, RollScene.dice[2].value = 20, 20
RollScene:computeResult()
check(RollScene.result.banner == nil, "banner should not appear for multiple d20s")
check(RollScene.result.total == 40, "2d20 total wrong")

-- The breakdown line brackets the dice once a modifier is in play.
RollScene:enter(config(DiceTypes[3], 3, 2))
RollScene.dice[1].value, RollScene.dice[2].value, RollScene.dice[3].value = 4, 2, 6
RollScene:computeResult()
local function breakdown()
    return Dice.breakdownText(RollScene.config, RollScene.result.parts)
end
check(breakdown() == "(4 + 2 + 6)  + 2", "breakdown was " .. breakdown())
RollScene:enter(config(DiceTypes[3], 3, 0))
RollScene.dice[1].value, RollScene.dice[2].value, RollScene.dice[3].value = 4, 2, 6
RollScene:computeResult()
check(breakdown() == "4 + 2 + 6", "breakdown was " .. breakdown())
RollScene:enter(config(d20, 1, -1))
RollScene.dice[1].value = 11
RollScene:computeResult()
check(breakdown() == "11  - 1", "breakdown was " .. breakdown())

-- A: reroll from the result screen; B: back to setup.
SetupScene = { enter = noop }
RollScene:enter(config(d20, 1))
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
    local res = playThrough(config(d20, 1))
    totals[res.total] = true
end
local distinct = 0
for _ in pairs(totals) do distinct = distinct + 1 end
check(distinct > 5, "40 d20 rolls only produced " .. distinct .. " distinct totals")

if failures == 0 then print("all roll-scene checks passed")
else print(failures .. " check(s) failed"); os.exit(1) end
