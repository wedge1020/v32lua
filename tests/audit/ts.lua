function main()
  local a = tostring(1)
  local b = tostring(2)
  R_1 = a .. b                 -- "12"
  local c = 3 .. ""
  local d = 4 .. ""
  R_2 = c .. d                 -- "34"
  local t = {}
  for i = 1, 3 do t[i] = tostring(i * 10) end
  R_3 = t[1] .. t[2] .. t[3]   -- "102030"
  local e = tostring(7)
  local f = tostring(8.5)
  R_4 = e .. "," .. f
  R_5 = math.floor(7.9) .. ""
end
