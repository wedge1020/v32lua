--#api pico8
-- PICO-8 layer unit test 1: math / tables / map / input
function f5() return 5 end

r_flr = 0  r_ceil = 0  r_abs = 0  r_min = 0 r_max = 0
r_sgn0 = 0 r_sgnn = 0
r_mid1 = 0 r_mid2 = 0 r_midcall = 0
r_sin = 0 r_cos = 0 r_tan = 0
r_rnd_ok = 0
r_add_ret = 0 r_add_len = 0 r_add_ins = 0
r_count = 0 r_count_mixed = 0
r_del_ret = 0 r_del_len = 0 r_del_first = 0
r_fe_sum = 0 r_fe_calls = 0
r_fe_del_calls = 0 r_fe_del_nil = 0
r_mget0 = 0 r_mset_ret = 0 r_mget_after = 0 r_mget_b3 = 0 r_mget_oob = 0
r_heap_ok = 0
r_btn = 0 r_btnp = 0

function _init()
  r_flr = flr(3.7)
  r_ceil = ceil(3.2)
  r_abs = abs(-4)
  r_min = min(3, 9)
  r_max = max(3, 9)
  r_sgn0 = sgn(0)
  r_sgnn = sgn(-3)
  r_mid1 = mid(1, 5, 3)
  r_mid2 = mid(7, 2, 4)
  r_midcall = mid(1, f5(), 9)     -- b contains a CALL
  r_sin = sin(0.25)               -- pico8: -1
  r_cos = cos(0.5)                -- -1
  r_tan = tan(0.125)              -- pico8: -1
  local ok = 1
  for i = 1, 50 do
    local v = rnd(10)
    if v < 0 or v >= 10 then ok = 0 end
  end
  r_rnd_ok = ok

  local t = {}
  r_add_ret = add(t, 10)
  add(t, 20)
  add(t, 30)
  add(t, 15, 2)                   -- insert at 2 -> 10 15 20 30
  r_add_len = #t
  r_add_ins = t[2] * 100 + t[3]   -- 1520

  local c = {1, 2, 3}
  r_count = count(c)
  local m = {1, 2, x = 5, y = 6}
  r_count_mixed = count(m)        -- pico8: 2

  local d = {"a", "b", "c", "b"}
  r_del_ret = del(d, "b")
  r_del_len = #d                  -- 3
  r_del_first = d[2]              -- "c"

  local s = 0
  local n = 0
  foreach({1, 2, 3, 4}, function(v) s = s + v n = n + 1 end)
  r_fe_sum = s
  r_fe_calls = n

  -- deleting the current element during foreach (celeste pattern)
  local objs = {}
  for i = 1, 5 do add(objs, {id = i}) end
  local calls = 0
  local nils = 0
  foreach(objs, function(o)
    calls = calls + 1
    if o == nil then nils = nils + 1 else
      if o.id == 2 or o.id == 3 then del(objs, o) end
    end
  end)
  r_fe_del_calls = calls          -- pico8: 5 (every object visited once)
  r_fe_del_nil = nils             -- pico8: 0

  r_mget0 = mget(3, 4)            -- empty map -> 0
  r_mset_ret = mset(3, 4, 77)
  r_mget_after = mget(3, 4)       -- 77
  mset(7, 0, 200)
  r_mget_b3 = mget(7, 0)          -- byte 3 of a word, >=128
  r_mget_oob = mget(500, 0)       -- out of range -> 0 in pico8

  -- heap sanity after map writes: allocate and read back a table
  local h = {}
  for i = 1, 20 do h[i] = i end
  r_heap_ok = h[20]

  r_btn = btn(1)                  -- right; pad script holds Right
  r_btnp = btnp(4)                -- O button (A) pressed this frame
end

function _update()
end
