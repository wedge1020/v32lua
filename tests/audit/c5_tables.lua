-- core audit 5: tables
function main()
  local t = {10, 20, 30, x = 1, ["y z"] = 2, [5] = 50}
  R_t1 = #t                      -- 3
  R_t2 = t.x + t["y z"] + t[5]
  R_t3 = t[4] == nil
  t[#t + 1] = 40
  R_t4 = #t                      -- 4
  table.insert(t, 45)
  R_t5 = t[5]                    -- 45 (overwrote the [5]=50)
  table.insert(t, 1, 5)
  R_t6 = t[1] * 1000 + t[2]      -- 5010
  R_t7 = table.remove(t, 1)
  R_t8 = table.remove(t)         -- last
  R_t9 = #t
  R_t10 = table.concat({1, 2, 3}, ",")
  R_t11 = table.concat({"a", "b"})

  -- sort
  local s = {5, 2, 8, 1, 9, 3}
  table.sort(s)
  R_s1 = s[1] .. s[2] .. s[3] .. s[4] .. s[5] .. s[6]
  table.sort(s, function(a, b) return a > b end)
  R_s2 = s[1] .. s[6]
  local names = {"pear", "apple", "fig"}
  table.sort(names)
  R_s3 = names[1] .. names[2] .. names[3]

  -- pairs / ipairs
  local sum, cnt = 0, 0
  for k, v in pairs({a = 1, b = 2, c = 3}) do sum = sum + v cnt = cnt + 1 end
  R_p1 = sum * 10 + cnt
  local order = ""
  for i, v in ipairs({"p", "q", "r"}) do order = order .. i .. v end
  R_p2 = order
  local stop = 0
  for i, v in ipairs({1, 2, nil, 4}) do stop = i end
  R_p3 = stop                    -- 2
  local nk = 0
  for k in pairs({}) do nk = nk + 1 end
  R_p4 = nk

  -- nested & references
  local m = {{1, 2}, {3, 4}}
  R_n1 = m[2][1] + m[1][2]
  local alias = m[1]
  alias[1] = 99
  R_n2 = m[1][1]
  local grid = {}
  for y = 1, 3 do grid[y] = {} for x = 1, 3 do grid[y][x] = y * 10 + x end end
  R_n3 = grid[3][2]

  -- keys of different types
  local k = {}
  local keyt = {}
  k[keyt] = "tablekey"
  k[1.5] = "float"
  k[-3] = "neg"
  k[true] = "bool"
  k["1"] = "strone"
  k[1] = "numone"
  R_k1 = k[keyt]
  R_k2 = k[1.5] .. k[-3]
  R_k3 = k[true]
  R_k4 = k["1"] .. k[1]

  -- deletion and length
  local d = {1, 2, 3, 4, 5}
  d[5] = nil
  R_d1 = #d                      -- 4
  d.x = 7
  d.x = nil
  local dc = 0
  for _ in pairs(d) do dc = dc + 1 end
  R_d2 = dc                      -- 4

  -- growth
  local big = {}
  for i = 1, 300 do big[i] = i * 2 end
  R_b1 = #big
  R_b2 = big[300] + big[1]
  local hb = {}
  for i = 1, 200 do hb["k" .. i] = i end
  R_b3 = hb.k150 + hb.k1
  local hs = 0
  for _, v in pairs(hb) do hs = hs + v end
  R_b4 = hs                      -- 20100

  -- methods & self
  local obj = {v = 3}
  function obj:get() return self.v end
  function obj.add(self, n) self.v = self.v + n end
  obj:add(4)
  R_o1 = obj:get()
  local cls = {}
  cls.__index = cls
  R_o2 = type(cls)
  R_o3 = type(nil) .. type(1) .. type("s") .. type({}) .. type(print)
end
