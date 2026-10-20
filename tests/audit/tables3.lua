function main()
  local t = {}
  for i = 100, 160 do t[i] = i end
  local s = 0
  for i = 100, 160 do s = s + (t[i] or 0) end
  R_hint = s
  local u = {}
  for i = 1, 30 do u["k" .. i] = i end
  s = 0
  for i = 1, 30 do s = s + (u["k" .. i] or 0) end
  R_hstr = s
  local w = {}
  w[0] = 1 w[-1] = 2 w[-2] = 3 w[0.5] = 4 w[1.5] = 5
  R_w = w[0] + w[-1] + w[-2] + w[0.5] + w[1.5]
  local d = {}
  for i = 1, 20 do d["a" .. i] = i end
  for i = 1, 20, 2 do d["a" .. i] = nil end
  s = 0
  local n = 0
  for k, v in pairs(d) do s = s + v n = n + 1 end
  R_dsum = s
  R_dn = n
  local e = {}
  for i = 1, 40 do e[i] = i end
  for i = 1, 40, 3 do e[i] = nil end
  s = 0 n = 0
  for k, v in pairs(e) do s = s + v n = n + 1 end
  R_esum = s R_en = n
end
