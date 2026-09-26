function main()
  local seed = 1234
  local function rnd(n)
    seed = (seed * 97 + 13) % 4096
    return seed % n
  end
  local lits = {"alpha", "beta", "x"}
  local function key_for(r)
    local c = r % 3
    if c == 0 then return 1 + rnd(40)
    elseif c == 1 then return lits[1 + rnd(3)]
    else return "k" .. rnd(30) end
  end
  local s = 0
  for i = 1, 50 do s = s + rnd(1000) end
  R_s = s
  R_seed = seed
  local ks = ""
  for i = 1, 10 do ks = ks .. tostring(key_for(rnd(3))) .. "," end
  R_ks = ks
end
