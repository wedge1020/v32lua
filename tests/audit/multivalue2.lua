-- Multi-value spreads into call arguments: `...`, table.unpack and
-- multi-return calls as the last argument (node/multivalue.c).
function main()
  local function cnt(...) return #{...} end
  local function sum(a, b, c, d) return (a or 0) + (b or 0)*10 + (c or 0)*100 + (d or 0)*1000 end
  local function fwd(...) return sum(...) end
  R_1 = fwd(1, 2, 3)
  local t = {4, 5, 6}
  R_2 = sum(table.unpack(t))
  R_3 = sum(1, table.unpack(t))
  local function three() return 7, 8, 9 end
  R_4 = sum(three())
  R_5 = sum(1, three())
  local function pk(...) local a = {...} return #a end
  R_6 = pk(1, 2, 3, 4)
  local function fwd2(x, ...) return sum(x, ...) end
  R_7 = fwd2(1, 2, 3)
  local function ret(...) return ... end
  R_8 = sum(ret(1, 2, 3))
end
