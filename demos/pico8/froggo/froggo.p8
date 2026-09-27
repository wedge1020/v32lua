pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- pico froggo
-- hop across the seasons
function _init()
	mode = "title"
	cam_x, cam_y = 0, 0
	--template object
	d_obj  = {x=64,    y=0,
											w=16,    h=16,
											osx=0,   osy=1, --offset x / y
											f_w=2, 	 f_h=2, --frame w / h
											x_v=0,   y_v=0,
											frame=1,
											grounded=0,
											name="",
										}
	timer = 0
	jump_pressed, x_pressed = false, false
	ani_frames = {52, 54, 52, 56, 60, 62}
	bell_frames = {118, 120, 118, 122}
	spin_frames = {{true, false}, {false, false}, {false, true}, {true, true}}
	
	cavern_pal = {[2]=3,  [3]=4,  [11]=4, [15]=9, [7]=15}
	summer_pal = {[2]=3,  [3]=4,  [11]=9}
	autmun_pal = {[3]=4,  [11]=9, [0]=128}
	winter_pal = {[3]=13, [11]=6}
	
	lvl = 0
	data = {{season=0, level=0, msc=0,  clr=12, bg=5, filter={8,78,110,111,126,127,15}},
	        {season=0, level=2, msc=10, clr=0,  bg=0, filter={108,109,125,230,231,232,233,107,28,14,15, 30}},
	        
	        {season=1, level=1, msc=0,  clr=1,  bg=0, filter={76,11}},
	        {season=1, level=0, msc=0,  clr=12, bg=3, filter={246,247,248,249,96,97,112,113,72,78,110,111,126,127,15,201,202,203,218,219}},
	        
	        {season=2, level=1, msc=20, clr=15, bg=1, filter={74,244,30}},
	        {season=2, level=2, msc=10, clr=0,  bg=4, filter={96,97,112,113,108,109,125,107,15,245,216,217}},
	        
	        {season=3, level=0, msc=20, clr=0,  bg=2, filter={8,246,247,248,249,96,97,112,113,72,201,202,203,218,219}},
	        {season=3, level=2, msc=10, clr=0,  bg=7, filter={26,96,97,112,113,230,231,232,233,14, 30,245,216,217}},
	       }
	title_bg = {6,2,3,5}
	title_init()
	txts = {"start of spring", "frisky flowery field",
								 " end of spring ", "venture in the cavern",
								 "start of summer", "tongue through the woods",
									" end of summer ", "ribbit in the beach",
									"start of autumn", "fallen golden leaves",
									" end of autumn ", "hop across the mushrooms",
									"start of winter", "snowball fight",
									" end of winter ", "dodge the deadly icicles",
								}
	grad_1 = {7, 6, 6, 12}
	grad_2 = {1, 5, 13, 12}
	end_txts = {"it's the end of the journey,",
	            "the end of the year",
	            
													"through spring and summer,",
												 "across autumn and winter",
												 
												 "froggo had much fun going",
												 "on this seasonal adventure",
													}
	hats = {{56, 48, 8},
									{72, 48, 8},
									{96, 113, 7},
									{96, 120, 8},
									}
	hat = 0
	cheat = 0
	pp_init()
	tr_timer, init = 32, true
end 

--flags
--solid, semisolid, hurt, grapple, _, _, _, object

function _update()
	--misc
	timer = (timer + 1)%3200
	--loop
	if mode == "title" then
		loop_title()
	elseif mode == "level" then
		loop_level()
	elseif mode == "end" then
		loop_end()
	end
	--variables
	jump_pressed = btn(🅾️)
	x_pressed = btn(❎)
	up_pressed = btn(⬆️)
	down_pressed = btn(⬇️)
	left_pressed = btn(⬅️)
	right_pressed = btn(➡️)

end

function _draw()
	if mode=="title" then
		draw_title()
	elseif mode == "level" then
		draw_level()
	elseif mode == "end" then
		draw_end()
	end
	if cheat == 12 then
		pal(11, 6, 1)
		pal(3, 5, 1)
	end
end

function loop_title()
	cam_x = (cam_x+1)%128
	camera(cam_x, 0)
	if not init and tr_timer < 32 then
		tr_timer += 1
		if tr_timer >= 32 then init = true end
	end
	if init then
		if btn(🅾️) and tr_timer == 32 then
			tr_timer -= 1
			music(-1)
			sfx(5)
		end
		if tr_timer < 32 then
			tr_timer -= 1
		end
		if tr_timer <= -8 then
			mode = "level"
			load_level(0)
			cam_x = 0
			tr_timer = -8
			camera(0, 0)
		end
	end
	--password
	if btn(❎) then
		if not x_pressed then
			password = ""
		end
		if #password < 8 then
			if btn(⬆️) and not up_pressed    then password = password.."⬆️" end
			if btn(⬇️) and not down_pressed  then password = password.."⬇️" end
			if btn(⬅️) and not left_pressed  then password = password.."⬅️" end
			if btn(➡️) and not right_pressed then password = password.."➡️" end
			cheat = 0
			if #password == 8 and cheat_list[password] != nil then
				cheat = cheat_list[password][1]
				sfx(2)
			end
		end
	end
	particles_update()
end

function loop_level()

	if player.alive and not goal and tr_timer < 32 then
		tr_timer += 2
		tr_x, tr_y = player.x+8-cam_x, player.y+4-cam_y
	end
	--player script
	player_movement(player)
	if player.alive then	move_obj(player) end
	if cheat != 11 then
		if player.x < 0 then player.x = 0 end
		if player.x > 1008 then player.x = 1008 end
		if player.y < level*128 then player.y = level*128 end
	end
	if player.y > level*128+128 then
		if cheat == 9 and player.alive then player.y -= 132
		elseif cheat == 10 and player.alive then player.y, player.grounded = level*128+128, 4
		elseif cheat == 11 and player.alive then 
			if player.y > 512 then player.y = 0 end
		else
			tr_timer -= 2
			tr_y = 128
			tr_x = 64
			if tr_timer > 0 and player.alive then
				sfx(6,3)
				player.alive = false
			end
			if tr_timer <= -16 then
				reload()
				load_level(lvl)
				tr_y = 64
			end
		end
	end
	if goal then
		tr_timer -= 2
		tr_x = player.x + 8 - cam_x
		tr_y = player.y + 4 - cam_y
		if tr_timer <= -16 then
			reload()
			cp, goal, init = false, false, true
			if lvl+1 == 8 then
				mode = "end"
				particles_init(0)
				particles_init(10)
				tr_x, tr_y, tr_timer = 64, 64, -16
				end_timer = 0
				for i=1, 3 do
					add(ptcs, {x=64, y=32*i-12, x_v=0, y_v=0, shape=13, grad=0, txt_1=end_txts[i*2-1], txt_2=end_txts[i*2], timer=72*i+32})
				end
				srand(stat(95))
				add(ptcs, {x=32, y=114, x_v=0, y_v=0, shape=13, grad=0, txt_1="❎ - "..hint_list[ceil(rnd(#hint_list))], txt_2="", timer=300})
				music(53)
			else
				load_level((lvl+1)%8)
			end
			tr_y = 64
		end
	end
	--camera
	cam_x = player.x-64+player.w/2
	if cheat == 11 then cam_y = player.y-64+player.h/2
	else
		if cam_x < 0 then cam_x = 0 end
		if cam_x > 896 then cam_x = 896 end
	end
	camera(cam_x, cam_y)
	--object update
	if tr_timer >= -16 then
		for obj in all(room) do
			if obj.hurt then enemy(obj) end
			if obj.t_hurt then t_enemy(obj) end
			if obj.physics then
				physics(obj)
				move_obj(obj)
			end
			if obj.name == "jim" then jim_update(obj) end
			if obj.name == "ant" then ant_update(obj) end
			if obj.name == "ball" then ball_update(obj) end
			if obj.name == "h_ball" then h_ball_update(obj) end
			if obj.name == "coin" then coin_update(obj) end
			if obj.name == "leaf" then leaf_update(obj) end
			if obj.name == "seagull" then seagull_update(obj) end
			if obj.name == "icicle" then icicle_update(obj) end
			if obj.name == "checkpoint" then checkpoint_update(obj) end
			if obj.name == "goal" then goal_update(obj) end
			if obj.name == "hat" then hat_update(obj) end
			if obj.y > 512 then del(room, obj) end
		end
	end
	particles_update()
end

function loop_end()
	cam_x, cam_y = 0, 0
	camera(cam_x, cam_y)
	if end_timer < 300 then
		end_timer += 1
		if tr_timer < 32 then tr_timer += 1 end
	else
		if ((btn(🅾️) or btn(❎)) and tr_timer == 32) or tr_timer < 32 then
			tr_timer -= 1
		end
		if tr_timer == -8 then
			mode = "title"
			title_init()
		end
	end
	particles_update()
end

function draw_title()
	if t_bg == 2 then
		cls(0)
	else
		cls(12)
	end
	draw_bg(t_bg)
	particles_draw()
	map(112, 48, cam_x, 0, 16, 8)
	for i=-1, 1 do
		for j =-1, 1 do
			print("hop across the seasons", cam_x+20+i, 66+j, 1)
		end
	end
	print("hop across the seasons", cam_x+20, 66, 11)

	if cheat != 0 then
		st = cheat_list[password][2]
		for i=-1, 1 do
			for j=-1, 1 do
				print(st, cam_x+64+i-#st*2, 80+j, 0)
			end
		end
		print(st, cam_x+64-#st*2, 80, 10)
	end
	if btn(❎) then
		print("❎ - ", cam_x+21, 97, 0)
		print("❎ - ", cam_x+22, 96, 7)
		print(password, cam_x+41, 97, 0)
		print(password, cam_x+42, 96, 7)
	elseif tr_timer != 32 and init then
		print("press 🅾️ to start!", cam_x+29, 97, 0)
		print("press 🅾️ to start!", cam_x+30, 96, 7+3*flr(timer/2%2))
	elseif timer % 32 < 16 then
		print("press 🅾️ to start!", cam_x+29, 97, 0)
		print("press 🅾️ to start!", cam_x+30, 96, 7)
	end
	
	--particles
	particles_draw()
end

function draw_level()
	cls(clr)
	palette()
	draw_bg(bg)
	if cheat == 11 then
		map(0, 0, 0, 0, 128, 128)
	else
		map(0, level*16, 0, level*128, 128, 16)
	end
	pal()
	--dark background for this specific level lmao
	if season == 2 and level == 2 then
		poke(0x5f10,128)
	end
	--draw objects
	for obj in all(room) do
		if obj.rotate then
			spr(obj.frame, obj.x+obj.osx, obj.y+obj.osy, obj.f_w, obj.f_h, spin_frames[flr(obj.x%32/8)+1][1], spin_frames[flr(obj.x%32/8)+1][2])
		elseif obj.name == "jim" then
			spr(obj.frame, obj.x+obj.osx, obj.y+obj.osy, 1, 2)
			spr(obj.frame, obj.x+obj.osx+8, obj.y+obj.osy, 1, 2, true)
			spr(obj.frame2, obj.x+obj.osx, obj.y+obj.osy+13, 1, 1)
			spr(obj.frame2, obj.x+obj.osx+8, obj.y+obj.osy+13, 1, 1, true)
		elseif obj.name == "ant" then
			if obj.hat > 0 then
				sspr(hats[obj.hat][1],hats[obj.hat][2],16,hats[obj.hat][3],obj.x+obj.osx,obj.y+obj.osy+6-hats[obj.hat][3],16,hats[obj.hat][3],obj.face_r, false)
			end
			spr(obj.frame, obj.x+obj.osx, obj.y+obj.osy, 2, 1, obj.face_r)
			spr(obj.frame2, obj.x+obj.osx, obj.y+obj.osy+8, 2, 1, obj.face_r)
		elseif obj.name == "ball" then
			spr(obj.frame, obj.x, obj.y, 1, 1)
			spr(obj.frame, obj.x+8, obj.y, 1, 1, true)
		elseif obj.four then
			spr(obj.frame, obj.x, obj.y, 1, 1)
			spr(obj.frame, obj.x+8, obj.y, 1, 1, true)
			spr(obj.frame, obj.x, obj.y+8, 1, 1, false, true)
			spr(obj.frame, obj.x+8, obj.y+8, 1, 1, true, true)
		elseif obj.name == "seagull" then
			spr(obj.frame, obj.x, obj.y, 2, 2)
			spr(obj.frame+2, obj.x-8, obj.y, 1, 1, true)
			spr(obj.frame+2, obj.x+16, obj.y, 1, 1)
		elseif obj.name == "goal" then
			spr(116, obj.x, obj.y, 2, 1)
			spr(obj.frame, obj.x, obj.y+8, 2, 1)
		elseif obj.name == "hat" then
			sspr(hats[obj.type][1],hats[obj.type][2],16,hats[obj.type][3],obj.x,obj.y)
		else
			spr(obj.frame, obj.x+obj.osx, obj.y+obj.osy, obj.f_w, obj.f_h, obj.face_r)
		end
	end
	
	--draw player
	if player.alive then
		if hat > 0 then
			sspr(hats[hat][1],hats[hat][2],16,hats[hat][3],player.x+player.osx,player.y+player.osy-1-hats[hat][3],16,hats[hat][3],player.face_r, false)
		end
		if player.t_timer > 0 then
			rectfill(player.x+8, player.y+1, player.t_x, player.y+3, 1)
		end
		if player.inv <= 0 or timer%2==1 then
			spr(player.frame_2, player.x, player.y-7+player.osy, 2, 1, player.face_r, false)
			spr(player.frame, player.x, player.y+1+player.osy, 2, 1, player.face_r, false)
		end
		--tongue
		if player.t_timer > 0 then
			rectfill(player.x+8, player.y+2, player.t_x, player.y+2, 8)
			spr(1, player.t_x-4, player.y)
			if player.t then
				spr(player.t.frame, player.t_x-8+player.t.osx, player.y-6+player.t.osy, player.t.f_w, player.t.f_h)
			end
		end
	else
		spr(16, player.x, player.y-7, 2, 2, false, true)
	end
	
	--ui
	if hp==2 then
			spr(18, cam_x+4, cam_y+4, 1, 2, false)
			spr(18, cam_x+12, cam_y+4, 1, 2, true)
	elseif hp==1 then
			spr(18, cam_x+4, cam_y+4, 1, 2, false)
			spr(19, cam_x+12, cam_y+4, 1, 2, true)
	else
			spr(19, cam_x+4, cam_y+4, 1, 2, false)
			spr(19, cam_x+12, cam_y+4, 1, 2, true)
	end
	--particles
	particles_draw()
end

function draw_end()
	cls(12)
	draw_bg(3)
	if end_timer >= 300 and timer % 32 < 16 then
		spr(41, 112, 112)
	end
	particles_draw()
end

function draw_bg(n)
	if n == 2 then
		pal(11,6,0)
		pal(3,13,0)
		map(56, 48+4*flr(timer%40*0.05), cam_x, cam_y+8, 8, 4)
		map(56, 48+4*flr(timer%40*0.05), cam_x+64, cam_y+8, 8, 4)
		for i=0, 3 do
			map(48, 53, cam_x+64*i-cam_x/2%64, cam_y+56, 8, 4)
		end
		rectfill(cam_x, cam_y+88,cam_x+128,cam_y+128,13)
		map(56, 56+4*flr(timer%40*0.05), cam_x, cam_y+88, 8, 4)
		map(56, 56+4*flr(timer%40*0.05), cam_x+64, cam_y+88, 8, 4)
		pal()
		palette()
		rectfill(cam_x, cam_y+80,cam_x+128,cam_y+80,6)
		rectfill(cam_x, cam_y+94,cam_x+128,cam_y+96,6)
		rectfill(cam_x, cam_y+102,cam_x+128,cam_y+102,6)
		rectfill(cam_x, cam_y+89,cam_x+128,cam_y+89,6)
		rectfill(cam_x, cam_y+112,cam_x+128,cam_y+112,6)
	elseif n == 3 then
		circfill(cam_x+16,cam_y+60,24+sin(timer/64)*2,7)
		circfill(cam_x+100,cam_y+64,28+sin(timer/60)*1.5,7)
		circfill(cam_x+48,cam_y+68,20+cos(timer/72)*2,7)
		rectfill(cam_x,cam_y+64,cam_x+128,cam_y+128,12)
		for i=0,16 do
			len = abs(sin(timer/128+i*0.19625)*(24-i)*2)
			line(cam_x+64-len,cam_y+i+64,cam_x+64+len,cam_y+i+64,7)
		end
	elseif n == 4 then
		pal(1, 2)
	elseif n == 5 then
		for i=0, 3 do
			map(48, 48, cam_x+64*i-cam_x/2%64, cam_y+16, 8, 5)
		end
		for i=0, 3 do
			map(48, 53, cam_x+64*i-cam_x/2%64, cam_y+64, 8, 2)
		end
		for i=0,8 do
			len = abs(sin(timer/128+i*0.19625)*(24-i)*2)
			line(cam_x+64-len,cam_y+i+80,cam_x+64+len,cam_y+i+80,7)
		end
	elseif n == 6 then
		pal(11,9,0)
		pal(3,4,0)
		pal(1,2,0)
		for i=0, 3 do
			map(48, 48, cam_x+64*i-cam_x/2%64, cam_y+16, 8, 5)
		end
		for i=0, 3 do
			map(48, 53, cam_x+64*i-cam_x/2%64, cam_y+64, 8, 2)
		end
		pal()
		for i=0,8 do
			len = abs(sin(timer/128+i*0.19625)*(24-i)*2)
			line(cam_x+64-len,cam_y+i+80,cam_x+64+len,cam_y+i+80,7)
		end
	elseif n == 7 then
		for i=0, 2 do
			map(56, 48+4*flr(timer%40*0.05), cam_x+64*i-cam_x/2%64, cam_y+24, 8, 4)
		end
		for i=0, 2 do
			map(56, 56+4*flr(timer%40*0.05), cam_x+64*i-cam_x/2%64, cam_y+72, 8, 4)
		end
	end
end

function title_init()
	srand(stat(95))
	t_bg = title_bg[flr(rnd(4))+1]
	particles_init(t_bg)
	particles_init(10)
	music(55)
	tr_x, tr_y, tr_timer = 64, 64, -16
	goal, cp, init = false, false, false
end
-->8
--functions
--collision
function move_obj(obj)
	local t1, t2, dx, dy
	
	if obj.grounded > 0 then obj.grounded -= 1 end
	
	--horizontal collision
	if obj.x_v >= 0 then dx=(obj.x+obj.w+obj.x_v)/8
	elseif obj.x_v < 0 then dx=(obj.x+obj.x_v)/8 end
	dy=(obj.y)/8
	
	--semi solid (ghost mode)
	if cheat == 6 and obj.name=="player" then
		t1 = mget(dx, dy)
		if fget(t1, 0) and obj.y_v >= 2 then
			if obj.name == "player" and obj.y_v > 0 and obj.grounded == 0 then sfx(8, 3) end
			obj.grounded, obj.y_v = 4, 0
		end
	--regular
	elseif (dy >= level*16 and dy <= level*16+16) or cheat == 11 then
	
		t1, t2 = mget(dx, dy), mget(dx, dy+obj.h/8)
		
		if (fget(t1, 0) or fget(t2, 0)) and obj.x_v != 0 then
			if obj.x_v > 0 then
				obj.x = dx*8-obj.w-obj.x_v
				obj.hit_r = true
			elseif obj.x_v < 0 then
				obj.x = dx*8-obj.x_v
				obj.hit_l = true
			end
			obj.x_v = 0
		end
		if obj.name=="player" and obj.inv <= 0 and (fget(t1, 2) or fget(t2, 2)) then
			hurt_player()
		end
	
	end
	
	--vertical collision
	dx=(obj.x)/8
	if obj.y_v >= 0 then dy=(obj.y+obj.h+obj.y_v)/8
	elseif obj.y_v < 0 then dy=(obj.y+obj.y_v)/8 end
	
	if (dy >= level*16 and dy <= level*16+16) or cheat == 11 then
	
		t1, t2 = mget(dx, dy), mget(dx+obj.w/8, dy)
		
		if (fget(t1, 0) or fget(t2, 0)) and obj.y_v != 0 and dy <= level*16+16 and dy >= level*16 then
			if obj.y_v > 0 then
				obj.y = flr(dy)*8-obj.h
				if obj.name == "player" and obj.y_v > 2 and obj.grounded == 0 then sfx(8, 3) end
				obj.grounded = 4
				obj.y_v = -0.5
				if fget(t1, 5) or fget(t2, 5) then obj.ice = 4 end
			elseif obj.y_v < 0 then
				obj.y = dy*8-obj.y_v
				obj.y_v = 0
			else
				obj.y_v = 0
			end
	
	--semi solid
		elseif (fget(t1, 1) or fget(t2, 1)) and obj.y_v >= 0 then
			if obj.name == "player" and obj.y_v > 2 and obj.grounded == 0 then sfx(8, 3) end
			obj.y, obj.grounded, obj.y_v = flr(dy)*8-obj.h, 4, -0.5
		end
		
		if obj.name=="player" and obj.inv <= 0 and (fget(t1, 2) or fget(t2, 2)) then
			hurt_player()
		end
	end
	
	--platform objects
	for plt in all(room) do
		if plt.platform and obj.y_v >= 0 and obj.y+obj.h-obj.y_v <= plt.y+4 and collide(obj, plt) then
			obj.y, obj.grounded, obj.y_v = plt.y+plt.y_v-obj.h, 4, 0
			obj.x += plt.x_v
		end
	end
		
	--ant edge detection
	if obj.name == "ant" then
		if fget(t1, 0) or fget(t1, 1) then obj.feet.l = true end
		if fget(t2, 0) or fget(t2, 1) then obj.feet.r = true end
	end
	
	obj.x += obj.x_v
	obj.y += obj.y_v
	
end

--entity collision
function collide(a, b)
	return a.x <= b.x+b.w and a.y <= b.y + b.h and b.x <= a.x+a.w and b.y <= a.y + a.h
end
function t_collide(a)
	return a.y <= player.y + player.h and player.y <= a.y + a.h and abs(player.t_x - a.x - a.w/2) < 8 and player.t_timer > 0
end
--enemy hit
function hurt_player()
	player.inv = 60
	hp -= 1
	if hp <= 0 or cheat == 1 then
		player.alive = false
		player.y_v = -6
	end
	sfx(6,3)
end
function enemy(a)
	if player.inv <= 0 and a.x <= player.x+player.w and a.y <= player.y + player.h and player.x <= a.x+a.w and player.y <= a.y + a.h then
		hurt_player()
	end
end
function t_enemy(a)
	if not player.t and player.inv <= 0 and a.y <= player.y + player.h and player.y <= a.y + a.h and abs(player.t_x - a.x - a.w/2) < 8 and player.t_timer > 0 then
		hurt_player()
	end
end

--object creation
function create_obj(id, x, y)
	local obj = {}
	for key, value in pairs(d_obj) do
		obj[key] = value
	end
	obj.x, obj.y, obj.frame = x*8, y*8, id
	--player
	if id == 48 then
		obj.y -= 1
		obj.name, obj.w, obj.h, obj.face_r, obj.frame, obj.frame_2, obj.t_pos, obj.t_x, obj.t_timer, obj.s_timer, obj.t, obj.climb, obj.inv, obj.alive, obj.climb_cooldown, obj.ice = "player", 14, 8, true, 52, 48, 0, 0, 0, 0, nil, false, 0, true, 0, 0
	--coin
	elseif id == 64 then
		obj.name, obj.osy = "coin", 0
	--jim
	elseif id == 26 then
		obj.y += 7
		obj.x += 4
		obj.w, obj.h, obj.timer, obj.osx, obj.osy, obj.name, obj.physics, obj.hurt, obj.t_hurt = 8, 8, 0, -4, -7, "jim", true, true, true
	--ant
	elseif id == 28 or id == 30 then
		obj.y += 7
		obj.x += 4
		obj.feet = {l=false, r=false}
		if ceil(rnd(8)) == 4 then
			obj.hat = season+1
		elseif cheat == 13 then
			obj.hat = ceil(rnd(4))
		else
			obj.hat = 0
		end
		obj.w, obj.h, obj.timer, obj.osx, obj.osy, obj.step, obj.name, obj.physics, obj.hurt, obj.edible, obj.face_r = 8, 8, 0, -4, -7, 0, "ant", true, true, true, false
	--ball
	elseif id == 14 or id == 15 then
		obj.name = "ball"
	--leaf
	elseif id == 11 then	
		obj.init, obj.name, obj.osx, obj.osy, obj.w, obj.h, obj.platform, obj.f_w, obj.f_h = false, "leaf", 4, -4, 32, 8, true, 3, 1
	--seagull
	elseif id == 8 then
		obj.name, obj.o_x, obj.y, obj.w, obj.h, obj.platform, obj.y_v = "seagull", obj.x, level*128-16, 32, 8, true, 4
	--icicles
	elseif id == 108 then
		obj.name, obj.f_w, obj.f_h, obj.hurt = "icicle", 1, 2, true
	--checkpoint
	elseif id == 98 then
		obj.name, obj.frame, obj.spawn = "checkpoint", -2, true
	--goal
	elseif id == 116 then
		obj.name, obj.timer, obj.rung, obj.m = "goal", 150, false, false
	--hat
	elseif id <= 106 and id >= 103 then
		obj.name, obj.type, obj.physics, obj.h, obj.physics = "hat", id-102, true, 8, true
	end
	--movable platform objects
	if 70 < id and id < 80 then
		obj.x += 3
		obj.frame = 72 + season * 2
		obj.name, obj.platform, obj.edible, obj.s, obj.rotate, obj.physics, obj.osx, obj.w = "plt", true, true, true, true, true, -3, 10
		if id == 78 then obj.rotate = false end
	end
	
	return obj
end
--particles
function particles_init(n)
	//leaf
	if n == 1 or n == 6 then
		ptcs = {}
		for i = 0, 10 do
			add(ptcs, {x=rnd(128), y=rnd(128), x_v=-0.25*rnd(3)-0.25, y_v=0.25*rnd(3)+0.25, shape=0, clr=4+flr(rnd(2))*5, size=rnd(2)*0.5+1})
		end
	//snow
	elseif n == 2 then
		ptcs = {}
		for i = 0, 10 do
			add(ptcs, {x=rnd(128), y=rnd(128), x_v=-0.25*rnd(3)-0.25, y_v=0.25*rnd(3)+0.25, shape=1, clr=6+rnd(2), size=rnd(4)*0.5+0.5})
		end
	//transition bubble
	elseif n == 10 then
		for i = -1, 5 do
			for j = -1, 10 do
				add(ptcs, {x=j*16, y=i*32, x_v=0, y_v=0, shape=2, clr=0, size=0})
			end
			for j = -1, 10 do
				add(ptcs, {x=j*16-8, y=i*32+16, x_v=0, y_v=0, shape=2, clr=0, size=0})
			end
		end
	//clear
	else
		ptcs = {}
	end
end
--level load
function load_level(lv)
	lvl = lv
	--< properties >--
	season = data[lvl+1].season
	level = data[lvl+1].level
	clr = data[lvl+1].clr
	bg = data[lvl+1].bg
	
	if cheat > 1 and cheat < 6 then season = cheat-2 end
	
	--< particles >--
	particles_init(bg)
	particles_init(10)
	tr_x, tr_y, tr_timer = 64, 64, -16

	--< generate level >--
	cam_y = level*128
	room = {}
	if init or stat(54)==63 then
		music(data[lvl+1].msc)
	end
	if init then
		init = false
		add(ptcs, {x=-64, y=48, x_v=0, y_v=0, shape=11, clr=7, txt=txts[lvl*2+1], timer=32})
		add(ptcs, {x=192, y=64, x_v=0, y_v=0, shape=12, clr=7, txt=txts[lvl*2+2], timer=32})
	end
	hp, coin = 2, 0
	srand(stat(95))
	--generate tiles
	for x=0, 128 do
		for y=level*16, level*16+15 do
			tle = mget(x, y)
			if cheat != 8 then
				for i in all(data[lvl+1].filter) do
					if i == tle then
						mset(x, y, 0)
						tle = -1
					end
				end
			end
			if fget(tle, 7) then
				if tle == 48 then
					player = create_obj(48, x, y)
					mset(x, y, 0)
				else
					add(room, create_obj(tle, x, y))
					mset(x, y, 0)
				end
			end
			if tle == 240 then mset(x, y, tle + season) end
		end
	end
	srand(69)
	tr_x, tr_y = player.x+8, player.y
end

function palette()
	if     season == 3 then pal(winter_pal, 0)
	elseif season == 2 then pal(autmun_pal, 0)
	elseif level  == 2 then pal(cavern_pal, 0)
	elseif season == 1 then pal(summer_pal, 0)
	end
end

function particles_update()
	for p in all(ptcs) do
		p.x += p.x_v
		--transition bubbles
		if p.shape == 2 then
			p.size = (((tr_x-p.x)^2+(tr_y-p.y)^2)^0.5 - tr_timer * 4) / 4
			if p.size < 0 then p.size = 0 end
			if p.size > 20 then p.size = 20 end
		--intro text
		elseif p.shape == 11 then
			if p.x < 64 then p.x += (64-p.x)/8 else p.timer -= 1 end
			if p.x > 192 then del(ptcs, p) end
			if abs(p.x - 64) < 0.5 then p.x = 64 end
			if p.timer <= 0 then
				p.x_v += 0.4
				player.paused = false
			else
				tr_timer = -16
				player.paused = true
			end
		--intro text
		elseif p.shape == 12 then
			if p.x > 64 then p.x += (64-p.x)/8 else p.timer -= 1 end
			if p.x < -64 then del(ptcs, p) end
			if abs(p.x - 64) < 0.5 then p.x = 64 end
			if p.timer <= 0 then p.x_v -= 0.4 end
		--ending text
		elseif p.shape == 13 then
			if end_timer < 300 then
				if p.timer > 0 then p.timer -= 1 end
			elseif tr_timer < 32 then
				if p.timer < 39 then p.timer += 2 end
			end
			if p.timer < 40 then p.grad = flr(p.timer/10)+1 end
		else
			if p.x < cam_x then p.x += 128 end
			if p.x > cam_x + 128 then p.x -= 128 end
			p.y = (p.y + p.y_v) % 128
		end
	end
end

function particles_draw()
	for p in all(ptcs) do
		if p.shape == 0 then
			x, y = p.x, cam_y+p.y
			rectfill(x,y,x+p.size,y+p.size,p.clr)
		elseif p.shape == 1 then
			x, y = p.x, cam_y+p.y
			circfill(x,y,p.size,p.clr)
		elseif p.shape == 2 and p.size > 0 then
			x, y = cam_x+p.x, cam_y+p.y
			circfill(x,y,p.size,p.clr)
		elseif p.shape == 11 or p.shape == 12 then
			x, y = cam_x+p.x, cam_y+p.y
			print(p.txt, x-#p.txt*2-1, y+1, 1)
			print(p.txt, x-#p.txt*2, y, p.clr)
		elseif p.shape == 13 and p.grad > 0 and p.grad <= 3 then
			x, y = cam_x+p.x, cam_y+p.y
			for i=-1,1 do
				for j=-1,1 do
					print(p.txt_1, x-#p.txt_1*2+i, y+j, grad_2[p.grad])
				end
			end
			print(p.txt_1, x-#p.txt_1*2, y, grad_1[p.grad])
			for i=-1,1 do
				for j=-1,1 do
					print(p.txt_2, x-#p.txt_2*2+i, y+j+10, grad_2[p.grad])
				end
			end
			print(p.txt_2, x-#p.txt_2*2, y+10, grad_1[p.grad])
		end
	end
end

function pp_init()
	cheat_list = {["⬆️⬆️⬇️⬇️⬅️⬅️➡️➡️"]={1,"hard mode"},--
															["⬆️⬇️⬆️⬇️⬅️⬅️⬅️⬅️"]={2,"spring mode"},--
															["⬆️⬇️⬆️⬇️➡️⬆️⬇️⬅️"]={3,"summer mode"},--
															["⬆️⬇️⬆️⬇️⬆️⬅️⬅️➡️"]={4,"autumn mode"},--
															["⬆️⬇️⬆️⬇️⬇️⬇️⬅️➡️"]={5,"winter mode"},--
															["⬅️⬅️➡️➡️⬆️⬅️➡️⬅️"]={6,"frogghost's adventure"},--
															["⬆️⬆️⬆️⬇️⬆️⬅️⬆️➡️"]={7,"infinite jump"},--
															["⬆️➡️⬅️⬅️➡️⬇️⬆️⬇️"]={8,"filter's day off"},--
															["➡️⬆️⬇️⬆️⬇️⬆️⬇️⬅️"]={9,"wrap around"},--
															["⬇️⬅️➡️⬆️⬅️⬇️➡️⬆️"]={10,"eater of worlds: froggo"},--
															["⬅️➡️⬅️➡️⬇️⬅️⬇️➡️"]={11,"free cam"},--
															["⬆️⬅️⬅️⬅️➡️➡️➡️⬇️"]={12,"green is not a creative color"},--
															["⬆️⬇️⬅️⬅️⬅️⬆️➡️⬇️"]={13,"h.a.t.s."},--
															}
	hint_list = {"⬆️⬇️⬆️⬇️⬅️⬅️⬅️⬅️",--
														"⬆️⬇️⬆️⬇️➡️⬆️⬇️⬅️",--
														"⬆️⬇️⬆️⬇️⬆️⬅️⬅️➡️",--
														"⬆️⬇️⬆️⬇️⬇️⬇️⬅️➡️",--
														"⬅️⬅️➡️➡️⬆️⬅️➡️⬅️",--
														"⬆️⬆️⬆️⬇️⬆️⬅️⬆️➡️",--
														"⬆️➡️⬅️⬅️➡️⬇️⬆️⬇️",--
														"➡️⬆️⬇️⬆️⬇️⬆️⬇️⬅️",--
														"⬇️⬅️➡️⬆️⬅️⬇️➡️⬆️",--
														"⬅️➡️⬅️➡️⬇️⬅️⬇️➡️",--
														"⬆️⬇️⬅️⬅️⬅️⬆️➡️⬇️",--
														}
end
-->8
--entities
--player movement
function player_movement()
	----horizontal movement
	player.frame = 52
	--walk animation
	if btn(⬅️) or btn(➡️) then
		if not player.paused then player.frame = ani_frames[flr(timer%12/3)+1] end
	end
	--movement
	if player.climb then player.x_v = 0
	elseif btn(⬅️) and not player.paused and player.x_v > -1.6 then
		player.x_v -= 0.4
		if player.t_timer <= 0 then player.face_r = false end
	elseif btn(➡️) and not player.paused and player.x_v < 1.6 then
	 player.x_v += 0.4
		if player.t_timer <= 0 and not btn(⬅️) then player.face_r = true end
	elseif player.x_v < 0 and player.ice == 0 then
	 player.x_v += 0.4
	elseif player.x_v > 0 and player.ice == 0 then
	 player.x_v -= 0.4
	end
	--grounded
	if player.climb_cooldown > 0 then
		player.climb_cooldown -= 1
	end
	if player.grounded > 0 then
		player.grounded -= 1
	elseif not player.t then
		player.frame = 54
	end
	----jump
	if btn(🅾️) and not player.paused and (player.grounded > 0 or (player.climb and player.t_timer <= 0) or cheat == 7) then
		player.y_v, player.grounded, player.climb, player.climb_cooldown = -6, 0, false, 4
		sfx(0, 3)
	end
	if not btn(🅾️) and jump_pressed and player.y_v < 0 then
		player.y_v *= 0.5
	end
	--gravity
	if player.y_v < 8 and not player.climb then player.y_v += 0.5 end
	----tongue
	if player.s_timer > 0 then
		player.s_timer -= 1
		player.frame = 58
	end
	if player.t_timer > 0 then
		player.t_timer -= 1
		player.t_pos, player.frame = sin(player.t_timer/30)*48, 58
		--catch objects
		for obj in all(room) do
			if not player.t and obj.edible and t_collide(obj) then
				if obj.hat != nil and obj.hat > 0 then add(room, create_obj(obj.hat+102, obj.x/8, obj.y/8-1)) end
				player.t = obj
				del(room, obj)
			end
		end
		--grapple
		for i=-1, 1 do
			for j=-1, 1 do
				if player.climb_cooldown <=0 and fget(mget(player.t_x/8+i, player.y/8+j), 3) then
					player.x, player.y = flr(player.t_x/8+i)*8-8, flr(player.y/8+j)*8
					if player.face_r then player.x += player.t_pos else player.x -= player.t_pos end
					player.y_v, player.climb = 0, true
				end
			end
		end
		--eater of worlds
		if cheat == 10 then
			mset(player.t_x/8, player.y/8, 0)
			mset(player.t_x/8, player.y/8+1, 0)
		end
	end
	--spit tongue
	if player.t_timer <= 0 and player.s_timer <= 0 and btn(❎) and not x_pressed and not player.paused then
		if player.t then
		 if player.t.name == "plt" then
				player.t.x, player.t.y, player.t.x_v, player.s_timer = player.x, player.y-10, -5, 4
				if player.face_r then player.t.x_v *= -1 end
				add(room, player.t)
				sfx(7,3)
			else
				sfx(3,3)
			end
			player.t = nil
		else
			player.t_timer, player.t_pos = 15, 0
			sfx(1,3)
		end
	end
	--tongue position
	if player.face_r then
		player.t_x = player.x+8-player.t_pos
	else
		player.t_x = player.x+8+player.t_pos
	end
	--thicc walk
	if player.t and player.t_timer <= 0 then
		player.frame = ani_frames[flr(player.x%8/4)+5]
		player.frame_2 = 50
	else
		player.frame_2 = 48
	end
	--invincibility frames
	if player.inv > 0 then player.inv -= 1 end
	--dying
	if not player.alive then
		player.x_v = 2
		if player.face_r then player.x_v = -2 end
		if player.y > 128+level*128 then player.x_v = 0 end
		player.x += player.x_v
		player.y += player.y_v
	end
	--bop
	if player.frame == 54 or player.frame == 56 then
		player.osy = -1
	else
		player.osy = 0
	end
	if player.ice > 0 then player.ice -= 1 end
end

----object updates
--physics
function physics(obj)
	--grounded
	if obj.grounded > 0 then
		obj.grounded -= 1
		--friction
		if obj.x_v < 0 then
		 obj.x_v += 0.4
		elseif obj.x_v > 0 then
		 obj.x_v -= 0.4
		end
		if abs(obj.x_v) < 0.4 then obj.x_v = 0 end
	end
	--gravity
	if obj.y_v < 8 then obj.y_v += 0.5 end
	
end
--coin
function coin_update(obj)
	if obj.dead then
		obj.timer -= 1
		obj.frame = obj.timer+1
		if obj.timer <= 0 then del(room, obj) end
	else
		obj.frame = 64+flr(timer%16/4)*2
		if collide(obj, player) or t_collide(obj) then
			obj.dead, obj.four, obj.timer = true, true, 3
			sfx(2,3)
		end
	end
end
--hat
function hat_update(obj)
	if collide(obj, player) then
		hat = obj.type
		del(room, obj)
	end
end
--jim
function jim_update(obj)
	obj.timer = (obj.timer+1)%3200
	if obj.timer % 60 == 0 and obj.grounded >= 0 then obj.y_v = -7 end
	if obj.timer % 30 == 0 and obj.grounded >= 0 and cheat == 1 then obj.y_v = -7 end
	if obj.grounded <= 0 then obj.frame2 = 43 else obj.frame2 = 27 end
end
--ant
function ant_update(obj)
	--roam mode
	if obj.step == 0 then
		if cheat == 1 then
			if obj.face_r then obj.x_v = 2 else obj.x_v = -2 end
		else
			if obj.face_r then obj.x_v = 1.5 else obj.x_v = -1.5 end
		end
		if not obj.feet.l and obj.feet.r and not obj.face_r then obj.face_r = true end
		if obj.feet.l and not obj.feet.r and obj.face_r then obj.face_r = false end
		if obj.hit_l then obj.face_r = true end
		if obj.hit_r then obj.face_r = false end
		obj.frame, obj.frame2 = 28, 44+flr(timer%8/4)*2
	--yeet mode
	elseif obj.step == 1 then
	 obj.frame, obj.frame2 = 30, 44
		obj.x_v, obj.ball.y_v = 0, 0
		if obj.timer < 24 then obj.timer += 3
		else
			if player.x+player.w/2 > obj.x+obj.w/2 then obj.face_r = true else obj.face_r = false end
			--yeet when player is close
			if abs(player.x+4 - obj.x) <= 48 then
				obj.ball.y_v, obj.ball.physics = -5, true
				if obj.face_r then obj.ball.x_v = 2 else obj.ball.x_v = -2 end
				obj.step = 0
				sfx(7,3)
			end
		end
		obj.ball.x, obj.ball.y = obj.x-4, obj.y-obj.timer
	end
	obj.hit_r, obj.hit_l, obj.feet.l, obj.feet.r = false, false, false, false
end
--ball
function ball_update(obj)
 if abs(player.x - obj.x) < 64 then
		for ant in all(room) do
		 if collide(ant, obj) and ant.name == "ant" and ant.step == 0 then
		 	obj.name, obj.hurt, obj.four = "h_ball", true, true
		 	ant.step, ant.timer, ant.ball = 1, 0, obj
		 end
		end
	end
end
--thrown ball
function h_ball_update(obj)
	if not obj.physics then
		obj.y_v += 0.5
		obj.y += obj.y_v
	elseif obj.grounded > 0 then
		sfx(8, 3)
		obj.hurt, obj.physics, obj.y_v = false, false, -3
	end
end
--leaf
function leaf_update(obj)
	if not obj.init then 
		if flr(rnd(2)) == 1 then
			obj.face_r = true
		else
			obj.face_r = false
		end
		obj.init = true
	end
	if obj.face_r then
		obj.x_v = sin(timer*0.03)
	else
		obj.x_v = cos(timer*0.03)
	end
	obj.y_v = 0.5
	obj.y += obj.y_v
	obj.x += obj.x_v
	if obj.y > level*128+128 then obj.y = level*128 end
end
--seagull
function seagull_update(obj)
 if obj.x < player.x + 96 then
		obj.x_v = -1.5
		obj.y_v -= 0.1
		obj.x += obj.x_v
		obj.y += obj.y_v
		if obj.y < level*128-16 then
			obj.x = obj.o_x
			obj.y_v = 4
		end
	end
end
--icicle
function icicle_update(obj)
	if abs(player.x-obj.x) < 32 and obj.y_v == 0 then obj.osx = rnd(4)-2 else obj.osx = 0 end
	if abs(player.x-obj.x) < 20 then
		if obj.y_v == 0 then sfx(7, 3) end
		obj.osx, obj.y_v = 0, 4
	end
	obj.y += obj.y_v
end
--checkpoint
function checkpoint_update(obj)
	if obj.spawn then
		if cp then
			obj.spawn = false
			player.x, player.y = obj.x, obj.y+7
			del(room, obj)
		else
			obj.spawn = false
		end
	else
		if not cp and player.x > obj.x then
			cp = true
			del(room, obj)
		end
	end
end
--
function goal_update(obj)
	if obj.rung then
		if obj.timer == 30 then
			sfx(3)
		elseif obj.timer < 30 then
			player.frame, player.frame_2 = 114, 98
		end
		if not obj.music and obj.timer < 120 then
			obj.music = true
			music(63)
		end
	 if obj.timer > 0 then obj.timer -= 1 end
		if obj.timer <= 0 then
			goal = true
		end
		obj.frame = bell_frames[flr(timer%12/3)+1]
	else
		if collide(obj, player) or t_collide(obj, player) then
			obj.rung = true
			obj.frame = 2
			player.paused = true
			music(-1)
			sfx(4)
		end
		obj.frame = 118
	end
end
__gfx__
00000000001111000000009f000000ff000000000000000000000000000100000000111111000000011111100000000000000111000110000000002900000011
000000000177881000000000000f9000000009ff00000000000100000006000011117777771000111777771000000000000112441111011000002911000011dd
007007000178881000f0000000f000000009ff77000100000016100000171000771717717771117776661100110000000012499494111221000911440001dd66
0007700001888810000000000f000000009ff70700161000016761001677761011111171777677666611000014100000114949994991442100214444001d6666
00077000001111000000000009007f0000ff000700010000001610000017100019994417777766161100000012411111249994aa991442210914449901d66677
0070070000000000000000000000f77f09f700f7000000000001000000060000011111177777766100000000012214999949aa94144422100214499901d66777
00000000000000009000000ff00007770f700f77000000000000000000010000001777777777766100000000001122149a99491444221000914499991d667777
0000000000000000f00000f7f0000f770f777777000000000000000000000000001777777777666100000000000011111141122210000000214499991d667777
000000000000000000000000000000000003333333333000333333331bbbbb730016777777766661000000270000000000000220000000000022222000222222
000011100111000000000000000000000037777777777300777777731bbbbbb70001666666666610220000270249942000220002000000000022994200299992
00017771177710000000011000000110037bbbbbbbbbb730bbbbbb731bbbbbbb0000166666666100272202670222222000002002000000000002242200029920
001b717bb717b100000013300000100037bbbbbbbbbbbb73bbbbbbb31bbbbbbb0000011111111410277622660000000000022222220000000002222222029200
01bb777bb777bb10000133b0000100003bbbbbbbbbbbbbb3bbbbbbb11bbbbbbb0000000199119910026662220000000000299999992000000029999999229200
1bbbbbbbbbbbbbb100013be0000100203bbbbbb11bbbbbb3333333311bbbbbb30000000011101110022624220000000002779779999200000277977999929200
1bbb11111111bbb10013be7e001002021bbbbb1111bbbbb1111111111bbbbb310000000000000000022249990000000027277277999920002727727799929200
1bb1ffffffff1bb10013beee001002001bbbbb1001bbbbb1000000001bbbbb100000000000000000024999990000000027277277999920002727727799929200
1b1bffffffffb1b10013b8ee001002001bbbbb1001bbbbb11bbbbb1003bbbbb13333333001111000249922220000000027277277999922002727727799992200
1b111ffffff111b100133b8e001000201bbbbb7117bbbbb11bbbbb1037bbbbb13777777311771111244267770002222229779779999922202977977999992220
01fff1bffb1fff10000133b8000100021bbbbbb77bbbbbb11bbbbb107bbbbbb137bbbbb717771171222622220024442202999999999222220299999999922222
01fbbb1bb1bbbf1000011333000110001bbbbbbbbbbbbbb11bbbbb10bbbbbbb13bbbbbbb17771771266277220029942000299999992222220029999999279222
01bbbb1111bbbb10000011330000110013bbbbbbbbbbbb311bbbbb10bbbbbbb113bbbbbb17777771022222720029942000022222222792220002222222799922
001bbb1001bbb1000000001100000011013bbbbbbbbbb3101bbbbb10bbbbbbb1013bbbbb17777771002222220024920000000024427999220000002442999922
000111000011100000000000000000000013333333333100133333103bbbbbb10013333311777711000022220002200000000022229999200000002992222220
0000000000000000000000000000000000011111111110001111111013bbbbb10001111101111110000000000000000000000000022222200000002222220000
0000000000000000000011101110000011fffffff1bbbbb111fffffff1bbbbb111fffffff1bbbbb11111111881bbbbb11ffffffffff1bbb11ffffffffff1bbb1
000000000000000000017b117bb100001fffffffff1bbbb11fffffffff1bbbb11fffffffff1bbbb111111188881bbbb11ffffffffff1bbb11ffffffffff1bbb1
0000111011100000001b1bbb1bbb10001bfffffffff1bb111111fffffff1bb111bfffff111f1bb11111111888811bb111bfffffffff1bb111bfffffffff1bb11
00017b117bb1000001bb1bbb1bbbb10001bfffffffb1b1101ffb1fffffb1b11101bfff1ffb11b1100111111111b1b11001bfffffffb1b11001bfffffffb1b110
001b1bbb1bbb10001bbbbbbbbbbbbb10001bbbbbbb1111001bbbb1bbbb111111001bbb1bbbb11100001bfffffb111110001bbbbbbb111100001bbbbbbb111100
01bb1bbb1bbbb1001b1111111bbbbbb1000111111111b1001bbbb111111111b10001111bbbb110000001111111111b10000111111bfb1100001bfb111111b100
1bbbbbbbbbbbbb1011fffffff1bbbbb1001bfb111bfb110001bbb100001bbb1000001bb1bbb1000000001bbb11bbb100001bfb1111111000001111111bfb1100
1b1111111bbbbbb11fffffffff1bbbb1001111101111100000111000000111000000011111100000000001110011100000111110000000000000000011111000
00000022220000000000002222000000000000222200000000000022220000000000001111111100000002222000000000000222220000000001111111111000
00002277772200000000027777200000000002777720000000000277772000000000117ccc796910000028888220000000002444442202200001d66666dd1000
000277aaaa77200000002777aa720000000002a777200000000027aa777200000001677bbcccaa910002888888810000000024949999222000016666666d1000
0027aa2222aa72000002277a22a72000000002aaa720000000022a22a777200000167bbb77ccca61001288882213bb000002224449ff9200001d6666666dd100
022a22aaaa22a7200002277aa2a72000000002aa7720000000022a2aa777200001cbbbb7ee7ccc9101282888213bb20000299922449ff920001d6662666dd100
022a2a2777a2a720002222a2772a7200000002aaa72000000022a7772a77720001cbbbb7eee7cc610122888882228f20029ffff92449f920001ddddd2dddd100
22a7aa2777aa2a72002222a2772a7200000002aaa72000000022a7772a77720016ccbb77eee7bc11122828888fffff2002ffffff924499420011111112111100
22a7aa2777aa2a72002222a2772a72000000022aa72000000022a7772a77720016ccbb77777bb1111222828888fff88129fffffff92449420016777777226120
22a7aa2777aa2a72002222a2772a72000000022aa72000000022a7772a777200167ccb777bbb6611112228288888888129ffffffff9244420167177717772210
22a7aa2777aa2a72002222a2772a72000000022aaa2000000022a7772a777200116cccbbbbb36611122282828888888129ffffffff9249420167177717776610
022a7a2222a7a720002222a2777a72000000022aaa2000000022a7772a77720001661ccbbb366610012228282828282129ffffffff9924420449999777776610
022a77aaaa77a7200002222aa7a7200000000222aa20000000022a7aa777200001166111133661100112222282828210299fffffff9922200144499777776610
0022aa7777aa22000002222aa7a720000000022aaa20000000022a7aa2772000001166611116110000112222222221000299fffff99920000161777771776610
000222aaaa22200000002222aa220000000002222a200000000022aa222200000001116661111000000112121212100002999999999200000166111117766610
00002222222200000000022222200000000002222220000000000222222000000000111111110000000011111111000002229999922000000016666666666100
00000022220000000000002222000000000000222200000000000022220000000000001111000000000000111100000000002222200000000001666666661000
0000001111000000000000000000000011111111111111111111111100000000000000000000002222200000111111117c1111c7ccddddcc0000111111441440
011111999911111000000000000000001111111111111111111111110000000000000000000002fffff200001777777d7c7111c7cc7dddcc0001666666494994
011b19777791b110000011101110000011111111111111111111111100070b7b07b0000000222228fff2220017ccc7cd1c7111c17c7dddc70016777776449994
01b1177777711b100001b7b1b7b1000011111111d111111d11111111007a67a67a67300002fffff22822822017cddd7c1c7711c1dc77ddcd0167717777699942
0111971111791110001bb1bbb1bb1000d111111ddd1111dd1111111106a6b373367a67002f99999ff22822f2177dddcc07771c700c77ddc00177777777769420
019771999917791001bbb1bbb1bbb100dd1111ddddd11ddd111111110b73311113367a60029999999f222f921777ddcd07c77c700cc77cc01677777777774261
19771977991177911bbbbbbbbbbbbb10ddd11ddddddddddd111111110011100001113631002299999992222017c77ccd01c77c1007c77c701677717777776661
19771977991177911bb11111111bbbb1dddddddddddddddd11111111000000000000111000002222222220001ddddddd01c177100dcd77d01677777777776661
19771999991177911b1111888881bbb1000000022000000000299aaaaaaaa20000299aaaaaaaa20000299aaaaaaaa200007c770000cd77001677777777776661
197719999111779111f11888881f1bb100000029a2000000002999aaaaaa9200002999aaaaaa9200002999aaaaaa9200007cc70000cdd7001677717777776661
01977111111779101111111111ff1b110000022222200000022222222222222002222222222222200222222222222220001cc100007cc7001667777777766661
01119711117911101ffb1ffffffb11110000299aaaa2000029999aaa7777aa9229999aaa7777aa9229999aaa7777aa92001cc10000dccd000166777777666610
01b1177777711b101bbbb1bbbbb11111000299aa777a200002222222222222200222222222222220022222222222222000077000000cc0000166666666666610
011b19777791b1101bbbb111111111b100029aa77777200000222299992222000029aa92222222000022222229aa920000077000000cc0000016666666666100
011111999911111001bbb100001bbb1000299aa77777a20000000299aa2000000002992000000000000000000299200000011000000770000001666666661000
0000001111000000001110000001110000299aa77777a20000000022220000000000220000000000000000000022000000011000000dd0000000111111110000
1d1d0d1d1d0f2d1d2d0f1d1d1d1d0d1d1d0f1d1d2d0d1d1d1d1d2d1d1d2d1e1e1e1e1e1e1e2e0d1d1d1d1d1d1d1d2d8d9d008d9d0d0f2d1e1e1e0d0f2d1e2ed6
d700d7c6d6c600c68d9d8d9dd7d6d600d70d1d0f0f1d1d0d0f1d1d2d1e1e1e1e1e1e1e2e8d9d008d9d0e1e1e1e1e2e1d2d1e1e1e1e2e00000000000000000000
1d1d0e1e1e1e2e1d2d1d1d1d1d1d0d1d1d1d0f1d2d0d1d1d0f1d2d1d1d2d8d9dc6d6d6008d9d0e1e1e1e1e1e1e1e2e8d9d008d9d0d1d2d8d9dd70e1e2ed6d7d7
00000000d70000008d9d8d9d00d7d700000e1e1e1e1e1e0d0f0f1d2d8d9d00d6d600c6008d9d008d9d00d7d6d60e1e1e2e8d9d00c60000000000000047000000
1d0f2d1d1d1d1d1d2d1e1e1e1e1e0d0f1d1d1d1d2d0d1d0f1d1d2d1d1d2d8d9d00d7d7008d9d00d700c6d6d6d7c6008d9d0000000e1e2e8d9d0000d700d70000
000000000000000000008d9d0000000000d78d9dd7d6000e1e1e1e2e8d9d00d7d70000000000008d9d0000d7d78d9dd6c68d9d00000000000000000000000000
1d1d2d1e1e1e1e1e2e008d9d8d9d0d1d1d1d1d1d2d0d1d1d1d1d2d1e1e2e8d9d00000000000000000000d7d7000000000000000000c6008d9d00000000000000
061600040004000000008d9d0000000000008d9d00d70000c6d6c6008d9d0000000000000000000000000000008d9dd700000000000000000000000000000000
1e1e2ed6d600d78d9d008d9d8d9d0e1e1e1e1e1e2e0d1d1d1d1d2d8d9d008d9d00000000000000000004000400000000000000000000008d9d00000000000000
0717000000000000000000000000000000008d9d0000000000d70000000000000000000000000000000000000000000000040004000616000000000000000000
d6d6d7d7d700008d9d0000008d9d00c6c6000000d70e1e1e1e1e2e8d9d0000000000000000000000000000000000000000000000000000000000000000000000
0000006e7e8e00000000260000000000000000000000000000000000000616000000000006160000000000000000000000000000000717e1000c1c1c1c1c1c1c
d7d700000000000004000004000000000000000000c6d6d7008d9d8d9d0000000000000000000000000400040000c10000000000000616000000e10000000000
000000009e0000000000000000000000000616000000000000040004000717000000e100071700b6b6b6b600000000000000000000e000e0000d1d1d0f1d0c1c
00000000000000000000000000000000000000000000d700008d9d000000000000000000061600000000000000000000000000000007170000e0000000000000
000000009e000000000c1c1c2c000000000717000000000616000000000000e000000000000c1c1c1c1c2c000000000000000000006e7e7e7e0d1d0f0c1c0d1d
9d000000000000006e7e7e7e8e00000000000000000000000000000000000000000000000717000c1c1c1c1c1c1c1c2c00000000000000004f0c1c1c2c000000
000000009ee1b6b6000d1d0f2d000000000000e10000000717000000006e7e7e7e7e7e8e000d1d0f1d1d2d00000000c100000000b6b6009e000d1d1d0d1d0d1d
9d8d9d000000000000009e000000000000000000000006160000000000000000000000e10000000d1d0f0f1d1d0f1d2d0000000000000000000d0f1d2d000000
00e000009e00b6b6000d0f1d2d0000000000e0000000000000000000000000009e000000000d0f1d1d1d2d000000f0e0000000a10000009e000e1e1e0d1d0d0f
9d8d9d000300000000009e00000000000000000000000717000000a1000000000000000000e0000e1e1e1e1e1e1e1e2e6e7e7e7e7e7e7e7e8e0d1d1d2d5f5f00
006e7e8e0c1c1c1c1c0d1d1d2d00006e7e7e7e7e7e8e000000000000000000009eb6b600000d1d1d1d0f2d00000c1c1c2c0000000000009e00008d9d0d0f0d1d
1c1c1c1c1c1c2cb6b6b69e0000000000000000000000000000000000000000006e7e7e7e7e7e8e8d9d8d9d00d78d9d00000000009e000006160d1d0c1c1c2c00
00c19e000d1d1d1d1d0d1d1d2d00000000009e00000000006e7e7e7e7e7e8e009eb6b600000d1d1d1d1d2d00000d1d1d2d00004f4f00009e00008d9d0e1e0d1d
1d1d0f1d1d1d2d4f4f0c1c2ca1008d9d8d9d000000000000000c1c1c1c1c2c000000009e0000008d9d8d9d00008d9d0000a1b6b69e000007170d1d0d1d0f2d5f
5ff09e000d1d1d0c1c1c2c1d2d000000b6b69e00000000000000009e00b6b6009e000000000e1e1e1e1e2e00000d1d1d2d0000000000009e00008d9d8d9d0d1d
1d1d1d1d0f1d2d00000d1d2d00008d9d8d9d8d9d6e7e7e7e8e0d1d0f1d1d2d00008d9d9e00000000008d9d00000000000000b6b69e000000000d1d0d1d1d0c1c
1c1c1c1c2c1d1d0d0f1d2d1d2d000000b6b69e0000b6b6b6b600009e00b6b6009e00000000008d9d0d1d2d00000d1d1d2d0000000000009e000000008d9d0d1d
1d1d1d0f1d1d2d00000d1d2d4f4f0c1c1c2c8d9d00009e00000d0f0f1d1d2d8d9d8d9d9e00005f00000000000000004f4f4f4f4f9e000000000d0f0d1d1d0d1d
1d0f0f1d2d1d1d0d1d0f2d1d2d000000b6b69e0000b6b6b6b600009e00b6b6009e00000000008d9d0d1d2d00000d0f1d2d0000000000009e0000000000000d0f
1d1d1d1d1d1d2d00000d1d2d00000d1d0f2d8d9db6b69e00000d1d1d1d1d2d8d9d8d9d9e4f4f4f4f4f00004f4f000000000000009e000000000d1d0d0f1d0d1d
0f0f1d1d2d1d1d0d1d1d2d1d2d000000b6b69e0000b6b6b6b600009e00b6b6009e000000000000000d1d2d00000d1d0f2d0000000000009e0000000000000d1d
111111111111111111111111111111111111111111111111222222222222222222222222777777777777777777777777000000000000bdad0000600000500000
11777777777777777777771114499fff77777777fff9944122222222222222222222222277777777777777777777777700000000000000000000000000000000
17ffffffffffffffffffff711444999ff99ffffff9994441222222222222222222222222777777777777777777777777ad00bdad00bd9c9c5000007000000000
1fbfbfbfbfbfbfbfbfbfbfb114499f9ff9fffffff9f9944122222222222222222222222277777777777777777777777700000000000000000000000000000000
1b3b3b3b3b3b3b3b3b3b3b3114999fffffffff9ffff99941222222200222222222222222777777777777777007777777acbd9c9cadbc9c9c0000000050005060
133333311333333113333331149499f9fffff99f9f99494122222220022222222222222277777777777777700777777700000000000000000000000000000000
1133331111333311113333111444999ffffff9fff999444122222200002222222222222277777777777777000077777700bc9c9cac00bcac0000005000006000
1b11113333111133331111b114499f9ffffffffff9f9944122220000000022222222222277777777777700000000777700000000000000000000000000000000
1fb3b33333333333333b3bf114999ffffffffffffff999412222000000002222222220022200000077770000000077770000bcac000000000000500000000000
1fbb3333333333333333bbf1149499f9ff9fffff9f99494122222200002222222022222222000000777777000077777700004161000000000000000000000000
1fb3b33333333333333b3bf11444999ff99ffffff9994441222222200222222222002222200222227777777007777777aebeaebeaebeaebe0000006000000000
1fbb3333333333333333bbf114499f9ff9fffffff9f9944122222220022222222222002220222202777777700777777700007161416141514151415141510000
1fb3b33333333333333b3bf114999fffffffff9ffff99941222222222222222202222222222200227777777777777777afbfafbfafbfafbf0050000060006050
1fbb3333333333333333bbf1149499f9fffff99f9f99494122222222222222220022220222002222777777777777777700006200620042524272427242520000
1fb3b33333333333333b3bf11444999ffffff9fff999444122222222222222220000000222222220777777777777777766666666666666660000000000007000
1fbb3333333333333333bbf114499f9ffffffffff9f9944122222222222222220000000022222200777777777777777700000000000000008252825200000000
1b11113333111133331111b114999ffffffffffffff99941001111111111111111111100449fff94000000000000000046564656465646560000005000506000
113333111133331111333311149499f9ff9fffff9f99494101777777777777777777771049fff944000330000000000000000022222022000000000000000000
1333333113333331133333311444999ff99ffffff999444117ffffffffffffffffffff71449fff940033330000011000000002494942b3200000000050005060
1b3b3b3b3b3b3b3b3b3b3b3114499f9ff9fffffff9f994411f8ff888888ff888888ff8f149fff9440333333000111100000024949aa942200000000000000000
13b3b3b3b3b3b3b3b3b3b33114999fffffffff9ffff9994118ffff8ff8ffff8ff8ffff81449fff943333333301111110000024949aaa94225000007000000000
11333333333333333333331114949999999999499999494112ffff8ff8ffff8ff8ffff2149fff94433333333bb11111300000222229944420000000000000000
111111111111111111111111144444444444444444444441012882222228822222288210449fff943333333bbbb1113300000022222244420000600000000000
11111111111111111111111111111111111111111111111100111111111111111111110049fff944333333bbbbbb133300000002222224200000000000000000
33311333416fff1424999424dddddddd11111111000100000000000002422222222220002220000033333bbbbbbbb33300020111111000000000000000007000
331991331f6666f142222224dd6ddddd1ffffff10001000000000002222449999994442294200000b333bbbbbbbbbb3b002e2d666d5110000000000000000000
31199113f661166f44292224d66ddddd1f9999f10013100000002229449944444444994442200000bb3bbbbbbbbbbbbb00ecedd666d510000050000060006050
199779916616f166442f4942d6dddddd14999941001b100002222949944222222244224944920000bbbbbbbbbbbbbbbb00111111ddd111000000000000000000
199779916616666142222224dddddd6d014444100137310002929499424422224442442494992000bbbbbbbbbbbbbbbb01d66666111111100000006000000000
3119911316f1611424942924ddddd66d0111111001b7b10000249499242222222222224299942000bbbbbbbbbbbbbbbb1d111111661115d10000000000000000
331991334166ff6142222f24ddddd6dd000110001377731000244949922422222222222449449222bbbbbbbbbbbbbbbb11111111116ddd110000500000000000
333113334416661142924244dddddddd000000001b777b1000229499992222222222229494499442bbbbbbbbbbbbbbbb01111111111111100000000000000000
__label__
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccccc111111111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccccc1133333333333331ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
cccccccccccccccc11377777777777731ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccc1137bbbbbbbbbbb731ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccc137bbbbbbbbbbbbb31ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccc13bbbbbbbbbbbbbb11ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccc13bbbbbb1333333311ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccc11bbbbb11111111111ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
ccccccccccccccc11bbbbb11111111111c111111111111111c111111111111cccc111111111111cccc111111111111cccc111111111111cccccccccccccccccc
ccccccccccccccc11bbbbb73333333331113333333333333111333333333311cc11333333333311cc11333333333311cc11333333333311ccccccccccccccccc
ccccccccccccccc11bbbbbb77777777311377777777777731137777777777311113777777777731111377777777773111137777777777311cccccccccccccccc
ccccccccccccccc11bbbbbbbbbbbbb73137bbbbbbbbbbb73137bbbbbbbbbb731137bbbbbbbbbb731137bbbbbbbbbb731137bbbbbbbbbb7311ccccccccccccccc
ccccccccccccccc11bbbbbbbbbbbbbb337bbbbbbbbbbbbb337bbbbbbbbbbbb7337bbbbbbbbbbbb7337bbbbbbbbbbbb7337bbbbbbbbbbbb731ccccccccccccccc
ccccccccccccccc11bbbbbbbbbbbbbb13bbbbbbbbbbbbbb13bbbbbbbbbbbbbb33bbbbbbbbbbbbbb33bbbbbbbbbbbbbb33bbbbbbbbbbbbbb31ccccccccccccccc
ccccccccccccccc11bbbbbb3333333313bbbbbb1333333313bbbbbb11bbbbbb33bbbbbb11bbbbbb33bbbbbb11bbbbbb33bbbbbb11bbbbbb31ccccccccccccccc
ccccccccccccccc11bbbbb31111111111bbbbb11111111111bbbbb1111bbbbb11bbbbb1111bbbbb11bbbbb1111bbbbb11bbbbb1111bbbbb11ccccccccccccccc
ccccccccccccccc11bbbbb11111111111bbbbb11111111111bbbbb1111bbbbb11bbbbb1111bbbbb11bbbbb1111bbbbb11bbbbb1111bbbbb11ccccccccccccccc
ccccccccccccccc11bbbbb11111111111bbbbb11111111111bbbbb1111bbbbb11bbbbb1113bbbbb11bbbbb1113bbbbb11bbbbb1111bbbbb11ccccccccccccccc
ccccccccccccccc11bbbbb11ccccccc11bbbbb11ccccccc11bbbbb7117bbbbb11bbbbb7137bbbbb11bbbbb7137bbbbb11bbbbb7117bbbbb11ccccccccccccccc
ccccccccccccccc11bbbbb11ccccccc11bbbbb11ccccccc11bbbbbb77bbbbbb11bbbbbb77bbbbbb11bbbbbb77bbbbbb11bbbbbb77bbbbbb11ccccccccccccccc
ccccccccccccccc11bbbbb11ccccccc11bbbbb11ccccccc11bbbbbbbbbbbbbb11bbbbbbbbbbbbbb11bbbbbbbbbbbbbb11bbbbbbbbbbbbbb11ccccccccccccccc
ccccccccccccccc11bbbbb11ccccccc11bbbbb11ccccccc113bbbbbbbbbbbb3113bbbbbbbbbbbbb113bbbbbbbbbbbbb113bbbbbbbbbbbb311ccccccccccccccc
ccccccccccccccc11bbbbb11ccccccc11bbbbb11ccccccc1113bbbbbbbbbb311113bbbbbbbbbbbb1113bbbbbbbbbbbb1113bbbbbbbbbb3111ccccccccccccccc
ccccccccccccccc113333311ccccccc113333311ccccccc11113333333333111111333333bbbbbb1111333333bbbbbb111133333333331111ccccccccccccccc
ccccccccccccccc111111111ccccccc111111111cccccccc11111111111111111111111113bbbbb11111111113bbbbb11111111111111111cccccccccccccccc
ccccccccccccccc111111111ccccccc111111111ccccccccc1111111111111113333333111bbbbb13333333111bbbbb1111111111111111ccccccccccccccccc
ccccccccccccccc111111111ccccccc111111111cccccccccc111111111111c13777777317bbbbb13777777317bbbbb11c111111111111cccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc137bbbbb77bbbbbb137bbbbb77bbbbbb11ccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc13bbbbbbbbbbbbbb13bbbbbbbbbbbbbb11ccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc113bbbbbbbbbbbb3113bbbbbbbbbbbb311ccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc1113bbbbbbbbbb311113bbbbbbbbbb3111ccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc1111333333333311111133333333331111ccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc111111111111111111111111111111117777777777cccccccccccccccccccccc
cccccccccccc777777111111111111111c111111111111111111111111111c111111111111111111111111111111111111111111111117cccccccccccccccccc
cccccccc7777777777111111111111111c111111111111111111111111111c11111111111111111111111111111111111111111111111777cccccccccccccccc
cccccc77777777777711b1b11bb1bbb11c11bbb11bb1bbb11bb11bb11bb11c11bbb1b1b1bbb11c111bb1bbb1bbb11bb11bb1bb111bb1177777cccccccccccccc
cccc7777777777777711b1b1b1b1b1b11c11b1b1b111b1b1b1b1b111b1111c111b11b1b1b1111c11b111b111b1b1b111b1b1b1b1b11117777777cccccccccccc
ccc77777777777777711bbb1b1b1bbb11c11bbb1b111bb11b1b1bbb1bbb11c111b11bbb1bb111c11bbb1bb11bbb1bbb1b1b1b1b1bbb1177777777ccccccccccc
c7777777777777777711b1b1b1b1b1111c11b1b1b111b1b1b1b111b111b11c111b11b1b1b1111c1111b1b111b1b111b1b1b1b1b111b117777777777ccccccccc
77777777777777777711b1b1bb11b1111c11b1b11bb1b1b1bb11bb11bb111cc11b11b1b1bbb11c11bb11bbb1b1b1bb11bb11b1b1bb11177777777777cccccccc
7777777777777777771111111111111117111111111111111111111111111cc11111111111111c1111111111111111111111111111111777777777777ccccccc
7777777777777777771111111111111777111111111111111111111111111cc11111111111111c11111111111111111111111111111117777777777777cccccc
777777777777777777111111111111177711111111111111111111111111ccc11111111111111c111111111111111111111111111111777777777777777ccccc
777777777777777777777777777777777777cccccccccccccccccccccccccc11111111111111177777777777777777777777777777777777777777777777cccc
7777777777777777777777777777777777777ccccccc777777777cccccccc11111113bbbb111117777777777777777777777777777777777777777777777cccc
77777777777777777777777777777777777777ccc777771111111117cccc111113bbbbbbbbb11117777777777777777777777777777777777777777777777ccc
77777777777777777777777777777777777777c7777711111111111177c111133bbbbbbb17bb11117777777777777777777777777777777777777777777777cc
7777777777777777777777777777777777777777771111111111111111111133bbbbbbb1777bb1111777777777777777777777777777777777777777777777cc
777777777777777777777777777777777777777711111113bbbbbb111111133bbbbbbbb1777bbb1117777777777777777777777777777777777777777777777c
7777777777777777777777777777777777777771111113bbbbbbbbb11133333bbbbbbbb11777bbb111777777777777777777777777777777777777777777777c
77777777777777777777777777777777777777111113bbbbbbb17bbb1113333bbbbbbbb11777bbb1111177777777777777777777777777777777777777777777
77777777777777777777777777777777777771111333bbbbbb1777bbb1bbb33bbbbbbbbb11711bbb111117777777777777777777777777777777777777777777
777777777777777777777777777777777771111333bbbbbbbb17777bbbbbbbbbbbbbbbbb11111bbbb11111777777777777777777777777777777777777777777
77777777777777777777777777777777771111333bbbbbbbbb11777bbbbbbbbbbbbbbbbb111111bbbbb111177777777777777777777777777777777777777777
7777777777777777777777777777777777111333bbbbbbbbbb11777bbbbbbbbbbbbbbbbbb11111bbbbbb11117777777777777777777777777777777777777777
777777777777777777777777777777777111333bbbbbbbbbbbb11711bbbbbbbbbbbbbbbbb11111bbbbbbb1117777777777777777777777777777777777777777
777777777777777777777777777777771113333bbbbbbbbbbbb11111bbbbbbbbbbbbbbbbbb111bbbbbbbbb111777777777777777777777777777777777777777
77777777777777777777777777777771113333bbbbbbbbbbbbb11111bbbbbbbbbbbbbbbbbbb11bbbbbbbbb111177777777777777777777777777777777777777
77777777777777777777777777777771113333bbbbbbbbbbbbbb11111bbbbbbbbbbbbbbbbbbbbbbbbbbbbb311177777777777777777777777777777777777777
77777777777777777777777777777711133333bbbbbbbbbbbbbb11111bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb31117777777777777777777777777777777777777
777777777777777777777777777771111333333bbbbbbbbbbbbb11111bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1117777777777777777777777777777777777777
cccccccccccccccc77777777777771113333bbbbbbbbbbbbbbbbb111bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb111177777777777777777777cccccccccccccccc
cccccccccccccccccccccccccccc1111333bbbbbbbbbbbbbbbbbbb11bbbbbbbbbbb111111111111111bbbbbb3111cccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccc777111333bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb11111111111111111111bbbb311177777777777ccccccccccccccccccccccccc
cccccccccccccccccccccccccccc111333bbbbbbbbbbbbbbbbbbbbbbbbbbbb11111111111111111111111bbb31111777cccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccc111133bbbbbbbbbbbbbbbbbbbbbbbbbbb1111111199fffffffff9911111b333111ccccccccccccccccccccccccccccccccccc
cccccccccccccccccccccccccc7111333bbbbbbbbbbbbbbbbbbbbbbbbb11111119ffffffffffffffff91111333111777777777cccccccccccccccccccccccccc
ccccccccccccccccccccccccccc111333bbbbbbbbbbbbbbbbbbbbbb111111119fffffffffffffffffff9111133111ccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccc11133bbbbbbbbbbbbbbbbbbbbbb11111119ffffffffffffffffffffff911113111ccccccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccc11133bbbbbbbbbbbbbbbbbbbb1111119ffffffffffffffffffffffffff91111111111cccccccccccccccccccccccccccccccc
ccccccccccccccccccccccccccc11133bbbbbbbbbbbbbbbbbbb111119fffffffffffffffffffffffffffff911111111111cccccccccccccccccccccccccccccc
cccccccccccccccccccccccccc111133bbbbbbbbbbbbbbbbbb11119fffffffffffffffffffffffffffffff9911111111111ccccccccccccccccccccccccccccc
cccccccccccccccccccccccccc11133bbbbbbbbbbbbbbbbbb11119ffffffffffffffffffffffffffffffff91111bbb311111cccccccccccccccccccccccccccc
cccccccccccccccccccccccccc11133bbbbbbbbbbbbbbbbb11119ffffffffffffffffffffffffffffffff91113bbbbbb31111ccccccccccccccccccccccccccc
cccccccccccccccccccccccccc11133bbbbbbbbbbbbbbbb1111fffffffffffffffffffffffffffffffff1111bbbbbbb3331111cccccccccccccccccccccccccc
cccccccccccccccccccccccccc11133bbbbbbbbbbbbbbb1111fffffffffffffffffffffffffffffffff1111bbbbbbbbbb33111cccccccccccccccccccccccccc
cccccccccccccccccccccccccc11133bbbbbbbbbbbbbb1111fffffffffffffffffffffffffffffffff1111bbbbbbbbbbbb31111ccccccccccccccccccccccccc
cccccccccccccccccccccccccc11133bbbbbbbbbbbbbb111fffffffffffffffffffffffffffffffff1111bbbbbbbbbbbbbb3111ccccccccccccccccccccccccc
cccccccccccccccccccccccccc11133bbbbbbbbbbbbb1111ffffffffffffffffffffffffffffffff1111bbbbbbbbbbbbbbb3111ccccccccccccccccccccccccc
cccccccccccccccccccccccccc111133bbbbbbbbbbbb111ffffffffffffffffffffffffffffffff1111bbbbbbbbbbbbbbbb3111ccccccccccccccccccccccccc
ccccccccccccccccccccccccccc11133bbbbbbbbbbb1111fffffffffffffffffffffffffffffff9111bbbbbbbbbbbbbbbbb3111ccccccccccccccccccccccccc
ccccccccccccccccccccccccccc11133bbbbbbbbbbb111fffffffffffffffffffffffffffffff9111bbbb3bbbbbbbbbbbbb1111ccccccccccccccccccccccccc
ccccccccccccccccccccccccccc111133bbbbbbbbbb111ffffffffffffffffffffffffffffff91111bb33bbbbbbbbbbbbbb111cccccccccccccccccccccccccc
cccccccccccccccccccccccccccc11133bbbbbbbbb1111ffffffffffffffffffffffffffffff1111bb33bbbbbbbbbbbbbb3111ccccc1c1111cc11111cccccccc
cccccccccccccccccccccccccccc111133bbbbbbbb1119fffffffffffffffffffffffffffff91113b333bbbbbbbbbbbbbb1111c1c11111c1111111111ccccccc
ccccccccccccccccccccccccccccc111333bbbbbbb1119fffffffffffffffffffffffffffff11133333bbbbbbbbbbbbbb3111c1111111c7c1111c7111ccccccc
ccccccccccccccccccccccccccccc1111333bbbbb11119ffffffffffffffffffffffffffff11113b333bbbbbbbbbbbbbb1111111c1111c77111c77c111cccccc
cccccccccccccccccccccccccccccc11113333bb311199ffffffffffffffffffffffffffff11133333bbbbbbbbbbbbbb3111c111c7c11cc711c77c1111111ccc
ccccccccccccccccccccccccccccccc1111333333111999fffffffffffffffffffffffff991113b333bbbbbbbbbbbbb31111c111c7771cc71c77c111111cc11c
cccccccccccccccccccccccccccccccc111133333111499ffffffffffffffffffffffff9911113b333bbbbbbbbbbbb31111cc1111cc777c7777c1111111c7c11
ccccccccccccccccccccccccccccccccc111113331114999fffffffffffffffffffff9991111333333bbbbbbbbbb33311111111111ccc777ccc11111111c7c11
cccccccccccccccccccccccccccccccc11111111331114999fffffffffffffffff99999111113333333bbbbbbbb331111111111111111cc771111111111c7c11
c1111ccccccccccccccccccccccccccc111311111111144999ffffffffffff9999991111111113333333bbbbb333111111ccc111111111cc7111111111cc71c7
1111111cccccccccccccccccccccccc111133311111111449999999999999999991111111c111333333333333311111c11cc7111111111cc71111ccc11c77777
11111111ccccccccccccccccccccccc11133333311111111111499999999111111111111cc11113333333331111111cc11cc77c1111111ccc111ccc111c77777
11ee11111cccccccccccccccccccccc1113b333331111111111111111111111111111cccccc111133331111111111111111cc77111c111ccc11c11111c77cccc
eeeeee1111cc111cccccccccccccccc111bbb333333331111111111111111111111ccccccccc11111111111111111111111ccc7711cc111ccc111111c77cc1cc
eeeeeee1111111111ccccccccccccc1113bbbbb3333333333311111111111cccccccccccccccc11111111111cc1111cc777cccc7c111111ccc11111cc7c11111
eeeeeeee11111111111ccccccccccc111bbbbbbbbbb33333333111cccccccccccccccccccccccc1111111111cc1111cccc77ccccc111111cccc111cccc111111
eeeeeeeee1118e111111cccccccccc111bbbbbbbbbbbbbb3331111cccccccccccccccccccccccccccc111211cc111111cccccccccc111111cc711cc7c1111111
eeeeeeeee111eeee11111ccccccccc111bbbbbbbbbbbbb3331111cccccccccccccccccccccccccccc1114111ccc11111777cccccccc71111cc71c77c11111111
8eeeeeeeee118eeeee1111cccccccc111bbbbbbbbbbbb3331111ccccccccccccccc111111111111cc111411ccc111cc77ccc11cccccccc11cc7c77c111111ccc
8eeeeeeeee118eeeeee1111ccccccc1113bbbbbbbbbb3311111cccccccccccccc1111111111111111112211ccc111cccccc11111c1ccc777cc777c111111cccc
8eeeeeeee81188eeeeee1111cccccc1113bbbbbbbbb3111111cccccccccccccc11112444442111111111111ccc11ccccc111111111111cc7777777cc11111ccc
88eeeeeee81111eeeeeee1111ccccc11113bbbbbb31111111cccccccccccccc1112444999999994211111111cc11111111111111111111cc77c7ccc77c111111
8888ee888111111eeeeeee111cccccc1111133311111111cccccccccccccccc1124449999999999999421111111111111111111111111ccc7ccccccc77cc1111
1111188811111111eeeeeee11cccccc11111111111111cccccccccccccccccc112444999999999999994442111111111111ccccc111cccc71cc711ccccc77c11
11111111119991111eeeee811ccccccc11111111111ccccccccccccccccccc1112444499999999999994444421111111111111111ccccc711cc711111ccc7777
11111111199aaa1111ee88111cccccccccc1111111111111cccccccccccccc1112244444444444999944444444211111111111111cccc7c111c7c11111ccc7cc
888e1111119aaaa111188111ccccccccccc111111111111111cccccccccccc1111224444444444444444444444422111111cccccccccc11111c77111111cc71c
8eeeee111119aaaa11111111cccccccc11111111cccccc111111cccccccccc1111111111111124444444444444442211111cccccccccc11111cc7111111ccc71
eeeeeeee11119aaa9111111cccccccc11111111111111111cc111ccccccccc111111111111111111244444444444222111c777cccccc111111cc71111111cc77
eeeeeeeee11119aa9111111cccccc1111aaa111111111111111111ccccccccc1111111111111111111124444444422211117cccccccc111c11ccc11111111cc7
eeeeeeeeee1119991111111ccccc1111aaaaa1111888888111111111ccccccc111199fffff91111111111124444422221111ccc71cc711cc11ccc11111111ccc
eeeeeeeeee1111911111e111ccc1119aaaaa911188888888881111111cccccc11199ffffffffff911111111144422222111cc7111c71111c111cccc1111111c1
eeeeeeeeeee11111118eee111c1119aaaaa9111188888888888811111cccccc1119ffffffffffffff911111111222222111c77111c71111111cccccc11111111
eeeeeeeeeee11111188eeee111119aaaaa911118888888888888881111ccccc1199fffffffffffffffff911111122222111cc111cc7111111cccccccc1111111
8eeeeeeeeeee111188eeeee111119aaaa99111188888888888888881111cccc119fffffffffffffffffff99111111221111c1111c71111111cccc7ccc7111111
8eeeeeeeeeee11188eeeeeee11199aaa9911118888888888888888881111ccc119ffffffffffffffffffff999111111111111111c7111111c77cc71cc7711111
88eeeeeeeee811188eeeeeee111999999111188888888888888888888111cc111ffffffffffffffffffffff9991111111111111ccc11111c771cc7111c771111
888eeeeeeee111188eeeeee1111199991111288888888888888888888811cc119ffffffffffffffffffffff9999111111111c11cc111111c7c11c7c111cc111c
1888eeeeee8111188eeeee111111111111122888888888888888888888111c119ffffffffffffffffffffff999911111cccccc11111111ccc111cc711111111c
11888eeee811111188eeee111111111111122888888888888888888888811c119fffffffffffffffffffff999991111ccccccc111111111c1111cc711111111c
1118888888111111188eee111f111111111128888888888888888888888111119fffffffffffffffffffff99999111ccccccccc111cc11111111cc71111111cc
c111188811111c11111181111f777777111128888888888888888888888111119ffffffffffffffffffff999991111cccccccccccccc11111111ccc11111cccc

__gff__
0000000000000000800000800000808000000000000000000000800080008000000000000000000000000000000000008000000000000000000000000000000080000000000000008000800080008000000000000000000000000000000000000808800000000000000000218004010108080000800000000000000000040101
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001010101010100000000000000000000010101010101000000000000000000000101010101010202020000000000000001010101020400000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000080000000000000000000000000000080000000000000000000000000000000000000008000000000000000000000008000000e0e1e1e1d0f0d1d1d2000000000000000000000000
000000000000000000000000000000004000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d0d1f0d1d2000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0e1e1e1e2000000000000000000000000
00000000000000000000000000000000f4f4f4f40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000606100004e000000000000000000000000000000000000004000400000000000000000000000001c00004e0000400040006e6f00000000000000000074000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c20000000000000070710000000000000000000000000000000000000000000000000000000000000000000000000f000000000000000000007e7f00000000000000000000000000
00000000000000400040000000000000000000000000000000000000000000000000000000000000000040004000000000000000000000d0d20062000000000000000000c0c1c1c200000000000000000000000000000000000000001c0000000000000000f4f4f4f4f4f4c0c1c1c1c1c1c1c200000000000000000000000000
00000000000000000000004000000000000000f4f4000000000000000000606100c0c1c1c2000000000000000000000000000000000000d0d20000000000000000000000d0d1d1d24000400000000000000000000000006061000f00000000000000000000000000000000e0e1e1e1e1e1e1e200000000000000000000000000
00000000000000000000000000000000001c000000000000000000000000707100d0d1f0d2000000000040004000000000000000000000d0c0c1c2f40000000000000000d0d1f0d20000000000000000001c0000000000707100f4f4c0c20000000000000000000000000000000000000000000000000000000000c0c1c1c1c1
0000000000000000000000000000000000000f0000000000000000000000004e00d0d1c0c1c1c1c200000000000000000000001c000000d0d0d1d2000000000000000000d0f0d1d2c1c1c1c200000000000000000000000000000000d0d20000000000000000000000000000000000000000000000000000000000d0d1d1d1d1
000000300000000000000000000000c0c1c1c1c200000000000000000000000000d0f0d0d1d1d1d200000000000000000ff6f7f8f96e6fd0d0f0d2000000000000000000d0d1d1d2d1d1d1d20000c0c1c1c1c20000004e0000000000d0d2000000006e6f0000000000000000000000000000000000c0c1c1c1c1c1d0d1d1f0d1
00c0c1c1c200000000000000000000d0d1d1f0d2000000c0c1c1c2000000006e6fd0c0c2d1d1d1d20000000000000000c0c1c1c1c27e7fd0d0f0d2000000000000000000e0e1e1e2e1e1e1e20000d0d1d1d1d2000000000000000000d0d2000000007e7f000000001c000000000000000000000000d0d1d1f0d1d1d0d1d1d1f0
c1c1c2d1d20000000000c0c1c1c1c2d0d1f0f0d2000000d0d1d1d2000000007e7fd0d0d2c1c2e1e2f400000000000000d0d1d1f0d2c1c1c1d0d1d2f4000000000000000000000000000000000000d0d1d1f0d20000006e6f00000000d0d2c1c1c1c1c1c200000000000f0000000000000000006061d0d1c0c1c1c2d0f0d1d1f0
d1f0d2c1c1c1c1c20000d0d1d1f0d2d0d1d1d1d2000000d0d1d1d2c0c1c1c1c1c2d0d0d2d1d248000000000000c0c1c1d0d1f0d1d2e1e1e1d0d1d200000000000000000000000000000000000000d0f0d1d1d20000007e7f00000000d0d2d1d1d1f0d1d2000000c0c1c1c1c2000000000000007071d0d1d0d1f0d2d0c0c1c1c1
d1d1d2d1f0d1d1d20000d0d1d1c0c1c1c1c2d1d2000000d0f0d1c0c1c1c2f0d1d2d0d0d2d1d200000000000000d0f0d1d0c0c1c1c1c24000d0d1d200000000000000000000000000000000000000d0d1d1d1d2000000c0c200000000d0d2d1d1d1d1d1d2000000d0d1d1f0d2400040000000000000d0f0d0d1d1d2d0d0d1f0d1
f0d1d2d1d1f0d1d20000d0d1d1d0f0d1d1d2d1d2000000d0d1f0d0d1f0d2c1c1c1c1c2d2d1d2f4f4000000f4f4d0d1d1d0d0d1d1d1d20000d0d1d200000000000000f4f4c0c1c1c1c1c1c1c26e6fd0d1d1f0d2000000d0d200006e6fd0d2d1d1f0d1d1d2000000d0d1f0d1d2000000000000006e6fd0d1d0c0c1c1c1c1c2d1d1
d1f0d2d1d1d1d1d20000d0d1d1d0d1d1d1d2f0d2000000d0d1d1d0d1d1d2d1d1d1f0d2d2d1d200000000000000d0d1d1d0d0d1d1f0d2c0c1d0d1d2c1c1c2000000000000d0d1d1f0d1f0f0d27e7fd0d1d1d1d2000000d0d200007e7fd0d2d1d1d1d1d1d2000000d0d1d1d1d2c1c1c1c20000007e7fd0d1d0d0d1d1f0d1d2d1d1
c8c8c8c8c6000000d7c8c8c8d3d4d4d4d5d3d4d4d5c6c7c8c8c60000d3d4d5c7c8c8c8c8d3d5d6000b0000d7c8c8d3d4d4d5c8d60b000000d7c8d3d4d4d500000bd7c8c8c6c7c6e3e4e5c7c8d3d5d60b000000d7c8c8c8c6c7c8e0d0d1d1d1d3d5d60b00d7c8c8e3e4e500c7c8c8c8c8c6c7c8c8c600d3d4d5d7c8c8c8e3e5d4
c8c8c8c8d6000000c7c8c8c6d3d4d4d4d5d3d4d4d50000c7c6000000e3e4e500c7c6c7c8d3d5c8d6d7d6d7c8c8c8e3e4e4e5c8c8d64000d7c8c8d3d4d4d50000d7c8c8c600000000000000c7d3d5c8d60000d7c8c8c8c60000c7c8e0e1e1e1d3d5c8d6d7c8c6c7c600000000c7c8c8c8d60bc7c8d600e3e4e5c8c8c8c8c8d3d4
c6c7c8c8c8d60000d7c8c600d3d4d4d4d5e3e4e4e50b00000000000000000000000000c7d3d5c8c8c8c8c8c8c8c6000000c7c8c8c8d6d7c8c8c8e3e4e4e5d6d7c6c7c6000000000000004000d3d5c8c8d6d7c8c6c7c6000b0000c7c8c8c6c7d3d5c8c6c7c60000000000000000c7c8c8c8d6d7c8c8d6d7c8c8c8c6c7c8c8e3e4
0000c7c8c8c8d6d7c8c8d600d3d4d4d4d5c8c60000000000000000000000000000000000e3e5c8c8c8c8c8c8c60000000000c7c8c8c8c8c8c8c8c8c8c8c8c8c6000000001a00006200000000d3d5c6c7c8c8c64000400000000000c7c60000d3d5c6400040000000000000000000c7c6c7c8c8c8c8c8c8c8c8c60000c7c8c8c6
000000c7c6c7c8c8c8c8c8d6e3e4e4e4e5c60000000000000000000000000000000000004000c7c8c8c6c7c60000001a000000c7c8c8c8c8c8c6c7c8c8c8c8d60b0000000000000000004000e3e5000bc7c8d6000000000000000000004a00d3d5000b0000000000000000000000000000c7c6c7c8c8c6c7c600000074c7c600
000000000000c7c8c8c8c8c8c8c600c7c6000000000040000000000000000000000000000000d7c8c600000000000000000000d7c8c8c6c7c60000c7c8c8c8c8d60000f4f4f4f4c3c4c500000000000000c7c8d6d7d60000000000000000d7d3d5d640004000000000000000001c00d7d60b0000c7c600000000000000d7d600
00000000000000c7c8c8c8c8c60000000000000000000000000000000000000000d7d60040d7c8c6000000000000c3c4c4c5d7c8c8c6000000000000c7c8c8c8c8d6d7d60000d7d3d4d54000000000000000c7c8c6c7d60b00000000c0c1c2d3d5c8d60000000000000000000000d7c8c8d600000000000000000000d7c8c8d6
00000000000000d7c8c8c8c60000000000004c000000000000001c0000000000d7c8c8d6d7c8c6000040000000d7e3e4e4e5c8c8c64000000000000000c7c8c6c7c8c8c8d6d7c8d3d4d50000000000000000d7c60000c7d600000000d0d1d2d3d5c8c6f4f40000c3c4c5f4f4c3c4c4c5c8c61a0000d7d600000000d7c8c8c8c8
000000000000d7c8c8c8c8d600000000000000000000000000000000000000d7c8c8c8c8c3c5d6000b000000d7c8c8c8c6c7c8c60b0000000000001a00d7c6000bc7c8c8c8c8c8d3d4d500000000000b00d7c8d61a00d7c6f4f4f4f4e0e1e2e3e5c60b000000d7d3d4d50000e3e4e4e5c6000000d7c8c8d60000d7c0c1c1c1c1
0000003000d7c8c8c8c8c8c6000000000000c3c5f4f4f4f4f4f4c3c50000d7c8c8c8c8c8d3d5c600f4f4f4f4c7c8c8c60000c7d6f4f4f4f400000000d7c8d6000000c7c8c8c6c7d3d4d5000000000000d7c8c8c8d6d7c6000000000000c7c8c8c600000000d7c8d3d4d5d6000000c7c8d60b00d7c8c8c3c4c5d7c8d0d1d1d1d1
0000c3c4c5c8c8c8c8c8c600000000000000d3d5000b0000d7d6d3d50000c7c8c8c8c6c7d3d500000000000000c7c61c0000d7c8d60000000000c3c4c4c5c600000000c7c60000d3d4d54a00000000d7c6c7c8c8c3c5d60b000000000000c7c600000000d7c8c8e3e4e5c600400000c7c8d6d7c8c8c8d3d4d5c8c0d0d1d1d1d1
f4f4d3d4d5c8c8c8c8c8d600000000000000d3d5d60040d7c8c8e3e5000000c7c8c60000d3d5000000000000000000000000c7c8c8d60000d7d6d3d4d4d5f4f4f4f4f4f4f4f4f4d3d4d500000000d7c60000c7c8d3d5c600000000000000000000000000c7c8c8c6c7c60000000000d7c8c8c6c7c8c8d3d4d5c8d0d0d1d1c3c4
d7d6d3d4d5c3c4c4c5c8c6001a0000004ad7d3d5c8d6d7c8c6c7c8c8d60000d7c8d60000d3d50000000000000000c3c4c4c500c7c8c8d6d7c8c8d3d4d4d5d6000b000000000000d3d4d5f4f4c3c5c60b000000c7d3d5000000000000d7d6000000000b0000c7c600000000004000d7c8c8c60000c7c6d3d4d5c6d0d0d1d1d3d4
c8c8d3d4d5d3d4d4d5c6000000000000d7c8d3d5c8c6c7c6001cc7c8c8d6d7c8c0c1c1c2d3d5d6d7d60000000000d3d4d4d500d7c8c8c8c8c8c8d3d4d4d5c8d600000000000000d3d4d50000d3d5d600f4f4f4f4d3d5f4f4000000d7c8c8d600000000000000001a0000000000d7c8c8c60b00000000d3d4d500d0d0d1d1d3d4
c8c8d3d4d5d3d4d4d5f4f4c3c4c5f4f4c3c5d3d5c60000000000d7c8c8c8c0c1c1c2d1d2d3d5c8c8c8d60000d7d6d3d4d4d5d7c8c8c8c8c6c7c8d3d4d4d5c8c8d60000d7d60000d3d4d500d7d3d5c8d60000d7d6d3d5000b0000d7c8c8c8c8d6000000000000000000000000c3c4c4c5f4f4f4f4f4f4d3d4d500d0d0d1d1d3d4
c8c8d3d4d5d3d4d4d5d6d7d3d4d5d6d7d3d5d3d5f4f4f4f4f4f4c3c5c8c8d0d1d1d2d1d2d3d5c8c8c8c8d6d7c8c8d3d4d4d5c8c8c8c8c60000c7d3d4d4d5c8c8c8d6d7c8c8d600d3d4d5d7c8d3d5c8c8d6d7c8c8d3d5000000d7c8c8c0c1c2c3c5f4f4f4f4f4f4f4f4f4c3c5d3d4d4d5000000000000d3d4d5d7d0d0c3c4c5d4
__sfx__
01020000180711a0711c0711d0711f071210712307100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
480200000032003320073300a3300d3400f3401134013350153501735018360193601a3601a370173701136009350033400031002300010000100000000000000000000000000000000000000000000000000000
190100002b3502b3502b3102b31021350213502131021310213102131021300213000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001000006770147701877017770147700f770097700477002770017700177003770067700b7700f77013770187701a7700000000000000000000000000000000000000000000000000000000000000000000000
094d0000303552e3052e3052e3052e3052e3052e3052e3052e3052e3052e3052e3052e3052e3052e3052e3052e3052e3052e3052e305000050000500005000050000500005000050000500005000050000500005
1108000024355243002435524300283552830029355293002b3552b3002b3552b3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010100003b6703767034670316702f6702b6702967025670226701e6701b67018670126700d670096700367000000000000000000000000000000000000000000000000000000000000000000000000000000000
0001000013610156501666018670196701b6701d6701f650216402264024630256302562026620276102861028610146000060000600266000000000000000000000000000000000000000000000000000000000
000100002965026640236401e6301a620176202c60000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010c00000c050100500c050100500c050100500c050100500c050100500c050100500c050100500c050100500c055000000c055000000c055000000c055000000c055000000c055000000c055000000c05500000
010c0000183501835018340183401c3501d3501d3501f3501f3501f3401d3501d3501f3501f350213502135023350233402333024350243402433023350233501f3401f3401f3301f3301c3501c3501c3401c340
010c00000c050000001005000000130500000013050000000c0500c000100500c000130500c000130500c0000c0500c000100500c000130500c000100500c000130500c000100500c000130500c0001005000000
010c000024615000002d6252d62518615000052d6252d62518615000052d6252d62518615000052d6252d62518615000052d6252d62518615000052d6252d62518615000052d6252d625186252d6252d6252d625
010c0000183501835018340183401c3501d3501d3501f3501f3501f3501d3501d3501f3501f35021350213501f3501f3501f3401f3401f3301f3301f3201f3201c3501c3501c3401c3401c3301c3301c3201c320
010c0000213502135021350213501f3501d3501d3501f3501f3501f3501f3401f340183501835018340183401a3501a3501a3401a3401c3501c3501c3401c3401d3501d3501d3401d3401f3501f3501f3401f340
010c0000214202142021430214302144021450234502445026450264502645024450244502445023450234501f4201f4201f4301f4301f4401f4401f4501f4501f4501f4501f4401f4401f4301f4301f4201f420
010c00001d4201d4201d4301d4301d4401d450214502345024450244502445023450234502345021450214501c4201c4201c4301c4301c4401c4401c4501c4501c4501c4501c4401c4401c4301c4301c4201c420
010c00001105015050110501505011050150501105015050130501705013050170501305017050130501705010050130501005013050100501305010050130501005013050100501305010050130501005013050
010c00000e050110500e050110500e050110500e0501105013050170501305017050130501705013050170500c050100500c050100500c050100500c050100500c050100500c050100500c050100500c05010050
010c00001a4101a4201a4301a4301a4401a4501c4501d4501f4501f4501f4501f4501a4501a4501a4401a4401f4101f4201f4301f4301f4401f4502145023450244502445024450244501c4501c4501c4401c440
010c00001c4101c4201c4301c4301c4401c4501d4501d4501f4501f4501d4501d4501c4501c45018450184501a4501a4501a4501a4501a4501a4501a4501a4501c4501c4501c4501c4501c4501c4501c4501c450
010c00001841018420184301844018440184501845018450184401844018440184401844018440184401844018430184301843018430184201842018420184201841018410184101841018410184101841018410
010c00000e050110500e050110500e050110500e05011050130501705013050170501305017050130501705010050130501005013050100501305010050130501505018050150501805015050180501505018050
010c00000c050100500c050100500c050100500c0501005010050130501005013050100501305010050130500b0500e0500b0500e0500b0500e0500b0500e0500c050100500c050100500c050100500c05010050
010e00000c67500000000000c6550c655306550c6550c60030655000001860030600306550000000000000050c67500000000000c6550c655306550c6550c6003065500000186003060030655000000000018600
010e00000c67500000000000c6550c655306550c6550c60030655000001860030600306550000000000000000c655000003065500000306553060030655306553065500000000000c65530655000000000000000
550e00001a4501a4501a4501a4521a4521a45221450214501f4501f4501f4501f4521f4521f4521f4521f4521a4501a4501a4501a4521a4521a45221450214501f4501f4501f4501f4521f4521f4521f4521f452
550e00001a4501a4501a4501a4521a4521a452214502145023450234502345221450214502145223450234522445024450244522345023450234521f4501f4502145021450214502145221452214522145221452
550e00001a4501a4501a4501a4521a4521a45221450214501f4501f4501f4501f4521f4521f4521f4521f4521a4501a4501a4501a4521a4521a45221450214502345023450234502345223452234522345223452
550e00001a4501a4501a4501a4521a4521a452234502345021450214502145224450244502445223450234501f4501f4501f4522145021450214521d4501d4501f4501f4501f4501f4521f4521f4521f4521f452
650e00001a3501c3501c3501d3501a3501a3501a3501a3501a3521a3521a3521a3521a3521a3521a3521a3521a3501c3501c3501d3501f3501f3501f3501f3501f3521f3521f3521f3521f3521f3521f3521f352
650e00001c3501d3501d3501f3501835018350183501835018352183521835218352183521835218352183521d3501c3501c3501d3501a3501a3501a3501a3501a3521a3521a3521a3521a3521a3521a3521a352
650e00001a4501c4501c4501d4501a4501a4501a4501a4501a4521a4521a4521a4521a4521a4521a4521a4521d4501c4501c4501f450214502145021450214502145221452214522145221452214522145221452
650e00001f45021450214502345024450244502445024450244522445224452244522645226452264522645226450234502345026450284502845028450284502845228452284522845228452284522845228452
011400000c0501005013050170501a0501d05026050230501f0501c05018050150500c0501005013050170501a0501d05026050230501f0501c0501805015050090500c0501005013050170501a0501f0501c050
0114000018050170501305010050090500c0501005013050170501a0501f0501c0501805017050130501005005050090500c0501005013050170501c050180501705013050100500c05005050090500c05010050
0114000013050170501c050180501705013050100500c050070500b0500e0501105015050180501f0501c05018050170501305010050070500b0500e0501105015050180501f0501c05018050170501305010050
491400002435424350243502435021350213501d3501d3501d3501d35018350183501f3511f35021350213502235022350213502135021350213501f3501f3501d3501d3501d3501d3501c3501c3501d3501d350
491400001d3501d350183501835024351243502435024350243502435024350243502435224352243522435226354263502635026350293502935028350283502635026350243502435026350263502435024350
4914000021350213501d3501d3501d3501d3501f3501f3502135121350223502235021350213501d3501d3501d3521d3521c3501c3501d3511d3501d3501d3501d3501d3501d3501d3501d3521d3521d3521d352
01140000180501805018050180501505015050110501105011050110500c0500c0501305013050150501505016050160501505015050150501505013050130501105011050110501105010050100501105011050
0114000011050110500c0500c0501805018050180501805018050180501805018050180501805018050180501a0501a0501a0501a0501d0501d0501c0501c0501a0501a05018050180501a0501a0501805018050
491400001505015050110501105011050110501305013050150501505016050160501505015050110501105011050110501005010050110501105011050110501105011050110501105011050110501105011050
011400003065500005186551860518655246053065524600186551865518655000003065500000306550000018655000003065500000186551865518655000003065500005186551860518655246053065500000
011400001865518655186550000030655000003065500000186550000030655000001865518655186550000030655000051865518605186552460530655000001865518655186550000030655000003065500000
011400001865500000306550000018655186551865500000306550000518655186051865524605306550000018655186551865500000306550000030655000001865500000306550000030655306553065500000
011400002805524055210551f05521055240552805524055210551f055210552405526055230551f0551c0551f0552305526055230551f0551c0551f0552305524055210551d0551a0551d055210552405521055
011400001d0551a0551d055210552805524055210551f05521055240552805524055210551f05521055240552805524055210551f05521055240552805524055210551f055210552405526055230551f0551c055
011400001f0552305526055230551f0551c0551f0552305524055210551d0551a0551d0552105524055210551d0551a0551d0552105524055210551d0551a0551d0552105524055210551d0551a0551d05521055
011000002a6352930029300293002a6002930029300293002a6352930029300293002a60026300283002b3002a6352630029300233002a6002130000000000002a6350000000000000002a600000000000000000
011800000705007050070500705007050070500205002050020500205002050020500005000050000500005000050000500004000035283002630024300243003030030300303003030030300000000000000000
011800000505005050050500505005050050500505005050050500505005050050500405004050040500205002050020500005000050000500005000050000500005000050040500405004050040500405004050
0118000018300183001a3001a3001c3001c3002b3552935528355293552835526355243551f3001f3001f300183001830018300183001a3001a3001a3001a3001a3001a3001a3001a30018300183001830018300
01180000214551d3001d3001f3001f3001f3001f3001f300214552345524455264552445523455244552645528455294552b4551d4051c4051c4051c3001c3001c3001c3001c3001c30000000000000000000000
011800001f3501f3401f3301f32018350183401a3501a3501c3501c330183501833018350183401833018320183101f3001f3001f3001f3001f3001f3001f3001f3001f3001f3001f3001f300000000000000000
011800001535015330153101c3501d3501d3301f3501f3401f3301f32018350183501f3501f3401f3301d3501d3401d3301c3501c3401c3301c3201c3101c310183501a3501c3501c3401c3301c3201d3501d340
011000000c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c0500c050
011000000e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e0500e050
011000000000000000000000000000000000000000000000290502904029050290402b0502b040290502905029050290502905029050290402904029040290402903029030290302903528050280502805028050
011000000000000000000000000000000000000000000000240502404026050260402805028040280502805028050280502805028050280402804028040280402803028030280302803528050280502805028050
4910000030455004052b45500405284550040530455004052b45500405284550040530455004052b45500405284550040530455004052b45500405284550040530455004052b4550040530455004052b45500405
010a00001c0501c0501c0501c0501c0501c0501c0501c0501c0501c0501d0511d0501d0501d0501d0501d0501d0501d0501d0501d0501f0511f0501f0501f0501305013050150511505018051180501805018050
010a00002465500000376550000537655376553765537655376550000524655000003765500000376553765537655376553765500000246550000037655000002465500000376553765537655000000000000000
010a000028450264502445023450214501f4501d4501f45021450184002945028450264502445023450214501f4502145023450184002b4502945028450264502445023450214502345024450244500000000000
__music__
00 4d0b0c44
01 0a0b0c44
00 0d0b0c44
00 0a0b0c44
00 0e0b0c44
00 0f110c44
00 10120c44
00 13160c44
00 14170c44
02 15090c44
00 5a581844
00 5a581944
01 1a581844
00 1b581944
00 1c421844
00 1d421944
00 1e421844
00 1f421944
00 20421844
02 21421944
01 652b2844
00 662c2944
00 672d2a44
00 252b2844
00 262c2944
00 272d2a44
00 2e2b2544
00 2f2c2644
02 302d2744
00 31420c44
00 32420c44
00 31420c44
00 33420c44
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
01 37353344
04 36343244
01 3b3c3844
00 3a3c3944
00 3b3c3844
00 3a3c3944
00 3b3c3831
00 3a3c3931
00 3b3c3831
02 3a3c3931
05 3f3e3d44

