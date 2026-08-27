-- Preferences that outlive a launch.
--
-- Same idea as history.lua: playdate.datastore serialises a plain Lua table to
-- the game's save folder and reads it back. It lives in its own file rather
-- than alongside the history because a corrupt history should not cost you your
-- settings, and a cleared history should not either.
--
-- Deliberately dumb: this module stores values and knows nothing about what any
-- of them mean. Whatever owns a setting is what decides which values are legal,
-- so a hand-edited file or a key left over from an older version is ignored by
-- the reader rather than trusted here.

Settings = {}

local FILE <const> = "settings"
local VERSION <const> = 1

Settings.values = {}

function Settings.load()
    local data = playdate.datastore.read(FILE)
    if type(data) == "table" and data.version == VERSION and type(data.values) == "table" then
        Settings.values = data.values
    else
        Settings.values = {}
    end
end

function Settings.save()
    playdate.datastore.write({ version = VERSION, values = Settings.values }, FILE)
end

function Settings.get(key, fallback)
    local value = Settings.values[key]
    if value == nil then
        return fallback
    end
    return value
end

-- Written straight through on every change. There are only a handful of bytes
-- in the file, and a preference that is lost to a flat battery is worse than a
-- write that was not strictly necessary.
function Settings.set(key, value)
    Settings.values[key] = value
    Settings.save()
end
