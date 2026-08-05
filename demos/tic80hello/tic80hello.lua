--#title "TIC80 default hello"
--#api "tic80"
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
    spr(1,x,y,0,1,0,0,2,2)
    print("HELLO WORLD!",84,84)
    t=t+1
end
