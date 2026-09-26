function main()
  local a, b, n, m1, big = 0xF0F0, 0x0FF0, 4, -1, 0xFF
  R_and = a & b
  R_or = a | b
  R_xor = a ~ b
  R_not0 = ~0
  R_notv = ~a
  R_negand = m1 & 0xFF
  R_negand2 = -256 & 0xFFFF
  R_shl = big << 24
  R_shl2 = 1 << n
  R_shr = a >> n
  R_shrneg = a >> -n
  R_shlneg = a << -n
  R_shr0 = m1 >> 0
  R_prec1 = 1 | 2 & 3
  R_prec2 = 1 << 2 + 1
  R_prec3 = 5 & 3 == 1
  R_prec4 = 6 ~ 3 | 8
  R_float = 7.0 & 3
  R_neg = -5 & 7
  R_nnot = ~m1
  R_xor2 = -1 ~ 0xFF
  R_cmp = (a & 0xF0) == 0xF0
  R_lit = 0xFF00 & 0x0FF0
  R_lit2 = ~5
  R_lit3 = 3 << 2
  R_hexfrac = 0x1.8
  R_mixed = (n & 1) + (n | 1) * 2
  local t = {x = 12}
  R_tbl = t.x & 8 | 1
  R_call = math.floor(9.5) & 3
  R_colors = (255 << 24) | (16 << 16) | (32 << 8) | 64
  local function mk() local k = 3; return function() return k ^ 2 end end
  R_powcap = mk()()   -- x^y inside a closure used to lose its upvalue
end
