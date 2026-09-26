-- core audit 6: misc corners
function main()
  local s = 0
  for k, v in pairs({10, 20, 30}) do s = s + k * v end
  R_1 = s                          -- 140
  local mixed = {5, 6, a = 7}
  s = 0
  for k, v in pairs(mixed) do s = s + v end
  R_2 = s                          -- 18
  R_3 = true
  local k1, v1 = "x", 9
  R_4 = k1 .. v1

  R_5 = tostring(10 / 2)           -- lua 5.4: "5.0"
  R_6 = tostring(0.5)
  R_7 = tostring(-3)
  R_8 = "v" .. 2.25
  R_9 = tostring(1 / 3)
  R_10 = tostring(123456)
  R_11 = math.floor(7.9) .. ""

  local t = {}
  for i = 1, 10 do t[i] = i end
  for i = 1, 5 do table.remove(t, 1) end
  R_12 = #t .. ":" .. t[1]         -- 5:6

  local acc = ""
  for i = 1, 3 do
    for j = 1, 3 do
      if (i + j) % 2 == 0 then goto continue end
      acc = acc .. i .. j
      ::continue::
    end
  end
  R_13 = acc

  local function outer()
    local x = 1
    local function mid()
      local function inner() x = x + 10 return x end
      return inner()
    end
    mid()
    return x
  end
  R_14 = outer()                   -- 11

  local obj = {n = 0}
  function obj.inc(self, by) self.n = self.n + (by or 1) return self end
  obj:inc():inc(5):inc()
  R_15 = obj.n                     -- 7

  local long = ""
  for i = 1, 50 do long = long .. "x" end
  R_16 = #long

  R_17 = string.format("%d items", 3)
  R_18 = #{n = 1}
  R_19 = 2^0.5 > 1.41 and 2^0.5 < 1.42
  R_20 = math.sqrt(16) + math.abs(-2) + math.ceil(1.1)
  R_21 = 5 // 0.5
  R_22 = 3 % math.huge
  local a, b = 1, 2
  a, b = b, a
  R_23 = a * 10 + b                -- 21
  local q = {1, 2, 3}
  q[1], q[3] = q[3], q[1]
  R_24 = q[1] * 100 + q[3]         -- 301
end
