-- core audit 4: functions, closures, varargs, multi-return, control flow
function add3(a, b, c) return a + (b or 10) + (c or 100) end
function mr() return 1, 2, 3 end
function mr2() return "x", "y" end
function fact(n) if n <= 1 then return 1 end return n * fact(n - 1) end
function fib(n) if n < 2 then return n end return fib(n - 1) + fib(n - 2) end
function va(...) local t = {...} return #t end
function vsum(...)
  local s = 0
  for i, v in ipairs({...}) do s = s + v end
  return s
end
function first(...) local a = ... return a end
function counter()
  local c = 0
  return function() c = c + 1 return c end
end
function nested() return mr() end

function main()
  -- missing args are nil
  R_f1 = add3(1)
  R_f2 = add3(1, 2)
  R_f3 = add3(1, 2, 3)
  R_f4 = fact(6)
  R_f5 = fib(15)

  -- multiple returns
  local a, b, c = mr()
  R_m1 = a + b + c
  local x, y = mr(), 10          -- truncated to 1
  R_m2 = x + y
  local p, q, r, s = mr()
  R_m3 = s == nil
  local t = {mr()}
  R_m4 = #t
  local t2 = {mr(), mr()}
  R_m5 = #t2                     -- 4
  R_m6 = add3(mr())              -- 1+2+3
  R_m7 = (mr())                  -- parens truncate: 1
  local u, v = nested()
  R_m8 = u + v
  local s1, s2 = mr2()
  R_m9 = s1 .. s2

  -- varargs
  R_v1 = va()
  R_v2 = va(1, 2, 3)
  R_v3 = vsum(1, 2, 3, 4)
  R_v4 = first(9, 8)

  -- closures
  local c1 = counter()
  local c2 = counter()
  c1() c1()
  R_cl1 = c1()                   -- 3
  R_cl2 = c2()                   -- 1
  local fns = {}
  for i = 1, 3 do fns[i] = function() return i * 10 end end
  R_cl3 = fns[1]() + fns[2]() + fns[3]()   -- 60 (per-iteration capture)
  local shared = 0
  local function inc() shared = shared + 1 end
  inc() inc()
  R_cl4 = shared                 -- 2 (upvalue written through)
  local function mk(n) return function(m) return n + m end end
  R_cl5 = mk(5)(6)

  -- control flow
  local sum = 0
  for i = 10, 1, -2 do sum = sum + i end
  R_cf1 = sum                    -- 30
  sum = 0
  for i = 0, 1, 0.25 do sum = sum + i end
  R_cf2 = sum                    -- 2.5
  local n = 0
  while true do n = n + 1 if n >= 7 then break end end
  R_cf3 = n
  n = 0
  repeat n = n + 2 until n > 9
  R_cf4 = n                      -- 10
  local hits = 0
  for i = 1, 3 do for j = 1, 3 do if j == 2 then break end hits = hits + 1 end end
  R_cf5 = hits                   -- 3
  local cnt = 0
  for i = 5, 1 do cnt = cnt + 1 end
  R_cf6 = cnt                    -- 0
  local w = 0
  if w == 1 then w = 10 elseif w == 0 then w = 20 else w = 30 end
  R_cf7 = w

  -- scope / shadowing
  local sh = 1
  do local sh = 2 R_sc1 = sh end
  R_sc2 = sh
  for sh = 5, 5 do R_sc3 = sh end
  R_sc4 = sh

  -- recursion through a local function
  local function lf(k) if k == 0 then return 0 end return 1 + lf(k - 1) end
  R_r1 = lf(20)

  -- negative numbers & comparisons
  R_n1 = -3 < -2
  R_n2 = -1.5 <= -1.5
  R_n3 = math.max(-5, -2)
  R_n4 = math.min(3, -7)
  R_n5 = math.floor(-2.5)
  R_n6 = math.abs(-4)
end
