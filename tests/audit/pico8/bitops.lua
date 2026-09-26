--#api pico8
-- PICO-8 bitwise operators and band/bor/... (16.16 fixed point, as PICO-8)
function _init()
  local a, one, m8 = 0x5555, 1, -8
  r_band = band(a, 0x0ff0)   -- 1360
  r_band_op = a & 0x0ff0   -- 1360
  r_bor = bor(0.5, one)   -- 1.5
  r_bnot = bnot(0)   -- -1/65536
  r_shr = shr(m8, 1)   -- -4
  r_sar = m8 >> 1   -- -4
  r_lshr = lshr(-1, 16)   -- 0xffff/65536
  r_lshr_op = -one >>> 16   -- 0xffff/65536
  r_rotl = rotl(one, 16)   -- 1/65536
  r_rotl_op = one <<> 16   -- 1/65536
  r_rotr = rotr(0x0000.0001, 1)   -- -32768
  r_rotr_op = 0x0.0001 >>< one   -- -32768
  r_shl = shl(one, 15)   -- -32768
  r_ffff = 0xffff   -- -1
  r_bin = 0b1010   -- 10
  r_binfrac = 0b1.1   -- 1.5
  r_xor = 6 ^^ 3   -- 5
  r_bxor = bxor(6, 3)   -- 5
  local c = 12
  c &= 10
  r_cand = c   -- 8
  c |= 1
  r_cor = c   -- 9
  c ^^= 3
  r_cxor = c   -- 10
  c <<= 2
  r_cshl = c   -- 40
  c >>= 1
  r_cshr = c   -- 20
  c >>>= 1
  r_clshr = c   -- 10
  r_sarbig = shr(-1, 40)   -- -1/65536
  r_frac = 1.75 & 1.25   -- 1.25
end
function _update() end
function _draw() end
