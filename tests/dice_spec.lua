dofile(DIR .. "/stub.lua")
dofile(OUT .. "/dice.lua")
dofile(OUT .. "/layout.lua")

local failures = 0
local function check(ok, msg)
    if not ok then
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

math.randomseed(12345)

-- 1. Every die type produces values in range -------------------------------
for _, spec in ipairs(DiceTypes) do
    local seen = {}
    for _ = 1, 20000 do
        local _, groups = Dice.build(spec, 1)
        for _, g in ipairs(groups) do
            for _, d in ipairs(g) do d.value = d:randomValue() end
            local v = Dice.groupValue(spec, g)
            check(v >= 1 and v <= spec.sides,
                spec.key .. " produced out-of-range value " .. tostring(v))
            seen[v] = (seen[v] or 0) + 1
        end
    end
    local distinct = 0
    for _ in pairs(seen) do distinct = distinct + 1 end
    check(distinct == spec.sides,
        spec.key .. " only ever produced " .. distinct .. " of " .. spec.sides .. " faces")
end

-- 2. Percentile edge cases --------------------------------------------------
local d100 = DiceTypes[#DiceTypes]
check(d100.percentile, "last dice type should be the percentile one")
local _, pgroups = Dice.build(d100, 1)
local g = pgroups[1]
g[1].value, g[2].value = 0, 0
check(Dice.groupValue(d100, g) == 100, "00 + 0 must read as 100")
check(Dice.groupLabel(d100, g) == "00+0=100", "label was " .. Dice.groupLabel(d100, g))
g[1].value, g[2].value = 0, 1
check(Dice.groupValue(d100, g) == 1, "00 + 1 must be 1")
g[1].value, g[2].value = 90, 9
check(Dice.groupValue(d100, g) == 99, "90 + 9 must be 99")
g[1].value, g[2].value = 70, 0
check(Dice.groupValue(d100, g) == 70, "70 + 0 must be 70")

-- 3. Totals add up ----------------------------------------------------------
for _, spec in ipairs(DiceTypes) do
    for count = 1, spec.maxCount do
        local all, groups = Dice.build(spec, count)
        check(#groups == count, spec.key .. " x" .. count .. ": wrong group count")
        check(#all == count * (spec.percentile and 2 or 1),
            spec.key .. " x" .. count .. ": wrong physical dice count")
        local total = 0
        for _, gr in ipairs(groups) do
            for _, d in ipairs(gr) do d.value = d:randomValue() end
            total = total + Dice.groupValue(spec, gr)
        end
        check(total >= count and total <= count * spec.sides,
            spec.key .. " x" .. count .. ": total " .. total .. " outside " ..
            count .. ".." .. count * spec.sides)
    end
end

-- 4. Layout keeps every die on screen --------------------------------------
local AX, AY, AW, AH = 8, 28, 384, 164
for _, spec in ipairs(DiceTypes) do
    for count = 1, spec.maxCount do
        local all, groups = Dice.build(spec, count)
        Layout.arrange(groups, spec, AX, AY, AW, AH)
        for _, d in ipairs(all) do
            local r = d.size / 2
            check(d.size >= 20, spec.key .. " x" .. count .. ": die too small (" .. d.size .. ")")
            check(d.x - r >= 0 and d.x + r <= 400,
                spec.key .. " x" .. count .. ": die off screen horizontally (x=" ..
                string.format("%.1f", d.x) .. " size=" .. string.format("%.1f", d.size) .. ")")
            check(d.y - r >= 24 and d.y + r <= 196,
                spec.key .. " x" .. count .. ": die outside the play area (y=" ..
                string.format("%.1f", d.y) .. " size=" .. string.format("%.1f", d.size) .. ")")
        end
        -- Percentile pairs must not overlap each other.
        if spec.percentile then
            for _, gr in ipairs(groups) do
                check(gr[2].x > gr[1].x, "percentile pair not left-to-right")
            end
        end
    end
end

if failures == 0 then
    print("all checks passed")
else
    print(failures .. " check(s) failed")
    os.exit(1)
end
