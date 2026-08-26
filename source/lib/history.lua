-- The last few rolls, kept across launches.
--
-- playdate.datastore serialises a plain Lua table to a file in the game's save
-- folder and reads it back -- no format to define, as long as everything in the
-- table is a string, a number, a boolean, or another such table.

History = {}

History.MAX = 20

local FILE <const> = "history"

-- Stored alongside the data so that a future change to the entry format can be
-- recognised and discarded rather than half-read into a crash.
local VERSION <const> = 1

History.entries = {}

function History.load()
    local data = playdate.datastore.read(FILE)
    if type(data) == "table" and data.version == VERSION and type(data.entries) == "table" then
        History.entries = data.entries
    else
        History.entries = {}
    end
end

function History.save()
    playdate.datastore.write({ version = VERSION, entries = History.entries }, FILE)
end

-- Writing on every roll rather than only on the way out: the file is a few
-- hundred bytes, and a history that loses the last few rolls to a flat battery
-- is not much of a history.
function History.record(config, result)
    table.insert(History.entries, 1, {
        notation = result.notation,
        total = result.total,
        breakdown = Dice.breakdownText(config, result.parts),
        -- Enough to rebuild the throw, so a past roll can be thrown again.
        typeKey = config.spec.key,
        count = config.count,
        modifier = config.modifier,
        mode = config.mode,
    })
    while #History.entries > History.MAX do
        table.remove(History.entries)
    end
    History.save()
end

function History.latest()
    return History.entries[1]
end

function History.clear()
    History.entries = {}
    History.save()
end

-- Rebuild a config from a stored entry. Returns nil if the entry can't be
-- honoured -- the file is on disk and outlived whichever version wrote it, so
-- a die type that no longer exists is a real possibility rather than paranoia.
local VALID_MODES <const> = { normal = true, advantage = true, disadvantage = true }

function History.configOf(entry)
    for _, spec in ipairs(DiceTypes) do
        if spec.key == entry.typeKey then
            local mode = "normal"
            if spec.allowAdvantage and VALID_MODES[entry.mode] then
                mode = entry.mode
            end
            return {
                spec = spec,
                count = Util.clamp(entry.count or 1, 1, spec.maxCount),
                modifier = Util.clamp(entry.modifier or 0, Dice.MOD_MIN, Dice.MOD_MAX),
                mode = mode,
            }
        end
    end
    return nil
end
