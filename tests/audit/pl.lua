function main()
  local hb = {}
  for i = 1, 20 do hb["k" .. i] = i end
  local hs = 0
  local n = 0
  for _, v in pairs(hb) do hs = hs + v n = n + 1 if n > 100 then break end end
  R_hs = hs
  R_n = n
end
