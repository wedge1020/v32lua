--#api tic80
-- BDR(row) is called before each screen row of screen RAM is drawn
-- (row = y + 4). Palette entry 1 gets red = 4 * y, green = 255 on odd rows.
function BDR(row)
  local y = row - 4
  poke(0x3FC0+3, y*4)
  poke(0x3FC0+4, (y%2==1) and 255 or 0)
  poke(0x3FC0+5, 0)
end
function TIC()
  cls(0)
  memset(0, 0x11, 120*40)            -- rows 0-39: color 1
  poke(120*50+10, 0x11)              -- row 50: x=20,21 color 1
end
