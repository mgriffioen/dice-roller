-- Works out where to put N dice inside a rectangle.

Layout = {}

local MAX_DIE <const> = 78
local MIN_DIE <const> = 20

-- `groups` is the list from Dice.build. A group of two dice -- a percentile
-- pair, or an advantage/disadvantage pair -- has to sit side by side, so a cell
-- is wider for those.
--
-- The rectangle does double duty: it is the grid the dice are read from once
-- they stop, and it is the tray they career around inside while they are still
-- moving.
--
-- Rather than hard-coding a grid per count, try every column count and keep
-- whichever produces the largest dice. Cheap (there are at most 12 groups) and
-- it means the layout stays sensible if the count limits ever change.
function Layout.arrange(groups, x, y, w, h)
    local n = #groups
    if n == 0 then return end

    local pair = #groups[1] == 2
    local cellRatioW = pair and 1.95 or 1.18   -- cell width  in die-sizes
    local cellRatioH <const> = 1.30            -- cell height in die-sizes

    local best = { size = 0, cols = 1, rows = n }
    for cols = 1, n do
        local rows = math.ceil(n / cols)
        local size = math.min(w / cols / cellRatioW, h / rows / cellRatioH)
        if size > best.size then
            best = { size = size, cols = cols, rows = rows }
        end
    end

    local size = math.min(best.size, MAX_DIE)
    size = math.max(size, MIN_DIE)

    local cellW = size * cellRatioW
    local cellH = size * cellRatioH
    local gridH = cellH * best.rows
    local top = y + (h - gridH) / 2

    local index = 1
    for row = 0, best.rows - 1 do
        local inRow = math.min(best.cols, n - row * best.cols)
        local rowW = cellW * inRow
        local left = x + (w - rowW) / 2
        for col = 0, inRow - 1 do
            local group = groups[index]
            local cx = left + cellW * (col + 0.5)
            local cy = top + cellH * (row + 0.5)
            if pair then
                -- Side by side and slightly smaller, so the two dice read as
                -- one result rather than two.
                local half = size * 0.86
                group[1].size = half
                group[1]:setHome(cx - half * 0.56, cy)
                group[2].size = half
                group[2]:setHome(cx + half * 0.56, cy)
            else
                group[1].size = size
                group[1]:setHome(cx, cy)
            end
            for _, die in ipairs(group) do
                die:setTray(x, y, w, h)
            end
            index += 1
        end
    end
end
