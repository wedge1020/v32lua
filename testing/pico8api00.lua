--#title "pico-8 API spr() test"
--#texture sprites "textures/pico8apitest.png"
--#version "0.3"

player                          = { }
up                              = 0
down                            = 0
left                            = 0
right                           = 0
frames                          = 0
adj                             = 0

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
	while (row                 <  16) do
		col                     = 0
		while (col             <  16) do
			ioports.gpu.region  = region_id

			x                   = (row * col) + (col * 8) -- left
			y                   = (row * col) + (row * 8) -- top

			ioports.gpu.minX    = x
			ioports.gpu.hotX    = x
			ioports.gpu.minY    = y
			ioports.gpu.hotY    = y
			ioports.gpu.maxX    = x + 7
			ioports.gpu.maxY    = y + 7
		end
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
	if (frames                 >= 30) then
		adj                     = 1
	else
		adj                     = 0
	end

	--
	-- clear the screen
	--
	ioports.gpu.clear ("black")

	--
	-- display our player (using spr()!)
	--
	spr (player.tile + adj, player.x, player.y, 1.0, 1.0, player.xflip, player.yflip)

	--
	-- input checks
	--
	if (btn (up)) then
		player.tile             = 82
		player.y                = player.y - 1
		player.xflip            = false
		player.yflip            = false
	end

	if (btn (down)) then
		player.tile             = 80
		player.y                = player.y + 1
		player.xflip            = false
		player.yflip            = false
	end

	if (btn (left)) then
		player.tile             = 84
		player.x                = player.x - 1
		player.xflip            = false
		player.yflip            = false
	end

	if (btn (right)) then
		player.tile             = 84
		player.x                = player.x + 1
		player.xflip            = true
		player.yflip            = false
	end

	--
	-- 60 frames a second
	--
	frames                      = (frames + 1) % 60
end
