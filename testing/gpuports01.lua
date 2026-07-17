BIOS = -1

function init()
    ioports.gpu.texture  = BIOS
	ioports.gpu.region   = 65
end

function game_loop()
	-- draw a capital A in the dead center of the screen
	ioports.gpu.x        = 315
	ioports.gpu.y        = 170
	ioports.gpu.draw()
end
