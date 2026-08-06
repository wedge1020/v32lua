--#title "TIC80 default hello"
--#api tic80
--#texture sprites "textures/tic80hello_sprites.png"

t=0
x=96
y=24

function game_loop()

    if btn(0) then y=y-1 end
    if btn(1) then y=y+1 end
    if btn(2) then x=x-1 end
    if btn(3) then x=x+1 end

    cls(13)
    spr(1+t%60//30*2,x,y,14,3,0,0,2,2)
    print(84,84,"HELLO WORLD!")
    t=t+1
end
