dofile(DIR .. "/stub.lua")
dofile(OUT .. "/numerals.lua")
dofile(OUT .. "/dice.lua")
dofile(OUT .. "/settings.lua")

local failures = 0
local function check(ok, msg)
    if not ok then failures = failures + 1; print("FAIL: " .. msg) end
end

-- Nothing saved yet: every reader falls back to what it asked for.
resetDatastore()
Settings.load()
check(Settings.get("rollStyle", Dice.SCATTER) == Dice.SCATTER,
    "a missing setting should come back as the fallback")
check(Settings.get("neverHeardOfIt") == nil,
    "a missing setting with no fallback should be nil")

-- Set, and it survives a reload -- which is the whole point of the file.
Settings.set("rollStyle", Dice.IN_PLACE)
check(Settings.get("rollStyle", Dice.SCATTER) == Dice.IN_PLACE, "set should take effect")
Settings.values = {}
Settings.load()
check(Settings.get("rollStyle", Dice.SCATTER) == Dice.IN_PLACE,
    "a saved setting should survive a reload")

-- Settings and history are separate files, so clearing one leaves the other.
Settings.set("rollStyle", Dice.IN_PLACE)
playdate.datastore.write({ version = 1, entries = {} }, "history")
Settings.load()
check(Settings.get("rollStyle", Dice.SCATTER) == Dice.IN_PLACE,
    "writing the history file must not disturb the settings")

-- A corrupt, empty or future-versioned file is discarded rather than half-read.
for _, junk in ipairs({
    "not a table", 42, {}, { version = 1 }, { version = 99, values = { rollStyle = Dice.IN_PLACE } },
    { version = 1, values = "not a table" },
}) do
    resetDatastore()
    playdate.datastore.write(junk, "settings")
    Settings.load()
    check(Settings.get("rollStyle", Dice.SCATTER) == Dice.SCATTER,
        "a bad settings file should fall back to the defaults, not be trusted")
end

-- Dice.setStyle is the gate: it takes the two real styles and refuses anything
-- else, so a hand-edited file cannot leave the dice in an undrawable style.
check(Dice.setStyle(Dice.IN_PLACE) == Dice.IN_PLACE, "setStyle should accept 'in place'")
check(Dice.style == Dice.IN_PLACE, "setStyle should take effect")
check(Dice.setStyle(Dice.SCATTER) == Dice.SCATTER, "setStyle should accept 'scatter'")

for _, bogus in ipairs({ "sideways", "", "SCATTER", 7, true }) do
    Dice.setStyle(Dice.SCATTER)
    check(Dice.setStyle(bogus) == Dice.SCATTER,
        "setStyle should refuse " .. tostring(bogus))
    check(Dice.style == Dice.SCATTER, "a refused style must leave the old one in force")
end
Dice.setStyle(nil)
check(Dice.style == Dice.SCATTER, "setStyle(nil) should change nothing")

-- Both styles are offered to the menu, and the menu hands its choice straight
-- back, so every entry in the list has to be a style setStyle will take.
check(#Dice.STYLES == 2, "the menu should offer both styles")
for _, style in ipairs(Dice.STYLES) do
    Dice.setStyle(Dice.SCATTER)
    check(Dice.setStyle(style) == style, "the menu offers '" .. tostring(style) ..
        "', which setStyle refuses")
end

if failures == 0 then print("all settings checks passed")
else print(failures .. " check(s) failed"); os.exit(1) end
