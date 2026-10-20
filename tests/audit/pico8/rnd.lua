--#api pico8
r1=0 r2=0 r3=0 r4=0 m1=0 m2=0 m3=0 m4=0 bad=0
function f2() return 2 end
function _init()
  r1 = rnd(10) r2 = rnd(10) r3 = rnd() r4 = rnd(1)
  m1 = math.random() m2 = math.random()
  for i=1,200 do
    local a = math.random(6)
    if a < 1 or a > 6 or a ~= flr(a) then bad = bad + 1 end
    local b = math.random(f2(), 4)
    if b < 2 or b > 4 then bad = bad + 1 end
    local c = rnd(3)
    if c < 0 or c >= 3 then bad = bad + 1 end
  end
  m3 = math.random(3, 3)
end
function _update() end
