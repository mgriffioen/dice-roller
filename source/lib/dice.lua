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
    { key = "d20",  sides = 20,  shape = "hexagon",  maxCount = 12, allowAdvantage = true },
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
-- Interior detail
-- ---------------------------------------------------------------------------
-- Two looks, both cheap to turn off. A die reads as a die because of its
-- facets, not its silhouette -- an outline on its own is just a polygon.
local SHOW_FACETS <const> = true
local SHOW_SHADOW <const> = true

-- How far in the inset face sits, as a fraction of the silhouette. Big enough
-- that the number still lands on clean white.
local FACET_INSET <const> = 0.62

-- Per shape: the inset face as a closed polygon, plus the spokes joining it to
-- the corners. Unit-space like the silhouettes, so one table works at any size
-- and any angle.
local FACETS = {}

for name, pts in pairs(SHAPES) do
    local face, spokes = {}, {}
    for i, p in ipairs(pts) do
        face[i] = { p[1] * FACET_INSET, p[2] * FACET_INSET }
        spokes[i] = { face[i], p }
    end
    FACETS[name] = { face = face, spokes = spokes }
end

do
    -- The d20 is the one silhouette everybody recognises, so it gets its real
    -- face-on projection instead of the generic inset: a central triangle with
    -- three spokes. The hexagon's vertices start at -90 and step 60 degrees, so
    -- the -90/30/150 corners are entries 1, 3 and 5.
    local hexagon = SHAPES.hexagon
    local face, spokes = {}, {}
    for i, angle in ipairs({ -90, 30, 150 }) do
        local a = math.rad(angle)
        face[i] = { math.cos(a) * 0.62, math.sin(a) * 0.62 }
        spokes[i] = { face[i], hexagon[i * 2 - 1] }
    end
    FACETS.hexagon = { face = face, spokes = spokes }
end

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
    self.dropped = false     -- the loser of an advantage/disadvantage pair
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

    if SHOW_SHADOW then
        self:drawShadow(r, dy)
    end

    if self.spec.shape == "coin" then
        self:drawCoin(cx, cy, r, squash)
    else
        self:drawPolygonDie(cx, cy, r, squash)
    end

    -- Advantage and disadvantage each throw one of the pair away. Crossing it
    -- out is the clearest way to show which face actually counted.
    if self.dropped then
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(2)
        gfx.drawLine(cx - r * 0.85, cy - r * 0.85, cx + r * 0.85, cy + r * 0.85)
        gfx.setLineWidth(1)
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

    -- The coin's equivalent of a facet: a rim just inside the edge.
    if SHOW_FACETS and flip > 0.4 then
        gfx.drawEllipseInRect(cx - w * 0.39, cy - h * 0.39, w * 0.78, h * 0.78)
    end

    if flip > 0.55 then
        self:drawFace(cx, cy)
    end
end

-- A dithered ellipse on the ground that stays put while the die hops above it.
-- Shrinking it as the die rises is what makes the hop read as height rather
-- than as the whole die sliding up the screen.
function Die:drawShadow(r, dy)
    local lift = math.min(-dy / (r * 0.9), 1)
    local w = r * (1.5 - lift * 0.5)
    local h = r * 0.34 * (1 - lift * 0.4)

    gfx.setPattern({ 0x88, 0x22, 0x88, 0x22, 0x88, 0x22, 0x88, 0x22 })
    gfx.fillEllipseInRect(self.x - w / 2, self.y + r * 0.86 - h / 2, w, h)
    gfx.setColor(gfx.kColorBlack)
end

function Die:drawPolygonDie(cx, cy, r, squash)
    local rad = math.rad(self.angle)
    local cosA, sinA = math.cos(rad), math.sin(rad)

    -- One transform for the silhouette and the facets alike, so the interior
    -- detail tumbles and squashes with the body instead of sliding around on it.
    local function place(p)
        local px, py = p[1] * r, p[2] * r * squash
        return cx + px * cosA - py * sinA, cy + px * sinA + py * cosA
    end

    local function polygonOf(pts)
        local coords = {}
        for i = 1, #pts do
            local x, y = place(pts[i])
            coords[#coords + 1] = x
            coords[#coords + 1] = y
        end
        local poly = geo.polygon.new(table.unpack(coords))
        poly:close()
        return poly
    end

    local body = polygonOf(SHAPES[self.spec.shape])

    gfx.setColor(gfx.kColorWhite)
    gfx.fillPolygon(body)
    gfx.setColor(gfx.kColorBlack)

    -- Facets first and thin, then the silhouette over them and thick: the
    -- outline stays the strongest edge, which is what holds the shape together
    -- at the sizes a crowded roll uses.
    if SHOW_FACETS then
        local facets = FACETS[self.spec.shape]
        gfx.setLineWidth(1)
        gfx.drawPolygon(polygonOf(facets.face))
        for _, spoke in ipairs(facets.spokes) do
            local x1, y1 = place(spoke[1])
            local x2, y2 = place(spoke[2])
            gfx.drawLine(x1, y1, x2, y2)
        end
    end

    gfx.setLineWidth(2)
    gfx.drawPolygon(body)
    gfx.setLineWidth(1)

    self:drawFace(cx, cy)
end

-- Below this size the number is drawn in the plain font; at or above it, at
-- double size. Scaled bitmap text only comes in whole multiples -- a fractional
-- scale doubles some pixel rows and not others, which looks broken at this
-- resolution -- so this is one step rather than a smooth ramp.
--
-- Triple size does fit inside the bigger shapes, but it reads as a number with
-- a die drawn around it rather than a die with a number on it.
local DOUBLE_FACE_SIZE <const> = 58

-- ...unless the number would end up wider than the die carrying it. A
-- two-digit percentile face is nearly twice the width of a single digit, and
-- the system font's exact metrics are not something to assume.
local FACE_WIDTH_LIMIT <const> = 0.62

function Die:faceScale(text)
    if self.size < DOUBLE_FACE_SIZE then
        return 1
    end
    if gfx.getTextSize(text) * 2 > self.size * FACE_WIDTH_LIMIT then
        return 1
    end
    return 2
end

function Die:drawFace(cx, cy)
    local text = self:label()
    local scale = self:faceScale(text)
    local _, h = Util.bigTextSize(text, scale)
    Util.drawBigText(text, cx, cy - h / 2, scale, kTextAlignment.center)
end

-- ---------------------------------------------------------------------------
-- Building and scoring a handful of dice
-- ---------------------------------------------------------------------------
-- Everything below takes a `config`: the whole description of one throw.
--
--   { spec = <entry from DiceTypes>, count = 3, modifier = 2, mode = "normal" }
--
-- `mode` is "normal", "advantage" or "disadvantage", and only means anything
-- for a die type flagged allowAdvantage (the d20).
Dice = {}

Dice.MOD_MIN = -20
Dice.MOD_MAX = 20

function Dice.newConfig()
    return { spec = DiceTypes[3], count = 1, modifier = 0, mode = "normal" }
end

function Dice.usesAdvantage(config)
    return config.spec.allowAdvantage == true and config.mode ~= "normal"
end

-- How many physical dice make up one result. Two for a percentile pair, and two
-- for advantage/disadvantage -- which is why both fall out of the same code.
function Dice.groupSize(config)
    if config.spec.percentile or Dice.usesAdvantage(config) then
        return 2
    end
    return 1
end

-- Returns the flat list of physical dice, and a list of groups. A group is one
-- "roll" the player asked for: one die normally, a tens/units pair for a d100,
-- a pair to choose between under advantage or disadvantage.
function Dice.build(config)
    local all, groups = {}, {}
    for _ = 1, config.count do
        local group = {}
        if config.spec.percentile then
            group[1] = Die(config.spec, "tens")
            group[2] = Die(config.spec, "units")
        else
            for i = 1, Dice.groupSize(config) do
                group[i] = Die(config.spec)
            end
        end
        for _, die in ipairs(group) do all[#all + 1] = die end
        groups[#groups + 1] = group
    end
    return all, groups
end

-- Which die of an advantage/disadvantage pair counts. Ties keep the first,
-- which is arbitrary but means the crossed-out die is always the second.
local function keptIndex(config, group)
    local a, b = group[1].value, group[2].value
    if config.mode == "advantage" then
        return b > a and 2 or 1
    end
    return b < a and 2 or 1
end

-- The score of one group, before any modifier: a plain die's face value, a
-- percentile pair added together with 00 + 0 reading as 100, or the kept die
-- of an advantage/disadvantage pair.
function Dice.groupValue(config, group)
    if config.spec.percentile then
        local tens, units = group[1].value, group[2].value
        if tens == 0 and units == 0 then return 100 end
        return tens + units
    end
    if Dice.usesAdvantage(config) then
        return group[keptIndex(config, group)].value
    end
    return group[1].value
end

function Dice.groupLabel(config, group)
    if config.spec.percentile then
        return string.format("%02d+%d=%d", group[1].value, group[2].value,
            Dice.groupValue(config, group))
    end
    if Dice.usesAdvantage(config) then
        local kept = keptIndex(config, group)
        return group[kept].value .. "(" .. group[3 - kept].value .. ")"
    end
    return tostring(group[1].value)
end

-- Flag the die each advantage/disadvantage pair discards, as soon as both dice
-- in that pair have landed, so it can be crossed out while the rest are still
-- in the air.
function Dice.markDropped(config, groups)
    if not Dice.usesAdvantage(config) then return end
    for _, group in ipairs(groups) do
        if not group.marked and group[1].settled and group[2].settled then
            group.marked = true
            group[3 - keptIndex(config, group)].dropped = true
        end
    end
end

-- Sum of every group plus the modifier, with the dice-only subtotal alongside
-- it: a natural 20 is about the die, not about the total.
function Dice.total(config, groups)
    local diceTotal = 0
    for _, group in ipairs(groups) do
        diceTotal += Dice.groupValue(config, group)
    end
    return diceTotal + config.modifier, diceTotal
end

function Dice.notation(config)
    local text = config.count .. config.spec.key
    if config.modifier > 0 then
        text = text .. "+" .. config.modifier
    elseif config.modifier < 0 then
        text = text .. "-" .. -config.modifier
    end
    if Dice.usesAdvantage(config) then
        text = text .. (config.mode == "advantage" and " adv" or " dis")
    end
    return text
end

-- Advantage narrows which results are likely but not which are possible, so it
-- does not move the ends of the range.
function Dice.range(config)
    return config.count + config.modifier,
           config.count * config.spec.sides + config.modifier
end

-- Plain dice add up, so " + " reads correctly between them. Pairs already carry
-- their own arithmetic inside each label, so they get a list separator instead.
function Dice.separator(config)
    if config.spec.percentile or Dice.usesAdvantage(config) then
        return ",  "
    end
    return " + "
end

-- "4 + 2 + 6" on its own, or "(4 + 2 + 6)  + 3" once a modifier is involved --
-- the brackets keep it honest about what was added to what. The result overlay
-- and the history page both show this, so it lives here rather than in either.
function Dice.breakdownText(config, parts)
    local dice = table.concat(parts, Dice.separator(config))
    if config.modifier == 0 then
        return dice
    end
    if #parts > 1 then
        dice = "(" .. dice .. ")"
    end
    return dice .. (config.modifier > 0 and "  + " or "  - ") .. math.abs(config.modifier)
end
