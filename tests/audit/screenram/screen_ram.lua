--#api tic80
local function pal(c,r,g,b) poke(0x3FC0+3*c,r) poke(0x3FC0+3*c+1,g) poke(0x3FC0+3*c+2,b) end
function TIC()
  pal(1,255,0,0) pal(2,0,255,0) pal(3,0,0,255) pal(4,255,255,0)
  cls(0)
  memset(0, 0x11, 120*10)            -- rows 0-9: color 1
  poke(120*20+10, 0x23)              -- row 20: x=20 color 3, x=21 color 2
  for i=0,59 do poke(0x5000+i,0x44) poke(0x5000+60+i,0x12) end
  memcpy(120*30, 0x5000, 120)        -- row 30: x 0-119 color 4, x 120-.. 1 then 2
  memset(120*40, 0x33, 60)           -- row 40-: half row of 3
end
