-- Dice data, shapes, and the Die class that knows how to tumble and draw itself.

local gfx <const> = playdate.graphics
local geo <const> = playdate.geometry

-- ---------------------------------------------------------------------------
-- Dice types
-- ---------------------------------------------------------------------------
-- `percentile` dice (d100) are not one physical die: they are a pair of d10s,
-- one reading 00..90 and one reading 0..9, added together, where 00 + 0 is 100.
DiceTypes = {
    { key = "d2",   sides = 2,   shape = "coin",     maxCount = 12 },
    { key = "d4",   sides = 4,   shape = "tri",      maxCount = 12 },
    { key = "d6",   sides = 6,   shape = "square",   maxCount = 12 },
    { key = "d8",   sides = 8,   shape = "diamond",  maxCount = 12 },
    { key = "d10",  sides = 10,  shape = "kite",     maxCount = 12 },
    { key = "d12",  sides = 12,  shape = "pentagon", maxCount = 12 },
    { key = "d20",  sides = 20,  shape = "hexagon",  maxCount = 12 },
    { key = "d100", sides = 100, shape = "kite",     maxCount = 6, percentile = true },
}

-- ---------------------------------------------------------------------------
-- Shapes
-- ---------------------------------------------------------------------------
-- Every shape is a list of unit-circle points centred on the origin. At draw
-- time we rotate them, scale them by the die size and translate them into
-- place. Storing them normalised means one table works at any size.
local function regularPolygon(sides, startAngle)
    local pts = {}
    for i = 0, sides - 1 do
        local a = math.rad(startAngle + i * 360 / sides)
        pts[#pts + 1] = { math.cos(a), math.sin(a) }
    end
    return pts
end

local SHAPES <const> = {
    tri      = regularPolygon(3, -90),   -- d4
    square   = regularPolygon(4, -45),   -- d6
    diamond  = regularPolygon(4, -90),   -- d8
    pentagon = regularPolygon(5, -90),   -- d12
    hexagon  = regularPolygon(6, -90),   -- d20
    -- The classic pentagonal-trapezohedron silhouette of a d10.
    kite     = { {0, -1}, {0.74, -0.14}, {0.45, 0.94}, {-0.45, 0.94}, {-0.74, -0.14} },
}

-- ---------------------------------------------------------------------------
-- Die
-- ---------------------------------------------------------------------------
-- `role` is "normal", or "tens"/"units" for the two halves of a d100 pair.
class("Die").extends()

function Die:init(spec, role)
    Die.super.init(self)
    self.spec = spec
    self.role = role or "normal"
    self.size = 48
    self.x, self.y = 200, 120

    self.value = self:randomValue()
    self.angle = math.random() * 360
    self.spin = 0            -- degrees per frame, driven by the crank
    self.hopPhase = math.random() * math.pi * 2
    self.settled = false
    self.landFrames = 0      -- counts down through the squash-and-settle bounce
end

-- Raw value in "die units": 1..sides normally, 0/10/20..90 for a tens die,
-- 0..9 for a units die.
function Die:randomValue()
    if self.role == "tens" then
        return math.random(0, 9) * 10
    elseif self.role == "units" then
        return math.random(0, 9)
    end
    return math.random(self.spec.sides)
end

function Die:label()
    if self.role == "tens" then
        return string.format("%02d", self.value)
    end
    return tostring(self.value)
end

-- energy is the shared "how hard was this thrown" number owned by the roll
-- scene; every die reads from it so the whole handful moves together.
function Die:update(energy)
    if self.settled then
        if self.landFrames > 0 then
            self.landFrames -= 1
        end
        return
    end

    self.spin = energy * (2.4 + (self.hopPhase % 1) * 1.6)
    self.angle = (self.angle + self.spin) % 360
    self.hopPhase += 0.34

    -- Re-roll the face every few frames so the numbers blur while in motion.
    if energy > 0.6 and math.random() < 0.5 then
        self.value = self:randomValue()
    end
end

function Die:settle(value)
    self.value = value
    self.settled = true
    self.spin = 0
    self.angle = 0
    self.landFrames = 8
end

-- Vertical bounce while tumbling, plus a short squash on landing.
function Die:visualOffsets(energy)
    local dy, squash = 0, 1
    if not self.settled then
        dy = -math.abs(math.sin(self.hopPhase)) * math.min(energy * 2.2, 22)
    elseif self.landFrames > 0 then
        -- 8 -> 0 becomes a quick 1.25 -> 1.0 vertical squash.
        squash = 1 - (self.landFrames / 8) * 0.25
        dy = 0
    end
    return dy, squash
end

function Die:draw(energy)
    local dy, squash = self:visualOffsets(energy)
    local cx, cy = self.x, self.y + dy
    local r = self.size / 2

    if self.spec.shape == "coin" then
        self:drawCoin(cx, cy, r, squash)
    else
        self:drawPolygonDie(cx, cy, r, squash)
    end
end

-- A d2 is a coin, so it flips instead of tumbling: squeeze its width by the
-- cosine of the spin angle and it reads as edge-on at 90 degrees.
function Die:drawCoin(cx, cy, r, squash)
    local flip = self.settled and 1 or math.abs(math.cos(math.rad(self.angle)))
    local w = math.max(r * 2 * flip, 3)
    local h = r * 2 * squash

    gfx.setColor(gfx.kColorWhite)
    gfx.fillEllipseInRect(cx - w / 2, cy - h / 2, w, h)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawEllipseInRect(cx - w / 2, cy - h / 2, w, h)
    gfx.setLineWidth(1)

    if flip > 0.55 then
        self:drawFace(cx, cy)
    end
end

function Die:drawPolygonDie(cx, cy, r, squash)
    local pts = SHAPES[self.spec.shape]
    local rad = math.rad(self.angle)
    local cosA, sinA = math.cos(rad), math.sin(rad)

    local coords = {}
    for i = 1, #pts do
        local px, py = pts[i][1] * r, pts[i][2] * r * squash
        coords[#coords + 1] = cx + px * cosA - py * sinA
        coords[#coords + 1] = cy + px * sinA + py * cosA
    end

    local poly = geo.polygon.new(table.unpack(coords))
    poly:close()

    gfx.setColor(gfx.kColorWhite)
    gfx.fillPolygon(poly)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawPolygon(poly)
    gfx.setLineWidth(1)

    self:drawFace(cx, cy)
end

function Die:drawFace(cx, cy)
    local scale = 1
    if self.size >= 62 then
        scale = 3
    elseif self.size >= 38 then
        scale = 2
    end
    local text = self:label()
    local _, h = Util.bigTextSize(text, scale)
    Util.drawBigText(text, cx, cy - h / 2, scale, kTextAlignment.center)
end

-- ---------------------------------------------------------------------------
-- Building and scoring a handful of dice
-- ---------------------------------------------------------------------------
Dice = {}

-- Returns the flat list of physical dice, and a list of groups. A group is one
-- "roll" the player asked for: one die normally, a tens/units pair for a d100.
function Dice.build(spec, count)
    local all, groups = {}, {}
    for _ = 1, count do
        local group = {}
        if spec.percentile then
            group[1] = Die(spec, "tens")
            group[2] = Die(spec, "units")
        else
            group[1] = Die(spec)
        end
        for _, die in ipairs(group) do all[#all + 1] = die end
        groups[#groups + 1] = group
    end
    return all, groups
end

-- The score of one group: a plain die's face value, or the percentile pair
-- added together with 00 + 0 reading as 100.
function Dice.groupValue(spec, group)
    if spec.percentile then
        local tens, units = group[1].value, group[2].value
        if tens == 0 and units == 0 then return 100 end
        return tens + units
    end
    return group[1].value
end

function Dice.groupLabel(spec, group)
    if spec.percentile then
        return string.format("%02d+%d=%d", group[1].value, group[2].value,
            Dice.groupValue(spec, group))
    end
    return tostring(group[1].value)
end

function Dice.notation(spec, count)
    return count .. spec.key
end
