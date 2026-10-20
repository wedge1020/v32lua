function main()
  local obj = {n = 0}
  function obj.inc(self, by) self.n = self.n + (by or 1) return self end
  obj:inc()
  R_1 = obj.n            -- 1
  obj:inc(5)
  R_2 = obj.n            -- 6
  local r = obj:inc()
  R_3 = obj.n            -- 7
  R_4 = r == obj
  r:inc(10)
  R_5 = obj.n            -- 17
  obj:inc():inc()
  R_6 = obj.n            -- 19
  local o2 = {n = 0}
  function o2:add(by) self.n = self.n + (by or 1) return self end
  o2:add()
  R_7 = o2.n             -- 1
  o2:add(2):add(3)
  R_8 = o2.n             -- 6
end
