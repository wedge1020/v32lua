--#api pico8
objs = {1,2,3}
function f(x)
  for o in all(objs) do
    if o == x then return true end
  end
  return false
end
function g()
  local obj = {x=5}
  function obj.left() return obj.x + 1 end
  function obj.check(v)
    for o in all(objs) do
      if o == v then return o end
    end
  end
  return obj
end
function _init()
  r_a = f(2)
  r_b = f(9)
  local o = g()
  r_c = o.left()
  r_d = o.check(3)
  r_e = o.check(7)
  r_after = 42
end
function _update() end
