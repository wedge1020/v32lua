-- Locals that are always numbers skip the numeric-string test; everything
-- else must still be coerced / guarded.
local function f(n, s)
  local a = 0
  for i = 1, n do a = a + i % 3 end        -- number locals
  local b = s                              -- parameter value: not a number local
  b = b + 1                                -- "41" + 1
  local c = 10
  c = "7"                                  -- c is ruled out by this assignment
  c = c * 2
  local d = 5
  local function bump() d = "8" end        -- assigned a string in a closure
  bump()
  d = d + 1
  local z = 0
  local e = 9 % z                          -- guard kept: 0
  local g = 0
  for k = 3, 1, -1 do g = g + 12 / k end   -- counts down: guard kept, 22
  for k = -1, 1 do g = g + 6 % k end       -- passes through 0: guard kept
  local h = 0
  for j = 2, 6, 2 do h = h + 24 // j + 24 % j + 24 / j end
  local m = 0
  local q = "2"
  for i = 1, 3 do m = m + i * q end        -- q holds a string: 12
  return a, b, c, d, e, g, h, m
end
local function sh(x)
  local t = 1
  do local t = x  t = t + 1  R_s = t end   -- shadowing: `t` here holds a parameter value
  return t + 1
end
function main()
  R_a, R_b, R_c, R_d, R_e, R_g, R_h, R_m = f(10, "41")
  R_t = sh("5")
end
