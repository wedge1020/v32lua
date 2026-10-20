--#api pico8
r_n=0
function _init() end
function _update() end
function _draw()
 cls()
 line(5,5)             -- startup: from (0,0) to (5,5), pen 6
 line(10,10,20,10,8)   -- full form
 line(20,30)           -- (20,10)->(20,30), pen stays 8
 line(40,30,12)        -- (20,30)->(40,30), color 12
 line()
 line(60,60,9)         -- draws nothing: sets the point, pen 9
 line(70,60)           -- (60,60)->(70,60), pen 9
 local f=_ENV["line"]
 f(70,80)              -- through a function value: (70,60)->(70,80)
 line()                -- so every frame starts the same
 line(0,0)
end
