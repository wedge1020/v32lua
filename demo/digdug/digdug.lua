--#title "Dig Dug - v32lua Tech Demo"
--#version "1.0"
--#texture tileset "digdug_sprites.png"

--@ ============================================================================
--@ VIRCON32 HARDWARE CONSTANTS & CONFIGURATION
--@ ============================================================================
local SCREEN_WIDTH  = 640
local SCREEN_HEIGHT = 360
local TILE_SIZE     = 32
local MAP_COLS      = 20  -- 640 / 32 = 20 columns
local MAP_ROWS      = 10  -- 320 / 32 = 10 rows (Top 40px reserved for HUD)
local HUD_OFFSET_Y  = 40

-- Sprite Sheet Coordinates (tx, ty in digdug_sprites.png)
local SPR_DIRT      = 0
local SPR_SKY       = 32
local SPR_PLAYER    = 64
local SPR_POOKA     = 0
local SPR_POOKA_EYES = 32
local SPR_HARPOON   = 0

--@ ============================================================================
--@ HARDWARE RENDERING HELPERS
--@ ============================================================================

-- Configures GPU Region 0 on the fly and renders a 32x32 sprite tile
function draw_sprite(tx, ty, screen_x, screen_y)
    ioports.gpu.texture = 0
    ioports.gpu.region  = 0
    ioports.gpu.minX    = tx
    ioports.gpu.minY    = ty
    ioports.gpu.maxX    = tx + TILE_SIZE
    ioports.gpu.maxY    = ty + TILE_SIZE
    ioports.gpu.hotX    = 0
    ioports.gpu.hotY    = 0
    ioports.gpu.x       = screen_x
    ioports.gpu.y       = screen_y
    ioports.gpu.draw()
end

--@ ============================================================================
--@ GAME STATE & MAP GENERATION
--@ ============================================================================
local Game = {}

function Game:init()
    self.score = 0
    self.lives = 3
    self.game_over = 0
    self.map = {}
    
    -- Generate underground dirt grid adhering strictly to `{}` grammar
    local row = 0
    while row < MAP_ROWS do
        self.map[row] = {}
        local col = 0
        while col < MAP_COLS do
            if row == 0 then
                self.map[row][col] = 2  -- 2 = Surface Sky/Grass
            else
                self.map[row][col] = 1  -- 1 = Underground Dirt
            end
            col = col + 1
        end
        row = row + 1
    end
end

--@ ============================================================================
--@ PLAYER (TAIZO HORI) CLASS
--@ ============================================================================
local Player = {}

function Player:init(start_col, start_row)
    self.col = start_col
    self.row = start_row
    self.x   = start_col * TILE_SIZE
    self.y   = (start_row * TILE_SIZE) + HUD_OFFSET_Y
    self.dir = 0  -- 0: Right, 1: Down, 2: Left, 3: Up
    self.speed = 2
    self.is_pumping = 0
    
    -- Clear starting position dirt
    Game.map[start_row][start_col] = 0
end

function Player:update()
    if self.is_pumping == 1 then
        return nil
    end

    -- Poll Vircon32 Gamepad 0 discrete inputs
    ioports.inp.gamepad = 0
    
    local moved = 0
    local next_col = self.col
    local next_row = self.row

    if ioports.inp.right > 0 then
        self.dir = 0
        self.x = self.x + self.speed
        next_col = (self.x + (TILE_SIZE - 4)) / TILE_SIZE
        moved = 1
    elseif ioports.inp.left > 0 then
        self.dir = 2
        self.x = self.x - self.speed
        next_col = (self.x + 4) / TILE_SIZE
        moved = 1
    elseif ioports.inp.down > 0 then
        self.dir = 1
        self.y = self.y + self.speed
        next_row = ((self.y - HUD_OFFSET_Y) + (TILE_SIZE - 4)) / TILE_SIZE
        moved = 1
    elseif ioports.inp.up > 0 then
        self.dir = 3
        self.y = self.y - self.speed
        next_row = ((self.y - HUD_OFFSET_Y) + 4) / TILE_SIZE
        moved = 1
    end

    -- Dig dirt logic & grid alignment
    if moved == 1 then
        if next_col >= 0 and next_col < MAP_COLS and next_row >= 1 and next_row < MAP_ROWS then
            self.col = next_col
            self.row = next_row
            if Game.map[self.row][self.col] == 1 then
                Game.map[self.row][self.col] = 0  -- Excavate dirt
                Game.score = Game.score + 10      -- +10 points per tile
            end
        end
    end
end

function Player:draw()
    local sprite_offset = self.dir * TILE_SIZE
    draw_sprite(SPR_PLAYER + sprite_offset, 0, self.x, self.y)
end

--@ ============================================================================
--@ HARPOON / PUMP WEAPON CLASS
--@ ============================================================================
local Harpoon = {}

function Harpoon:init()
    self.active = 0
    self.x = 0
    self.y = 0
    self.dir = 0
    self.target = nil
    self.cooldown = 0
end

function Harpoon:fire(px, py, pdir)
    if self.active == 1 or self.cooldown > 0 then
        return nil
    end
    
    self.active = 1
    self.dir = pdir
    self.x = px
    self.y = py
    
    -- Extend tip 64 pixels in facing direction
    if pdir == 0 then self.x = px + 64 end
    if pdir == 1 then self.y = py + 64 end
    if pdir == 2 then self.x = px - 64 end
    if pdir == 3 then self.y = py - 64 end
end

function Harpoon:update(enemies, enemy_count)
    if self.cooldown > 0 then
        self.cooldown = self.cooldown - 1
    end

    ioports.inp.gamepad = 0
    if ioports.inp.A > 0 then
        self:fire(Player.x, Player.y, Player.dir)
    end

    if self.active == 0 then
        return nil
    end

    -- Check collision against enemies
    local idx = 0
    while idx < enemy_count do
        local e = enemies[idx]
        if e.alive == 1 then
            local dx = self.x - e.x
            local dy = self.y - e.y
            -- Simple bounding box check
            if dx > -24 and dx < 24 and dy > -24 and dy < 24 then
                self.target = e
                e.inflation = e.inflation + 1
                self.active = 0
                self.cooldown = 15
                
                -- Pop enemy at inflation level 4!
                if e.inflation >= 4 then
                    e.alive = 0
                    Game.score = Game.score + 200
                end
                break
            end
        end
        idx = idx + 1
    end
    
    -- Retract if missed
    if self.target == nil then
        self.cooldown = 10
        self.active = 0
    end
end

function Harpoon:draw()
    if self.active == 1 then
        draw_sprite(SPR_HARPOON, 64, self.x, self.y)
    end
end

--@ ============================================================================
--@ ENEMY (POOKA) CLASS
--@ ============================================================================
local Enemy = {}

function Enemy:init(start_col, start_row)
    self.x = start_col * TILE_SIZE
    self.y = (start_row * TILE_SIZE) + HUD_OFFSET_Y
    self.dir = 0
    self.speed = 1
    self.alive = 1
    self.is_ghost = 0
    self.inflation = 0
    self.ghost_timer = 0
end

function Enemy:update()
    if self.alive == 0 or self.inflation > 0 then
        return nil
    end

    -- Basic AI: Patrol horizontal tunnels or enter Ghost Mode to pass dirt
    self.ghost_timer = self.ghost_timer + 1
    if self.ghost_timer > 180 then
        self.is_ghost = 1
    end

    if self.is_ghost == 1 then
        -- Move directly toward player through dirt
        if self.x < Player.x then self.x = self.x + self.speed end
        if self.x > Player.x then self.x = self.x - self.speed end
        if self.y < Player.y then self.y = self.y + self.speed end
        if self.y > Player.y then self.y = self.y - self.speed end
        
        -- Return to normal when reaching open tunnel
        local col = (self.x + 16) / TILE_SIZE
        local row = ((self.y - HUD_OFFSET_Y) + 16) / TILE_SIZE
        if Game.map[row][col] == 0 then
            self.is_ghost = 0
            self.ghost_timer = 0
        end
    else
        -- Normal movement
        if self.dir == 0 then self.x = self.x + self.speed end
        if self.dir == 2 then self.x = self.x - self.speed end
        
        -- Bounce off screen borders
        if self.x <= 0 then self.dir = 0 end
        if self.x >= SCREEN_WIDTH - TILE_SIZE then self.dir = 2 end
    end
    
    -- Check lethal collision with Player
    local dx = self.x - Player.x
    local dy = self.y - Player.y
    if dx > -20 and dx < 20 and dy > -20 and dy < 20 then
        Game.lives = Game.lives - 1
        Player:init(10, 4) -- Reset player position
    end
end

function Enemy:draw()
    if self.alive == 0 then
        return nil
    end

    if self.inflation > 0 then
        -- Draw inflated sprite frame
        local inflate_offset = self.inflation * TILE_SIZE
        draw_sprite(SPR_POOKA + inflate_offset, 32, self.x, self.y)
    elseif self.is_ghost == 1 then
        -- Draw floating eyes in dirt
        draw_sprite(SPR_POOKA_EYES, 32, self.x, self.y)
    else
        draw_sprite(SPR_POOKA, 32, self.x, self.y)
    end
end

--@ ============================================================================
--@ MAIN EXECUTION LOOP
--@ ============================================================================

Game:init()
Player:init(10, 4)
Harpoon:init()

-- Instantiate enemy pool using while loop (no for-loops in v32lua!)
local enemies = {}
local ENEMY_COUNT = 3
local i = 0
while i < ENEMY_COUNT do
    enemies[i] = {}
    -- Set prototype methods manually to simulate class instance
    enemies[i].init   = Enemy.init
    enemies[i].update = Enemy.update
    enemies[i].draw   = Enemy.draw
    
    enemies[i]:init(4 + (i * 5), 3 + (i * 2))
    i = i + 1
end

-- Main Hardware Frame Loop
while 1 == 1 do
    -- 1. Hardware Screen Clear Intrinsic
    ioports.gpu.clear("black")
    
    if Game.lives > 0 then
        -- 2. Update Game Entities
        Player:update()
        Harpoon:update(enemies, ENEMY_COUNT)
        
        local e_idx = 0
        while e_idx < ENEMY_COUNT do
            enemies[e_idx]:update()
            e_idx = e_idx + 1
        end
    end

    -- 3. Render Underground Map Grid
    local r = 0
    while r < MAP_ROWS do
        local c = 0
        while c < MAP_COLS do
            local tile_type = Game.map[r][c]
            local screen_x = c * TILE_SIZE
            local screen_y = (r * TILE_SIZE) + HUD_OFFSET_Y
            
            if tile_type == 1 then
                draw_sprite(SPR_DIRT, 0, screen_x, screen_y)
            elseif tile_type == 2 then
                draw_sprite(SPR_SKY, 0, screen_x, screen_y)
            end
            c = c + 1
        end
        r = r + 1
    end

    -- 4. Render Entities
    local d_idx = 0
    while d_idx < ENEMY_COUNT do
        enemies[d_idx]:draw()
        d_idx = d_idx + 1
    end
    
    Player:draw()
    Harpoon:draw()

    -- 5. Render HUD UI using NaN-boxed string concatenation & print intrinsic
    print(16, 10, "SCORE: " .. Game.score)
    print(520, 10, "LIVES: " .. Game.lives)
    
    if Game.lives <= 0 then
        print(260, 180, "GAME OVER")
    end

    -- 6. Hardware Vsync Wait Intrinsic (Injects Vircon32 WAIT instruction)
    __asm__("WAIT")
end
