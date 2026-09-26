--#api pico8
x=0 d1=0 d2=0 d3=0 n=0 y=0 z1=0
function _init()
  local d = {"a", "b", "c", "b"}
  x = del(d, "b")
  d1 = d[1] d2 = d[2] d3 = d[3] n = #d
  local t = {10, 20, 30}
  y = del(t, 20)
  z1 = t[2]
end
function _update() end
