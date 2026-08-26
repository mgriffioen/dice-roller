-- Scene 1: describe the throw -- die type, how many, modifier, and (for a d20)
-- advantage or disadvantage.
--
-- With four things to set and only a d-pad, this is a field list rather than a
-- set of fixed bindings: up/down chooses a field, left/right changes it. The
-- crank changes it too, which matters for the modifier -- +20 is forty button
-- presses but about half a turn of the crank.

local gfx <const> = playdate.graphics

SetupScene = {}

local ROW_X <const>, ROW_W <const>, ROW_H <const> = 118, 276, 34
local ROW_TOP <const>, ROW_GAP <const> = 34, 6

-- Degrees of crank per single step of the selected field.
local CRANK_STEP <const> = 12

local MODES <const> = { "normal", "advantage", "disadvantage" }

-- Small solid triangles used as "press this direction" hints. The system font
-- has no arrow glyphs, so we draw them.
local function triangle(cx, cy, size, dir, color)
    gfx.setColor(color or gfx.kColorBlack)
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

local function indexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then return i end
    end
    return 1
end

function SetupScene:enter()
    self.config = self.config or Dice.newConfig()
    self.typeIndex = self.typeIndex or indexOf(DiceTypes, self.config.spec)
    self.selected = self.selected or 1
    self.crankAccum = 0
    self.previewAngle = 0
    self:refresh()
end

-- Take on a throw described elsewhere -- the history page handing back a past
-- roll -- so that backing out of it lands on a setup screen that matches.
function SetupScene:adopt(config)
    self.config = config
    self.typeIndex = indexOf(DiceTypes, config.spec)
    self.selected = 1
    self:refresh()
end

-- The advantage row only exists for die types that support it, so the field
-- list is rebuilt rather than fixed.
function SetupScene:fields()
    local fields = {
        { id = "type",  label = "DIE" },
        { id = "count", label = "HOW MANY" },
        { id = "mod",   label = "MODIFIER" },
    }
    if self.config.spec.allowAdvantage then
        fields[#fields + 1] = { id = "adv", label = "D20 ROLL" }
    end
    return fields
end

function SetupScene:refresh()
    local config = self.config
    config.spec = DiceTypes[self.typeIndex]
    config.count = Util.clamp(config.count, 1, config.spec.maxCount)
    config.modifier = Util.clamp(config.modifier, Dice.MOD_MIN, Dice.MOD_MAX)
    if not config.spec.allowAdvantage then
        config.mode = "normal"
    end
    self.selected = Util.clamp(self.selected, 1, #self:fields())

    -- A single static die, drawn with the same code the rolling scene uses.
    local die = Die(config.spec, config.spec.percentile and "tens" or "normal")
    die.size = 76
    die.x, die.y = 58, 100
    die.settled = true
    die.angle = 0
    die.value = config.spec.percentile and 20 or config.spec.sides
    self.previewDie = die
end

function SetupScene:valueText(id)
    local config = self.config
    if id == "type" then
        return config.spec.key
    elseif id == "count" then
        return tostring(config.count)
    elseif id == "mod" then
        return config.modifier > 0 and ("+" .. config.modifier) or tostring(config.modifier)
    end
    return config.mode
end

-- delta is +1 or -1. Type, count and mode wrap around; the modifier clamps,
-- because sliding from +20 straight to -20 is never what anyone meant.
function SetupScene:adjust(id, delta)
    local config = self.config
    if id == "type" then
        self.typeIndex = (self.typeIndex - 1 + delta) % #DiceTypes + 1
    elseif id == "count" then
        config.count = (config.count - 1 + delta) % config.spec.maxCount + 1
    elseif id == "mod" then
        config.modifier = Util.clamp(config.modifier + delta, Dice.MOD_MIN, Dice.MOD_MAX)
    elseif id == "adv" then
        config.mode = MODES[(indexOf(MODES, config.mode) - 1 + delta) % #MODES + 1]
    end
    self:refresh()
end

function SetupScene:update()
    local fields = self:fields()

    if playdate.buttonJustPressed(playdate.kButtonUp) then
        self.selected = (self.selected - 2) % #fields + 1
        Sfx.move()
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        self.selected = self.selected % #fields + 1
        Sfx.move()
    end

    -- Read the row after moving, so a direction pressed on the same frame as
    -- up/down acts on the row the cursor ended on.
    local field = fields[self.selected]

    if playdate.buttonJustPressed(playdate.kButtonLeft) then
        self:adjust(field.id, -1)
        Sfx.move()
    elseif playdate.buttonJustPressed(playdate.kButtonRight) then
        self:adjust(field.id, 1)
        Sfx.move()
    end

    -- The crank drives the same adjustment, in detents rather than continuously,
    -- so it feels like a dial with stops rather than a slider.
    self.crankAccum += playdate.getCrankChange()
    while math.abs(self.crankAccum) >= CRANK_STEP do
        local step = self.crankAccum > 0 and 1 or -1
        self.crankAccum -= step * CRANK_STEP
        self:adjust(field.id, step)
        Sfx.move()
    end

    if playdate.buttonJustPressed(playdate.kButtonA) then
        Sfx.select()
        Game.switchTo(RollScene, self.config)
        return
    end

    if playdate.buttonJustPressed(playdate.kButtonB) then
        Sfx.select()
        Game.switchTo(HistoryScene)
        return
    end

    -- Idle wobble on the preview die so the screen isn't completely static.
    self.previewAngle += 0.9
    self.previewDie.angle = math.sin(math.rad(self.previewAngle)) * 7

    self:draw()
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------
function SetupScene:draw()
    local config = self.config

    gfx.clear(gfx.kColorWhite)

    -- Header ---------------------------------------------------------------
    Util.drawBar(0, 0, 400, 22)
    Util.drawInvertedText("DICE ROLLER", 8, 3)
    local last = History.latest()
    if last then
        Util.drawInvertedText("last: " .. last.notation .. " = " .. last.total,
            392, 3, kTextAlignment.right)
    end

    -- Preview column -------------------------------------------------------
    self.previewDie:draw(0)

    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(6, 142, 104, 22, 4)
    Util.drawInvertedText(Dice.notation(config), 58, 145, kTextAlignment.center)

    local low, high = Dice.range(config)
    gfx.drawTextAligned(low .. " to " .. high, 58, 168, kTextAlignment.center)

    -- Field rows -----------------------------------------------------------
    for i, field in ipairs(self:fields()) do
        self:drawRow(field, ROW_TOP + (i - 1) * (ROW_H + ROW_GAP), i == self.selected)
    end

    -- Hints ----------------------------------------------------------------
    Util.drawBar(0, 196, 400, 44)
    Util.drawInvertedText("up/down: choose", 8, 200)
    Util.drawInvertedText("A: roll", 392, 200, kTextAlignment.right)
    Util.drawInvertedText("left/right or crank: change", 8, 220)
    Util.drawInvertedText("B: history", 392, 220, kTextAlignment.right)
end

function SetupScene:drawRow(field, y, selected)
    local value = self:valueText(field.id)
    local textY = y + 9
    local valueRight = ROW_X + ROW_W - 24

    if selected then
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRoundRect(ROW_X, y, ROW_W, ROW_H, 6)
        Util.drawInvertedText(field.label, ROW_X + 12, textY)
        Util.drawInvertedText(value, valueRight, textY, kTextAlignment.right)

        -- Arrows bracket the value to show which way it can be nudged.
        local valueWidth = gfx.getTextSize(value)
        triangle(valueRight - valueWidth - 12, y + ROW_H / 2, 5, "left", gfx.kColorWhite)
        triangle(valueRight + 12, y + ROW_H / 2, 5, "right", gfx.kColorWhite)
    else
        Util.drawPanel(ROW_X, y, ROW_W, ROW_H, 6)
        gfx.drawTextAligned(field.label, ROW_X + 12, textY, kTextAlignment.left)
        gfx.drawTextAligned(value, valueRight, textY, kTextAlignment.right)
    end
end
