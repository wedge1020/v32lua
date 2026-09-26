function main()
  local t = {10, 20, 30, x = 1, ["y z"] = 2, [5] = 50}
  R_a = #t
  t[#t + 1] = 40
  R_b = #t
  table.insert(t, 45)
  R_c = #t
  R_c5 = t[5]
  table.insert(t, 1, 5)
  R_d = #t
  R_d6 = t[6]
  R_d7 = t[7]
  R_e = table.remove(t, 1)
  R_f = #t
  R_g = table.remove(t)
  R_h = #t
end
