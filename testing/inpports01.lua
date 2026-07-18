--#title "inpports01 test of GPU+INP port access"
--#version "0.4"

function init()
	ioports.gpu.texture = -1
	x = 315
	y = 170
	ioports.gpu.clear("black")
	ioports.gpu.x = x
	ioports.gpu.y = y
	ioports.gpu.draw()
end

function game_loop()
	buttonA = ioports.inp.A
	if (buttonA >  0) then
		speed = 5
	else
		speed = 1
		ioports.gpu.clear("black")
	end

	left = ioports.inp.left
	if (left >  0) then
		ioports.gpu.region = 60
		x = x - speed
	end

	right = ioports.inp.right
	if (right >  0) then
		ioports.gpu.region = 62
		x = x + speed
	end

	up = ioports.inp.up
	if (up >  0) then
		ioports.gpu.region = 94
		y = y - speed
	end

	down = ioports.inp.down
	if (down >  0) then
		ioports.gpu.region = 86
		y = y + speed
	end

	ioports.gpu.x = x
	ioports.gpu.y = y
	ioports.gpu.draw()
end
