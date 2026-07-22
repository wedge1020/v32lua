--#title "pico-8 API spr() test"
--#texture sprites "textures/pico8apitest.png"
--#version "0.3"

player                          = { }
up                              = 0
down                            = 1
left                            = 2
right                           = 3
frames                          = 0

function init()
	local x                     = 0
	local y                     = 0

	--
	-- set the texture
	--
	ioports.gpu.texture         = sprites

	--
	-- start region_id at 0
	--
	region_id                   = 0

	--
	-- define all the textures on the 128x128 sprite sheet
	--
	row                         = 0
	while (row                 <  11) do
		col                     = 0
		while (col             <  16) do
			ioports.gpu.region  = region_id

			x                   = col * 8
			y                   = row * 8

			ioports.gpu.minX    = x
			ioports.gpu.hotX    = x
			ioports.gpu.minY    = y
			ioports.gpu.hotY    = y
			ioports.gpu.maxX    = x + 7
			ioports.gpu.maxY    = y + 7

			col                 = col + 1
			region_id           = region_id + 1
		end
		row                     = row + 1
	end

	player.tile                 = 80
	player.x                    = 316
	player.y                    = 176
	player.xflip                = false
	player.yflip                = false
end

function game_loop()

	--
	-- attempt some low quality animation
	--
	if (frames                 >= 30) and (secondframe == false) then
		player.tile             = player.tile + 1
		secondframe             = true
	else
		secondframe             = false
	end

	--
	-- clear the screen
	--
	ioports.gpu.clear ("black")

	--
	-- display our player (using spr()!)
	--
	ioports.gpu.region          = player.tile
	spr (player.tile, player.x, player.y, 1, 1, player.xflip, false)

	--
	-- input checks
	--
	if (btn (up, 0)) then
		player.tile             = 82
		player.y                = player.y - 1
		player.xflip            = false
		player.yflip            = false
	end

	if (btn (down, 0)) then
		player.tile             = 80
		player.y                = player.y + 1
		player.xflip            = false
		player.yflip            = false
	end

	if (btn (left, 0)) then
		player.tile             = 84
		player.x                = player.x - 1
		player.xflip            = false
		player.yflip            = false
	end

	state = btn(right,0)
	if (btn(right,0)) then
		player.tile             = 84
		player.x                = player.x + 1
		player.xflip            = true
		player.yflip            = false
	end

	--
	-- 60 frames a second
	--
	frames                      = (frames + 1) % 60

	if frames == 0 then
		player.tile             = player.tile + 2 
		if player.tile         >= 86 then
			player.tile         = 80
		end
	end

	print (0,     0,   "player.x: ")
	print (100,   0,   player.x)
	print (0,    20,   "player.y: ")
	print (100,  20,   player.y)
	print (0,    40,   "texture:  ")
	print (100,  40,   ioports.gpu.texture)
	print (0,    60,   "region:   ")
	print (100,  60,   ioports.gpu.region)
	print (0,    80,   "minX:     ")
	print (100,  80,   ioports.gpu.minX)
	print (0,   100,   "minY:     ")
	print (100, 100,   ioports.gpu.minY)
	print (0,   120,   "maxX:     ")
	print (100, 120,   ioports.gpu.maxX)
	print (0,   140,   "maxY:     ")
	print (100, 140,   ioports.gpu.maxY)
	print (0,   160,   "tile:     ")
	print (100, 160,   player.tile)
	print (0,   180,   "btn(up):  ")
	state = btn(up,0)
	print (100, 180,   state)
	print (0,   200,   "frames:   ")
	print (100, 200,   frames)
end
