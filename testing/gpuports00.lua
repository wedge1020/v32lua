current=0

function game_loop()
    current=ioports.gpu.texture
	value=4
	ioports.gpu.texture  = value
end
