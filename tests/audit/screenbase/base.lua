--#api tic80
-- A 240x136 test image with dithered, noisy, speckled and banded rows, copied
-- to screen RAM in one memcpy: every pixel must come out as its palette color
-- whatever the renderer does to cut the number of draws (base color per row).
local done = false
local seed = 12345
local function rnd() seed = (seed * 75 + 74) % 65537 return seed end
local function pick(y, x)
  if y < 34 then return (rnd() % 10 < 7) and 3 or 5 end
  if y < 68 then local r = rnd() % 5 if r < 2 then return 1 elseif r < 4 then return 7 else return 12 end end
  if y < 102 then return (rnd() % 12 == 0) and 14 or 9 end
  return (x // 30) % 16
end
function TIC()
  if done then return end
  done = true
  for c = 0, 15 do
    poke(0x3FC0 + 3 * c, (c * 16) % 256)
    poke(0x3FC0 + 3 * c + 1, (c * 37 + 11) % 256)
    poke(0x3FC0 + 3 * c + 2, (c * 91 + 50) % 256)
  end
  cls(0)
  for y = 0, 135 do
    for bx = 0, 119 do
      local lo = pick(y, 2 * bx)
      local hi = pick(y, 2 * bx + 1)
      poke(0x4000 + y * 120 + bx, lo | (hi << 4))
    end
  end
  memcpy(0, 0x4000, 16320)
  poke(120 * 5 + 7, 0x2E)            -- short writes (no base color): one byte ...
  memset(120 * 6 + 50, 0xA5, 10)     -- ... and ten
end
