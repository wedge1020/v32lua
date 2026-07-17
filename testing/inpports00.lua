function game_loop()
	gpu.clear(black)
	left = ioports.inp.left
	if (left >  0) then
		print (0, 0, "up   ")
	end

	right = ioports.inp.right
	if (right >  0) then
		print (0, 0, "down ")
	end

	up = ioports.inp.up
	if (up >  0) then
		print (0, 0, "up   ")
	end

	down = ioports.inp.down
	if (down >  0) then
		print (0, 0, "down ")
	end

	start = ioports.inp.START
	if (start >  0) then
		print (0, 0, "start")
	end
end
