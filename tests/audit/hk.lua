function main()
  local t = {}
  t["ab"] = 1
  R_1 = t["a" .. "b"]        -- literal store, computed lookup
  local k = "c" .. "d"
  t[k] = 2
  R_2 = t["cd"]              -- computed store, literal lookup
  R_3 = t["c" .. "d"]        -- computed store, other computed lookup
  R_4 = t[k]                 -- same pointer
  t.x = 3
  R_5 = t["x"]
  local u = {}
  u["q" .. 1] = 5
  u["q" .. 1] = 6            -- overwrite via equal string
  local c = 0
  for _ in pairs(u) do c = c + 1 end
  R_6 = c                    -- 1
end
