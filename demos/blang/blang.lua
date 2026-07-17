--#title "BLANG!"
--#version "0.4"

function init()
    ioports.gpu.texture  = -1  -- set BIOS texture
    player               = { }
	player.r             = 94  -- region
    player.x             = 315 -- x position
    player.y             = 170 -- y position
    player.v             = 0   -- velocity

	-- enemy[]              = { }

    ioports.gpu.clear("black") -- initial clear screen

	-- draw player at initial position
	draw(player)
	-- ioports.region       = player.r   -- set region
    -- ioports.gpu.x        = player.x   -- set drawing point X
    -- ioports.gpu.y        = player.y   -- set drawing point Y
    -- ioports.gpu.draw()                -- draw region to screen
end

function draw(object)
	ioports.region       = object.r   -- set region
    ioports.gpu.x        = object.x   -- set drawing point X
    ioports.gpu.y        = object.y   -- set drawing point Y
    ioports.gpu.draw()                -- draw region to screen
end

function game_loop()
    buttonA = ioports.inp.A
    if (buttonA >  0) then
        player.v = 5
    else
        player.v = 1
        ioports.gpu.clear("black")
    end

    left = ioports.inp.left
    if (left >  0) then
        player.r = 60
        player.x = player.x - player.v
    end

    right = ioports.inp.right
    if (right >  0) then
        player.r = 62
        player.x = player.x + player.v
    end

    up = ioports.inp.up
    if (up >  0) then
		player.r = 94
        player.y = player.y - player.v
    end

    down = ioports.inp.down
    if (down >  0) then
		player.r = 86
        player.y = player.y + player.v
    end

	-- render player
	-- ioports.region = player.r
    -- ioports.gpu.x  = player.x
    -- ioports.gpu.y  = player.y
    -- ioports.gpu.draw()
	draw(player)
end
