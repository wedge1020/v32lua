function id(x) return x end
function main()
  local s = "abcdef"
  R_1 = string.sub(s, 2, #s)
  R_2 = string.sub(s, id(2), id(4))
  R_3 = string.rep(s, id(2))
  R_4 = string.find(s, id("cd"))
  R_5 = string.byte(s, id(3))
  R_6 = string.sub(id(s), id(3))
  R_7 = string.upper(id("q") .. id("r"))
  R_8 = string.format("%s=%d", id("k"), id(9))
  R_9 = string.rep(id("ab"), #s - 4)
end
