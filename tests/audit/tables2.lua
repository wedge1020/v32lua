function main()
  local seed = 1234
  local function rnd(n)
    seed = (seed * 97 + 13) % 4096
    return seed % n
  end
  local lits = {"alpha", "beta", "x", "y", "spd", "rem", "hitbox", "type"}
  local t = {}
  local keys = {}
  local nkeys = 0
  local function key_for(r)
    local c = r % 6
    if c == 0 then return 1 + rnd(40)
    elseif c == 1 then return lits[1 + rnd(8)]
    elseif c == 2 then return "k" .. rnd(30)
    elseif c == 3 then return rnd(5) - 2
    elseif c == 4 then return (rnd(8) + 1) / 2
    else return 100 + rnd(60) end
  end
  for i = 1, 600 do
    local k = key_for(rnd(6))
    if nkeys < 400 then nkeys = nkeys + 1 keys[nkeys] = k end
    if rnd(4) == 0 then t[k] = nil else t[k] = i end
  end
  -- every key read back
  local s = 0
  for i = 1, nkeys do
    local v = t[keys[i]]
    if v ~= nil then s = s + v * (i % 7 + 1) end
  end
  R_sum = s
  -- pairs: count and value sum
  local n, vs = 0, 0
  for k, v in pairs(t) do n = n + 1 vs = vs + v end
  R_pairs_n = n
  R_pairs_sum = vs
  -- runtime-built keys find literal-stored entries
  t.alpha = 7
  R_rt = t["al" .. "pha"]
  t["be" .. "ta"] = 9
  R_lit = t.beta
  -- array behaviour
  local a = {}
  for i = 1, 100 do a[#a + 1] = i * 2 end
  R_alen = #a
  R_a50 = a[50]
  for i = 1, 30 do table.remove(a, 1) end
  R_alen2 = #a
  R_afirst = a[1]
  R_alast = a[#a]
  local b = {}
  for i = 20, 1, -1 do b[i] = i end
  R_blen = #b
  local bs = 0
  for i, v in ipairs(b) do bs = bs + v end
  R_bsum = bs
  local big = {}
  for i = 1, 300 do big["f" .. i] = i end
  local bsum = 0
  for i = 1, 300 do bsum = bsum + big["f" .. i] end
  R_big = bsum
  local cnt = 0
  for k, v in pairs(big) do cnt = cnt + 1 end
  R_bigcnt = cnt
end
