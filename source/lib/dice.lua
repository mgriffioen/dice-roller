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
-- Two ways to throw
-- ---------------------------------------------------------------------------
-- These are the strings the system menu shows, so the menu can hand its choice
-- straight back without a lookup table in between.
--
--   scatter   the dice are thrown: they travel across the tray, bounce off the
--             walls and off each other, and gather back into their reading
--             positions once they land
--   in place  the dice hold their positions and spin on the spot, hopping up
--             and down on a sine wave. Cheaper -- no collision pass, no square
--             roots -- and easier to read at a glance, because every die stays
--             where you last looked for it
Dice = {}

Dice.SCATTER = "scatter"
Dice.IN_PLACE = "in place"
Dice.STYLES = { Dice.SCATTER, Dice.IN_PLACE }

Dice.style = Dice.SCATTER

-- Anything that is not one of the two is ignored, so a hand-edited settings
-- file or a key left over from an older version cannot leave the dice in a
-- style that nothing knows how to draw. Returns the style actually in force.
function Dice.setStyle(style)
    for _, known in ipairs(Dice.STYLES) do
        if style == known then
            Dice.style = style
            break
        end
    end
    return Dice.style
end

-- ---------------------------------------------------------------------------
-- Physics
-- ---------------------------------------------------------------------------
-- A thrown die is not a spinning icon: it travels, it bounces off the walls of
-- the tray and off the other dice, and it loses speed to the table until it
-- stops. All of it runs in pixels-per-frame at 30fps, and all of it is tuned by
-- eye rather than derived -- the point is that it *reads* as a real throw.
--
-- None of it runs in the "in place" style, which is the handful of lines in
-- Die:spinInPlace instead.
local GRAVITY <const> = 1.0            -- vertical pull, in pixels per frame squared
local FLOOR_BOUNCE <const> = 0.52      -- how much drop is kept on hitting the table
local FLOOR_MIN <const> = 1.2          -- below this the die stays down instead of buzzing
local WALL_BOUNCE <const> = 0.66
-- Two equal masses swapping the head-on part of their velocity is a perfectly
-- elastic bounce; scaling it by (1 + e) / 2 takes a little out of each hit.
local DIE_BOUNCE <const> = 0.85
local GROUND_DRAG <const> = 0.93       -- the table takes speed off a rolling die
local AIR_DRAG <const> = 0.995         -- almost nothing, but it stops perpetual motion
local MAX_SPEED <const> = 11
-- The one quantity the crank must not be able to run away with. Cranking hard
-- makes for a bigger shove, and a shove lifts the die -- without a ceiling a
-- violent throw fires the dice clean off the top of the screen. 7 leaves an
-- apex of about 25px, which is as high as a die needs to go to read as a hop.
local MAX_RISE <const> = 7
local KICK_TURN <const> = 0.9          -- radians a shove may swing the heading by
local WALL_TURN <const> = 1.0          -- and a wall, which is hit corner-first
local MAX_SPIN <const> = 42            -- degrees per frame
local SPIN_PER_PIXEL <const> = 2.4     -- a die crossing the tray fast is tumbling fast

-- Gathering back into the reading position. Timed by distance rather than fixed,
-- so a die that stopped next to its slot nudges into it and one that stopped
-- across the tray takes longer, instead of every die zipping home at whatever
-- speed its own distance happened to work out to.
local GLIDE_SPEED <const> = 16         -- pixels per frame
local GLIDE_MIN <const> = 5
local GLIDE_MAX <const> = 16
local LAND_FRAMES <const> = 8          -- the squash once it arrives

-- Rotating a regular polygon by this much leaves it looking identical, so a die
-- can seat itself on the nearest one instead of unwinding all the way to zero:
-- it comes to rest at a believable angle and still reads as square-on.
local SYMMETRY <const> = {
    tri = 120, square = 90, diamond = 90, pentagon = 72, hexagon = 60,
    kite = 360, coin = 360,
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
    self.spin = 0            -- degrees per frame, signed

    -- Where the layout wants this die to be read from, and the tray it is free
    -- to career around inside until it settles.
    self.homeX, self.homeY = self.x, self.y
    self.trayL, self.trayT, self.trayR, self.trayB = 8, 28, 392, 192

    self.vx, self.vy = 0, 0  -- across the table
    self.z, self.zv = 0, 0   -- and above it: z is height, 0 is resting
    self.spinBias = math.random() < 0.5 and -1 or 1
    self.hopPhase = math.random() * math.pi * 2   -- the "in place" style's bounce
    self.lastEnergy = 0
    self.impacts = 0         -- collisions since the scene last looked

    self.settled = false
    self.glideFrames = 0     -- counts down while gathering back into position
    self.landFrames = 0      -- counts down through the squash-and-settle bounce
    self.dropped = false     -- the loser of an advantage/disadvantage pair
end

-- The layout owns both of these: where the die is read from once it stops, and
-- the rectangle it may roam while it is still moving.
function Die:setHome(x, y)
    self.homeX, self.homeY = x, y
    self.x, self.y = x, y
end

function Die:setTray(x, y, w, h)
    self.trayL, self.trayT = x, y
    self.trayR, self.trayB = x + w, y + h
end

-- Back to the reading position with nothing left over, ready to be thrown again.
function Die:rest()
    self.x, self.y = self.homeX, self.homeY
    self.vx, self.vy, self.z, self.zv = 0, 0, 0, 0
    self.spin = 0
    self.spinBias = math.random() < 0.5 and -1 or 1
    self.hopPhase = math.random() * math.pi * 2
    self.lastEnergy = 0
    self.impacts = 0
    self.settled = false
    self.glideFrames = 0
    self.landFrames = 0
    self.dropped = false
    self.angle = math.random() * 360
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

function Die:speed()
    return math.sqrt(self.vx * self.vx + self.vy * self.vy)
end

function Die:capSpeed()
    local s = self:speed()
    if s > MAX_SPEED then
        self.vx, self.vy = self.vx / s * MAX_SPEED, self.vy / s * MAX_SPEED
    end
end

-- Turn the whole velocity without changing how fast the die is going.
function Die:steer(radians)
    local speed = self:speed()
    if speed < 0.01 then return end
    local heading = math.atan(self.vy, self.vx) + radians
    self.vx, self.vy = math.cos(heading) * speed, math.sin(heading) * speed
end

-- One shove from the throw: faster, and pointed somewhere near but never
-- exactly where the die was already going.
--
-- It has to steer rather than just add speed along the heading. A shove that
-- only pushed forwards would be capped back to the same vector every frame, and
-- the die would end up running on rails, bouncing between two walls in a
-- straight line -- which is the one thing a thrown die never does.
function Die:kick(strength)
    local speed = self:speed()
    local heading
    if speed > 0.6 then
        heading = math.atan(self.vy, self.vx) + (math.random() - 0.5) * KICK_TURN
    else
        heading, speed = math.random() * math.pi * 2, 0
    end

    speed = math.min(speed + strength, MAX_SPEED)
    self.vx, self.vy = math.cos(heading) * speed, math.sin(heading) * speed

    self.spin += (math.random() - 0.5) * strength * 9
    if self.z <= 0 then
        -- A shove only lifts a die that is on the table; one already in the air
        -- keeps the arc it is on.
        self.zv = math.min(math.max(self.zv, strength * 2.2 + math.random() * 2), MAX_RISE)
    end
end

-- The walls of the tray. A die never leaves it, and every edge it clips knocks
-- it off its line -- which is most of what keeps a long throw unpredictable.
function Die:bounceWalls()
    local r = self.size * 0.45
    local left, top = self.trayL + r, self.trayT + r
    local right, bottom = self.trayR - r, self.trayB - r
    -- Which way the die has to be heading once it is done with the wall.
    local awayX, awayY = 0, 0

    if self.x < left then
        self.x, self.vx, awayX = left, -self.vx * WALL_BOUNCE, 1
    elseif self.x > right then
        self.x, self.vx, awayX = right, -self.vx * WALL_BOUNCE, -1
    end
    if self.y < top then
        self.y, self.vy, awayY = top, -self.vy * WALL_BOUNCE, 1
    elseif self.y > bottom then
        self.y, self.vy, awayY = bottom, -self.vy * WALL_BOUNCE, -1
    end

    if awayX == 0 and awayY == 0 then return end

    -- A tumbling die clips the wall on a corner, so it comes off at an angle
    -- rather than mirroring cleanly. Whichever component has to point away from
    -- the wall is then put back, in case the turn was steep enough to aim the
    -- die straight back into it.
    self:steer((math.random() - 0.5) * WALL_TURN)
    if awayX ~= 0 then self.vx = math.abs(self.vx) * awayX end
    if awayY ~= 0 then self.vy = math.abs(self.vy) * awayY end

    self.spin = -self.spin * 0.7
    self.spinBias = -self.spinBias
    if self.z <= 0 then
        self.zv = math.max(self.zv, math.random() * 2.2)
    end
    self.impacts += 1
end

-- Put the die back inside the tray without bouncing it: separating a pile of
-- dice can shove one through a wall, and a die that is merely in the wrong place
-- should be moved, not fired off in the opposite direction.
function Die:clampToTray()
    local r = self.size * 0.45
    self.x = math.max(self.trayL + r, math.min(self.trayR - r, self.x))
    self.y = math.max(self.trayT + r, math.min(self.trayB - r, self.y))
end

-- One frame of falling, sliding and tumbling.
function Die:integrate()
    self.zv -= GRAVITY
    self.z += self.zv

    if self.z <= 0 then
        self.z = 0
        if self.zv < -FLOOR_MIN then
            -- Still some drop left in it: bounce, and come off the table a
            -- little further out of true than it went in.
            self.zv = -self.zv * FLOOR_BOUNCE
            self.spin += (math.random() - 0.5) * self.zv * 9
            self.impacts += 1
        else
            self.zv = 0
        end
        self.vx *= GROUND_DRAG
        self.vy *= GROUND_DRAG
        self.spin *= GROUND_DRAG
    else
        self.vx *= AIR_DRAG
        self.vy *= AIR_DRAG
        self.spin *= AIR_DRAG
    end

    self.x += self.vx
    self.y += self.vy
    self:bounceWalls()

    -- A die crossing the tray quickly is a die that is tumbling quickly, so the
    -- spin never lags behind the travel however the last few hits left it.
    local rolling = self:speed() * SPIN_PER_PIXEL
    if math.abs(self.spin) < rolling then
        self.spin = rolling * self.spinBias
    end
    self.spin = math.max(-MAX_SPIN, math.min(MAX_SPIN, self.spin))
    self.angle = (self.angle + self.spin) % 360
end

-- The thrown style. Only the energy that is *new* this frame becomes a shove,
-- so winding the crank keeps feeding the dice rather than pinning them at one
-- speed, and the moment you stop they are coasting on what they already have.
function Die:throwAround(energy)
    local gained = energy - self.lastEnergy
    self.lastEnergy = energy
    if gained > 0.05 then
        self:kick(gained * 2.2 + 0.4)
    elseif energy > 1 and self.z <= 0 and self:speed() < 0.5 then
        -- Nothing should sit dead still while the rest of the handful is live.
        self:kick(0.9)
    end
    self:integrate()
end

-- The "in place" style: the die holds its reading position and spins on the
-- spot, hopping up and down. Spin and hop are both read straight off the shared
-- energy, which is what makes the whole handful move as one -- the opposite of
-- what the thrown style is for, and the reason the two look so different.
function Die:spinInPlace(energy)
    self.spin = energy * (2.4 + (self.hopPhase % 1) * 1.6)
    self.angle = (self.angle + self.spin) % 360

    local was = self.hopPhase
    self.hopPhase += 0.34

    -- Height off a sine rather than out of gravity, which is exactly why the
    -- hop is even and repetitive instead of a bounce that decays.
    self.z = math.abs(math.sin(self.hopPhase)) * math.min(energy * 2.2, 22)

    -- The die touches down every time the sine crosses zero. Reporting that as
    -- an impact means the clatter is timed off the hops in this style just as
    -- it is timed off real collisions in the other one.
    if energy > 1 and math.floor(was / math.pi) ~= math.floor(self.hopPhase / math.pi) then
        self.impacts += 1
    end
end

-- energy is the shared "how hard was this thrown" number owned by the roll
-- scene; every die reads from it so the whole handful moves together.
function Die:update(energy)
    if self.settled then
        self:updateLanding()
        return
    end

    if Dice.style == Dice.IN_PLACE then
        self:spinInPlace(energy)
    else
        self:throwAround(energy)
    end

    -- Re-roll the face every few frames so the numbers blur while in motion.
    if energy > 0.6 and math.random() < 0.5 then
        self.value = self:randomValue()
    end
end

-- The angle this die will come to rest at: the nearest orientation that leaves
-- its silhouette looking the same as square-on, so it seats itself instead of
-- unwinding however far it happened to have turned.
function Die:restAngle()
    local step = SYMMETRY[self.spec.shape] or 360
    return math.floor(self.angle / step + 0.5) * step
end

function Die:settle(value)
    self.value = value
    self.settled = true
    self.vx, self.vy, self.zv = 0, 0, 0
    self.spin = 0
    self.fromX, self.fromY, self.fromZ = self.x, self.y, self.z
    self.fromAngle, self.toAngle = self.angle, self:restAngle()

    local dx, dy = self.homeX - self.x, self.homeY - self.y
    local away = math.sqrt(dx * dx + dy * dy)
    self.glideFrames = math.max(GLIDE_MIN,
        math.min(GLIDE_MAX, math.ceil(away / GLIDE_SPEED)))
    self.glideTotal = self.glideFrames
    self.landFrames = 0
end

-- A die that stopped wherever the physics left it would be honest and unreadable
-- -- twelve of them would be a pile. So a landed die takes one short, eased
-- slide back to the slot the layout picked for it, then squashes as it arrives.
function Die:updateLanding()
    if self.glideFrames > 0 then
        self.glideFrames -= 1
        local t = 1 - self.glideFrames / self.glideTotal
        local e = 1 - (1 - t) * (1 - t) * (1 - t)
        self.x = self.fromX + (self.homeX - self.fromX) * e
        self.y = self.fromY + (self.homeY - self.fromY) * e
        self.z = self.fromZ * (1 - e)
        self.angle = (self.fromAngle + (self.toAngle - self.fromAngle) * e) % 360
        if self.glideFrames == 0 then
            self.x, self.y, self.z = self.homeX, self.homeY, 0
            self.angle = self.toAngle % 360
            self.landFrames = LAND_FRAMES
        end
    elseif self.landFrames > 0 then
        self.landFrames -= 1
    end
end

-- Height above the table while it is in the air, plus a short squash on landing.
function Die:visualOffsets()
    local squash = 1
    if self.landFrames > 0 then
        -- 8 -> 0 becomes a quick squeeze back out to full height.
        squash = 1 - (self.landFrames / LAND_FRAMES) * 0.25
    end
    return -self.z, squash
end

function Die:draw()
    local dy, squash = self:visualOffsets()
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

-- How much of the die the number takes up. Drawing numerals as shapes means
-- any height is available, so these are a look rather than a compromise: the
-- number should read as sitting on the die, not filling it.
local FACE_HEIGHT <const> = 0.40
local FACE_WIDTH <const> = 0.56

-- The height this die's face will be drawn at. Two digits are nearly twice the
-- width of one, so a wide label is shrunk to fit rather than allowed to spill
-- over the outline.
function Die:faceHeight(text)
    return Numerals.fit(text, self.size * FACE_WIDTH, self.size * FACE_HEIGHT)
end

-- Every face this die can show, for pre-rendering before a throw starts.
function Die:possibleLabels()
    local labels = {}
    if self.role == "tens" then
        for v = 0, 9 do labels[#labels + 1] = string.format("%02d", v * 10) end
    elseif self.role == "units" then
        for v = 0, 9 do labels[#labels + 1] = tostring(v) end
    else
        for v = 1, self.spec.sides do labels[#labels + 1] = tostring(v) end
    end
    return labels
end

function Die:drawFace(cx, cy)
    local text = self:label()
    Numerals.draw(text, cx, cy, self:faceHeight(text))
end

-- ---------------------------------------------------------------------------
-- A handful of dice at once
-- ---------------------------------------------------------------------------
-- Dice bumping into each other is most of what makes a handful look chaotic
-- rather than like a dozen dice each doing its own tidy thing. Push any
-- overlapping pair apart, then swap the part of their velocity that lies along
-- the line between them -- an elastic bounce between two equal masses.
--
-- Returns how many impacts happened this frame, walls included, so the scene
-- can clatter in time with the collisions instead of on a timer. Dice that have
-- already landed are out of the tray as far as this is concerned.
function Dice.collide(dice)
    local impacts = 0
    for i = 1, #dice do
        impacts += dice[i].impacts
        dice[i].impacts = 0
    end

    -- Dice that hold their positions can never run into each other, so the
    -- "in place" style skips the whole pass and keeps its lower cost.
    if Dice.style == Dice.IN_PLACE then
        return impacts
    end

    for i = 1, #dice - 1 do
        local a = dice[i]
        if not a.settled then
            for j = i + 1, #dice do
                local b = dice[j]
                if not b.settled then
                    local dx, dy = b.x - a.x, b.y - a.y
                    local reach = (a.size + b.size) * 0.45
                    local sq = dx * dx + dy * dy
                    if sq < reach * reach then
                        local dist = math.sqrt(sq)
                        if dist < 0.01 then
                            -- Exactly on top of each other: any side will do.
                            dx, dy, dist = 1, 0, 1
                        end
                        local nx, ny = dx / dist, dy / dist
                        local push = (reach - dist) * 0.5
                        a.x -= nx * push
                        a.y -= ny * push
                        b.x += nx * push
                        b.y += ny * push
                        a:clampToTray()
                        b:clampToTray()

                        -- Only closing dice bounce; two that already overlap and
                        -- are separating just need the shove above.
                        local closing = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
                        if closing < 0 then
                            local p = closing * DIE_BOUNCE
                            a.vx += p * nx
                            a.vy += p * ny
                            b.vx -= p * nx
                            b.vy -= p * ny
                            a.spin = -a.spin * 0.6 + closing * 2.5
                            b.spin = -b.spin * 0.6 - closing * 2.5
                            if a.z <= 0 then a.zv = math.max(a.zv, -closing * 0.35) end
                            if b.z <= 0 then b.zv = math.max(b.zv, -closing * 0.35) end
                            a:capSpeed()
                            b:capSpeed()
                            impacts += 1
                        end
                    end
                end
            end
        end
    end

    return impacts
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
