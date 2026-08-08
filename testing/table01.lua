player = {
  x=8, y=112,
  vx=0, vy=0,
  spr=1,
  suelo=false,
  saltos=1,
  coins=0,
  key=false,
  map_offset=0
}

function main()
	print(0, 0,  player.spr)
	print(0, 20, player.map_offset)
end
