-- A numeral set drawn as shapes rather than scaled text.
--
-- The system font only enlarges in whole multiples -- 16px or 32px, nothing
-- between -- because a fractional scale doubles some pixel rows and not others.
-- That is the wrong constraint for numbers that have to fit inside a die whose
-- size the layout picks freely. Drawing each digit from a stroke path instead
-- gives any height, crisp, and lets the numerals be styled to sit with the
-- faceted dice: chamfered corners, no curves.

Numerals = {}

local gfx <const> = playdate.graphics

-- Digits as polylines on a unit-height grid: x runs 0..WIDTH, y runs 0..1 with
-- 0 at the top. Everything scales from these, so there is one definition per
-- digit no matter what size it is drawn at.
local WIDTH <const> = 0.62
local GAP <const> = 0.18       -- space between digits, in units of height
local C <const> = 0.20         -- corner chamfer

local GLYPHS <const> = {
    ["0"] = { { {C,0}, {WIDTH-C,0}, {WIDTH,C}, {WIDTH,1-C}, {WIDTH-C,1}, {C,1}, {0,1-C}, {0,C}, {C,0} } },
    ["1"] = { { {0.04,0.26}, {WIDTH*0.5,0} },
              { {WIDTH*0.5,0}, {WIDTH*0.5,1} },
              { {WIDTH*0.14,1}, {WIDTH*0.86,1} } },
    ["2"] = { { {0,C}, {C,0}, {WIDTH-C,0}, {WIDTH,C}, {WIDTH,0.36}, {0.02,1}, {WIDTH,1} } },
    ["3"] = { { {0,C}, {C,0}, {WIDTH-C,0}, {WIDTH,C}, {WIDTH,0.36}, {WIDTH-C,0.5},
                {WIDTH,0.64}, {WIDTH,1-C}, {WIDTH-C,1}, {C,1}, {0,1-C} },
              { {WIDTH*0.32,0.5}, {WIDTH-C,0.5} } },
    ["4"] = { { {WIDTH*0.74,0}, {0,0.68}, {WIDTH,0.68} },
              { {WIDTH*0.74,0}, {WIDTH*0.74,1} } },
    ["5"] = { { {WIDTH,0}, {0,0}, {0,0.40}, {WIDTH-C,0.40}, {WIDTH,0.40+C}, {WIDTH,1-C},
                {WIDTH-C,1}, {C,1}, {0,1-C} } },
    ["6"] = { { {WIDTH,C*0.9}, {WIDTH-C,0}, {C,0}, {0,C}, {0,1-C}, {C,1}, {WIDTH-C,1},
                {WIDTH,1-C}, {WIDTH,0.60}, {WIDTH-C,0.46}, {C,0.46}, {0,0.58} } },
    ["7"] = { { {0,0}, {WIDTH,0}, {WIDTH*0.30,1} } },
    ["8"] = { { {C,0}, {WIDTH-C,0}, {WIDTH,C}, {WIDTH,0.38}, {WIDTH-C,0.5}, {WIDTH,0.62},
                {WIDTH,1-C}, {WIDTH-C,1}, {C,1}, {0,1-C}, {0,0.62}, {C,0.5}, {0,0.38},
                {0,C}, {C,0} },
              { {C,0.5}, {WIDTH-C,0.5} } },
    ["9"] = { { {0,1-C*0.9}, {C,1}, {WIDTH-C,1}, {WIDTH,1-C}, {WIDTH,C}, {WIDTH-C,0},
                {C,0}, {0,C}, {0,0.40}, {C,0.54}, {WIDTH-C,0.54}, {WIDTH,0.42} } },
}

function Numerals.width(text, height)
    local n = #text
    if n == 0 then return 0 end
    return (n * WIDTH + (n - 1) * GAP) * height
end

-- The largest height at which `text` fits the given box.
function Numerals.fit(text, maxWidth, maxHeight)
    local perUnit = Numerals.width(text, 1)
    if perUnit > 0 and Numerals.width(text, maxHeight) > maxWidth then
        return maxWidth / perUnit
    end
    return maxHeight
end

local function strokeWeight(height)
    return math.max(2, math.floor(height * 0.17))
end

-- Strokes are drawn from Lua, so a number redrawn every frame for a dozen dice
-- would be hundreds of calls per frame. Rendering into an image once and
-- blitting it after is one call, and identical on screen.
local cache = {}
local cacheCount = 0

local function render(text, height)
    local weight = strokeWeight(height)
    local pad = weight + 2
    local img = gfx.image.new(math.ceil(Numerals.width(text, height)) + pad * 2,
                              math.ceil(height) + pad * 2, gfx.kColorClear)

    gfx.pushContext(img)
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(weight)
        local x = pad
        for i = 1, #text do
            local glyph = GLYPHS[text:sub(i, i)]
            if glyph then
                for _, stroke in ipairs(glyph) do
                    for p = 1, #stroke - 1 do
                        gfx.drawLine(x + stroke[p][1] * height, pad + stroke[p][2] * height,
                                     x + stroke[p + 1][1] * height, pad + stroke[p + 1][2] * height)
                    end
                    -- Thick lines meet in notches at the corners; a dot at each
                    -- joint fills them in.
                    for _, point in ipairs(stroke) do
                        gfx.fillCircleAtPoint(x + point[1] * height, pad + point[2] * height,
                            weight / 2)
                    end
                end
            end
            x = x + (WIDTH + GAP) * height
        end
        gfx.setLineWidth(1)
    gfx.popContext()
    return img
end

local function imageFor(text, height)
    height = math.max(math.floor(height), 6)
    local key = text .. "@" .. height
    local img = cache[key]
    if img == nil then
        if cacheCount > 240 then
            cache = {}
            cacheCount = 0
        end
        img = render(text, height)
        cache[key] = img
        cacheCount += 1
    end
    return img
end

-- Centred on (cx, cy).
function Numerals.draw(text, cx, cy, height)
    if #text == 0 then return end
    local img = imageFor(text, height)
    img:draw(cx - img.width / 2, cy - img.height / 2)
end

-- Build the images for a set of faces up front. A die re-rolls its face every
-- couple of frames while tumbling, so without this the first appearance of each
-- value would render mid-throw -- exactly when there is least time to spare.
function Numerals.prewarm(labels, height)
    for _, label in ipairs(labels) do
        imageFor(label, height)
    end
end
