--#api tic80
local seed=12345
local function rnd(n) seed=(seed*1103515245+12345)%2147483648 return seed%n end
local done=false
function TIC()
  if done then return end
  done=true
  for i=1,150 do
    local x1,y1,x2,y2,x3,y3
    local mode=i%5
    if mode==0 then
      x1,y1,x2,y2,x3,y3=rnd(300)-30,rnd(180)-20,rnd(300)-30,rnd(180)-20,rnd(300)-30,rnd(180)-20
    elseif mode==1 then
      x1,y1,x2,y2,x3,y3=rnd(240),rnd(136),rnd(240),rnd(136),rnd(240),rnd(136)
    elseif mode==2 then
      x1,y1,x2,y2,x3,y3=rnd(2400)/10,rnd(1360)/10,rnd(2400)/10,rnd(1360)/10,rnd(2400)/10,rnd(1360)/10
    elseif mode==3 then
      x1=rnd(240) y1=rnd(136) x2=x1+rnd(40) y2=y1 x3=x1+rnd(40) y3=y1+rnd(40)  -- flat edges
    else
      x1=rnd(240) y1=rnd(136) x2=x1 y2=y1+rnd(60) x3=x1+rnd(60)-30 y3=y2  -- vertical/horizontal edges
    end
    tri(x1,y1,x2,y2,x3,y3,i%16)
  end
end
