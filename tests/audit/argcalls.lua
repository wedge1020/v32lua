-- A register doesn't survive a CALL: two-argument math intrinsics whose
-- second argument is a call, and table constructors built as call arguments.
local function id(x) return x end
local function pick(c, a, b) return c and a or b end
local function second(a, t) return t[2] end
local function third(a, b, t) return t[1] .. t[2] end
function main()
  local sp = 0
  R_max1 = math.max(sp, pick(false, 1, 0))      -- 0
  R_max2 = math.max(5, id(3))                   -- 5
  R_min1 = math.min(2, id(7))                   -- 2
  R_min2 = math.min(id(9), id(4))               -- 4
  R_pow  = math.pow(2, id(5))                   -- 32
  R_fmod = math.fmod(17, id(5))                 -- 2
  -- constructors as arguments, under register pressure
  local o = { h = { n = 1 }, g = { n = 2 } }
  R_t1 = second(o.h, { o.h, "name" })           -- name
  R_t2 = third(o.h.n + o.g.n, id(o.g), { "a", "b" })   -- ab
  R_t3 = second(id(1) + id(2) * id(3), { o.g, "x" .. "y" })   -- xy
  local q = { { o.h, "left" }, { o.g, "right" } }
  R_t4 = q[1][2] .. q[2][2]                     -- leftright
end
