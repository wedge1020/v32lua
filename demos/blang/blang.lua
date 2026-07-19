--#title "BLANG!"
--#version "0.5"

-- 1. Initialize global tables at the root scope
player  = { }
enemies = { }

-- 2. Updated OOP draw method with compile-time string literal branching
function draw(object, mode)
    ioports.gpu.region   = object.r   -- set the region
    ioports.gpu.x        = object.x   -- set drawing point X
    ioports.gpu.y        = object.y   -- set drawing point Y
    
    -- Evaluate mode at runtime and invoke the intrinsic with static literals!
    if (mode == "zoom") then
        ioports.gpu.draw("zoom")      -- Emits: OUT GPU_Command, GPUCommand_DrawRegionZoomed
    elseif (mode == "rotate") then
        ioports.gpu.draw("rotate")    -- Emits: OUT GPU_Command, GPUCommand_DrawRegionRotated
    elseif (mode == "rotozoom") then
        ioports.gpu.draw("rotozoom")  -- Emits: OUT GPU_Command, GPUCommand_DrawRegionRotozoomed
    else
        ioports.gpu.draw()            -- Emits: OUT GPU_Command, GPUCommand_DrawRegion (Handles nil or "draw")
    end
end

function player:draw(mode)
    draw(self, mode)
end

function init()
    ioports.gpu.texture  = -1  -- set BIOS font/sprite texture
    
    -- Initialize player properties
    player.r             = 94  -- region
    player.x             = 315 -- x position
    player.y             = 170 -- y position
    player.v             = 0   -- velocity

    -- 3. Initialize an array of 4 enemies with distinct velocities and starting positions
    index = 1
    while index <= 4 do
        enemies[index] = { }
        enemies[index].r  = 80 + (index * 2)     -- assign slightly different visual regions
        enemies[index].x  = 100 * index          -- stagger initial X positions across screen
        enemies[index].y  = 50  * index          -- stagger initial Y positions down screen
        enemies[index].xv   = (index % 2 == 0) and 3 or -3 -- alternate horizontal directions
        enemies[index].yv   = (index > 2)      and 2 or -2 -- alternate vertical directions
        enemies[index].draw = player.draw       -- attach our OOP draw method to the enemy!
        index = index + 1
    end

    ioports.gpu.clear("black") -- initial clear screen

    -- Draw player and enemies at initial positions
    player:draw()
    index = 1
    while index <= 4 do
        enemies[index]:draw()
        index = index + 1
    end
end

function game_loop()
    -- --- PLAYER INPUT & PHYSICS ---
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

    -- Draw Player
    player:draw()

    -- --- ENEMY PONG-STYLE MOVEMENT & REFLECTION ---
    index = 1
    while index <= 4 do
        e = enemies[index]
        
        -- Apply velocity vectors to position
        e.x = e.x + e.xv
        e.y = e.y + e.yv

        -- Horizontal Screen Bounce (Left: 0, Right: 640)
        if (e.x <= 0) or (e.x >= 640) then
            e.xv = -e.xv -- Invert horizontal velocity vector
        end

        -- Vertical Screen Bounce (Top: 0, Bottom: 360)
        if (e.y <= 0) or (e.y >= 360) then
            e.yv = -e.yv -- Invert vertical velocity vector
        end

        -- Render enemy using default drawing (or "zoom", "rotate", "rotozoom")
        e:draw() 
        index = index + 1
    end
end
