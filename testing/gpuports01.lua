BIOS = -1

function main()
	-- draw a capital A in the dead center of the screen
    ioports.gpu.texture  = BIOS
	ioports.gpu.region   = 65
	ioports.gpu.X        = 315
	ioports.gpu.Y        = 170
	ioports.gpu.draw()

	__asm__("HLT")
end
