-- Multiple assignment: the table and key expressions of every target are
-- evaluated before any target is assigned (Lua 5.4 reference behaviour).
local function two() return 7, 8 end
local t3 = { three = function() return 1, 2, 3 end }

function main()
  -- the Just One Boss line: `self,vy` is a typo for `self.vy`
  local self = { vx = 5, movement = 9 }
  local keep = self
  self.vx, self, vy, self.movement = 0, 0
  R_a1 = keep.vx          -- 0
  R_a2 = keep.movement    -- nil
  R_a3 = self             -- 0
  R_a4 = vy               -- nil

  -- key variable reassigned in the same statement
  local t, i = {}, 1
  t[i], i = 10, i + 1
  R_b1 = t[1]             -- 10
  R_b2 = t[2]             -- nil
  R_b3 = i                -- 2
  i, t[i] = i + 1, 20
  R_b4 = t[2]             -- 20
  R_b5 = i                -- 3

  -- a target's table replaced in the same statement
  local a = { b = { c = 1 } }
  local old = a.b
  a.b.c, a.b = 2, { c = 3 }
  R_c1 = old.c            -- 2
  R_c2 = a.b.c            -- 3

  -- swaps through fields and indices
  local p = { x = 1, y = 2 }
  p.x, p.y = p.y, p.x
  R_d1 = p.x              -- 2
  R_d2 = p.y              -- 1
  local q = { 4, 5, 6 }
  q[1], q[3] = q[3], q[1]
  R_d3 = q[1] * 10 + q[3] -- 64

  -- multi-return sources (static, method, padded)
  local o = { n = 0 }
  local oo = o
  o.x, o, o2 = two()
  R_e1 = oo.x             -- 7
  R_e2 = o                -- 8
  R_e3 = o2               -- nil
  local m = {}
  local mm = m
  m.a, m, m3 = t3.three()
  R_f1 = mm.a             -- 1
  R_f2 = m                -- 2
  R_f3 = m3               -- 3
  local w = {}
  local ww = w
  w.a, w.b, w, w4 = 1, two()
  R_g1 = ww.a             -- 1
  R_g2 = ww.b             -- 7
  R_g3 = w                -- 8
  R_g4 = w4               -- nil

  -- nested: a function literal with its own multiple assignment
  local n = {}
  local nn = n
  n.f, n = function(u) u.p, u.q = 1, 2 return u.p + u.q end, 5
  R_h1 = nn.f({})         -- 3
  R_h2 = n                -- 5
end
