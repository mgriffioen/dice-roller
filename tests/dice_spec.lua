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

local function config(spec, count, modifier, mode)
    return { spec = spec, count = count or 1, modifier = modifier or 0, mode = mode or "normal" }
end

local function rollAll(groups)
    for _, g in ipairs(groups) do
        for _, d in ipairs(g) do d.value = d:randomValue() end
    end
end

local d20, d100
for _, s in ipairs(DiceTypes) do
    if s.key == "d20" then d20 = s end
    if s.key == "d100" then d100 = s end
end

-- 1. Every die type produces every one of its faces, and nothing else --------
for _, spec in ipairs(DiceTypes) do
    local seen = {}
    local c = config(spec, 1)
    for _ = 1, 20000 do
        local _, groups = Dice.build(c)
        rollAll(groups)
        local v = Dice.groupValue(c, groups[1])
        check(v >= 1 and v <= spec.sides,
            spec.key .. " produced out-of-range value " .. tostring(v))
        seen[v] = true
    end
    local distinct = 0
    for _ in pairs(seen) do distinct = distinct + 1 end
    check(distinct == spec.sides,
        spec.key .. " only ever produced " .. distinct .. " of " .. spec.sides .. " faces")
end

-- 2. Percentile edge cases --------------------------------------------------
local pc = config(d100, 1)
local _, pgroups = Dice.build(pc)
local g = pgroups[1]
g[1].value, g[2].value = 0, 0
check(Dice.groupValue(pc, g) == 100, "00 + 0 must read as 100")
check(Dice.groupLabel(pc, g) == "00+0=100", "label was " .. Dice.groupLabel(pc, g))
g[1].value, g[2].value = 0, 1
check(Dice.groupValue(pc, g) == 1, "00 + 1 must be 1")
g[1].value, g[2].value = 90, 9
check(Dice.groupValue(pc, g) == 99, "90 + 9 must be 99")
g[1].value, g[2].value = 70, 0
check(Dice.groupValue(pc, g) == 70, "70 + 0 must be 70")

-- 3. Advantage and disadvantage --------------------------------------------
check(Dice.groupSize(config(d20, 1, 0, "advantage")) == 2, "advantage should roll two dice")
check(Dice.groupSize(config(d20, 1, 0, "normal")) == 1, "normal d20 should roll one die")
-- Only the d20 offers it; asking for it on a d6 must change nothing.
for _, spec in ipairs(DiceTypes) do
    if spec.key ~= "d20" then
        check(Dice.groupSize(config(spec, 1, 0, "advantage")) ==
              (spec.percentile and 2 or 1),
            spec.key .. " should ignore advantage")
        check(not Dice.usesAdvantage(config(spec, 1, 0, "advantage")),
            spec.key .. " should not use advantage")
    end
end

local adv = config(d20, 1, 0, "advantage")
local dis = config(d20, 1, 0, "disadvantage")
for _, pair in ipairs({ {5, 17}, {17, 5}, {12, 12}, {1, 20}, {20, 1} }) do
    local _, gs = Dice.build(adv)
    gs[1][1].value, gs[1][2].value = pair[1], pair[2]
    check(Dice.groupValue(adv, gs[1]) == math.max(pair[1], pair[2]),
        "advantage should keep the higher of " .. pair[1] .. "/" .. pair[2])
    check(Dice.groupValue(dis, gs[1]) == math.min(pair[1], pair[2]),
        "disadvantage should keep the lower of " .. pair[1] .. "/" .. pair[2])
end

-- The label names the kept die first and brackets the discarded one.
local _, ags = Dice.build(adv)
ags[1][1].value, ags[1][2].value = 5, 17
check(Dice.groupLabel(adv, ags[1]) == "17(5)", "advantage label was " .. Dice.groupLabel(adv, ags[1]))
check(Dice.groupLabel(dis, ags[1]) == "5(17)", "disadvantage label was " .. Dice.groupLabel(dis, ags[1]))

-- markDropped crosses out exactly the die that did not count.
local _, mgs = Dice.build(adv)
mgs[1][1].value, mgs[1][2].value = 5, 17
Dice.markDropped(adv, mgs)
check(not mgs[1].marked, "a pair that has not landed must not be marked yet")
mgs[1][1].settled, mgs[1][2].settled = true, true
Dice.markDropped(adv, mgs)
check(mgs[1][1].dropped and not mgs[1][2].dropped,
    "advantage should cross out the lower die")
-- A tie keeps the first die, so exactly one is always crossed out.
local _, tgs = Dice.build(adv)
tgs[1][1].value, tgs[1][2].value = 9, 9
tgs[1][1].settled, tgs[1][2].settled = true, true
Dice.markDropped(adv, tgs)
check(not tgs[1][1].dropped and tgs[1][2].dropped, "a tie should keep the first die")

-- Advantage does not move the ends of the range.
local lo, hi = Dice.range(adv)
check(lo == 1 and hi == 20, "advantage range should still be 1-20, got " .. lo .. "-" .. hi)

-- 4. Modifiers --------------------------------------------------------------
local mods = config(d20, 1, 3)
local _, mgroups = Dice.build(mods)
mgroups[1][1].value = 14
local total, diceTotal = Dice.total(mods, mgroups)
check(total == 17, "14 + 3 should be 17, got " .. total)
check(diceTotal == 14, "dice subtotal should ignore the modifier, got " .. diceTotal)

local neg = config(d20, 1, -2)
mgroups[1][1].value = 14
check(Dice.total(neg, mgroups) == 12, "14 - 2 should be 12")

check(Dice.notation(config(d20, 1, 0)) == "1d20", Dice.notation(config(d20, 1, 0)))
check(Dice.notation(config(d20, 2, 3)) == "2d20+3", Dice.notation(config(d20, 2, 3)))
check(Dice.notation(config(d20, 1, -2)) == "1d20-2", Dice.notation(config(d20, 1, -2)))
check(Dice.notation(config(d20, 1, 3, "advantage")) == "1d20+3 adv",
    Dice.notation(config(d20, 1, 3, "advantage")))
check(Dice.notation(config(d20, 1, 0, "disadvantage")) == "1d20 dis",
    Dice.notation(config(d20, 1, 0, "disadvantage")))
check(Dice.notation(config(DiceTypes[3], 3, 0, "advantage")) == "3d6",
    "a d6 must not advertise advantage")

lo, hi = Dice.range(config(DiceTypes[3], 3, 2))
check(lo == 5 and hi == 20, "3d6+2 should span 5-20, got " .. lo .. "-" .. hi)
lo, hi = Dice.range(config(d100, 2, -1))
check(lo == 1 and hi == 199, "2d100-1 should span 1-199, got " .. lo .. "-" .. hi)

-- 5. Totals stay inside the advertised range -------------------------------
for _, spec in ipairs(DiceTypes) do
    for _, modifier in ipairs({ Dice.MOD_MIN, -3, 0, 5, Dice.MOD_MAX }) do
        for _, mode in ipairs({ "normal", "advantage", "disadvantage" }) do
            for count = 1, spec.maxCount do
                local c = config(spec, count, modifier, mode)
                local all, groups = Dice.build(c)
                check(#groups == count, "wrong group count")
                check(#all == count * Dice.groupSize(c), "wrong physical dice count")
                rollAll(groups)
                local t = Dice.total(c, groups)
                local rlo, rhi = Dice.range(c)
                check(t >= rlo and t <= rhi,
                    Dice.notation(c) .. ": total " .. t .. " outside " .. rlo .. ".." .. rhi)
            end
        end
    end
end

-- 6. Layout keeps every die on screen --------------------------------------
for _, spec in ipairs(DiceTypes) do
    for _, mode in ipairs({ "normal", "advantage" }) do
        for count = 1, spec.maxCount do
            local c = config(spec, count, 0, mode)
            local all, groups = Dice.build(c)
            Layout.arrange(groups, 8, 28, 384, 164)
            for _, d in ipairs(all) do
                local r = d.size / 2
                check(d.size >= 20, Dice.notation(c) .. ": die too small (" .. d.size .. ")")
                check(d.x - r >= 0 and d.x + r <= 400,
                    Dice.notation(c) .. ": die off screen horizontally")
                check(d.y - r >= 24 and d.y + r <= 196,
                    Dice.notation(c) .. ": die outside the play area")
            end
            if Dice.groupSize(c) == 2 then
                for _, gr in ipairs(groups) do
                    check(gr[2].x > gr[1].x, "a pair must be laid out left to right")
                end
            end
        end
    end
end

if failures == 0 then
    print("all dice checks passed")
else
    print(failures .. " check(s) failed")
    os.exit(1)
end
