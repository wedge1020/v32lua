-- math.min/math.max with one, three and more arguments, including calls among
-- the arguments (registers don't survive a CALL). Plain Lua: diffed against 5.4.
local function id(x) return x end
function main()
  R_a = math.min(3, 1, 2)                       -- 1
  R_b = math.max(3, 1, 2)                       -- 3
  R_c = math.min(5)                             -- 5
  R_d = math.max(-7)                            -- -7
  R_e = math.min(4, 9, -2, 6, 0.5)              -- -2
  R_f = math.max(4, 9, -2, 6, 0.5)              -- 9
  R_g = math.min(1, 50 / 200, (300 - 50) / 300) -- 0.25
  R_h = math.max(id(2), 8, id(5))               -- 8
  R_i = math.min(9, id(4), id(6))               -- 4
  R_j = math.max(0, id(3), id(11), 2)           -- 11
  R_k = math.min(id(7), id(3), id(5))           -- 3
  R_l = math.max(math.min(8, 2, 6), math.min(1, 5, 3))   -- 2
end
