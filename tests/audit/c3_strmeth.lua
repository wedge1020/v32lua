function main()
  local s = "hello"
  R_1 = s:sub(1, 1) .. s:len()
  R_2 = ("abc"):upper()
  R_3 = s:sub(2)
  R_4 = s:byte()
  R_5 = s:rep(2)
  R_6 = ("x" .. "Y"):lower()
  R_7 = s:find("ll")
  R_8 = s:reverse()
  R_9 = s:sub(-2) .. ("QQ"):len()
  local t = {sub = function(self, a) return "tbl" .. a end}
  R_10 = t:sub(5)
  R_11 = #s:upper()
end
