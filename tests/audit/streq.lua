function main()
  local a, b, c = "ant", "an".."t", "bee"
  local t = {name="ant"}
  R_1 = (a == "ant")
  R_2 = (b == "ant")
  R_3 = ("ant" == b)
  R_4 = (c == "ant")
  R_5 = (t.name ~= "ant")
  R_6 = (t.name == "bee")
  R_7 = (5 == "5")
  R_8 = (nil == "ant")
  R_9 = (t == "ant")
  R_10 = (type(t) == "table")
  R_11 = (tostring(12) == "12")
  local n = 0
  for i = 1, 3 do if ({"x","ant","y"})[i] == "ant" then n = n + 1 end end
  R_12 = n
  if b ~= "ant" then R_13 = 1 else R_13 = 2 end
  if a == "anteater" then R_14 = 1 else R_14 = 2 end
  R_15 = (false == "false")
  R_16 = ("" == ("x"):sub(2))
  R_17 = (("abc"):upper() == "ABC")
end
