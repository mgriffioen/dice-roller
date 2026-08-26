-- Scene 3: the last few rolls, newest first. Pick one and throw it again.

local gfx <const> = playdate.graphics

HistoryScene = {}

local LIST_X <const>, LIST_Y <const> = 6, 26
local ROW_H <const> = 33
local ROWS <const> = 5              -- how many fit between the header and the hints
local FULL_W <const> = 388
local NARROW_W <const> = 378        -- leaves room for the scrollbar
local CRANK_STEP <const> = 20       -- degrees of crank per row

function HistoryScene:enter()
    self.selected = 1
    self.offset = 0
    self.crankAccum = 0
end

function HistoryScene:move(delta)
    local n = #History.entries
    if n == 0 then return end
    self.selected = (self.selected - 1 + delta) % n + 1
    -- Scroll only as far as it takes to bring the selection back into view.
    if self.selected <= self.offset then
        self.offset = self.selected - 1
    elseif self.selected > self.offset + ROWS then
        self.offset = self.selected - ROWS
    end
    Sfx.move()
end

function HistoryScene:update()
    if playdate.buttonJustPressed(playdate.kButtonB) then
        Sfx.back()
        Game.switchTo(SetupScene)
        return
    end

    if playdate.buttonJustPressed(playdate.kButtonUp) then
        self:move(-1)
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        self:move(1)
    end

    self.crankAccum += playdate.getCrankChange()
    while math.abs(self.crankAccum) >= CRANK_STEP do
        local step = self.crankAccum > 0 and 1 or -1
        self.crankAccum -= step * CRANK_STEP
        self:move(step)
    end

    if playdate.buttonJustPressed(playdate.kButtonA) then
        local entry = History.entries[self.selected]
        local config = entry and History.configOf(entry)
        if config then
            Sfx.select()
            -- Leave the setup screen showing this throw, so backing out of the
            -- roll lands somewhere that matches what was just rolled.
            SetupScene:adopt(config)
            Game.switchTo(RollScene, config)
            return
        end
    end

    self:draw()
end

-- ---------------------------------------------------------------------------
-- Draw
-- ---------------------------------------------------------------------------
function HistoryScene:draw()
    local n = #History.entries

    gfx.clear(gfx.kColorWhite)

    Util.drawBar(0, 0, 400, 22)
    Util.drawInvertedText("HISTORY", 8, 3)
    if n > 0 then
        Util.drawInvertedText(self.selected .. " of " .. n, 392, 3, kTextAlignment.right)
    end

    if n == 0 then
        gfx.drawTextAligned("No rolls yet.", 200, 96, kTextAlignment.center)
        gfx.drawTextAligned("Throw some dice and they turn up here.",
            200, 118, kTextAlignment.center)
    else
        local width = n > ROWS and NARROW_W or FULL_W
        local last = math.min(self.offset + ROWS, n)
        for i = self.offset + 1, last do
            self:drawRow(History.entries[i], LIST_Y + (i - self.offset - 1) * ROW_H,
                width, i == self.selected)
        end
        if n > ROWS then
            self:drawScrollbar(n)
        end
    end

    Util.drawBar(0, 196, 400, 44)
    Util.drawInvertedText("up/down or crank: browse", 8, 200)
    if n > 0 then
        Util.drawInvertedText("A: roll it again", 392, 200, kTextAlignment.right)
    end
    Util.drawInvertedText("B: back", 8, 220)
end

function HistoryScene:drawRow(entry, y, width, selected)
    local textY = y + 8
    local total = tostring(entry.total)

    if selected then
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRoundRect(LIST_X, y, width, ROW_H - 2, 5)
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    else
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(1)
        gfx.drawLine(LIST_X + 6, y + ROW_H - 2, LIST_X + width - 6, y + ROW_H - 2)
    end

    gfx.drawTextAligned(entry.notation, LIST_X + 10, textY, kTextAlignment.left)
    gfx.drawTextAligned(total, LIST_X + width - 10, textY, kTextAlignment.right)

    -- Whatever room is left between the two goes to the dice themselves, cut
    -- short with an ellipsis when there are more than will fit.
    local totalWidth = gfx.getTextSize(total)
    local x = LIST_X + 112
    local room = (LIST_X + width - 10 - totalWidth - 10) - x
    if room > 40 then
        gfx.drawTextInRect(entry.breakdown, x, textY, room, 20, nil, "...", kTextAlignment.left)
    end

    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function HistoryScene:drawScrollbar(n)
    local x, w = 388, 8
    local trackH = ROWS * ROW_H - 2

    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    gfx.drawRoundRect(x, LIST_Y, w, trackH, 4)

    local thumbH = math.max(trackH * ROWS / n, 12)
    local maxOffset = n - ROWS
    local travel = maxOffset > 0 and (self.offset / maxOffset) or 0
    gfx.fillRoundRect(x + 2, LIST_Y + 2 + (trackH - 4 - thumbH) * travel, w - 4, thumbH, 2)
end
