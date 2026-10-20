-- t[k] inline array reads and their fallbacks
function main()
  local t = {10, 20, 30, 40}
  t[100] = "far"
  t[2.5] = "half"
  t[-1] = "neg"
  t[0] = "zero"
  t.name = "n"
  local one, two, big, half, neg, zero, mz, s, nk = 1, 2, 100, 2.5, -1, 0, -0.0, "name", nil
  local huge = 1e20
  R_1 = t[one]
  R_2 = t[two]
  R_3 = t[big]
  R_4 = t[half]
  R_5 = t[neg]
  R_6 = t[zero]
  R_7 = t[mz]
  R_8 = t[s]
  R_9 = t[nk]
  R_10 = t[huge]
  R_11 = t[4]
  R_12 = t[5]
  R_13 = t[1] + t[3]
  local sum = 0
  for i = 1, #t do sum = sum + t[i] end
  R_sum = sum
  local grid = {}
  for y = 1, 5 do grid[y] = {} for x = 1, 5 do grid[y][x] = x * y end end
  local g = 0
  for y = 1, 5 do local row = grid[y] for x = 1, 5 do g = g + row[x] end end
  R_grid = g
  local str = "abc"
  R_strk = t[str]
  local notab = 5
  R_len = #t
end
