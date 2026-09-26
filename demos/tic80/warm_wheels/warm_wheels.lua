-- title:  Warm Wheels
-- author: msx80
-- desc:   An arcade racing game!
-- script: lua

-- Thanks to @Fubuki for the awesome
-- car sprite and engine sound!
-- Thanks to the folks on the discord 
-- server for help and suggestions!

-- Want to make a game like this?
-- Read my tutorial on Making a
-- Racing game here:
-- https://github.com/nesbox/TIC-80/wiki/Fun-With-Vectors

-- https://twitter.com/msx80

DEBUG = false

TURN_RADIUS = 0.05    -- how much the car turn when pressing left or right
ACCEL_VALUE = 0.02    -- acceleration when pressing z
FRICTION = 0.98       -- how much the car decelerate on asphalt
DIRT_FRICTION = 0.95  -- deceleration on dirt
BRAKE_FRICTION = 0.94 -- deceleration when braking
ALIGNEMENT = 0.02     -- how fast the velocity catch up with direciton

t=0

curLev = nil

function incw(val, max)
 if val==max then return 1 else return val+1 end
end

function decw(val, max)
 if val==1 then return max else return val-1 end
end

-- generic class to display a multi
-- menu with different lines
multichoice={
  init=function(s, menu)
   s.menu=menu
   s.current=1
   s.selected={}
   s.maxWidthLabel=0
   for i=1,#s.menu do
    s.selected[i]=s.menu[i].def or 1
	local lw = s.menu[i].title
	if #lw> s.maxWidthLabel then s.maxWidthLabel = #lw end
   end
   end,
  update=function(s)
   if btnp(0) then s.current = decw(s.current, #s.menu) end
   if btnp(1) then s.current = incw(s.current, #s.menu) end
   if btnp(2) then s.selected[s.current] = decw(s.selected[s.current], (#s.menu[s.current].values)) end
   if btnp(3) then s.selected[s.current] = incw(s.selected[s.current], (#s.menu[s.current].values)) end
   if btnp(4) then 
     -- build return value
	local res = {}
	for i=1,#s.menu do
     res[s.menu[i].field]=s.menu[i].values[s.selected[i]]
    end
    return res
   end
   return nil
  end,
  render=function(s, cx, cy)
   for i,m in pairs(s.menu) do
    local sel = (s.current == i) and "> " or "  "
    print(sel..m.title, cx,i*6 + cy , 15, true)
	print(m.labels[s.selected[i]], cx+(s.maxWidthLabel+2)*6,i*6 + cy , 15, true)
   end
  end
  
}

function roundDec(val, decimal)
  if (decimal) then
    return math.floor( (val * 10^decimal) + 0.5) / (10^decimal)
  else
    return math.floor(val+0.5)
  end
end

-- function that returns a "brain"
-- (the object that decide how to move the car)
-- based on the gamepad buttons
function playerBrain(baseButton)
  return function(o)
    if editIdx==1 then -- if editing, don't move the car
     if btn(baseButton+2) then o.a=angleAdd(o.a,-TURN_RADIUS) end
     if btn(baseButton+3) then o.a=angleAdd(o.a,TURN_RADIUS) end
     if btn(baseButton+4) then
       -- apply an acceleration vector to current velocity
       local x1,y1 = vector(ACCEL_VALUE,o.a)
       o.vx=o.vx+x1
       o.vy=o.vy+y1 
     end
    end
  end
end

-- aiBrain parameters for the CPU
-- drivers, defining acceleration and
-- waypoint offset
cpuLevels={
  {accelCoeff = 0.9, offset = 5},
  {accelCoeff = 0.85, offset = 0},
  {accelCoeff = 0.85, offset = 10},
  {accelCoeff = 0.86, offset = 3},
}


-- function that returns an AI brain,
-- a brain that automatically drives a
-- cpu car
function aiBrain(accelCoeff, offset)
  local nextp=1
  local p = {x=curLev.points[nextp].x,y=curLev.points[nextp].y}

  return function(o)
 if distance(o, p) < 20 then
   nextp = incw(nextp, #curLev.points)
   --if nextp==#curLev.points then nextp = 1 else nextp = nextp + 1 end
   p.x=curLev.points[nextp].x
   p.y=curLev.points[nextp].y
   local offx, offy = vector(offset,curLev.points[nextp].a)
   p.x=p.x+offx
   p.y=p.y+offy
 end
 -- get desired angle, toward waypoint
 local desired = angle2(o.x, o.y, p.x, p.y)
 local sgn = angleDir(o.a, desired)
    o.a = angleAdd(o.a,TURN_RADIUS*sgn)
    if true then -- always accelerating!
       -- apply an acceleration vector to current velocity
       local x1,y1 = vector(ACCEL_VALUE*accelCoeff,o.a)
       o.vx=o.vx+x1
       o.vy=o.vy+y1 
    end
  end
end

-- all entities (cars, tires, etc)
ents={}
-- subset of ents with only the cars
-- this get sorted to calculate cars
-- position and ranking
cars={}


function isInDirt(o)
 local tile = mget(o.x//8, o.y//8)
 if tile>=242 and tile<=245 then return false end -- hack to make start line like asphalt
 local addr=0x4000+(tile)*32 -- get sprite address
 local color = peek4(addr*2+o.x%8+o.y%8*8) -- get sprite pixel
 return color ~= 3
end

-------------------
-- VECTOR FUNCTIONS

pi2 = math.pi*2.0

function vector(length, angle)
 return rotate(0, -length, angle)
end

function rotate(x,y,a)
 return 
  x*math.cos(a)-y*math.sin(a),
  x*math.sin(a)+y*math.cos(a)
end

function angle(x,y)
 local r = math.pi - math.atan2(x,y)
 
 return r
end

function angle2(fromx,fromy, tox, toy)
 return angle(tox-fromx, toy-fromy)
end


function angleDir(from, to)
 local diff = to-from
 -- avoid rounding errors that will prevent settling
 if math.abs(diff) < 0.00001 then return 0 end 
 if diff > math.pi then 
   return -1 
 elseif diff < -math.pi then
   return 1 
 else 
   return diff>0 and 1 or -1
 end
end

function vecLen(x,y)
  return math.sqrt(x^2 + y^2)
end

function angleAdd(a, d)
 a=a+d
 -- ensure angle is in 0..2pi range
 if a<0 then 
   a=a+pi2
 elseif a>=pi2 then 
   a=a-pi2
 end
 return a
end

------------------------------------------

function drawLine(x,y,a, length, color)
  local x1,y1 = vector(length,a)
  line(x,y,x+x1,y+y1, color)
end

function distance(a,b)
  return vecLen(a.x - b.x,a.y - b.y)
end

function adjustColl(a, b)
  if a.fixed and b.fixed then return end
  local dist = distance(a,b)
  local pen = a.r+b.r-dist
  if pen>0 then
    -- collision! find the angle pointing from one center to the other 
    
    local an = angle2(a.x, a.y, b.x, b.y)
    -- first resolve the penetration by pushing apart the entities 
    -- by half the penetration each
 
    local dx,dy = vector(pen, an)

    -- then we add a small impulse to the velocity in the same direction
    -- for some bounciness
    local impact = vecLen(a.vx-b.vx,a.vy-b.vy) -- difference between velocities  
    local dvx,dvy = vector(impact*0.8, an) --0.8 is empirical, 1 was too bouncy
 
    if not a.fixed then
     a.x = a.x-dx
     a.y = a.y-dy
     a.vx = a.vx-dvx
     a.vy = a.vy-dvy
    end
 
    if not b.fixed then
     b.x = b.x+dx
     b.y = b.y+dy
     b.vx = b.vx+dvx
     b.vy = b.vy+dvy
    end
 
  end
end

lvls = {
 {
  points={{x=31, y=18, a=5.8331853071796},{x=72, y=48, a=0.25},{x=116, y=57, a=6.1331853071796},{x=138, y=23, a=5.5331853071796},{x=229, y=37, a=0.3},{x=221, y=92, a=2.35},{x=172, y=79, a=0.45},{x=109, y=103, a=3.0331853071796},{x=57, y=94, a=0.3},{x=16, y=109, a=3.2331853071796},},
  checks={{x=33, y=-3,w=10, h=36},{x=93, y=9,w=10, h=74},{x=146, y=0,w=10, h=37},{x=215, y=62,w=29, h=10},{x=166, y=39,w=12, h=52},{x=96, y=81,w=10, h=56},{x=58, y=58,w=10, h=45},{x=26, y=96,w=6, h=45},{x=-1, y=57,w=50, h=7}},
  ents={{x=39, y=34,spr=497},{x=151, y=37,spr=497},{x=172, y=94,spr=497},{x=215, y=67,spr=497},{x=66, y=104,spr=497},{x=31, y=96,spr=497},{x=214, y=12,spr=496},{x=228, y=14,spr=496},{x=110, y=32,spr=496},{x=106, y=39,spr=496},{x=97, y=45,spr=496},},
  mx=90,my=0
 },
 {
points={{x=32, y=22, a=5.8331853071796},{x=90, y=22, a=6.1831853071796},{x=149, y=17, a=0},{x=199, y=21, a=0.6},{x=211, y=64, a=1.6},{x=181, y=99, a=3.0},{x=145, y=93, a=0.55},{x=104, y=77, a=1.3877787807814e-17},{x=75, y=95, a=5.7331853071796},{x=38, y=109, a=2.9331853071796},{x=27, y=73, a=4.5831853071796},},
checks={{x=51, y=-1,w=10, h=36},{x=113, y=-3,w=9, h=42},{x=174, y=-3,w=10, h=34},{x=190, y=52,w=52, h=10},{x=171, y=84,w=10, h=55},{x=95, y=57,w=10, h=33},{x=34, y=93,w=10, h=50},{x=-2, y=57,w=50, h=6},},
ents={{x=52, y=37,spr=497},{x=178, y=30,spr=497},{x=180, y=84,spr=497},{x=104, y=91,spr=497},{x=44, y=92,spr=497},{x=149, y=29,spr=496},{x=150, y=94,spr=496},{x=11, y=115,spr=496},},
  mx=30,my=0
  
 },
 {
points={{x=32, y=22, a=5.8331853071796},{x=88, y=26, a=1.0},{x=126, y=65, a=0.95},{x=180, y=109, a=3.8},{x=209, y=115, a=3.0},{x=230, y=97, a=1.85},{x=230, y=51, a=0.95},{x=198, y=21, a=0.0},{x=116, y=75, a=5.7331853071796},{x=57, y=105, a=3.0331853071796},{x=22, y=90, a=4.5831853071796},},
checks={{x=57, y=-3,w=10, h=36},{x=124, y=26,w=9, h=66},{x=191, y=95,w=10, h=39},{x=211, y=61,w=34, h=10},{x=188, y=-12,w=10, h=55},{x=81, y=57,w=97, h=16},{x=45, y=85,w=10, h=50},{x=-2, y=57,w=50, h=6},},
ents={{x=57, y=35,spr=497},{x=124, y=25,spr=497},{x=210, y=62,spr=497},{x=199, y=95,spr=497},{x=132, y=92,spr=497},{x=131, y=62,spr=496},{x=143, y=57,spr=496},{x=11, y=115,spr=496},{x=90, y=56,spr=497},{x=54, y=85,spr=497},},
  mx=60,my=0
  
 },
}

function loadEntities(lvl, humans, cpus, laps)
 curLev = lvl
 curLev.laps = laps
 curLev.humans = humans
 ents={}
 cars={}
 
  for x=0,29 do
	 for y=0,16 do
		 mset(x,y,mget(x+curLev.mx, y+curLev.my))
	 end
	end
 
 
 for i=1, humans do
  local c = ins(ents, {  a=0, vx=0, vy=0, r=3, spr=256+ #ents*16, name="P"..i, human=true,
     lastCheckTime=0,
       brain=playerBrain(0+(i-1)*8), directed=true, car=true, lap=0, nextCheck=#(curLev.checks)
  });
  ins(cars, c)
 end
 for i=1, cpus do
  local c = ins(ents, {
  a=0, vx=0, vy=0, r=3, spr=256+ #ents*16, name="CPU", human=false,
  lastCheckTime=0,
  brain=aiBrain(cpuLevels[i].accelCoeff, cpuLevels[i].offset), 
  
  directed=true, car=true, lap=0, nextCheck=#(curLev.checks),
  
 })
  ins(cars, c)
 end
 
 --place cars
 for i=1,#cars do
   cars[i].x = 10+ 10*((i-1) % 2)
   cars[i].y = 74+ 10*((i-1) // 2)
 end
 
 -- give initial sorting
 sortCars()

 for _,e in pairs(lvl.ents) do
  local o = {x=e.x, y=e.y, spr=e.spr, a=0, vx=0, vy=0, r=3}
  if e.spr==496 then -- tire
 o.r=3
  elseif e.spr==497 then -- fix
 o.fixed=true
 o.r=4
  end
  ins(ents, o)
 end
end

function noEditor()
 
end

function export()
  local tt = "points={"
  for i=1,#curLev.points do
   local e =  curLev.points[i]
   tt = tt.."{x="..e.x..", y="..e.y..", a="..e.a.."},"
  end
  tt=tt.."},\nchecks={"
  for i=1,#curLev.checks do
   local e =  curLev.checks[i]
   tt = tt.."{x="..e.x..", y="..e.y..",w="..e.w..", h="..e.h.."},"
  end
  tt=tt.."},\nents={"
  for i=1,#curLev.ents do
   local e =  curLev.ents[i]
   tt = tt.."{x="..e.x..", y="..e.y..",spr="..e.spr.."},"
  end
  tt=tt.."}"
  trace(tt)
end

function drawChecks(act)
 for i=1,#curLev.checks do
  local aa = (i == act);
  local e =  curLev.checks[i]
  rectb(e.x, e.y, e.w, e.h, aa and 15 or 13)
  print(i, e.x+2, e.y+2, 2)
 end
end

function checksEditor()
 print("Checks editor",0,0,15)
 if keyp(01) then
  ins(curLev.checks, {x=100, y=100, w=10, h=10})
  curLev.active = #curLev.checks
 end
 if keyp(49) then
  curLev.active = curLev.active + 1
  if curLev.active > #curLev.checks then curLev.active=1 end
 end
 local a = curLev.checks[curLev.active]
 if key(64) then
  if key(58) then a.h = a.h -1 end
  if key(59) then a.h = a.h +1 end
  if key(60) then a.w = a.w -1 end
  if key(61) then a.w = a.w +1 end
 else
  if key(58) then a.y = a.y -1 end
  if key(59) then a.y = a.y +1 end
  if key(60) then a.x = a.x -1 end
  if key(61) then a.x = a.x +1 end
 end
 
 if keyp(05) then
  export()
 end
 drawChecks(curLev.active)
 pp("A: add E: export TAB: cycle SHIFT: resiz", 1, 129)
end
function entEditor()
 print("Entities editor",0,0,15)
 if keyp(01) then
  ins(curLev.ents, {x=100, y=100, spr=496})
  curLev.active = #curLev.ents
 end
 if keyp(49) then
  curLev.active = curLev.active + 1
  if curLev.active > #curLev.ents then curLev.active=1 end
 end
 local a = curLev.ents[curLev.active]
  if key(58) then a.y = a.y -1 end
  if key(59) then a.y = a.y +1 end
  if key(60) then a.x = a.x -1 end
  if key(61) then a.x = a.x +1 end
  if keyp(64) then 
    if a.spr == 497 then a.spr=496 else a.spr = a.spr+1 end
  end
 if keyp(05) then
  export()
 end
 drawChecks(-1)
 for i=1,#curLev.ents do
  local aa = (i == curLev.active);
  local e =  curLev.ents[i]
  circb(e.x, e.y, 6, aa and 15 or 13)
  spr(e.spr, e.x-4, e.y-4, 3)
  print(i, e.x+4, e.y+4, 2)
 end
  pp("A: add E: export TAB: cycle SHIFT:change", 1, 129)
end

function wpEditor()
 print("Waypoint editor",0,0,15)
 if keyp(01) then
  ins(curLev.points, {x=100, y=100, a=0})
  curLev.active = #curLev.points
 end
 if keyp(49) then
  curLev.active = curLev.active + 1
  if curLev.active > #curLev.points then curLev.active=1 end
 end
 

 
 local a = curLev.points[curLev.active]
 if btn(4) then a.a=angleAdd(a.a,-TURN_RADIUS) end
 if btn(5) then a.a=angleAdd(a.a,TURN_RADIUS) end


  if key(58) then a.y = a.y -1 end
  if key(59) then a.y = a.y +1 end
  if key(60) then a.x = a.x -1 end
  if key(61) then a.x = a.x +1 end
 
 if keyp(05) then
  export()
 end
 for i=1,#curLev.points do
  local aa = (i == curLev.active);
  local e =  curLev.points[i]
  circb(e.x, e.y, 2, aa and 15 or 13)
  pix(e.x, e.y, aa and 15 or 13)
  local x1,y1=vector(20,e.a)
  line(e.x,e.y, e.x+x1, e.y+y1, 2)
  print(i, e.x+2, e.y+2, 2)
 end
  pp("A: add E: export TAB: cycle ZW: rot", 1, 129)
end

function pp(text, x, y)
 print(text, x+1, y+1, 0, true) 
 print(text, x, y, 15, true)

end

function rpad(s, l, c)
 local r = s .. string.rep(c or ' ', l - #s)
 return r, r ~= s
end

function lapTime(lapStart)
 return roundDec( (time()-lapStart) / 600, 3)
end

function pointInRect(p,r)
 return
  p.x>=r.x and p.x<r.x+r.w and
  p.y>=r.y and p.y<r.y+r.h
end

function lapCompleted(o)
  o.nextCheck = 1
  o.lap=o.lap+1
  if o.lapStart then
    o.prevLap = lapTime(o.lapStart)
	
	if o.bestLap then
	  if o.prevLap < o.bestLap then o.bestLap = o.prevLap end;
	else
	  -- no best lap yet, save this
	  o.bestLap = o.prevLap
	end
	
  end
  o.lapStart=time()
  if (o.lap-1)==curLev.laps then 
    -- this car completed the race. Remove pilot
	o.brain=nil
	-- if no human cars are left, end the game (no need to wait for cpu)
	for i=1,#cars do
	 if cars[i].human and cars[i].brain then return end;
	end
    switchMode(MODES.ENDGAME, 0)
  end
end

function checkLaps(o)
 local check = curLev.checks[o.nextCheck ]
 if pointInRect(o, check) then
   if o.nextCheck == #curLev.checks then
     lapCompleted(o)
   else
     o.nextCheck = o.nextCheck +1
   end
   -- if passed any check, resort
   o.lastCheckTime = time()
   sortCars()
 end
end


mode=nil


function endgameSetUp()
 -- remove drivers for any car that still has it
 for i=1, #cars do
  cars[i].brain=nil
 end
end

function updateGame()
  for i=1,#ents do
    local o = ents[i]
    if o.brain then o:brain() end
    -- decide and apply friction
    local inDirt = isInDirt(o)
    local fr = btn(5) and BRAKE_FRICTION or (inDirt and DIRT_FRICTION or FRICTION)
  
    -- slow current velocity
    o.vx = o.vx * fr
    o.vy = o.vy * fr
    if o.car then
      -- even if we are not accelerating, we must rotate the
      -- velocity vector to slowly catch up with the direction
      -- vector, simulating the wheels regaining traction.
      -- without this, in absence of acceleration the car would 
      -- spin freely without affecting the direction of movement
      local v = angle(o.vx, o.vy)
      local d = angleDir(v, o.a) 
      o.vx, o.vy = rotate(o.vx, o.vy, ALIGNEMENT * d)
   
    end
    -- apply velocity to position
    o.x=o.x+o.vx
    o.y=o.y+o.vy
  end
  for i=1,#ents do
   for j=i+1,#ents do
    adjustColl(ents[i], ents[j])
   end
  end
 for i=1,#ents do
  local o = ents[i]
  if o.x<0 then o.x=0 elseif o.x>240 then o.x=240 end
  if o.y<0 then o.y=0 elseif o.y>128 then o.y=128 end
 end
end

function engineSound()
 -- only first player will have engine sound but hey, 
 -- people this days don't have friends
 local playerSpeed = vecLen(cars[1].vx, cars[1].vy)

 if t%2==0 then 
  sfx(0,12+math.floor(playerSpeed*30))
 end 
end

function endgameTIC()
 engineSound() 
 updateGame() 
 render()
 if time()-modeStart > 2000 then
   if cars[1].human then 
    -- show message only if human won
     bPrint("* "..cars[1].name.. " won!! *", 120,20, 15, 2, true, 0)
   end
 
   local w = 160
   rect(120-w/2,40,w,90,15)
   rectb(120-w/2,40,w,90,0)
   bPrint("*Standings *", 120,44, 0, 1, true, -1)
   for i=1,#cars do
    if time()-modeStart > 2000+500*i then
    local n = rpad(cars[i].name, 3, ' ')
	local best = cars[i].bestLap and rpad(tostring(cars[i].bestLap), 6, '0') or "99.999"
    bPrint(" #"..i.." "..n.." "..(cars[i].lap-1).."/"..curLev.laps.." Best "..best, 120,46+i*10, 0, 1, true, -1)
	spr(cars[i].spr, 46,45+i*10,3)
	end
   end
   
 end
 
 if time()-modeStart > 5000 then
  if btnp(4) then
    switchMode(MODES.INTRO, nil)
  end 
 end
end

function TIC()
 t=t+1
 mode.tic()
end

function render()
 cls(0)
 map(0,0)
 for i=1,#ents do
  local o = ents[i]
  if DEBUG then
    drawLine(o.x,o.y, o.a , 10, 13)
    line(o.x,o.y, o.x+o.vx*20,o.y+o.vy*20, 14)
  end

  local idx = rou(o.a*16/pi2) % 16  
  spr(o.spr + (idx % 4),flr(o.x)-4, flr(o.y)-4,3, 1,0, idx // 4)
  if DEBUG and o.car then
    print(o.lap.."/"..o.nextCheck, o.x+4, o.y+4)
  end
 
 
  if DEBUG then
   circb(o.x,o.y, o.r, 10)
   pix(flr(o.x), flr(o.y),15)
  end
 end
end

function timeString(o, numPlayer, includeBest)
  local displayTime
  if o.lapStart then
   
   if o.prevLap and (time()-o.lapStart) < 1000 then
     -- stick on the current lap for some seconds to show it
     displayTime = o.prevLap
   else
     displayTime = rpad(tostring(lapTime(o.lapStart)), 6, '0')
   end
  else
   displayTime = ""
  end
  
  local bestLap = ""
  if o.bestLap and includeBest then
    bestLap = " Best: "..rpad(tostring(o.bestLap), 6, '0')
  end 
  
  local lap = o.lap
  if lap < 1 then lap = 1 elseif lap>curLev.laps then lap=curLev.laps end
  
  return "P"..numPlayer..": "..lap.."/"..curLev.laps.." #"..o.pos.." "..displayTime..""..bestLap
end

function gameTIC()

 engineSound()
 updateGame()
 for i=1,#cars do
  checkLaps(cars[i])
 end
  
 
 render()
 
 if editIdx == 1 then
  for i=1, curLev.humans do
    -- human players are always the first entities
    pp(timeString(ents[i], i, curLev.humans == 1), 1+(i-1)*120, 129)
	-- only two will ever show but hey
  end
 end
 
 -- cycle edit modes with "Q"
 if keyp(17) then
   curLev.active=1
   if editIdx==#editModes then 
    editIdx=1
    local desc = lastLevelDescriptor
    loadEntities(desc.track, desc.humans, desc.cpus, desc.laps)
   else 
    editIdx = editIdx+1 
   end
 end

 -- call the editor function
 editModes[editIdx]()
  
end
  
function sortCars()
table.sort(cars, function(a,b)
 local aa=a.lap*100+a.nextCheck
 local bb=b.lap*100+b.nextCheck
 if aa==bb then
   -- same loop and check, see who arrived first
   return a.lastCheckTime < b.lastCheckTime
 else
   return aa>bb
 end
end)
for i=1,#cars do
 cars[i].pos=i
end
end

function bPrint(text, x,y,color,size, center, borderColor)
 local xx
 if center then
   local w = print(text, 0, -50, color, true, size)
   xx=x-w/2
 else
   xx=x
 end
 if borderColor>-1 then
  for ax=-1,1 do
   for ay=-1,1 do
    print(text,xx+ax,y+ay,borderColor,true,size)
   end
  end
 end
 print(text,xx,y,color,true,size)

end

function loadLevel(desc)
 -- store descriptor to be able to restart the
 -- game in editor mode
 lastLevelDescriptor = desc
 
 loadEntities(desc.track, desc.humans, desc.cpus, desc.laps)
end

function semaphoreSetUp(desc)
 loadLevel(desc)
 mode.oldSem=-1
end

function semaphoreTIC()
  render()
  local sem = (time()-modeStart) // 800
  
  if sem>2 then 
   switchMode(MODES.GAME, nil)
   sfx(10,80,40,1)  
  else
   if mode.oldSem ~= sem then
      sfx(10,75,10,1)  
      mode.oldSem=sem
   end

   rect(88,58,64,20,15)
   rectb(88,58,64,20,0)
   spr(384+sem*2, 120-8+20,68-8, 0,1,0,0, 2,2)
   spr(384+sem*2, 120-8,68-8, 0,1,0,0, 2,2)
   spr(384+sem*2, 120-8-20,68-8, 0,1,0,0, 2,2)  
   if t%20 > 10 then bPrint("GET READY!", 120,90,15,1, true, 0) end
  end
end

function intoSetUp()

  multichoice:init({
    {title="Players: ", labels={"1", "2", "3", "4"}, values={1,2,3,4},def=1, field="humans"},
	{title="Cpu: ", labels={"0", "1", "2", "3"}, values={0,1,2,3}, def=4, field="cpus"},
	{title="Laps: ", labels={"1", "3", "5", "10", "15","50"}, values={1,3,5,10,15,50}, def=2, field="laps"},
	{title="Track: ", labels={"Montemarco", "Dry Lagoon", "Super8"}, values={lvls[1], lvls[2], lvls[3]}, def=1, field="track"},

  })
end
function introTIC()
 cls(0)
 bPrint("Warm Wheels", 120,20, 15, 3, true, 3)
 bPrint("Press Z to start!", 120,100, 15, 1, true, 3)
 local res = multichoice:update()
 if res then
   switchMode(MODES.SEMAPHORE, res)
   return
 end 
 multichoice:render(70,48)
end


editIdx=1
editModes={noEditor, wpEditor, checksEditor, entEditor}

function flr(a) return math.floor(a) end
function rou(x) return x + 0.5 - (x + 0.5) % 1 end
function ins(tbl,e) table.insert(tbl,e); return e end

--loadEntities(lvls[1])

function switchMode(newMode, param)
 if mode and mode.cleanUp then
  mode.cleanUp(param)
 end
 modeStart=time()
 mode = newMode
 if mode.setUp then
  mode.setUp(param)
 end
end


MODES={
 INTRO={setUp=intoSetUp, tic=introTIC, cleanUp=introCleanUp},
 SEMAPHORE={setUp=semaphoreSetUp, tic=semaphoreTIC},
 GAME={setUp=gameSetUp, tic=gameTIC, cleanUp=nil},
 ENDGAME={setUp=endgameSetUp, tic=endgameTIC, cleanUp=nil},
 
}



function init()
 switchMode(MODES.INTRO, nil)
end

init()

-- <TILES>
-- 000:3333333333333333333333333333333333333333333333333333333333333333
-- 001:3333333333333333333333333333333333333333333333333333333333333333
-- 002:3333333333333333333333333333333333333333333333333333333333333333
-- 003:3333333333333333333333333333333333333333333333333333333333333333
-- 004:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 005:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 006:3333333333333333333333333333333333333333333333333333333333333333
-- 007:3333333333333333333333333333333333333333333333333333333333333333
-- 008:3333333333333333333333333333333333333333333333333333333333333333
-- 009:3333333333333333333333333333333333333333333333333333333333333333
-- 010:3333333333333333333333333333333333333333333333333333333333333333
-- 011:3333333333333333333333333333333333333333333333333333333333333333
-- 012:3333333333333333333333333333333333333333333333333333333333333333
-- 013:3333333333333333333333333333333333333333333333333333333333333333
-- 014:3333333333333333333333333333333333333333333333333333333333333333
-- 015:3333333333333333333333333333333333333333333333333333333333333333
-- 016:3333333333333333333333333333333333333333333333333333333333333333
-- 017:3333333333333333333333333333333333333333333333333333333333333333
-- 018:3333333333333333333333333333333333333333333333333333333333333333
-- 019:3333333333333333333333333333333333333333333333333333333333333333
-- 020:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 021:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 022:3333333333333333333333333333333333333333333333333333333333333333
-- 023:3333333333333333333333333333333333333333333333333333333333333333
-- 024:3333333333333333333333333333333333333333333333333333333333333333
-- 025:3333333333333333333333333333333333333333333333333333333333333333
-- 026:3333333333333333333333333333333333333333333333333333333333333333
-- 027:3333333333333333333333333333333333333333333333333333333333333333
-- 028:3333333333333333333333333333333333333333333333333333333333333333
-- 029:3333333333333333333333333333333333333333333333333333333333333333
-- 030:3333333333333333333333333333333333333333333333333333333333333333
-- 031:3333333333333333333333333333333333333333333333333333333333333333
-- 032:bbbbbbbbbbbbbbbbbbbbbb6fbbbbb6f3bbbb6f33bbb6f333bbbf3333bbf63333
-- 033:bbbf6f6fbbf633336f3333333333333333333333333333333333333333333333
-- 034:3333333333333333333333333333333333333333333333333333333333333333
-- 035:3333333333333333333333333333333333333333333333333333333333333333
-- 036:6f6bbbbb336f6f6b333333f63333333333333333333333333333333333333333
-- 037:bbbbbbbbbbbbbbbbfbbbbbbb6f6bbbbb33f6bbbb333f6bbb3333f6bb33333fbb
-- 038:3333333333333333333333333333333333333333333333333333333333333333
-- 039:3333333333333333333333333333333333333333333333333333333333333333
-- 040:3333333333333333333333333333333333333333333333333333333333333333
-- 041:333333363333333f33333366333333fb3333336b333333fb33333f6b333336bb
-- 042:3333333333333333333333333333333333333333333333333333333333333333
-- 043:3333333333333333333333333333333333333333333333333333333333333333
-- 044:f333333363333333f333333363333333f6333333bf333333bbf33333bb633333
-- 045:3333333333333333333333333333333333333333333333333333333333333333
-- 046:3333333333333333333333333333333333333333333333333333333333333333
-- 047:3333333333333333333333333333333333333333333333333333333333333333
-- 048:bb633333b6f33333bf333333b6333333bf33333366333333f333333363333333
-- 049:3333333333333333333333333333333333333333333333333333333333333333
-- 050:3333333333333333333333333333333333333333333333333333333333333333
-- 051:3333333333333333333333333333333333333333333333333333333333333333
-- 052:3333333333333333333333333333333333333333333333333333333333333333
-- 053:333336bb33333fbb333333fb3333336f333333363333333f333333363333333f
-- 054:3333333333333333333333333333333333333333333333333333333333333333
-- 055:3333333333333333333333333333333333333333333333333333333333333333
-- 056:3333333333333333333333333333333333333333333333f633336fbbf6f6fbbb
-- 057:33336fbb3333fbbb333f6bbb33f6bbbb3f6bbbbbf6bbbbbbbbbbbbbbbbbbbbbb
-- 058:3333333333333333333333333333333333333333333333333333333333333333
-- 059:3333333333333333333333333333333333333333333333333333333333333333
-- 060:bbf33333bb6f3333bbb6f333bbbb6f33bbbbb6f6bbbbbbbfbbbbbbbbbbbbbbbb
-- 061:33333333333333333333333333333333333333336f333333b6f6f633bbbbb6f6
-- 062:3333333333333333333333333333333333333333333333333333333333333333
-- 063:3333333333333333333333333333333333333333333333333333333333333333
-- 064:6f333333bb6f6f33bbbbb6f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 065:333333333333333333333333f6333333b6f33333bb6f3333bbb63333bbbf6333
-- 066:3333333333333333333333333333333333333333333333333333333333333333
-- 067:3333333333333333333333333333333333333333333333333333333333333333
-- 068:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 069:bbbbbbb6bbbbbbbfbbbbbb63bbbbbbf3bbbbbb63bbbbb6f3bbbbbf33bbbbb633
-- 070:3333333333333333333333333333333333333333333333333333333333333333
-- 071:3333333333333333333333333333333333333333333333333333333333333333
-- 072:6bbbbbbbfbbbbbbb6bbbbbbb3fbbbbbb36fbbbbb336bbbbb33f6bbbb333fbbbb
-- 073:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 074:3333333333333333333333333333333333333333333333333333333333333333
-- 075:3333333333333333333333333333333333333333333333333333333333333333
-- 076:3333333333333333333333333333333633333f6f3333f6bb33366bbb333fbbbb
-- 077:333336f63336fbbb3f6fbbbbf6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 078:3333333333333333333333333333333333333333333333333333333333333333
-- 079:3333333333333333333333333333333333333333333333333333333333333333
-- 080:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 081:bbbbf333bbbb6f33bbbbb633bbbbbf63bbbbbbf3bbbbbbb6bbbbbbbfbbbbbbb6
-- 082:3333333333333333333333333333333333333333333333333333333333333333
-- 083:3333333333333333333333333333333333333333333333333333333333333333
-- 084:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6fbbbbf6f3bbbf63336f633333
-- 085:bbbbf333bbb66333bb6f3333f6f3333363333333333333333333333333333333
-- 086:3333333333333333333333333333333333333333333333333333333333333333
-- 087:3333333333333333333333333333333333333333333333333333333333333333
-- 088:3336fbbb33336bbb3333f6bb33333f6b3333336f333333333333333333333333
-- 089:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f6bbbbb33f6f6bb333333f6
-- 090:3333333333333333333333333333333333333333333333333333333333333333
-- 091:3333333333333333333333333333333333333333333333333333333333333333
-- 092:336bbbbb33fbbbbb3f6bbbbb36bbbbbb3fbbbbbb36bbbbbbfbbbbbbb6bbbbbbb
-- 093:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
-- 094:3333333333333333333333333333333333333333333333333333333333333333
-- 095:3333333333333333333333333333333333333333333333333333333333333333
-- 096:3333333333333333333333333333333333333333333333333333333333333333
-- 097:333333363333333f3333336b333333fb3333336b333333fb3333336b3333333f
-- 098:3333333333333333333333333333333333333333333333333333333333333333
-- 099:3333333333333333333333333333333333333333333333333333333333333333
-- 100:3333333333333333333333333333333333333333333333333333333333333333
-- 101:3333333333333333333333333333333333333333333333333333333333333333
-- 102:3333333333333333333333333333333333333333333333333333333333333333
-- 103:3333333333333333333333333333333333333333333333333333333333333333
-- 104:63333333f3333333b6333333bf333333b6333333bf333333b633333363333333
-- 105:3333333333333333333333333333333333333333333333333333333333333333
-- 106:3333333333333333333333333333333333333333333333333333333333333333
-- 107:3333333333333333333333333333333333333333333333333333333333333333
-- 108:6fbbbbbf336f6f63333333333333333333333333333333333333333333333333
-- 109:6bbbbbf636f6f633333333333333333333333333333333333333333333333333
-- 110:3333333333333333333333333333333333333333333333333333333333333333
-- 111:3333333333333333333333333333333333333333333333333333333333333333
-- 112:3333333333333333333333333333333333333333333333333333333333333333
-- 113:333333363333336b333333fb3333336b333333fb3333336b3333333f33333336
-- 114:3333333333333333333333333333333333333333333333333333333333333333
-- 115:3333333333333333333333333333333333333333333333333333333333333333
-- 116:333333333333333333333333333333333333333333333333336f6f636fbbbbb6
-- 117:33333333333333333333333333333333333333333333333336f6f633fbbbbbf6
-- 118:3333333333333333333333333333333333333333333333333333333333333333
-- 119:3333333333333333333333333333333333333333333333333333333333333333
-- 120:f3333333b6333333bf333333b6333333bf333333b6333333f333333363333333
-- 121:3333333333333333333333333333333333333333333333333333333333333333
-- 122:3333333333333333333333333333333333333333333333333333333333333333
-- 123:3333333333333333333333333333333333333333333333333333333333333333
-- 124:3333333333333333333333333333333333333333333333333333333333333333
-- 125:3333333333333333333333333333333333333333333333333333333333333333
-- 126:3333333333333333333333333333333333333333333333333333333333333333
-- 127:3333333333333333333333333333333333333333333333333333333333333333
-- 128:333333f6333f6f6b3366bbbb36fbbbbb36bbbbbb6bbbbbbbfbbbbbbb6bbbbbbb
-- 129:f33333336f633333bb6f6333bbbb6f33bbbbb633bbbbbbf3bbbbbb66bbbbbbbf
-- 130:3333333333333333333333333333333333333333333333333333333333333333
-- 131:3333333333333333333333333333333333333333333333333333333333333333
-- 132:bbbbbbf6bbbf6f63bb663333b6f33333b633333363333333f333333363333333
-- 133:fbbbbbbb6f6bbbbb336f6bbb33336fbb333336bb333333fb333333663333333f
-- 134:3333333333333333333333333333333333333333333333333333333333333333
-- 135:3333333333333333333333333333333333333333333333333333333333333333
-- 136:3333333333333333333333333333333333333333333333333333333333333333
-- 137:3333333333333333333333333333333333333333333333333333333333333333
-- 138:3333333333333333333333333333333333333333333333333333333333333333
-- 139:3333333333333333333333333333333333333333333333333333333333333333
-- 140:3333333333333333333333333333333333333333333333333333333333333333
-- 141:3333333333333333333333333333333333333333333333333333333333333333
-- 142:3333333333333333333333333333333333333333333333333333333333333333
-- 143:3333333333333333333333333333333333333333333333333333333333333333
-- 144:fbbbbbbb6bbbbbbbfbbbbbbb6bbbbbbb36bbbbbb36fbbbbb336fbbbb3336f6f6
-- 145:bbbbbbb6bbbbbbbfbbbbbbf6bbbbbb63bbbbb6f3bbbf6f33bb663333f6f33333
-- 146:3333333333333333333333333333333333333333333333333333333333333333
-- 147:3333333333333333333333333333333333333333333333333333333333333333
-- 148:f333333363333333f333333363333333b6333333b6f33333bb6f3333bbb6f6f6
-- 149:333333363333333f333333f63333336b333336fb333f6fbb3366bbbbf6fbbbbb
-- 150:3333333333333333333333333333333333333333333333333333333333333333
-- 151:3333333333333333333333333333333333333333333333333333333333333333
-- 152:3333333333333333333333333333333333333333333333333333333333333333
-- 153:3333333333333333333333333333333333333333333333333333333333333333
-- 154:3333333333333333333333333333333333333333333333333333333333333333
-- 155:3333333333333333333333333333333333333333333333333333333333333333
-- 156:3333333333333333333333333333333333333333333333333333333333333333
-- 157:3333333333333333333333333333333333333333333333333333333333333333
-- 158:3333333333333333333333333333333333333333333333333333333333333333
-- 159:3333333333333333333333333333333333333333333333333333333333333333
-- 160:333333f6333f6f6b3366bbbb36fbbbbb36bbbbbb6bbbbbbbfbbbbbbb6bbbbbbb
-- 161:f33333336f633333bb6f6333bbbb6f33bbbbb633bbbbbbf3bbbbbb66bbbbbbbf
-- 162:3333333333333333333333333333333333333333333333333333333333333333
-- 163:3333333333333333333333333333333333333333333333333333333333333333
-- 164:3333333333333333333333333333333333333333333333333333333333333333
-- 165:3333333333333333333333333333333333333333333333333333333333333333
-- 166:3333333333333333333333333333333333333333333333333333333333333333
-- 167:3333333333333333333333333333333333333333333333333333333333333333
-- 168:3333333333333333333333333333333333333333333333333333333333333333
-- 169:3333333333333333333333333333333333333333333333333333333333333333
-- 170:3333333333333333333333333333333333333333333333333333333333333333
-- 171:3333333333333333333333333333333333333333333333333333333333333333
-- 172:3333333333333333333333333333333333333333333333333333333333333333
-- 173:3333333333333333333333333333333333333333333333333333333333333333
-- 174:3333333333333333333333333333333333333333333333333333333333333333
-- 175:3333333333333333333333333333333333333333333333333333333333333333
-- 176:fbbbbbbb6bbbbbbbfbbbbbbb6bbbbbbbfbbbbbbb6bbbbbbbfbbbbbbb6bbbbbbb
-- 177:bbbbbbb6bbbbbbbfbbbbbbb6bbbbbbbfbbbbbbb6bbbbbbbfbbbbbbb6bbbbbbbf
-- 178:3333333333333333333333333333333333333333333333333333333333333333
-- 179:3333333333333333333333333333333333333333333333333333333333333333
-- 180:3333333333333333333333333333333333333333333333333333333333333333
-- 181:3333333333333333333333333333333333333333333333333333333333333333
-- 182:3333333333333333333333333333333333333333333333333333333333333333
-- 183:3333333333333333333333333333333333333333333333333333333333333333
-- 184:3333333333333333333333333333333333333333333333333333333333333333
-- 185:3333333333333333333333333333333333333333333333333333333333333333
-- 186:3333333333333333333333333333333333333333333333333333333333333333
-- 187:3333333333333333333333333333333333333333333333333333333333333333
-- 188:3333333333333333333333333333333333333333333333333333333333333333
-- 189:3333333333333333333333333333333333333333333333333333333333333333
-- 190:3333333333333333333333333333333333333333333333333333333333333333
-- 191:3333333333333333333333333333333333333333333333333333333333333333
-- 192:33333333333f6f333366bb6336fbbbf336bbbbb66bbbbbbffbbbbbb66bbbbbbf
-- 193:6f633333bbb66333bbbbf633bbbbb6f3bbbbbb63bbbbbbf3bbbbf633f6f63333
-- 194:fbbbbbb66bbbbbbffbbbbbb66bbbbb633fbbbf6336bb663333f6f33333333333
-- 195:33336f6f336fbbbb3fbbbbbb36bbbbbb3f6bbbbb336fbbbb33366bbb333336f6
-- 196:3333333333333333333333333333333333333333333333333333333333333333
-- 197:3333333333333333333333333333333333333333333333333333333333333333
-- 198:3333333333333333333333333333333333333333333333333333333333333333
-- 199:3333333333333333333333333333333333333333333333333333333333333333
-- 200:3333333333333333333333333333333333333333333333333333333333333333
-- 201:3333333333333333333333333333333333333333333333333333333333333333
-- 202:3333333333333333333333333333333333333333333333333333333333333333
-- 203:3333333333333333333333333333333333333333333333333333333333333333
-- 204:3333333333333333333333333333333333333333333333333333333333333333
-- 205:3333333333333333333333333333333333333333333333333333333333333333
-- 206:3333333333333333333333333333333333333333333333333333333333333333
-- 207:3333333333333333333333333333333333333333333333333333333333333333
-- 208:3333333333333333333333333333333333333333333333333333333333333333
-- 209:3333333333333333333333333333333333333333333333333333333333333333
-- 210:3333333333333333333333333333333333333333333333333333333333333333
-- 211:3333333333333333333333333333333333333333333333333333333333333333
-- 212:3333333333333333333333333333333333333333333333333333333333333333
-- 213:3333333333333333333333333333333333333333333333333333333333333333
-- 214:3333333333333333333333333333333333333333333333333333333333333333
-- 215:3333333333333333333333333333333333333333333333333333333333333333
-- 216:3333333333333333333333333333333333333333333333333333333333333333
-- 217:3333333333333333333333333333333333333333333333333333333333333333
-- 218:3333333333333333333333333333333333333333333333333333333333333333
-- 219:3333333333333333333333333333333333333333333333333333333333333333
-- 220:3333333333333333333333333333333333333333333333333333333333333333
-- 221:3333333333333333333333333333333333333333333333333333333333333333
-- 222:3333333333333333333333333333333333333333333333333333333333333333
-- 223:3333333333333333333333333333333333333333333333333333333333333333
-- 224:3333333333333333333333333333333333333333333333333333333333333333
-- 225:3333333333333333333333333333333333333333333333333333333333333333
-- 226:3333333333333333333333333333333333333333333333333333333333333333
-- 227:3333333333333333333333333333333333333333333333333333333333333333
-- 228:3333333333333333333333333333333333333333333333333333333333333333
-- 229:3333333333333333333333333333333333333333333333333333333333333333
-- 230:3333333333333333333333333333333333333333333333333333333333333333
-- 231:3333333333333333333333333333333333333333333333333333333333333333
-- 232:3333333333333333333333333333333333333333333333333333333333333333
-- 233:3333333333333333333333333333333333333333333333333333333333333333
-- 234:3333333333333333333333333333333333333333333333333333333333333333
-- 235:3333333333333333333333333333333333333333333333333333333333333333
-- 236:3333333333333333333333333333333333333333333333333333333333333333
-- 237:3333333333333333333333333333333333333333333333333333333333333333
-- 238:3333333333333333333333333333333333333333333333333333333333333333
-- 239:3333333333333333333333333333333333333333333333333333333333333333
-- 240:5b5b5b5bb5b5b5b55b5b5b5bb5b5b5b55b5b5b5bb5b5b5b55b5b5b5bb5b5b5b5
-- 241:bbb55bbbbbb55bbbbb5555bbb555555bbb5555bbb555555b55555555bbb44bbb
-- 242:33333333aa00aa00aa00aa0000aa00aa00aa00aaaa00aa00aa00aa0033333333
-- 243:33333333aa00aa00aa00aa0000aa00aa00aa00aaaa00aa00aa00aa0033333333
-- 244:33333336aa00aa0faa00aa0600aa00af00aa00a6aa00aa0faa00aa063333333f
-- 245:63333333fa00aa006a00aa00f0aa00aa60aa00aafa00aa006a00aa00f3333333
-- 246:b777777b700000037000000370000003700000037000000370000003b333333b
-- 248:1cccbbbb1666ccbb166666ccb16666bbb166bbbbb1bbbbbbbb1bbbbbbb1bbbbb
-- 249:bbbbbbbbbbbbbbbbbb4bcb4bbbb4c4bbbbbb4bbbbbb4b4bbbbb4b4bbbbbbbbbb
-- 250:bbb33bbbb33ff33bb3f66f3b3f6664a23f6664a2b3f44a2bb33aa22bbbb22bbb
-- 253:0000000000111100011003200100002001000020013002200022220000000000
-- </TILES>

-- <SPRITES>
-- 000:3333333333e66e33306dd60333d66d3333666633306666033366663333333333
-- 001:33333333333e6633330dd6e333d66d0330666d33366660333336633333333333
-- 002:333333333330e633333ddd6330666de336666d03336663333336033333333333
-- 003:3333333333330e33330dd66336666d6336666de33366d0333360333333333333
-- 004:33333333330330333666d6e336666d6336666d633666d6e33303303333333333
-- 005:33333333336033333366d03336666de336666d63330dd66333330e3333333333
-- 006:33333333333603333366633336666d0330666de3333ddd633330e63333333333
-- 007:33333333333663333666603330666d3333d66d03330dd6e3333e663333333333
-- 008:3333333333666633306666033366663333d66d33306dd60333e66e3333333333
-- 009:33333333333663333306666333d6660330d66d333e6dd0333366e33333333333
-- 010:33333333333063333336663330d666633ed6660336ddd333336e033333333333
-- 011:3333333333330633330d66333ed6666336d66663366dd03333e0333333333333
-- 012:33333333330330333e6d666336d6666336d666633e6d66633303303333333333
-- 013:3333333333e03333366dd03336d666633ed66663330d66333333063333333333
-- 014:33333333336e033336ddd3333ed6660330d66663333666333330633333333333
-- 015:333333333366e3333e6dd03330d66d3333d66603330666633336633333333333
-- 016:3333333333e88e33308dd80333d88d3333888833308888033388883333333333
-- 017:33333333333e8833330dd8e333d88d0330888d33388880333338833333333333
-- 018:333333333330e833333ddd8330888de338888d03338883333338033333333333
-- 019:3333333333330e33330dd88338888d8338888de33388d0333380333333333333
-- 020:33333333330330333888d8e338888d8338888d833888d8e33303303333333333
-- 021:33333333338033333388d03338888de338888d83330dd88333330e3333333333
-- 022:33333333333803333388833338888d0330888de3333ddd833330e83333333333
-- 023:33333333333883333888803330888d3333d88d03330dd8e3333e883333333333
-- 024:3333333333888833308888033388883333d88d33308dd80333e88e3333333333
-- 025:33333333333883333308888333d8880330d88d333e8dd0333388e33333333333
-- 026:33333333333083333338883330d888833ed8880338ddd333338e033333333333
-- 027:3333333333330833330d88333ed8888338d88883388dd03333e0333333333333
-- 028:33333333330330333e8d888338d8888338d888833e8d88833303303333333333
-- 029:3333333333e03333388dd03338d888833ed88883330d88333333083333333333
-- 030:33333333338e033338ddd3333ed8880330d88883333888333330833333333333
-- 031:333333333388e3333e8dd03330d88d3333d88803330888833338833333333333
-- 032:3333333333e99e33309dd90333d99d3333999933309999033399993333333333
-- 033:33333333333e9933330dd9e333d99d0330999d33399990333339933333333333
-- 034:333333333330e933333ddd9330999de339999d03339993333339033333333333
-- 035:3333333333330e33330dd99339999d9339999de33399d0333390333333333333
-- 036:33333333330330333999d9e339999d9339999d933999d9e33303303333333333
-- 037:33333333339033333399d03339999de339999d93330dd99333330e3333333333
-- 038:33333333333903333399933339999d0330999de3333ddd933330e93333333333
-- 039:33333333333993333999903330999d3333d99d03330dd9e3333e993333333333
-- 040:3333333333999933309999033399993333d99d33309dd90333e99e3333333333
-- 041:33333333333993333309999333d9990330d99d333e9dd0333399e33333333333
-- 042:33333333333093333339993330d999933ed9990339ddd333339e033333333333
-- 043:3333333333330933330d99333ed9999339d99993399dd03333e0333333333333
-- 044:33333333330330333e9d999339d9999339d999933e9d99933303303333333333
-- 045:3333333333e03333399dd03339d999933ed99993330d99333333093333333333
-- 046:33333333339e033339ddd3333ed9990330d99993333999333330933333333333
-- 047:333333333399e3333e9dd03330d99d3333d99903330999933339933333333333
-- 048:3333333333feef3330edde0333deed3333eeee3330eeee0333eeee3333333333
-- 049:33333333333fee33330ddef333deed0330eeed333eeee033333ee33333333333
-- 050:333333333330fe33333ddde330eeedf33eeeed0333eee333333e033333333333
-- 051:3333333333330f33330ddee33eeeede33eeeedf333eed03333e0333333333333
-- 052:33333333330330333eeedef33eeeede33eeeede33eeedef33303303333333333
-- 053:3333333333e0333333eed0333eeeedf33eeeede3330ddee333330f3333333333
-- 054:33333333333e033333eee3333eeeed0330eeedf3333ddde33330fe3333333333
-- 055:33333333333ee3333eeee03330eeed3333deed03330ddef3333fee3333333333
-- 056:3333333333eeee3330eeee0333eeee3333deed3330edde0333feef3333333333
-- 057:33333333333ee333330eeee333deee0330deed333fedd03333eef33333333333
-- 058:333333333330e333333eee3330deeee33fdeee033eddd33333ef033333333333
-- 059:3333333333330e33330dee333fdeeee33edeeee33eedd03333f0333333333333
-- 060:33333333330330333fedeee33edeeee33edeeee33fedeee33303303333333333
-- 061:3333333333f033333eedd0333edeeee33fdeeee3330dee3333330e3333333333
-- 062:3333333333ef03333eddd3333fdeee0330deeee3333eee333330e33333333333
-- 063:3333333333eef3333fedd03330deed3333deee03330eeee3333ee33333333333
-- 064:3333333333e55e33305dd50333d55d3333555533305555033355553333333333
-- 065:33333333333e5533330dd5e333d55d0330555d33355550333335533333333333
-- 066:333333333330e533333ddd5330555de335555d03335553333335033333333333
-- 067:3333333333330e33330dd55335555d5335555de33355d0333350333333333333
-- 080:3333333333e11e33301dd10333d11d3333111133301111033311113333333333
-- 081:33333333333e1133330dd1e333d11d0330111d33311110333331133333333333
-- 082:333333333330e133333ddd1330111de331111d03331113333331033333333333
-- 083:3333333333330e33330dd11331111d1331111de33311d0333310333333333333
-- 096:3333333333ecce3330cddc0333dccd3333cccc3330cccc0333cccc3333333333
-- 097:33333333333ecc33330ddce333dccd0330cccd333cccc033333cc33333333333
-- 098:333333333330ec33333dddc330cccde33ccccd0333ccc333333c033333333333
-- 099:3333333333330e33330ddcc33ccccdc33ccccde333ccd03333c0333333333333
-- 128:00000ccc0000c666000c666600c666660c666666c6666666c6666666c6666666
-- 129:6660000066660000666660006666660066666660666666666666666666666666
-- 130:00000eee0000e999000e999900e999990e999999e9999999e9999999e9999999
-- 131:9990000099990000999990009999990099999990999999999999999999999999
-- 132:00000ddd0000dbbb000dbbbb00dbbbbb0dbbbbbbdbbbbbbbdbbbbbbbdbbbbbbb
-- 133:bbb00000bbbb0000bbbbb000bbbbbb00bbbbbbb0bbbbbbbbbbbbbbbbbbbbbbbb
-- 144:6666666666666666666666660666666600666666000666660000666600000666
-- 145:6666666166666661666666616666661066666100666610006661000011100000
-- 146:9999999999999999999999990999999900999999000999990000999900000999
-- 147:9999999699999996999999969999996099999600999960009996000066600000
-- 148:bbbbbbbbbbbbbbbbbbbbbbbb0bbbbbbb00bbbbbb000bbbbb0000bbbb00000bbb
-- 149:bbbbbbb5bbbbbbb5bbbbbbb5bbbbbb50bbbbb500bbbb5000bbb5000055500000
-- 192:00000000000707000066666000d6d66000d6d660006666600007070000000000
-- 193:0000000000000000008dd80007888870008dd800078888700088880000000000
-- 194:000000000000000000edde0007eeee7000edde0007eeee7000eeee0000000000
-- 198:000000000066660007666670076dd670006dd60007666670076dd67006666660
-- 204:3333333333110033310000033103300330033103300010033300003333333333
-- 205:3333333333333333333333333333333333333333333333333333333333333333
-- 206:3333333333333333333333333333333333333333333333333333333333333333
-- 207:3333333333333333333333333333333333333333333333333333333333333333
-- 208:00000000000707000066666000d6d66000666660000707000000000000000000
-- 220:3333333333333333333333333333333333333333333333333333333333333333
-- 221:3333333333333333333333333333333333333333333333333333333333333333
-- 222:3333333333333333333333333333333333333333333333333333333333333333
-- 223:3333333333333333333333333333333333333333333333333333333333333333
-- 236:3333333333333333333333333333333333333333333333333333333333333333
-- 237:3333333333333333333333333333333333333333333333333333333333333333
-- 238:3333333333333333333333333333333333333333333333333333333333333333
-- 239:3333333333333333333333333333333333333333333333333333333333333333
-- 240:3333333333110033310000033103300330033103300010033300003333333333
-- 241:333aa3333aa777133a777713a7777771a77777713a7777133a77711333311333
-- 252:3333333333333333333333333333333333333333333333333333333333333333
-- 253:3333333333333333333333333333333333333333333333333333333333333333
-- 254:3333333333333333333333333333333333333333333333333333333333333333
-- 255:3333333333333333333333333333333333333333333333333333333333333333
-- </SPRITES>

-- <MAP>
-- 000:0000000000000000000000000000000000000000000000000000000000000212c6d6c6c6d6c6d6584048c6d6c6d6c6d6c6d6c6d6c6d6c6d6c6d6425202c6d6c6d6c6d6c6d6d6c642529440401f1f40400212c6d6c6d6c6d642520212c6d6c6d642524050405040500212c6d6c6d6c6d684944454c6d64252000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:00000000000000000000000000000000000000000000000000000000000003130000000000000000c600000000000000000000000000000000004353031300000000000000000043534040401f404040031300000000000043530313c7d7c7d7435341511f5141510313c7d7c7d7c7d785954555c7d74353000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:00000000000000000000000000000000000000000000000000000000000086000000000000000000000000004747570000000000470000000000001786000000000047475700000000d6849440400212000000000000000000168696010000010111841f4050445400000000000000000000000000000616000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:0000000000000000000000000000000000000000000000000000000000008700000000004757000000475708404040c2d200c4d4500414000000000887000000c4d4404040180000000085954040031300000047570000000017879700100a1a0010859541514555000000000a1a46564656465600000717000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:00000000000000000000000000000000000000000000000000000000000087000000c4d44040494759404040404040c3d347c5d5400515000000164086000000c5d540054050c2d2000000000919000000c4d44040041400001686960116401b01110000c6d60000000000000b4049574757475700000616000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:00000000000000000000000000000000000000000000000000000000000000000000c5404040404040404040404040404040404040404086000017408700001640409f404151c3d3000000000000000000c5d540400515000017879706164050c2d2465600c7d70000000616405040504050405004140717000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:0000000000000000000000000000000000000000000000000000000000008600001640401f404040404040404040404040404040404040870000005887000017409f401f40404050180000000000000016404040404040490016869607174151c3d347570000000000000717405041514151411f05150616000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:0000000000000000000000000000000000000000000000000000000000005f3f3f4f40404040404040404048c6d6c6d64252404040404049000000165f3f3f4f4040404040414151190000000000000017404040401f404086175f2f2f4f405040504050c2d24656005682920212c6d6425240501f508617000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:000000000000000000000000000000000000000000000000000000000000860000005840404002122cc6d60000000000435340404040401900000016c200001640401f40400212c600000000000000000840401f40404040871686960017411f41514151c3d34757475783930313c7d74353411f41518716000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:000000000000000000000000000000000000000000000000000000000000c200000016404040031300000000000000000000425240021200000000170300001740404040400313000000000000000000094040408f404040861787970016400212c6d6425240405040404454000111000000849444540017000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:0000000000000000000000000000000000000000000000000000000000000300000016404048000082000804140010000000435340031300000000088600000084944044540000000047570818000000004252404040404087168696001740031300004353404151404045550000000c0000859545550016000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:000000000000000000000000000000000000000000000000000000000000000000001740480000008292405015011100000000002c000000000016408700000085954045550000c4d44040404004140000435340404044540017879700084086000000000009404040190000008292408600000000000017000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:00000000000000000000000000000000000000000000000000000000000086000000002c0000000c8393414050041400000000000000000000001740860000000000c600000000c5d54040404005150000000009404045550016869600091900000818000000c6c6d6000000008393401800000000000092000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:00000000000000000000000000000000000000000000000000000000000086000000000000005940405050411f051500000000000000000000000058870000000000000000001640404040409f40404900000000c6d600000017879700000000005840860000c7c7d70000c4d44040404049000000000053000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:00000000000000000000000000000000000000000000000000000000000087d2000000000059404041511f50405040c2d20000000000000000008292c2d20000000000000082924040401f8f40404040c2d20000000000008292879746564656829240c2d2564656465659404040416f5140c2d246568292000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:000000000000000000000000000000000000000000000000000000000000c3d3475747575940404151514151415140c3d34757475747574747578393c3d347574757474757839340404040401f404040c3d34757475747578393c3d347574757839340c3d3574757475940405040506f4040c3d347578393000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 016:0000000000000000000000000000000000000000000000000000000000000f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 017:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f0f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 135:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:a0e000000000f00000000000a100a1b0
-- 001:78a868ab889ba541135895fdfd785142
-- 002:0123456789abcdef0123456789abcdef
-- 003:0123456789abcdeffedcba9876543210
-- 004:ffffffff00000000ffffffff00000000
-- </WAVES>

-- <SFX>
-- 000:a100a1b0a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100a100184000000200
-- 001:029002c002d002e002e002e002d002d002c002b002a0029002800270026002500240023002300220022002100210021002100210021002100210020033b000000000
-- 005:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009000000000
-- 010:030e030003010302030403050306030603070307030703070306030503050303030203010300030f030d030c030c030a030903090308030803080308539000000000
-- 011:030003000300030003000300030003000300030003000300030003000300030003000300030003000300030003000300030003000300030003000300005000000000
-- </SFX>

-- <SCREEN>
-- 000:bbbbbbbbbbbf6f6f6fbbbbbf6bbbbbf66fbbbbbf6bbbbbf66f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf6f6f6fbbbbbf6bbbbbf66fbbbbbf6bbbbbf66fbbbbbf6bbbbbf66bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb66fbbbbbf6bbbbbf66f6bbbbbbbbbbbbb
-- 001:bbbbbbbbbbf63333336f6f6336f6f633336f6f6336f6f633336f6f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf63333336f6f6336f6f633336f6f6336f6f633336f6f6336f6f633fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf336f6f6336f6f633336f6f6bbbbbbbbb
-- 002:bbbbbb6f6f33333333333333333333333333333333333333333333f6fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f6f3333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbb633333333333333333333333f6fbbbbbbb
-- 003:bbbbb6f33333333333333333333333333333333333333333333333336f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f3333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbf33333333333333333333333336f6bbbbb
-- 004:bbbb6f3333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f333333333333333333333333333333333333333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbbbbb6333333333333333333333333333f6bbbb
-- 005:bbb6f333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f33333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbb6f3333333333333333333333333333f6bbb
-- 006:bbbf33333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf33333333333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbf333333333333333333333333333333f6bb
-- 007:bbf6333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf6333333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbb63333333333333333333333333333333fbb
-- 008:bb633333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbb55bbbbbbbbbbbbbbbbbbbbbbbbbbbbb633333333333333333333333333333333333333333333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbf333333333333333333333333333333336bb
-- 009:b6f3333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbb55bbbbbbbbbbbbbbbbbbbbbbbbbbbb6f333333333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbb6633333331100333333333333333333333fbb
-- 010:bf333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbb5555bbbbbbbbbbbbbbbbbbbbbbbbbbbf333333333333333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbb6f3333333100000333333333333333333333fb
-- 011:b63333333333333333333333333333333333333333333333333333333333336fbbbbbbbbbbbbbbbbb555555bbbbbbbbbbbbbbbbbbbbbbbbbb63333333333333333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbf6f333333331033003333333331100333333336f
-- 012:bf33333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbb5555bbbbbbbbbbbbbbbbbbbbbbbbbbbf333333333333333333333333333333333333333333333333333333333333333333336fbbbbbbbbbbbbbb6f6333333333300331033333333100000333333336
-- 013:663333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbb555555bbbbbbbbbbbbbbbbbbbbbbbbb6633333333333333333333333333333333333333333333333333333333333333333333336f6bbbbbbbbbf6f3333333333330001003333333310330033333333f
-- 014:f333333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbb55555555bbbbbbbbbbbbbbbbbbbbbbbbf3333333333333333333333333333333333333333333333333333333333333333333333333f6f6bbbbbf63333333333333330000333333333003310333333336
-- 015:633333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbb44bbbbbbbbbbbbbbbbbbbbbbbbbbb633333333333333333333333333333333333333333333333333333333333333333333333333333f66f633333333333333333333333333333300010033333333f
-- 016:63333333333333333333333333333333333333333333333333333333333333336bbbbbbbbbb55bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb633333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333300003333333336
-- 017:f333333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbb55bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf3333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333f
-- 018:b6333333333333333333333333333333333333333333333333333333333333336bbbbbbbbb5555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb633333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333336b
-- 019:bf333333333333333333333333333333333333333333333333333333333333333fbbbbbbb555555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf3333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333fb
-- 020:b63333333333333333333333333333333333333333333333333333333333333336fbbbbbbb5555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb633333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333336b
-- 021:bf33333333333333333333333333333333333333333333333333333333333333336bbbbbb555555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f3333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333fb
-- 022:b63333333333333333333333333333333333333333333333333333333333333333f6bbbb55555555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbf333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333336b
-- 023:6333333333333333333333333333333333333333333333333333333333333333333fbbbbbbb44bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333f
-- 024:f3333333333333333333333333333333333333f6f333333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf33333333333333333333333333333333333333333f6f333333333333333333333333333333333333333333333333333333333333333333333333333333333333336
-- 025:b6333333333333333333333333333333333f6f6b6f633333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6633333333333333333333333333333333333333f6f6b6f6333333333333333333333333333333333333333333333333333333333333333333333333333333333336b
-- 026:bf3333333333333333333333333333333366bbbbbb6f633333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f3333333333333333333333333333333333333366bbbbbb6f6333333333333333333333333333333333333333333333333333333333333333333333333333333333fb
-- 027:b633333333333333333333333333333336fbbbbbbbbb6f33333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf6f333333333333333333333333333333333333336fbbbbbbbbb6f333333333333333333333333333333333333333333333333333333333333333333333333333333336b
-- 028:bf33333333333333333333333333333336bbbbbbbbbbb63333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f633333333333333333333333333333333333333336bbbbbbbbbbb633333333333333333333333333333333333333333333333333333333333333333333333333333333fb
-- 029:b63333333333333333333333333333336bbbbbbbbbbbbbf33333333333333333333333336f6bbbbbbbbbbbbbbbbbbbbbbbbbf6f333331100333333333333333333333333333333336bbbbbbbbbbbbbf33333333333333333333333333333333333333333333333333333333333333333333333333333336b
-- 030:f3333333333333333333333333333333fbbbbbaabbbbbb6633333333333333333333333333f6f6bbbbbbbbbbbbbbbbbbbbbf63333331000003333333333333333333333333333333fbbbbbbbbbbbbb663333333333333333333333333333333333333333333333333333333333333333333333333333333f
-- 031:633333333333333333333333333333336bbbaa7771bbbbbf333333333333333333333333333333f6bbbbbbbbbbbbbbbb6f63333333310330033333333333333333333333333333336bbbbbbbbbbbbbbf33333333333333333333333333333333333333333333333333333333333333333333333333333336
-- 032:63333333333333333333333333333336bbbba77771bbbbb6333333333333333333333333333333336fbbbbbf6bbbbbf6333333333330033103333333333333333333333333333333fbbbbbbbbbbbbbbbf3333333333333333333333333333333333333333333333333333333333333333333333333333336
-- 033:f333333333333333333333333333333fbbba7777771bbbbf33333333333333333333333333333333336f6f6336f6f6333333333333300010033333333333333333333333333333336bbbbbaabbbbbbbb6333333333333333333333333333333333333333333333333333333333333333333333333333333f
-- 034:b633333333333333333333333333336bbbba7777771bbbb6333333333333333333333333333333333333333333333333333333333333000033333333333333333333333333333333fbbbaa7771bbbbbbf333333333333333333333333333333333333333333333333333333333333333333333333333336b
-- 035:bf3333333333333333333333333333fbbbbba77771bbbbbf3333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333336bbba77771bbbbbb633333333333333333333333333333333333333333333333333333333333333333333333333333fb
-- 036:b633333333333333333333333333336bbbbba77711bbbbb6333333333333333333333333333333333333333333333333333333331100333333333333333333333333333333333333fbba7777771bbbbbb633333333333333333333333333333333333333333333333333333333333333333333333333336b
-- 037:bf3333333333333333333333333333fbbbbbbb11bbbbbbbf3333333333333333333333333333333333333333333333333333333100000333333333333333333333333333333333336bba7777771bbbbbb6f333333333333333333333333333333333333333333333333333333333333333333333333333fb
-- 038:b633333333333333333333333333336bbbbbbbbbbbbbbbb6333333333333333333333333333333333333333333333333333333310330033333333333333333333333333333333333fbbba77771bbbbbbbb6f333336f6f633336f6f6336f6f633336f6f6336f6f6333333333333333333333333333333336b
-- 039:6333333333333333333333333333333fbbbbbbbbbbbbbbbf3333333333333333333333333333333333333333333333333333333003310333333333333333333333333333333333336bbba77711bbbbbbbbb6f6f6fbbbbbf66fbbbbb6fbbbbbf66fbbbbb6fbbbbbf63333333333333333333333333333333f
-- 040:f3333333333333333333333333333336bbbbbbbbbbbbbbbbf33333333333333333333333333333333333333333333333333333300010033333333333333333333333333333333336bbbbbb11bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f333333333333333333333333333336
-- 041:b633333333333333333333333333333fbbbbbbbbbbbbbbbb63333333333333333333333333333333333333333333333333333333000033333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f6f3333333333333333333333336b
-- 042:bf33333333333333333333333333336bbbbbbbbbbbbbbbbbf3333333333333333333333333333333333333333333333110033333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f63333333333333333333333fb
-- 043:b63333333333333333333333333333fbbbbbbbbbbbbbbbbb6333333333333333333333333333333333333333333333100000333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf6333333333333333333336b
-- 044:bf33333333333333333333333333336bbbbbbbbbbbbbbbbbf6333333333333333333333333333333333333333333331033003333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f3333333333333333333fb
-- 045:b63333333333333333333333333333fbbbbbbbbbbbbbbbbbbf33333333333333333333333333333333333333333333003310333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f3333333333333333336b
-- 046:f333333333333333333333333333336bbbbbbbbbbbbbbbbbbbf33333333333333333333333333333333333333333330001003333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb63333333333333333333f
-- 047:6333333333333333333333333333333fbbbbbbbbbbbbbbbbbb633333333333333333333333333333333333333333333000033333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf63333333333333333336
-- 048:63333333333333333333333333333336bbbbbbbbbbbbbbbbbbf333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb55bbbbbbbbbbbbbbbf3333333333333333336
-- 049:f333333333333333333333333333336bbbbbbbbbbbbbbbbbbb6f3333333333333333333333333333333333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb55bbbbbbbbbbbbbbb6f33333333333333333f
-- 050:b63333333333333333333333333333fbbbbbbbbbbbbbbbbbbbb6f33333333333333333333333333333333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb5555bbbbbbbbbbbbbbb633333333333333336b
-- 051:bf33333333333333333333333333336bbbbbbbbbbbbbbbbbbbbb6f33333333333333333333333333333333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb555555bbbbbbbbbbbbbbf6333333333333333fb
-- 052:b63333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbb6f633333333333333333333333333333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb5555bbbbbbbbbbbbbbbbf3333333333333336b
-- 053:bf33333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbf6f3333333333333333333333333333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb555555bbbbbbbbbbbbbbbb633333333333333fb
-- 054:b633333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbb6f6f633336f6f6336f6f633333333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb55555555bbbbbbbbbbbbbbbf333333333333336b
-- 055:63333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f66fbbbbb6fbbbbbf63333333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb44bbbbbbbbbbbbbbbbbb6333333333333333f
-- 056:63333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf333333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbf6f6f6fbbbbbf6bbbbbf66f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb55bbbbbbbbbbb6333333333333336
-- 057:fa00aa00aa00aa00aa00aa00aa00aa0fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb633333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbf63333336f6f6336f6f633336f6f6bbbbbbbbbbbbbbbbbbbbbbbbbbbb55bbbbbbbbbbbf33333333333336b
-- 058:6a00aa00aa00aa00aa00aa00aa00aa06bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf333333300000000000000000000000000000000000000000000000000000000000000006f3333333333333333333333333333f6fbbbbbbbbbbbbbbbbbbbbbbbbb5555bbbbbbbbbbb6333333333333fb
-- 059:f0aa00aa00aa00aa00aa00aa00aa00afbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb633333330ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0333333333333333333333333333333336f6bbbbbbbbbbbbbbbbbbbbbb555555bbbbbbbbbbf3333333333336b
-- 060:60aa00aa00aa00aa00aa00aa00aa00a6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf63333330ffffffffdddbbbffffffffffffffdddbbbffffffffffffffdddbbbffffffff03333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbb5555bbbbbbbbbbb6333333333333fb
-- 061:fa00aa00aa00aa00aa00aa00aa00aa0fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf3333330fffffffdbbbbbbbffffffffffffdbbbbbbbffffffffffffdbbbbbbbfffffff033333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbb555555bbbbbbbbbbf3333333333336b
-- 062:6a00aa00aa00aa00aa00aa00aa00aa06bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf333330ffffffdbbbbbbbbbffffffffffdbbbbbbbbbffffffffffdbbbbbbbbbffffff0333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbb55555555bbbbbbbbb63333333333333f
-- 063:f333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6333330fffffdbbbbbbbbbbbffffffffdbbbbbbbbbbbffffffffdbbbbbbbbbbbfffff03333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbb44baabbbbbbbb6333333333333336
-- 064:63333333333333333333333333333336bbbbbbbbbbb55bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf333330ffffdbbbbbbbbbbbbbffffffdbbbbbbbbbbbbbffffffdbbbbbbbbbbbbbffff033333333333333333333333333333333333336bbbbbbbbbbbbb55bbbbbbbaa7771bbbbbbf333333333333336
-- 065:f333333333333333333333333333336bbbbbbbbbbbb55bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f33330fffdbbbbbbbbbbbbbbbffffdbbbbbbbbbbbbbbbffffdbbbbbbbbbbbbbbbfff03333333333333333333333333333333333333fbbbbbbbbbbbbb55bbbbbbba77771bbbbbbb63333333333333f
-- 066:b63333333333333333333333333333fbbbbbbbbbbb5555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f3330fffdbbbbbbbbbbbbbbbffffdbbbbbbbbbbbbbbbffffdbbbbbbbbbbbbbbbfff033333333333333333333333333333333333333fbbbbbbbbbbb5555bbbbba7777771bbbbbbf3333333333336b
-- 067:bf33333333333333333333333333336bbbbbbbbbb555555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f330fffdbbbbbbbbbbbbbbbffffdbbbbbbbbbbbbbbbffffdbbbbbbbbbbbbbbbfff0333333333333333333333333333333333333336fbbbbbbbbb555555bbbba7777771bbbbbb6333333333333fb
-- 068:b63333333333333333333333333333fbbbbbbbbbbb5555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f60fffbbbbbbbbbbbbbbb5ffffbbbbbbbbbbbbbbb5ffffbbbbbbbbbbbbbbb5fff03333333333333333333333333333333333333336bbbbbbbbbb5555bbbbbba77771bbbbbbbf3333333333336b
-- 069:bf33333333333333333333333333336bbbbbbbbbb555555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf0fffbbbbbbbbbbbbbbb5ffffbbbbbbbbbbbbbbb5ffffbbbbbbbbbbbbbbb5fff0333333333333333333333333333333333333333fbbbbbbbbb555555bbbbba77711bbbbbbb6333333333333fb
-- 070:b633333333333333333333333333333fbbbbbbbb55555555bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0fffbbbbbbbbbbbbbbb5ffffbbbbbbbbbbbbbbb5ffffbbbbbbbbbbbbbbb5fff03333333333333333333333333333333333333336bbbbbbbb55555555bbbbbb11bbbbbbbbf33333333333336b
-- 071:63333333e66e333333e88e3333333336bbbbbbbbbbb44bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0ffffbbbbbbbbbbbbb5ffffffbbbbbbbbbbbbb5ffffffbbbbbbbbbbbbb5ffff0333333333333333333333333333333333333333fbbbbbbbbbbb44bbbbbbbbbbbbbbbbbbb633333333333333f
-- 072:f33333306dd60333308dd80333333336bbbbbbbbbbbbbbbbbbbf6f6f6fbbbbbf6bbbbbf66f6bbbbbbbbbbbbb0fffffbbbbbbbbbbb5ffffffffbbbbbbbbbbb5ffffffffbbbbbbbbbbb5fffff033333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb63333333333333336
-- 073:b6333333d66d333333d88d333333333fbbbbbbbbbbbbbbbbbbf63333336f6f6336f6f633336f6f6bbbbbbbbb0ffffffbbbbbbbbb5ffffffffffbbbbbbbbb5ffffffffffbbbbbbbbb5ffffff03333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf333333333333336b
-- 074:bf33333366663333338888333333336bbbbbbbbbbbbbbb6f6f3333333333333333333333333333f6fbbbbbbb0fffffffbbbbbbb5ffffffffffffbbbbbbb5ffffffffffffbbbbbbb5fffffff033333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbb6333333333333333fb
-- 075:b63333306666033330888803333333fbbbbbbbbbbbbbb6f3333333333333333333333333333333336f6bbbbb0ffffffffbbb555ffffffffffffffbbb555ffffffffffffffbbb555ffffffff033333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbf3333333333333336b
-- 076:bf33333366663333338888333333336bbbbbbbbbbbbb6f333333333333333333333333333333333333f6bbbb0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0333333333333333333333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbbbbb6333333333333333fb
-- 077:b63333333333333333333333333333fbbbbbbbbbbbb6f33333333333333333333333333333333333333f6bbb00000000000000000000000000000000000000000000000000000000000000003333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbb6f3333333333333336b
-- 078:f333333333333333333333333333336bbbbbbbbbbbbf3333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf3333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbf33333333333333333f
-- 079:6333333333333333333333333333333fbbbbbbbbbbf633333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb633333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbb6333333333333333336
-- 080:63333333333333333333333333333336bbbbbbbbbb63333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf3333333333333333333333333333333333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbf3333333333333333336
-- 081:f3333333e99e333333feef333333336bbbbbbbbbb6f333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb66333333333333333333333333333333f6f33333333333333333333336bbbbbbbbbbbbbbbbbbbbbb66333333333333333333f
-- 082:b63333309dd9033330edde03333333fbbbbbbbbbbf33333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f33333333333333333333333333333366bb6333333333333333333333f6bbbbbbbbbbbbbbbbbbbb6f3333333333333333336b
-- 083:bf333333d99d333333deed333333336bbbbbbbbbb6333333333333333333333333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf6f3333333333333333333333333333336fbbbf3333333333333333333333f6bbbbbbbbbbbbbbbbbf6f3333333333333333333fb
-- 084:b63333339999333333eeee33333333fbbbbbbbbbbf3333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f6333333333333333333333333333333336bbbbb633333333333333333333336fbbbbbbbbbbbbbb6f63333333333333333333336b
-- 085:bf3333309999033330eeee033333336bbbbbbbbb66333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf6f3333333333333333333333333333333336bbbbbbf3333333333333333333333336f6bbbbbbbbbf6f33333333333333333333333fb
-- 086:b63333339999333333eeee333333333fbbbbbbbbf33333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf633333333333333333333333333333333333fbbbbbb633333333333333333333333333f6f6bbbbbf633333333333333333333333336b
-- 087:63333333333333333333333333333336bbbbbbbb63333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f633333333333333333333333333333333333336bbbbbbf333333333333333333333333333333f66f63333333333333333333333333333f
-- 088:f33333333333333333333333333333f6bbbbbbbb633333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb63333333333333333333333333333333333333336bbbbbbbb6333333333333333333333333333333333333333333333333333333333333336
-- 089:b63333333333333333333333333f6f6bbbbbbbbbf333333333333333333333333333333333333333333333336b000000000000000000bbbbb000000000000000000000000300000030000333333333333333333fbbbbbbbbf33333333333333333333333333333333333333333333333333333333333336b
-- 090:bf33333333333333333333333366bbbbbbbbbbbbb63333333333333333333333333333333333333333333333f00ffff0fffff00ffff0bbbbb0ffff00fffff00fff00ffff000ff0f030ff03333333333333333366bbbaabbbb6333333333333333333333333333333333333333333333333333333333333fb
-- 091:b6333333333333333333333336fbbbbbbbbbbbbbbf333333333333333333333333333333333333333333333360ff0000ff000000ff00bbbbb0ff00f0ff0000ff00f0ff00f00ff0f030ff033333333333333333fbbaa7771bbf3333333333333333333333333333333333333333333333333333333333336b
-- 092:bf333333333333333333333336bbbbaabbbbbbbbb6333333333333333333333333333333333333333333333330ff0ff0ffff0bb0ff0bbbbbb0ff00f0ffff00ff00f0ff00f00ffff030ff0333333333333333336bba77771bb6333333333333333333333333333333333333333333333333333333333333fb
-- 093:b633333333333333333333336bbbaa7771bbbbbbbf333333333333333333333333333333333333333333333330ff00f0ff0000b0ff0bbbbbb0ffff00ff0000fffff0ff00f000ff003000033333333333333333fba7777771bf3333333333333333333333333333333333333333333333333333333333336b
-- 094:f33333333333333333333333fbbba77771bbbbbbb63333333333333333333333333333333333333333333333300ffff0fffff0b0ff0bbbbbb0ff00f0fffff0ff00f0ffff0030ff0330ff03333333333333333f6ba7777771b63333333333333333333333333333333333333333333333333333333333333f
-- 095:6333333333333333333333336bba7777771bbbbb63333333333333333333333333333333333333333333333333000000000000b0000bbbbbb00000000000000000000000033000033000033333333333333336bbba77771b6333333333333333333333333333333333333333333333333333333333333336
-- 096:633333333333333333333333fbba7777771bbbb63333333333333333333333f6f33333333333333333333333333333336fbbbbbf6fbbbbbf6bbbbbf6333333333333333333333333333333333333333333336fbbba77711bf333333333333333333333333333333333333333333333333333333333333336
-- 097:f333333333333333333333336bbba77771bbbbbf3333333333333333333f6f6b6f633333333333333333333333333333336f6f63336f6f6336f6f63333333333333333333333333333333333333333333333fbbbbbb11bbb6f6333333333333333333333333333333333333333333333333333333333333f
-- 098:b63333333333333333333333fbbba77711bbbbf633333333333333333366bbbbbb6f63333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbb6f633333333333333333333333333333333333333333333333333333333366
-- 099:bf33333333333333333333336bbbbb11bbbbbb63333333333333333336fbbbbbbbbb6f33333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbb6f33333333333333333333333333333333333333333333333333333333fb
-- 100:b6333333333333333333333336bbbbbbbbbbb6f3333333333333333336bbbbbbbaabb63333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbb6333333333333333333333333333333333333333333333333333333336b
-- 101:bf333333333333333333333336fbbbbbbbbf6f3333333333333333336bbbbbbaa7771bf333333333333333333333333333333333333333333333333333333333333333333333333333333333333333f6f6bbbbbbbbbbbbbbbbbbbbf3333333333333333333333333333333333333333333333333333333fb
-- 102:b63333333333333333333333336fbbbbbb6633333333333333333333fbbbbbba77771b663333333333333333333333333333333333333333333333333333333333333333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbb6633333333333333333333333333333333333333333333333333333f6b
-- 103:6333333333333333333333333336f6f6f6f3333333333333333333336bbbbba7777771bf33333333333333333333333333333333333333333333333333333333333333333333333333333333f6f6fbbbbbbbbbbbbbbbbbbbbbbbbbbf333333333333333333333333333333333333333333333333333336bb
-- 104:f3333333333333333333333333333333333333333333333333333333fbbbbba7777771bb633333333333333333333333333333333333333333333333333333333333333333333333333336f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf33333333333333333333333333333333333333333333333333336bb
-- 105:b63333333333333333333333333333333333333333333333333333336f6bbbba77771bbbf333333333333333333333333333333333333333333333333333333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb63333333333333333333333333333333333333333333333333333fbb
-- 106:bf333333333333333333333333333333333333333333333333333333336f6bba77711bbbb633333333333333333333333333333333333333333333333333333333333333333333333f6fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbf33333333333333333333333333333333333333333333333333333fb
-- 107:b633333333333333333333333333333333333333333333333333333333336fbbb11bbbbbbf3333333333333333333333333333333333333333333333333333333333333333333336f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6333333333333333333333333333333333333333333333333333336f
-- 108:bf333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbb63333333333333333333333333333333333333333333333333333333333333333333f6fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6333333333333333333333333333333333333333333333333333336
-- 109:b6333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbf333333333333333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f3333333333333333333333333333333333333333333333333333f
-- 110:f333333333333333333333333333333333333333333333333333333333333366bbbbbbbbb63333333333333333333333333333333333333333333333333333333333333333366bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f3333333333333333333333333333333333333333333333333336
-- 111:633333333333333333333333333333333333333333333333333333333333333fbbbbbbbb6333333333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f6f633333333333333333333333333333333333333333333333f
-- 112:f333333333333333333333333333333333333333333333333333333333333336bbbbbbbbf333333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb777777bbbbbbbbbbbbbbbbbf33333333333333333333333333333333333333333333336
-- 113:b63333333333333333333333333333333333333333333333333333333333333fbbbbbbbb633333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbb63333333333333333333333333333333333333333333333f
-- 114:bf33333333333333333333333333333333333333333333333333333333333366bbbbbbbbf3333333333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbbf33333333333333333333333333333333333333333333366
-- 115:b6333333333333333333333333333333333333333333333333333333333333fbbbbbbbbb633333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbb6333333333333333333333333333333333333333333333fb
-- 116:bf3333333333333333333333333333333333333333333333333333333333336bbbbbbbbbf6333333333333333333333333333333333333333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbbf6333333333333333333333333333333333333333333336b
-- 117:b6333333333333333333333333333333333333333333333333333333333333fbbbbbbbbbbf333333333333333333333333333333333333333333333333333333333f6fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbbbf33333333333333333333333333333333333333333333fb
-- 118:f333333333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbf333333333333333333333333333333333333333333333333333333366bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbbbbf333333333333333333333333333333333333333333f6b
-- 119:63333333333333333333333333333333333333333333333333333333333336bbbbbbbbbbbb633333333333333333333333333333333333333333333333333333f6fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb333333bbbbbbbbbbbbbbbbbbb63333333333333333333333333333333333333333336bb
-- 120:bbf3333333333333333333333333333333333333333333333333333333336fbbbbbbbbbbbbf33333333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb777777bbbbbbbbbbbbbbbbbbbf333333333333333333333333333333333333333336fbb
-- 121:bb6f33333333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbb6f333333333333333333333333333333333333333333333333333fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbbbb6f3333333333333333333333333333333333333333fbbb
-- 122:bbb6f333333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbb6f3333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbbbbb6f33333333333333333333333333333333333333f6bbb
-- 123:bbbb6f3333333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbb6f3333333333333333333333333333333333333333333333336bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbbbbbb6f333333333333333333333333333333333333f6bbbb
-- 124:bbbbb6f63333333333333333333333333333333333333333333333333f6bbbbbbbbbbbbbbbbbb6f63333333333333333333333333333333333333333333336fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbbbbbbb6f6333333333333333333333333333333333f6bbbbb
-- 125:bbbbbbbf6f33333333333333333333333333333333333333333333f6f6bbbbbbbbbbbbbbbbbbbbbf6f33333333333333333333333333333333333333333f6fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbbbbbbbbbf6f3333333333333333333333333333f6f6bbbbbb
-- 126:bbbbbbbbb6f6f633336f6f6336f6f633336f6f6336f6f63333336fbbbbbbbbbbbbbbbbbbbbbbbbbbb6f6f63336f6f633336f6f6336f6f633336f6f633366bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb70000003bbbbbbbbbbbbbbbbbbbbbbbbb6f6f633336f6f6336f6f63333336fbbbbbbbbbb
-- 127:bbbbbbbbbbbbb6f66fbbbbb6fbbbbbf66fbbbbb6fbbbbbf6f6f6fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f6fbbbbbf66fbbbbb6fbbbbbf66fbbbbb6f6fbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb333333bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6f66fbbbbb6fbbbbbf6f6f6fbbbbbbbbbbb
-- 128:5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b
-- 129:b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5
-- 130:5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b
-- 131:b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5
-- 132:5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b
-- 133:b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5
-- 134:5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b
-- 135:b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5
-- </SCREEN>

-- <PALETTE>
-- 000:140c1c44243430346d4e4a4e854c30346524d04648757161597dced27d2c8595a16daa2cd2aa996dc2cadad45edeeed6
-- </PALETTE>

