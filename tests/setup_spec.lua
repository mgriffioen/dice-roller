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
dofile(OUT .. "/setup.lua")
resetDatastore()
History.load()
RollScene = { enter = noop }

local failures = 0
local function check(ok, msg)
    if not ok then failures = failures + 1; print("FAIL: " .. msg) end
end

local function typeIndexOf(key)
    for i, s in ipairs(DiceTypes) do
        if s.key == key then return i end
    end
end

-- Press a button (or turn the crank) for exactly one frame.
local function frame(button, crank)
    Input.justPressed = button and { [button] = true } or {}
    Input.crank = crank or 0
    SetupScene:update()
    Input.justPressed = {}
    Input.crank = 0
end

local function fresh(typeKey)
    SetupScene.config = Dice.newConfig()
    SetupScene.typeIndex = typeIndexOf(typeKey or "d6")
    SetupScene.selected = 1
    SetupScene:enter()
end

local function fieldIds()
    local ids = {}
    for _, f in ipairs(SetupScene:fields()) do ids[#ids + 1] = f.id end
    return table.concat(ids, ",")
end

-- 1. The advantage row exists only for the d20 -----------------------------
fresh("d6")
check(fieldIds() == "type,count,mod", "d6 fields were " .. fieldIds())
fresh("d20")
check(fieldIds() == "type,count,mod,adv", "d20 fields were " .. fieldIds())
fresh("d100")
check(fieldIds() == "type,count,mod", "d100 fields were " .. fieldIds())

-- 2. Selection wraps, and never points past the end of a shorter list -------
fresh("d20")
check(SetupScene.selected == 1, "should start on the first field")
frame(playdate.kButtonUp)
check(SetupScene.selected == 4, "up from the first field should wrap to the last")
frame(playdate.kButtonDown)
check(SetupScene.selected == 1, "down from the last field should wrap to the first")

-- Sitting on the d20-only row and then switching away from the d20 must not
-- leave the cursor pointing at a row that no longer exists.
fresh("d20")
SetupScene.selected = 4
SetupScene.typeIndex = typeIndexOf("d6")
SetupScene:refresh()
check(SetupScene.selected == 3, "selection should clamp to " .. fieldIds() ..
    ", got " .. SetupScene.selected)

-- 3. Die type wraps in both directions -------------------------------------
fresh("d2")
frame(playdate.kButtonLeft)
check(SetupScene.config.spec.key == "d100", "left from d2 should wrap to d100")
frame(playdate.kButtonRight)
check(SetupScene.config.spec.key == "d2", "right from d100 should wrap to d2")

-- 4. Count wraps inside the type's limit, and clamps when the limit shrinks --
fresh("d6")
SetupScene.selected = 2
SetupScene.config.count = DiceTypes[SetupScene.typeIndex].maxCount
frame(playdate.kButtonRight)
check(SetupScene.config.count == 1, "count should wrap back to 1")
frame(playdate.kButtonLeft)
check(SetupScene.config.count == 12, "count should wrap back to the maximum")

fresh("d6")
SetupScene.config.count = 12
SetupScene.typeIndex = typeIndexOf("d100")
SetupScene:refresh()
check(SetupScene.config.count == 6,
    "12 dice must clamp to the d100 limit of 6, got " .. SetupScene.config.count)

-- 5. The modifier clamps rather than wrapping ------------------------------
fresh("d6")
SetupScene.selected = 3
for _ = 1, 30 do frame(playdate.kButtonRight) end
check(SetupScene.config.modifier == Dice.MOD_MAX,
    "modifier should stop at " .. Dice.MOD_MAX .. ", got " .. SetupScene.config.modifier)
for _ = 1, 60 do frame(playdate.kButtonLeft) end
check(SetupScene.config.modifier == Dice.MOD_MIN,
    "modifier should stop at " .. Dice.MOD_MIN .. ", got " .. SetupScene.config.modifier)

-- 6. The crank drives the selected field, in whole detents ------------------
fresh("d6")
SetupScene.selected = 3
frame(nil, 12 * 5)
check(SetupScene.config.modifier == 5, "five detents of crank should be +5, got " ..
    SetupScene.config.modifier)
frame(nil, 12 * 2.5)
check(SetupScene.config.modifier == 7, "half a detent should not round up, got " ..
    SetupScene.config.modifier)
frame(nil, 12 * 0.5)
check(SetupScene.config.modifier == 8, "leftover crank should carry into the next step")
frame(nil, -12 * 3)
check(SetupScene.config.modifier == 5, "cranking back should subtract, got " ..
    SetupScene.config.modifier)

-- Crank on a different field moves that field instead.
fresh("d6")
SetupScene.selected = 2
frame(nil, 12 * 3)
check(SetupScene.config.count == 4, "crank should drive the count row, got " ..
    SetupScene.config.count)

-- 7. Advantage cycles, and resets when the d20 is left ---------------------
fresh("d20")
SetupScene.selected = 4
check(SetupScene.config.mode == "normal", "should start normal")
frame(playdate.kButtonRight)
check(SetupScene.config.mode == "advantage", "right should reach advantage")
frame(playdate.kButtonRight)
check(SetupScene.config.mode == "disadvantage", "right again should reach disadvantage")
frame(playdate.kButtonRight)
check(SetupScene.config.mode == "normal", "right again should cycle back to normal")
frame(playdate.kButtonLeft)
check(SetupScene.config.mode == "disadvantage", "left should cycle backwards")

SetupScene.typeIndex = typeIndexOf("d8")
SetupScene:refresh()
check(SetupScene.config.mode == "normal",
    "leaving the d20 should clear advantage, got " .. SetupScene.config.mode)

-- 8. A hands the finished config to the roll scene -------------------------
fresh("d20")
SetupScene.selected = 3
frame(nil, 12 * 3)                    -- +3
SetupScene.selected = 4
frame(playdate.kButtonRight)          -- advantage
Game.current = nil
frame(playdate.kButtonA)
check(Game.current == RollScene, "A should switch to the roll scene")
local passed = Game.args[1]
check(passed == SetupScene.config, "the roll scene should receive the live config")
check(Dice.notation(passed) == "1d20+3 adv", "handed over " .. Dice.notation(passed))

-- 9. Every field renders a value, for every die type -----------------------
for i = 1, #DiceTypes do
    SetupScene.typeIndex = i
    SetupScene:refresh()
    for _, f in ipairs(SetupScene:fields()) do
        local v = SetupScene:valueText(f.id)
        check(type(v) == "string" and #v > 0,
            DiceTypes[i].key .. " field " .. f.id .. " had no value")
    end
    SetupScene:draw()
end

if failures == 0 then print("all setup checks passed")
else print(failures .. " check(s) failed"); os.exit(1) end
