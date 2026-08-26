dofile(DIR .. "/stub.lua")

local noop = function() end
setmetatable(Util, { __index = function() return noop end })
Sfx = setmetatable({}, { __index = function() return noop end })
Game = { switchTo = function(scene, ...) Game.current = scene; Game.args = { ... } end }
playdate.kButtonA, playdate.kButtonB = "a", "b"
playdate.kButtonUp, playdate.kButtonDown = "u", "d"
playdate.kButtonLeft, playdate.kButtonRight = "l", "r"

local Input = { crank = 0, justPressed = {} }
playdate.getCrankChange = function() return Input.crank, Input.crank end
playdate.isCrankDocked = function() return false end
playdate.buttonJustPressed = function(b) return Input.justPressed[b] == true end
playdate.buttonIsPressed = function() return false end

dofile(OUT .. "/numerals.lua")
dofile(OUT .. "/dice.lua")
dofile(OUT .. "/layout.lua")
dofile(OUT .. "/history.lua")
dofile(OUT .. "/history_scene.lua")
SetupScene = { adopt = function(self, config) self.adopted = config end }
RollScene = { enter = noop }

local failures = 0
local function check(ok, msg)
    if not ok then failures = failures + 1; print("FAIL: " .. msg) end
end

local function specFor(key)
    for _, s in ipairs(DiceTypes) do
        if s.key == key then return s end
    end
end

local function config(key, count, modifier, mode)
    return { spec = specFor(key), count = count or 1,
             modifier = modifier or 0, mode = mode or "normal" }
end

-- Record a roll the way the roll scene does: notation, total, and the parts.
local function record(key, count, modifier, mode, parts, total)
    local c = config(key, count, modifier, mode)
    History.record(c, {
        notation = Dice.notation(c),
        total = total or 7,
        parts = parts or { "7" },
    })
    return c
end

local function frame(button, crank)
    Input.justPressed = button and { [button] = true } or {}
    Input.crank = crank or 0
    HistoryScene:update()
    Input.justPressed = {}
    Input.crank = 0
end

-- 1. Recording, ordering and the cap ---------------------------------------
resetDatastore()
History.load()
check(#History.entries == 0, "a fresh history should be empty")
check(History.latest() == nil, "an empty history has no latest roll")

record("d6", 3, 2, "normal", { "4", "2", "6" }, 14)
check(#History.entries == 1, "one roll should be recorded")
check(History.latest().notation == "3d6+2", "notation was " .. History.latest().notation)
check(History.latest().total == 14, "total was " .. History.latest().total)
check(History.latest().breakdown == "(4 + 2 + 6)  + 2",
    "breakdown was " .. History.latest().breakdown)

record("d20", 1, 0, "advantage", { "17(5)" }, 17)
check(#History.entries == 2, "two rolls recorded")
check(History.latest().notation == "1d20 adv", "newest roll should come first")
check(History.entries[2].notation == "3d6+2", "the older roll should move down")

for i = 1, History.MAX + 10 do
    record("d6", 1, 0, "normal", { tostring(i) }, i)
end
check(#History.entries == History.MAX,
    "history should cap at " .. History.MAX .. ", got " .. #History.entries)
check(History.latest().total == History.MAX + 10, "the newest roll should survive the cap")
check(History.entries[History.MAX].total == 11, "the oldest surviving roll is wrong")

-- 2. It survives a restart -------------------------------------------------
local before = #History.entries
local newest = History.latest().notation
History.entries = {}
History.load()
check(#History.entries == before, "history should reload from the datastore")
check(History.latest().notation == newest, "the newest roll should survive a reload")

History.clear()
check(#History.entries == 0, "clear should empty the history")
History.entries = { "junk" }
History.load()
check(#History.entries == 0, "a cleared history should stay cleared across a reload")

-- Rubbish on disk must not take the game down with it.
playdate.datastore.write({ version = 999, entries = { {} } }, "history")
History.load()
check(#History.entries == 0, "a future file version should be discarded, not read")
playdate.datastore.write({ nonsense = true }, "history")
History.load()
check(#History.entries == 0, "a malformed file should be discarded")

-- 3. Rebuilding a throw from an entry --------------------------------------
resetDatastore()
History.load()
record("d20", 2, 3, "disadvantage", { "5(17)", "8(12)" }, 16)
local rebuilt = History.configOf(History.latest())
check(rebuilt ~= nil, "a stored d20 roll should rebuild")
check(Dice.notation(rebuilt) == "2d20+3 dis", "rebuilt as " .. Dice.notation(rebuilt))

check(History.configOf({ typeKey = "d13", count = 1, modifier = 0, mode = "normal" }) == nil,
    "an unknown die type should not rebuild")

-- Stale entries are clamped rather than trusted: this file outlives the code.
local wild = History.configOf({ typeKey = "d100", count = 99, modifier = 500, mode = "advantage" })
check(wild.count == specFor("d100").maxCount, "a stale count should clamp, got " .. wild.count)
check(wild.modifier == Dice.MOD_MAX, "a stale modifier should clamp, got " .. wild.modifier)
check(wild.mode == "normal", "advantage on a d100 should not survive, got " .. wild.mode)
local bogus = History.configOf({ typeKey = "d20", count = 1, modifier = 0, mode = "sideways" })
check(bogus.mode == "normal", "an unknown mode should fall back to normal, got " .. bogus.mode)

-- 4. Browsing the page ------------------------------------------------------
resetDatastore()
History.load()
for i = 1, 12 do
    record("d6", 1, 0, "normal", { tostring(i) }, i)
end
HistoryScene:enter()
check(HistoryScene.selected == 1, "should open on the newest roll")
check(HistoryScene.offset == 0, "should open scrolled to the top")

frame(playdate.kButtonDown)
check(HistoryScene.selected == 2, "down should move to the next roll")
for _ = 1, 4 do frame(playdate.kButtonDown) end
check(HistoryScene.selected == 6, "selection should reach the sixth roll")
check(HistoryScene.offset == 1, "the list should have scrolled by one, got " .. HistoryScene.offset)

frame(playdate.kButtonUp)
check(HistoryScene.selected == 5, "up should move back")
check(HistoryScene.offset == 1, "scrolling back into view should not move the window")

-- Wrapping from either end, with the window following.
HistoryScene:enter()
frame(playdate.kButtonUp)
check(HistoryScene.selected == 12, "up from the first roll should wrap to the last")
check(HistoryScene.offset == 12 - 5, "the window should follow the wrap, got " .. HistoryScene.offset)
frame(playdate.kButtonDown)
check(HistoryScene.selected == 1, "down from the last should wrap to the first")
check(HistoryScene.offset == 0, "the window should follow back to the top")

-- The crank browses too.
HistoryScene:enter()
frame(nil, 20 * 3)
check(HistoryScene.selected == 4, "three detents should move three rows, got " ..
    HistoryScene.selected)

-- Every row the page can show must render.
for start = 0, 12 - 1 do
    HistoryScene.selected = start + 1
    HistoryScene.offset = math.min(start, math.max(0, 12 - 5))
    HistoryScene:draw()
end

-- 5. A throws the selected roll again --------------------------------------
resetDatastore()
History.load()
record("d6", 3, 2, "normal", { "4", "2", "6" }, 14)
record("d20", 1, 0, "advantage", { "17(5)" }, 17)
HistoryScene:enter()
frame(playdate.kButtonDown)          -- select the older 3d6+2
Game.current = nil
frame(playdate.kButtonA)
check(Game.current == RollScene, "A should throw the selected roll again")
check(Dice.notation(Game.args[1]) == "3d6+2", "threw " .. Dice.notation(Game.args[1]))
check(SetupScene.adopted ~= nil and Dice.notation(SetupScene.adopted) == "3d6+2",
    "the setup screen should adopt the rebuilt throw")

frame(playdate.kButtonB)
check(Game.current == SetupScene, "B should go back to the setup screen")

-- 6. The empty page is navigable and does not crash ------------------------
resetDatastore()
History.load()
HistoryScene:enter()
frame(playdate.kButtonDown)
frame(playdate.kButtonUp)
frame(nil, 20 * 4)
Game.current = nil
frame(playdate.kButtonA)
check(Game.current == nil, "A on an empty history should do nothing")
HistoryScene:draw()
frame(playdate.kButtonB)
check(Game.current == SetupScene, "B should still work on an empty history")

if failures == 0 then print("all history checks passed")
else print(failures .. " check(s) failed"); os.exit(1) end
