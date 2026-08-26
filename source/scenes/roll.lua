-- Scene 2: throw the dice with the crank, then show the total on an overlay.

local gfx <const> = playdate.graphics
local ease <const> = playdate.easingFunctions

RollScene = {}

-- How far the crank has to travel (in degrees) before the dice are allowed to
-- land. 540 is one and a half turns: enough to feel deliberate, short enough
-- that rolling twenty times in a session isn't a chore.
local CRANK_TARGET <const> = 540
local SETTLE_GAP <const> = 4     -- frames between one die landing and the next
local REVEAL_DELAY <const> = 14  -- frames between the last die and the overlay
local OVERLAY_FRAMES <const> = 10

local PANEL_X <const>, PANEL_W <const> = 24, 352
local PANEL_Y <const>, PANEL_H <const> = 40, 168

function RollScene:enter(config)
    self.config = config
    self.dice, self.groups = Dice.build(config)
    Layout.arrange(self.groups, 8, 28, 384, 164)
    self:reset()
end

function RollScene:reset()
    self.state = "ready"       -- ready -> tumbling -> settling -> result
    self.energy = 0
    self.cranked = 0
    self.frame = 0
    self.settleIndex = 0
    self.settleTimer = 0
    self.revealTimer = 0
    self.overlayFrames = 0
    self.result = nil
    self.hintAngle = 0
    for _, die in ipairs(self.dice) do
        die.settled = false
        die.dropped = false
        die.landFrames = 0
        die.angle = math.random() * 360
    end
    for _, group in ipairs(self.groups) do
        group.marked = false
    end
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------
function RollScene:update()
    self.frame += 1

    if playdate.buttonJustPressed(playdate.kButtonB) then
        Sfx.back()
        Game.switchTo(SetupScene)
        return
    end

    if self.state == "ready" or self.state == "tumbling" then
        self:updateThrow()
    elseif self.state == "settling" then
        self:updateSettle()
    else
        self:updateResult()
    end

    for _, die in ipairs(self.dice) do
        die:update(self.energy)
    end

    self:draw()
end

function RollScene:updateThrow()
    -- getCrankChange returns degrees moved since the last call, signed. We only
    -- care how *much* it moved, so either direction winds the dice up.
    local change = playdate.getCrankChange()
    local magnitude = math.abs(change)

    -- Fallback for a docked crank (and for anyone testing without one):
    -- holding A winds the throw up at a steady rate.
    if playdate.isCrankDocked() and playdate.buttonIsPressed(playdate.kButtonA) then
        magnitude = math.max(magnitude, 13)
    end

    if magnitude > 1.5 then
        self.cranked += magnitude
        self.energy = math.min(self.energy + magnitude * 0.05, 14)
        if self.state == "ready" then
            self.state = "tumbling"
        end
    end

    -- Energy bleeds away every frame, so the dice slow down the moment you stop.
    self.energy *= 0.93

    if self.energy > 2 and self.frame % 4 == 0 then
        Sfx.tumble()
    end

    if self.state == "tumbling" and self.cranked >= CRANK_TARGET and self.energy < 1.5 then
        self.state = "settling"
        self.settleTimer = SETTLE_GAP
    end
end

function RollScene:updateSettle()
    -- Keep a little energy in the pot so the dice still in the air keep moving.
    self.energy = 1.6

    if self.settleIndex < #self.dice then
        self.settleTimer += 1
        if self.settleTimer >= SETTLE_GAP then
            self.settleTimer = 0
            self.settleIndex += 1
            local die = self.dice[self.settleIndex]
            die:settle(die:randomValue())
            Sfx.land()
            -- Cross out a discarded die as soon as its partner has landed,
            -- rather than waiting for the whole handful.
            Dice.markDropped(self.config, self.groups)
        end
        return
    end

    self.energy = 0
    self.revealTimer += 1
    if self.revealTimer >= REVEAL_DELAY then
        self:computeResult()
        Sfx.reveal()
        self.state = "result"
    end
end

function RollScene:updateResult()
    self.energy = 0
    self.overlayFrames = math.min(self.overlayFrames + 1, OVERLAY_FRAMES)

    if playdate.buttonJustPressed(playdate.kButtonA) then
        Sfx.select()
        self:reset()
    end
end

function RollScene:computeResult()
    local config = self.config
    local parts = {}
    local high, low = nil, nil

    for _, group in ipairs(self.groups) do
        local value = Dice.groupValue(config, group)
        parts[#parts + 1] = Dice.groupLabel(config, group)
        if high == nil or value > high then high = value end
        if low == nil or value < low then low = value end
    end

    local total, diceTotal = Dice.total(config, self.groups)

    -- A natural 20 is a property of the die, not of the total, so this reads
    -- the dice subtotal and ignores the modifier. Under advantage it is the
    -- kept die that counts, which Dice.groupValue has already picked.
    local banner = nil
    if config.spec.key == "d20" and config.count == 1 then
        if diceTotal == 20 then banner = "NATURAL 20!"
        elseif diceTotal == 1 then banner = "NATURAL 1" end
    end

    self.result = {
        notation = Dice.notation(config),
        total = total,
        diceTotal = diceTotal,
        modifier = config.modifier,
        parts = parts,
        high = high,
        low = low,
        banner = banner,
    }
    Game.lastResult = self.result
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------
function RollScene:draw()
    gfx.clear(gfx.kColorWhite)

    Util.drawBar(0, 0, 400, 24)
    Util.drawInvertedText(Dice.notation(self.config), 8, 4)
    Util.drawInvertedText("B: change dice", 392, 4, kTextAlignment.right)

    for _, die in ipairs(self.dice) do
        die:draw(self.energy)
    end

    if self.state == "result" then
        self:drawOverlay()
    else
        self:drawThrowUI()
    end
end

function RollScene:drawThrowUI()
    -- Progress toward a legal throw.
    local progress = math.min(self.cranked / CRANK_TARGET, 1)
    local x, y, w, h = 60, 198, 280, 12

    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawRoundRect(x, y, w, h, 4)
    gfx.setLineWidth(1)
    if progress > 0 then
        gfx.fillRoundRect(x + 2, y + 2, math.max((w - 4) * progress, 2), h - 4, 2)
    end

    self:drawCrankHint(28, 204)

    Util.drawBar(0, 218, 400, 22)
    local message
    if playdate.isCrankDocked() then
        message = "undock the crank to roll   (or hold A)"
    elseif self.state == "ready" then
        message = "turn the crank to roll"
    elseif progress < 1 then
        message = "keep cranking..."
    else
        message = "let go - the dice are landing"
    end
    Util.drawInvertedText(message, 200, 221, kTextAlignment.center)
end

-- A little crank that spins along with the real one, so it is obvious what the
-- controller expects you to do.
function RollScene:drawCrankHint(cx, cy)
    self.hintAngle += 4 + self.energy * 12
    local a = math.rad(self.hintAngle)

    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawCircleAtPoint(cx, cy, 11)
    local hx, hy = cx + math.cos(a) * 11, cy + math.sin(a) * 11
    gfx.drawLine(cx, cy, hx, hy)
    gfx.fillCircleAtPoint(hx, hy, 3)
    gfx.setLineWidth(1)
end

function RollScene:drawOverlay()
    local r = self.result
    Util.dimScreen()

    -- Slide the panel up from below the screen.
    local y = ease.outCubic(self.overlayFrames, 240, PANEL_Y - 240, OVERLAY_FRAMES)
    Util.drawPanel(PANEL_X, y, PANEL_W, PANEL_H)

    -- The notation already carries the modifier and adv/dis, so the right-hand
    -- slot is free for whatever is most worth saying about this particular roll.
    gfx.drawTextAligned(r.notation, PANEL_X + 16, y + 12, kTextAlignment.left)
    local aside = r.banner
    if aside == nil and self.config.count > 1 then
        aside = "high " .. r.high .. "   low " .. r.low
    end
    if aside then
        gfx.drawTextAligned(aside, PANEL_X + PANEL_W - 16, y + 12, kTextAlignment.right)
    end

    Util.drawBigText(tostring(r.total), 200, y + 38, 4, kTextAlignment.center)

    -- The individual dice, wrapped and truncated if there are a lot of them.
    gfx.drawTextInRect(self:breakdownText(), PANEL_X + 14, y + 112, PANEL_W - 28, 44,
        nil, "...", kTextAlignment.center)

    Util.drawBar(0, 218, 400, 22)
    Util.drawInvertedText("A: roll again", 8, 221)
    Util.drawInvertedText("B: change dice", 392, 221, kTextAlignment.right)
end

-- "4 + 2 + 6" on its own, or "(4 + 2 + 6)  + 3" once a modifier is involved --
-- the brackets keep it honest about what was added to what.
function RollScene:breakdownText()
    local r = self.result
    local dice = table.concat(r.parts, Dice.separator(self.config))
    if r.modifier == 0 then
        return dice
    end
    if #r.parts > 1 then
        dice = "(" .. dice .. ")"
    end
    return dice .. (r.modifier > 0 and "  + " or "  - ") .. math.abs(r.modifier)
end
