--#api pico8
function _init()
  for y=0,19 do for x=0,19 do mset(x,y,1+(x+y)%3) end end
  camera(4.5,-3)
  map(0,0,-5,2,20,20)
end
function _update() end
