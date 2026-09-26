-- core audit 1: arithmetic, comparison, logic, strings
function id(x) return x end
function two() return 2 end

function main()
  -- arithmetic & precedence
  R_a1 = 1 + 2 * 3 - 4 / 2
  R_a2 = (1 + 2) * 3
  R_a3 = 2 ^ 3 ^ 2            -- right assoc: 512
  R_a4 = -2 ^ 2               -- -4
  R_a5 = 7 % 3
  R_a6 = -7 % 3               -- Lua: 2
  R_a7 = 7 % -3               -- Lua: -2
  R_a8 = 7.5 % 2              -- 1.5
  R_a9 = 7 // 2               -- 3
  R_a10 = -7 // 2             -- -4
  R_a11 = 7 / 2
  R_a12 = 10 - 2 - 3          -- left assoc 5
  R_a13 = 2 * id(3) + two() * 4
  R_a14 = id(1) + id(2) + id(3) + id(4)
  R_a15 = (id(10) - id(3)) * (id(2) + id(1))
  R_a16 = -id(5)
  R_a17 = 1e3 + .5
  R_a18 = 0x10 + 0xff
  R_a19 = 100000 * 100000     -- 1e10 in float

  -- comparisons
  R_c1 = 1 < 2
  R_c2 = 2 <= 2
  R_c3 = 3 > 4
  R_c4 = "a" < "b"
  R_c5 = "abc" < "abd"
  R_c6 = "Z" < "a"
  R_c7 = "ab" < "abc"
  R_c8 = 1 == 1.0
  R_c9 = "1" == 1
  R_c10 = nil == false
  R_c11 = -0.0 == 0
  R_c12 = 1 ~= 2
  R_c13 = id(3) >= two()
  R_c14 = {} == {}
  local t = {}
  R_c15 = t == t

  -- logic returns values
  R_l1 = nil or 5
  R_l2 = false or nil
  R_l3 = 3 and 4
  R_l4 = nil and 4
  R_l5 = false and nil
  R_l6 = not nil
  R_l7 = not 0
  R_l8 = 1 and nil or "x"
  R_l9 = id(nil) or id("d")
  R_l10 = (id(2) > 1) and "yes" or "no"
  local called = 0
  local function side() called = called + 1 return true end
  local _ = true or side()
  local _ = false and side()
  R_l11 = called              -- 0: short-circuit

  -- strings
  R_s1 = "a" .. "b" .. "c"
  R_s2 = "n=" .. 5
  R_s3 = 1 .. ""
  R_s4 = "x" .. id("y") .. two()
  R_s5 = #"hello"
  R_s6 = string.sub("hello", 2, 4)
  R_s7 = string.sub("hello", -3)
  R_s8 = string.upper("aBc")
  R_s9 = string.lower("AbC")
  R_s10 = string.rep("ab", 3)
  R_s11 = string.byte("A")
  R_s12 = string.char(72, 105)
  R_s13 = string.len("four")
  R_s14 = tostring(12)
  R_s15 = tonumber("42") + 1
  R_s16 = tonumber("3.5")
  R_s17 = tonumber("zz")
  R_s20 = string.format("%d-%s", 7, "x")
  R_s21 = string.find("hello world", "wor")
  R_s22 = "10" + 5
  R_s23 = tostring(nil) .. tostring(true)
  R_s24 = #("a" .. "bc")
  local s = "hello"
  R_s19 = s:sub(1, 1) .. s:len()
  R_s18 = ("abc"):upper()
end
