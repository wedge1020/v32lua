-- Multi-value lists: `...`, unpack and multi-return calls spread as the
-- last argument / return value / table field / assignment value
-- (node/multivalue.c). Compared against Lua 5.4 by difftest.py.
local function cnt(...) return #{...} end
local function pack(...) return {...} end
local function join(t) local s = "" for i = 1, #t do s = s .. tostring(t[i]) .. "," end return s end
local function myunpack(list, from, to)
  from, to = from or 1, to or #list
  if from <= to then
    return list[from], myunpack(list, from + 1, to)
  end
end
local function ret(...) return ... end
local function pre(...) return 0, ... end
local function three() return 7, 8, 9 end
local obj = {k = 100}
function obj:m(a, b, ...) return self.k + a + b + cnt(...) end
function obj:fw(...) return self:m(...) end
function main()
  R_1 = join(pack(myunpack({1, 2, 3, 4, 5})))
  R_2 = cnt(myunpack({1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}))
  R_3 = join({ret(4, 5, 6)})
  R_4 = join({pre(1, 2)})
  R_5 = join({10, three()})
  R_6 = join({three(), 10})
  local a, b, c, d = pre(1, 2, 3)
  R_7 = a + b * 10 + c * 100 + d * 1000
  local x, y = ret()
  R_8 = (x == nil) and (y == nil)
  R_9 = obj:fw(1, 2, 3, 4, 5)
  R_10 = obj:m(myunpack({1, 2, 3}))
  local big = {}
  for i = 1, 20 do big[i] = i end
  R_11 = cnt(table.unpack(big))
  R_12 = join(pack(ret(table.unpack(big, 3, 7))))
  local p, q = 1, three()
  R_13 = p * 10 + q
  local e, f, g = 5, three()
  R_14 = e * 100 + f * 10 + g
  R_15 = cnt(ret(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25))
  R_16 = cnt(ret(1, nil))
  local t = {three(), three()}
  R_17 = join(t)
  R_18 = cnt(pre())
  R_19 = cnt(myunpack({}))
  R_20 = join({pre(three())})
end
