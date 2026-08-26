dofile(DIR .. "/stub.lua")
dofile(OUT .. "/numerals.lua")

local failures = 0
local function check(ok, msg)
    if not ok then failures = failures + 1; print("FAIL: " .. msg) end
end

local gfx = playdate.graphics

-- 1. Widths scale with height and with digit count ------------------------
check(Numerals.width("", 40) == 0, "an empty string has no width")
check(Numerals.width("8", 40) > 0, "a digit has width")
check(math.abs(Numerals.width("8", 40) - Numerals.width("8", 20) * 2) < 0.001,
    "width should scale linearly with height")
check(Numerals.width("11", 40) > Numerals.width("1", 40), "two digits are wider than one")
check(Numerals.width("1234", 40) > Numerals.width("123", 40), "four digits are wider than three")

-- 2. Fitting ---------------------------------------------------------------
check(Numerals.fit("1", 1000, 40) == 40, "a number with room to spare keeps its height")
local squeezed = Numerals.fit("20", 30, 40)
check(squeezed < 40, "a number too wide for its box should shrink")
check(Numerals.width("20", squeezed) <= 30.001,
    "after shrinking it should actually fit, got " .. Numerals.width("20", squeezed))
-- Four digits in a narrow box is the result overlay's worst case.
local total = Numerals.fit("1200", 272, 62)
check(Numerals.width("1200", total) <= 272.001, "a four-digit total should fit the panel")

-- 3. Every digit has a glyph ----------------------------------------------
-- A missing or mistyped entry would draw nothing at all, silently, for one
-- digit only -- so count the strokes each one actually issues.
local strokes = 0
gfx.drawLine = function() strokes = strokes + 1 end

for digit = 0, 9 do
    strokes = 0
    -- A distinct height per digit keeps the image cache from answering for us.
    Numerals.draw(tostring(digit), 100, 100, 40 + digit)
    check(strokes >= 2, "digit " .. digit .. " drew " .. strokes ..
        " strokes -- it has no glyph, or a broken one")
end

-- Every digit should take a comparable number of strokes; one that collapses to
-- a couple of lines is more likely a truncated path than a simple design.
local counts = {}
for digit = 0, 9 do
    strokes = 0
    Numerals.draw(tostring(digit), 100, 100, 60 + digit)
    counts[digit] = strokes
end
for digit = 0, 9 do
    check(counts[digit] >= 2 and counts[digit] <= 20,
        "digit " .. digit .. " has " .. counts[digit] .. " strokes, which looks wrong")
end

-- 4. Nothing here should ever throw ---------------------------------------
local ok, err = pcall(function()
    Numerals.draw("", 100, 100, 40)
    Numerals.draw("d20", 100, 100, 40)          -- letters have no glyphs
    Numerals.draw("00", 100, 100, 6)            -- floor of the height clamp
    Numerals.draw("1200", 100, 100, 0.5)        -- below it
    Numerals.draw("7", 100, 100, 400)           -- far above any real use
    Numerals.prewarm({ "1", "2", "3" }, 30)
end)
check(ok, "drawing edge cases threw: " .. tostring(err))

-- 5. The cache answers repeats without re-rendering ------------------------
strokes = 0
Numerals.draw("15", 100, 100, 33)
local first = strokes
strokes = 0
for _ = 1, 20 do Numerals.draw("15", 100, 100, 33) end
check(first > 0, "the first draw should render")
check(strokes == 0, "repeat draws should come from the cache, got " .. strokes .. " strokes")

if failures == 0 then print("all numeral checks passed")
else print(failures .. " check(s) failed"); os.exit(1) end
