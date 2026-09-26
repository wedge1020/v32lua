--#api tic80
-- TIC-80 peek/poke/memcpy/memset on the emulated 96 KB RAM
function BOOT()
  r_pix = peek4(0x4000*2 + 1*64 + 3)   -- 3
  r_byte = peek(0x4000 + 32)   -- 16
  r_spr = peek4(0x6000*2 + 2)   -- 12
  r_map = peek(0x8000 + 1)   -- 1
  r_mget = mget(1, 0)   -- 1
  poke(0x8000 + 2, 7)
  r_mset_seen = mget(2, 0)   -- 7
  mset(3, 0, 9)
  r_peek_mset = peek(0x8000 + 3)   -- 9
  poke(0x14404 + 5, 0x81)
  r_fget = fget(5, 7)   -- true
  fset(6, 2, true)
  r_flagbyte = peek(0x14404 + 6)   -- 4
  poke4(0x3ff0*2 + 1, 12)
  r_palmap = peek(0x3ff0)   -- 192
  r_palmap4 = peek4(0x3ff0*2 + 1)   -- 12
  poke(0x14004, 200)
  r_pmem = peek(0x14004)   -- 200
  memset(0x14010, 5, 4)
  memcpy(0x14020, 0x14010, 3)
  r_memcpy = peek(0x14022)   -- 5
  r_memcpy_end = peek(0x14023)   -- 0
  r_bits1 = peek(0x4000*8 + 1*256 + 12, 1)   -- 1
  r_peek2 = peek2(0x4000*4 + 32*4)   -- 0
  r_oob = peek(0x20000)   -- 0
  r_pad = peek(0xff80)   -- 0 (no buttons)
  r_pal_r = peek(0x3fc0)   -- 26
end
function TIC() cls(0) end
-- <TILES>
-- 001:0123456789abcdef00000000000000000000000000000000000000000000000000
-- </TILES>
-- <SPRITES>
-- 000:00c0000000000000000000000000000000000000000000000000000000000000
-- </SPRITES>
-- <MAP>
-- 000:00100000
-- </MAP>
