-- Scene 1: choose the kind of die and how many to throw.

local gfx <const> = playdate.graphics

SetupScene = {}

local STRIP_Y <const> = 32
local STRIP_H <const> = 30
local CELL_W <const> = 400 / #DiceTypes

-- Small solid triangles used as "press this direction" hints. The system font
-- has no arrow glyphs, so we draw them.
local function triangle(cx, cy, size, dir)
    gfx.setColor(gfx.kColorBlack)
    if dir == "up" then
        gfx.fillTriangle(cx, cy - size, cx - size, cy + size, cx + size, cy + size)
    elseif dir == "down" then
        gfx.fillTriangle(cx, cy + size, cx - size, cy - size, cx + size, cy - size)
    elseif dir == "left" then
        gfx.fillTriangle(cx - size, cy, cx + size, cy - size, cx + size, cy + size)
    else
        gfx.fillTriangle(cx + size, cy, cx - size, cy - size, cx - size, cy + size)
    end
end

function SetupScene:enter()
    self.typeIndex = self.typeIndex or 3        -- default to d6
    self.count = self.count or 1
    self.previewAngle = 0
    self:refreshPreview()
end

function SetupScene:spec()
    return DiceTypes[self.typeIndex]
end

function SetupScene:refreshPreview()
    local spec = self:spec()
    self.count = Util.clamp(self.count, 1, spec.maxCount)

    -- A single static die, drawn with the same code the rolling scene uses.
    local die = Die(spec, spec.percentile and "tens" or "normal")
    die.size = 88
    die.x, die.y = 96, 132
    die.settled = true
    die.angle = 0
    die.value = spec.percentile and 20 or spec.sides
    self.previewDie = die
end

function SetupScene:update()
    if playdate.buttonJustPressed(playdate.kButtonLeft) then
        self.typeIndex = self.typeIndex - 1
        if self.typeIndex < 1 then self.typeIndex = #DiceTypes end
        self:refreshPreview()
        Sfx.move()
    elseif playdate.buttonJustPressed(playdate.kButtonRight) then
        self.typeIndex = self.typeIndex % #DiceTypes + 1
        self:refreshPreview()
        Sfx.move()
    end

    local spec = self:spec()
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        self.count = self.count % spec.maxCount + 1
        Sfx.move()
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        self.count = self.count - 1
        if self.count < 1 then self.count = spec.maxCount end
        Sfx.move()
    end

    if playdate.buttonJustPressed(playdate.kButtonA) then
        Sfx.select()
        Game.switchTo(RollScene, spec, self.count)
        return
    end

    -- Idle wobble on the preview die so the screen isn't completely static.
    self.previewAngle += 0.9
    self.previewDie.angle = math.sin(math.rad(self.previewAngle)) * 7

    self:draw()
end

function SetupScene:draw()
    local spec = self:spec()

    gfx.clear(gfx.kColorWhite)

    -- Header ---------------------------------------------------------------
    Util.drawBar(0, 0, 400, 24)
    Util.drawInvertedText("DICE ROLLER", 8, 4)
    if Game.lastResult then
        Util.drawInvertedText("last: " .. Game.lastResult.notation .. " = " ..
            Game.lastResult.total, 392, 4, kTextAlignment.right)
    end

    -- Dice type strip ------------------------------------------------------
    for i, t in ipairs(DiceTypes) do
        local x = (i - 1) * CELL_W
        if i == self.typeIndex then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRoundRect(x + 1, STRIP_Y, CELL_W - 2, STRIP_H, 4)
            Util.drawInvertedText(t.key, x + CELL_W / 2, STRIP_Y + 7, kTextAlignment.center)
        else
            gfx.drawTextAligned(t.key, x + CELL_W / 2, STRIP_Y + 7, kTextAlignment.center)
        end
    end

    -- Preview die ----------------------------------------------------------
    self.previewDie:draw(0)
    triangle(14, 132, 6, "left")
    triangle(178, 132, 6, "right")
    gfx.drawTextAligned(spec.key, 96, 180, kTextAlignment.center)
    if spec.percentile then
        gfx.drawTextAligned("a pair of d10s", 96, 198, kTextAlignment.center)
    end

    -- Count + notation -----------------------------------------------------
    Util.drawPanel(196, 76, 196, 128)
    gfx.drawTextAligned("HOW MANY", 294, 84, kTextAlignment.center)
    triangle(294, 108, 6, "up")
    Util.drawBigText(tostring(self.count), 294, 116, 2, kTextAlignment.center)
    triangle(294, 156, 6, "down")

    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(210, 172, 168, 22, 4)
    -- The possible range: one per die at worst, all maximums at best.
    Util.drawInvertedText(Dice.notation(spec, self.count) .. "   " ..
        self.count .. "-" .. (spec.sides * self.count), 294, 175, kTextAlignment.center)

    -- Hints ----------------------------------------------------------------
    Util.drawBar(0, 218, 400, 22)
    Util.drawInvertedText("left/right: die    up/down: count", 8, 221)
    Util.drawInvertedText("A: roll", 392, 221, kTextAlignment.right)
end
