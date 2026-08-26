-- A few synth blips. No audio files needed: the Playdate has synthesisers built
-- in, so a whole sound set fits in a dozen lines.

Sfx = { enabled = true }

local tones = {}      -- round-robin pool so overlapping blips don't cut each other off
local noise
local nextTone = 1

function Sfx.init()
    for i = 1, 4 do
        tones[i] = playdate.sound.synth.new(playdate.sound.kWaveSquare)
    end
    noise = playdate.sound.synth.new(playdate.sound.kWaveNoise)
end

local function tone(freq, volume, length)
    if not Sfx.enabled then return end
    tones[nextTone]:playNote(freq, volume, length)
    nextTone = nextTone % #tones + 1
end

function Sfx.move()   tone(660, 0.12, 0.02) end
function Sfx.select() tone(880, 0.16, 0.05) end
function Sfx.back()   tone(440, 0.14, 0.05) end

-- The clatter of a die hitting the table: a noise burst plus a low click.
function Sfx.land()
    if not Sfx.enabled then return end
    noise:playNote(1200 + math.random(-200, 200), 0.14, 0.04)
    tone(180 + math.random(0, 120), 0.10, 0.03)
end

-- Called while the dice are in the air, at a rate set by the crank speed.
function Sfx.tumble()
    if not Sfx.enabled then return end
    noise:playNote(2000 + math.random(-600, 600), 0.05, 0.02)
end

function Sfx.reveal()
    tone(523, 0.14, 0.07)
    tone(784, 0.14, 0.12)
end
