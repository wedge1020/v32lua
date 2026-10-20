-- conditions compiled as jumps; specialized equality
function f5() return 5 end
function fnil() return nil end
function main()
  local t, u = {}, {}
  local s1 = "ab"
  local s2 = "a" .. "b"
  local n0, nz = 0, -0
  local x, y = 3, 7
  local c = 0
  if x < y and y < 10 then c = c + 1 end
  if x > y or y == 7 then c = c + 10 end
  if not (x > y) then c = c + 100 end
  if nil or false then c = c + 1000 end
  if 0 then c = c + 10000 end
  if "" then c = c + 100000 end
  R_c1 = c
  R_eq = { t == t, t == u, t ~= u, s1 == s2, s1 ~= s2, s1 == "ab", "ab" == s2,
           n0 == nz, x == 3, 3 == x, x == 3.5, s1 == 3, 3 == s1, fnil() == nil,
           nil == fnil(), t == nil, nil ~= t, true == true, false == nil,
           x ~= 3, f5() == 5, 5 == f5() }
  local k = 0
  for i = 1, #R_eq do if R_eq[i] then k = k + 2^(i-1) end end
  R_eqbits = k
  R_rel = { x < y, x <= 3, x >= 3, x > 3, "a" < "b", "b" <= "a", "abc" >= "abc",
            -1 < 0, 1.5 > 1.25, y >= f5(), f5() > y }
  k = 0
  for i = 1, #R_rel do if R_rel[i] then k = k + 2^(i-1) end end
  R_relbits = k
  -- values of and/or/not
  R_v1 = nil and 1
  R_v2 = false or "x"
  R_v3 = 0 and "zero"
  R_v4 = x < y and "lt" or "ge"
  R_v5 = x > y and "gt" or "le"
  R_v6 = not nil
  R_v7 = not 0
  R_v8 = (x == 3) == true
  R_v9 = not (x < y and y < 5)
  R_v10 = (nil == false)
  -- loops
  local w = 0
  while w < 10 and not (w == 7) do w = w + 1 end
  R_w = w
  local r = 0
  repeat r = r + 1 until r >= 5 or r == 3
  R_r = r
  local m = 0
  for i = 1, 20 do
    if i % 2 == 0 and (i % 3 == 0 or i == 10) then m = m + i end
    if not (i < 15) and i ~= 18 then m = m + 100 end
  end
  R_m = m
  -- nested ands like celeste's collide
  local objs = { {type=t, x=1}, {type=u, x=5}, {type=t, x=9} }
  local hits = 0
  for i = 1, #objs do
    local o = objs[i]
    if o ~= nil and o.type == t and o.x > 2 and o.x < 20 then hits = hits + 1 end
  end
  R_hits = hits
  R_small = 0.0000001 * 10000000
  R_sqrt = 0.70710678118 * 0.70710678118
end
