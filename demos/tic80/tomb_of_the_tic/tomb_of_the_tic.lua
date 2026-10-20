--#title "Tomb of the Tic"
--#api tic80
-- title:  Tomb Of The Tic
-- author: betty.wolfy
-- desc:   You have entered the ancient sacred tomb in search of the golden Mask of Tic. The tomb is full of levels, the lower you go, the harder it gets.
-- script: lua
-- saveid: tomboftheticewau

-- this code has no salvation.

table = { }

DEBUG   = false;
VERSION = "0.2.0";

-- tiles flags
SOLID_FLAG      = 0;
DAMAGE_FLAG     = 1;
TRAP_FLAG       = 2;
BOUNCEABLE_FLAG = 3;

-- specific tiles
BARRIER_TILE = 188;
ENDING_TILE  = 191;
STAR_TILE    = 204;
PLAYER_TILE  = 205;
DOT_TILE     = 206;
PUFFER_TILE  = 207;
ARCHER_TILE  = 220;
MASK_TILE    = 236;

-- game states
INTRO_GAMESTATE   = 0;
MENU_GAMESTATE    = 1;
CREDITS_GAMESTATE = 2;
PLAY_GAMESTATE    = 3;

-- gameplay mode
PLAYING_GAMEMODE  = 0;
PAUSED_GAMEMODE   = 1;
GAMEOVER_GAMEMODE = 2;
CLEARED_GAMEMODE  = 3;

-- persistent memory addresses
COIN_ADDRESS     = 1;
UNLOCKED_ADDRESS = 2;
STAR_ADDRESS     = 3;

function clearMap()
  for x = 0, 239 do
    for y = 0, 135 do
      mset(x, y, 0);
    end
  end
end

-- variables

cameraX, cameraY = 0, 0;

frame, delta = 0, 0;

credits = {
  "Sprite", "Eliezer De M.B",
  "Programming", "betty.wolfy",
  "Inspiration", "Tomb Of The Mask"
};

frame = 0;
selectedLevel = 1;
gameState = INTRO_GAMESTATE;
gameMode = PLAYING_GAMEMODE;

function BOOT()
  if DEBUG then
    -- tilesets
    autotile(1, {33});
    autotile(17, {1});
    autotile(33, {1});
    
    sync(0, 0, true);
  end
  
  -- cache level boundaries
  do
    levelData = {};
    for x = 0, 239 do
      for y = 0, 135 do
        if mget(x, y) == 240 then
          -- size
          local sx, sy = x, y;
          local w = 1;
          sx = sx + 1;
          while mget(sx, sy) ~= 241 do
            sx = sx + 1;
            w = w + 1;
          end
          sy = sy + 1;
          local h = 1;
          while mget(sx, sy) ~= 241 do
            sy = sy + 1;
            h = h + 1;
          end
          
          -- storage
          local data = {};
          for iy = 0, h do
            for ix = 1, w do
              data[#data + 1] = mget(ix + x - 1, iy + y + 1);
            end
          end
          levelData[#levelData + 1] = {data, w, h};
        end
      end
    end
    
    unlockedLevels = min(max(1, pmem(UNLOCKED_ADDRESS)), #levelData);
  end
  
  -- player utils
  local function btnToRot(b)
    if b == 0 then
      return 3;
    elseif b == 1 then
      return 1;
    elseif b == 2 then
      return 2;
    end
    return 0;
  end
  
  player = {
    x = 0, y = 0,
    w = 8, h = 8,
    
    moving = false,
    mx = 0, my = 0,
    maskLink = false
  };
  function player:shouldStop(mx, my)
    local wc = rectVsTileFlag(self.x + mx, self.y + my, self.w, self.h, SOLID_FLAG);
    if wc then return true; end
    
    -- masks
    for i = 1, #masks.instances do
      local o = masks.instances[i];
      if
        rectVsRect(
          self.x + mx, self.y + my, self.w,
          self.h, o.x, o.y, 8, 8
        )
      then
        if o.frame == 0 then
          self.maskLink = o;
          self.maskDir = self.r;
          self.moving = false;
        end
        return true;
      end
    end
    return false;
  end
  function player:controls()
    if
      not (
        self.moving or
        (
          self.maskLink and
          self.maskLink.frame > 0
        )
      )
    then
      for i = 0, 3 do
        if btn(i) then
          self.moving = true;
          self.r = btnToRot(i);
          self.maskLink = false;
          return;
        end
      end
      --[[if swt then
        if abs(swx) > abs(swy) then
          self.r = (swx > 0) and 0 or 2;
        else
          self.r = (swy > 0) and 1 or 3;
        end
        self.moving = true;
        self.maskLink = false;
        return;
      end]]
    end
  end
  function player:update()
    cameraX = lerp(cameraX, self.x - 120, .15) // 1;
    cameraY = lerp(cameraY, self.y - 68, .15) // 1;
    
    if rectVsTileFlag(self.x, self.y, self.w, self.h, DAMAGE_FLAG) then
      signGameOver();
      return;
    end
    
    if self.maskLink then
      local dx, dy = dirToXY(self.maskDir);
      self.x = self.maskLink.x - dx * 8;
      self.y = self.maskLink.y - dy * 8;
      self.r = self.maskDir;
      if self:shouldStop(0, 0) then
        self.maskLink = false;
      end
    end
    
    -- dots
    local test, x, y = rectVsTile(self.x, self.y, self.w, self.h, DOT_TILE);
    if test then
      dots = dots + 1;
      mset(x, y, 0);
    end
    
    -- trap wall
    for i = 0, 3 do
      local dx, dy = dirToXY(i);
      local test, x, y = rectVsTileFlag(
        self.x - dx * 8,
        self.y - dy * 8,
        self.w,
        self.h,
        TRAP_FLAG
      );
      if test then
        spikes:create(x + dx, y + dy, i);
        break;
      end
    end
    
    -- springs
    do
      local mx, my = dirToXY(self.r);
      local test, x, y, tile = rectVsTileFlag(self.x, self.y, self.w, self.h, BOUNCEABLE_FLAG);
      if test then
        tile = tile - 112;
        self.x = x * 8;
        self.y = y * 8;
        if mx == 0 then
          if tile == 0 or tile == 3 then
            self.r = 0;
          else
            self.r = 2;
          end
        else
          if tile < 2 then
            self.r = 1;
          else
            self.r = 3;
          end
        end
      end
    end
    
    if self.x == endingX and self.y == endingY then
      signLevelClear();
    end
    
    if self.moving then
      local mx, my = dirToXY(self.r);
      local stopped = self:shouldStop(mx, my);
      if (not stopped) then
        self.trail[#self.trail + 1] = {self.x, self.y, self.r};
        self.x = self.x + mx * 8;
        self.y = self.y + my * 8;
      else
        self.moving = false;
      end
    end
  end
  
  -- game objects
  puffers = { instances = {} };
  function puffers:draw()
    for i = 1, #self.instances do
      local o = self.instances[i];
      local size = min(3, o.frame + 1);
      local hsize = (size - 1) * 4;
      local anim = 263 + (o.frame * (o.frame + 1)) // 2;
      spr(
        anim,
        o.x - hsize - cameraX,
        o.y - hsize - cameraY,
        9, 1, 0, 0, size, size
      );
      
      -- behavior
      if DEBUG then
        circb(
          o.x + 4 - cameraX,
          o.y + 4 - cameraY,
          5 * size - 1, 10
        );
      end
      if gameMode == PLAYING_GAMEMODE then
        if not o.dmg then
          if o.tickDmg < 70 then
            o.tickDmg = o.tickDmg + 1;
          else
            o.frame = o.frame + 1;
            if o.frame == 3 then
              o.dmg = true;
            end
          end
        else
          local dist = distance(o.x, o.y, player.x, player.y);
          if dist <= 5 * size then
            signGameOver();
            return;
          else
            if o.tickDmg > 0 then
              o.tickDmg = o.tickDmg - 1;
            else
              o.frame = o.frame - 1;
              if o.frame == 0 then
                o.dmg = false;
              end
            end
          end
        end
      end
    end
  end
  function puffers:create(x, y)
    table.insert(self.instances, {
      x = x * 8,
      y = y * 8,
      frame = 0,
      tickDmg = 0,
      dmg = false
    });
  end
  
  archers = { instances = {} };
  function archers:draw()
    for i = 1, #self.instances do
      local o = self.instances[i];
      local anim = (o.tick < 80) and 416 or 417;
      spr(
        anim,
        o.x - cameraX,
        o.y - cameraY,
        9, 1, 0, o.rot
      );
      
      -- behavior
      if gameMode == PLAYING_GAMEMODE then
        o.tick = (o.tick + 1) % 100;
        if o.tick == 80 then
          local dx, dy = dirToXY(o.rot);
          arrows:create(o.x // 8 + dx, o.y // 8 + dy, o.rot);
        end
      end
    end
  end
  function archers:create(x, y, rot)
    table.insert(self.instances, {
      x = x * 8,
      y = y * 8,
      rot = rot,
      tick = 0
    });
  end
  
  arrows = { instances = {} };
  function arrows:draw()
    for i = #self.instances, 1, -1 do
      local o = self.instances[i];
      spr(
        418,
        o.x - cameraX,
        o.y - cameraY,
        0, 1, 0, o.rot
      );
      
      -- behavior
      local dx, dy = dirToXY(o.rot);
      
      -- collision box
      local cw, ch = max(4, dx * 8), max(4, dy * 8);
      local cx = (cw < ch) and 2 or 0;
      local cy = 2 - cx;
      if DEBUG then
        rectb(
          o.x + cx - cameraX,
          o.y + cy - cameraY,
          cw, ch, 10
        );
      end
      if gameMode == PLAYING_GAMEMODE then
        o.x = o.x + dx * 4;
        o.y = o.y + dy * 4;
        if rectVsTileFlag(o.x + cx, o.y + cy, cw, ch, SOLID_FLAG) then
          table.remove(self.instances, i);
        elseif
          rectVsRect(
            player.x, player.y,
            player.w, player.h,
            o.x + cx, o.y + cy,
            cw, ch
          )
        then
          signGameOver();
          return;
        end
      end
    end
  end
  function arrows:create(x, y, rot)
    table.insert(self.instances, {
      x = x * 8,
      y = y * 8,
      rot = rot
    });
  end
  
  spikes = { instances = {} };
  function spikes:draw()
    for i = #self.instances, 1, -1 do
      local o = self.instances[i];
      spr(
        272 + o.frame,
        o.x - cameraX,
        o.y - cameraY,
        0, 1, 0, o.rot
      );
      
      -- behavior
      if gameMode == PLAYING_GAMEMODE then
        if not o.dmg then
          if o.tickDmg < 30 then
            o.tickDmg = o.tickDmg + 1;
          else
            if o.frame < 3 then
              o.frame = o.frame + 1;
            else
              o.tickDmg = 0;
              o.dmg = true;
            end
          end
        else
          if
            rectVsRect(
              player.x, player.y,
              player.w, player.h,
              o.x, o.y, 8, 8
            )
          then
            signGameOver();
            return;
          end
          
          if o.tickDmg < 60 then
            o.tickDmg = o.tickDmg + 1;
          else
            if o.frame > 0 then
              o.frame = o.frame - 1;
            else
              table.remove(self.instances, i);
            end
          end
        end
      end
    end
  end
  function spikes:create(x, y, rot)
    table.insert(self.instances, {
      x = x * 8,
      y = y * 8,
      rot = rot,
      frame = 0,
      tickDmg = 0,
      dmg = false
    });
  end
  
  masks = { instances = {} };
  function masks:draw()
    for i = 1, #self.instances do
      local o = self.instances[i];
      local kf = ((o.frame - 1) % 40) // 10;
      local anim = (o.frame == 0) and 388 or (384 + kf);
      local dx, dy = dirToXY(o.rot);
      spr(anim, o.x - cameraX, o.y - cameraY, 9, 1, 0, o.rot);
      if o.frame ~= 0 then
        spr(368 + kf, o.x - dx * 8 - cameraX, o.y - dy * 8 - cameraY, 0, 1, 0, o.rot);
      end
      
      -- behavior
      if gameMode == PLAYING_GAMEMODE then
        if o.frame == 0 then
          if o.tickDmg < 50 then
            o.tickDmg = o.tickDmg + 1;
          else
            o.frame = 1;
            o.tickDmg = 0;
          end
        else
          if
            rectVsRect(
              player.x, player.y, player.w,
              player.h, o.x, o.y, 8, 8
            ) and
            o.frame > 0
          then
            signGameOver();
            return;
          end
        
          o.frame = o.frame + 1;
          o.x = o.x + dx * 2;
          o.y = o.y + dy * 2;
          if
            rectVsTileFlag(o.x, o.y, 8, 8, SOLID_FLAG) or
            rectVsTileFlag(o.x, o.y, 8, 8, DAMAGE_FLAG)
          then
            o.frame = 0;
            o.rot = (o.rot + 2) % 4;
            while
              rectVsTileFlag(o.x, o.y, 8, 8, SOLID_FLAG) or
              rectVsTileFlag(o.x, o.y, 8, 8, DAMAGE_FLAG)
            do
              o.x = o.x - dx;
              o.y = o.y - dy;
            end
          end
        end
      end
    end
  end
  function masks:create(x, y, rot)
    table.insert(self.instances, {
      x = x * 8,
      y = y * 8,
      frame = 0,
      rot = rot,
      tickDmg = 0
    });
  end
end


-- game


function drawBorder(which)
  spr(304, (240 - (16 * 8)) / 2, 0, 0, 1, 0, 0, 16, 2);
  
  local kf = frame / 12;
  for x = 0, 239 do
    local color = (x <= 128) and 1 or 5;
    if which ~= 1 then
      local c = cos(radians(x) + kf) * 1.5;
      pix(x, 23 + (3 + c), color);
    end
    if which ~= 0 then
      local c2 = sin(radians(x) - kf) * 1.5;
      pix(x, 114 - (3 + c2), 1);
    end
  end
end

function drawLevel()
  local level = levelData[selectedLevel];
  map(0, 0, level[2], level[3], -cameraX, -cameraY, -1);
  -- rectb(-cameraX, -cameraY, level[2] * 8, level[3] * 8, 12);
  
  for i = #coins, 1, -1 do
    local o = coins[i];
    spr(353, o[1] - cameraX, o[2] - cameraY, 9);
    
    -- behavior
    if
      rectVsRect(
        player.x, player.y, player.w, player.h,
        o[1] + 1, o[2] + 1, 6, 6
      )
    then
      score = score + 1;
      dots = dots + 1;
      table.remove(coins, i);
    end
  end
  
  for i = #stars, 1, -1 do
    local o = stars[i];
    spr(337 + frame // 8 % 4, o[1] - cameraX, o[2] - cameraY, 9);
    
    -- behavior
    if
      rectVsRect(
        player.x, player.y, player.w, player.h,
        o[1], o[2], 8, 8
      )
    then
      table.remove(stars, i);
    end
  end
  
  spr(344 + frame // 8 % 4, endingX - cameraX, endingY - cameraY, 0);
  
  puffers:draw();
  archers:draw();
  arrows:draw();
  spikes:draw();
  masks:draw();
  
  -- player
  for i = #player.trail, 1, -1 do
    local o = player.trail[i];
    local anim = i == 1 and 260 or 261;
    if i > 1 then
      local d = player.trail[i - 1];
      local turn = o[3] ~= d[3];
      if turn then anim = 262; end
    end
    spr(anim, o[1] - cameraX, o[2] - cameraY, 9, 1, 0, o[3]);
    if
      i > 6 or (not player.moving) and i == 1
    then
      table.remove(player.trail, 1);
    end
  end
  spr(256 + frame // 10 % 4, player.x - cameraX, player.y - cameraY, 9, 1, 0, player.r);
  if DEBUG then
    rectb(player.x - cameraX, player.y - cameraY, player.w, player.h, 10);
  end
end

do
  local slsx = 1; -- selected level scroll x
  
  function ui()
    if gameState == INTRO_GAMESTATE then
      drawBorder(0);
      
      -- controls
      printMM(VERSION, 120, 102, 1, true, 1, true);
      printMB("PRESS (A) TO START", 120, 132, frame % 60 < 30 and 1 or 5, true, 1, true);
      
      if btnp(4) then gameState = MENU_GAMESTATE; end
      return;
    end
    
    if gameState == MENU_GAMESTATE then
      drawBorder(2);
      
      -- level list
      for i = #levelData, selectedLevel + 1, -1 do
        local j = (i - slsx) * 40;
        local size = min(1, abs(j) / 50);
        size = lerp(30, 15, size) // 1;
        j = 120 - size + j;
        
        if j < -size * 2 then break; end
        if j <= 240 then
          rect(j, 68 - size, 2 * size, 2 * size, 0);
          local color = (i <= unlockedLevels) and 1 or 5;
          rectb(j, 68 - size, 2 * size, 2 * size, color);
          printMM(i, j + size, 68, color, false, 2, false);
        end
      end
      for i = 0, selectedLevel do
        local j = (i - slsx) * 40;
        local size = min(1, abs(j) / 50);
        size = lerp(30, 15, size) // 1;
        j = 120 - size + j;
        if j > 240 then break; end
        if j >= -size * 2 then
          rect(j, 68 - size, 2 * size, 2 * size, 0);
          rectb(j, 68 - size, 2 * size, 2 * size, 1);
          if i == 0 then
            spr(337, j + size - 4, 64, 9);
          else
            printMM(i, j + size, 68, 1, false, 2, false);
            -- stars
            if i == selectedLevel then
              local spacing = size / 1.75;
              local value = pmem(STAR_ADDRESS + selectedLevel);
              spr(value > 0 and 337 or 336, j + size - 4 - spacing, 80, 9);
              spr(value > 1 and 337 or 336, j + size - 4, 80, 9);
              spr(value == 3 and 337 or 336, j + size - 4 + spacing, 80, 9);
            end
          end
        end
      end
      
      printMB("(A) PLAY LEVEL", 120, 132, 1, true, 1, true);
      
      -- controls
      -- little trick to avoid the risk of `selectedLevel`
      -- becoming a float number.
      slsx = lerp(slsx, selectedLevel, .15);
      
      if btnp(2) then
        if selectedLevel > 0 then
          selectedLevel = selectedLevel - 1;
        end
      elseif btnp(3) then
        if selectedLevel < unlockedLevels then
          selectedLevel = selectedLevel + 1;
        end
      elseif btnp(4) then
        slsx = selectedLevel;
        if selectedLevel == 0 then
          gameState = CREDITS_GAMESTATE;
        else
          loadLevel();
        end
      end
      
      return;
    end
    
    if gameState == CREDITS_GAMESTATE then
      drawBorder(0);
      
      for k = 1, #credits, 2 do
        local w = print(credits[k], 14, 45 + (k - 1) * 10, 1, true, 1, true);
        local w2 = printRM(credits[k + 1], 227, 48 + (k - 1) * 10, 1, true, 1, true);
        
        -- dots
        local h = (222 - w2) - (18 - w);
        local s = (h / (h / 3)) // 1;
        for x = 18 + w, 222 - w2, s do
          pix(x, 50 + (k - 1) * 10, 1);
        end
      end
      
      printMB("(A) MENU", 120, 132, 1, true, 1, true);
      
      -- controls
      if btnp(4) then
        gameState = MENU_GAMESTATE;
      end
      return;
    end
    
    -- game state
    
    if gameMode ~= PLAYING_GAMEMODE then
      for i = 0, 29 do
        for j = 0, 16 do
          spr(511, i * 8, j * 8, 9);
        end
      end
    end
    
    -- level cleared
    if gameMode == CLEARED_GAMEMODE then
      rect(60, 15, 120, 106, 0);
      rectb(60, 15, 120, 106, 1);
      
      printMM("LEVEL " .. selectedLevel, 120, 25, 1, true, 1, true);
      printMM("CLEARED!", 120, 36, 1, true, 2, false);
      
      for a = 0, 2 do
        spr((3 - #stars) <= a and 336 or 337, 85 + (a * 27), 60, 9, 2);
      end
      
      printMM(string.format("%s / %s .. DOTS COLLECTED", score, score + dots), 120, 100, 1, true, 1, true);
      printMM("(A) CONTINUE", 120, 111, 1, true, 1, true);
      
      -- controls
      if btnp(4) then
        gameState = MENU_GAMESTATE;
      end
      return;
    end
    
    -- game over
    if gameMode == GAMEOVER_GAMEMODE then
      rect(55, 35, 130, 66, 0);
      rectb(55, 35, 130, 66, 1);
      
      printMM("LEVEL " .. selectedLevel, 120, 45, 1, true, 1, true);
      printMM("GAME OVER", 120, 56, 1, true, 2, false);
      
      print("(A) RETRY", 75, 88, 1, true, 1, true);
      printRM("(B) MENU", 165, 91, 1, true, 1, true);
      
      -- controls
      if btnp(4) then
        loadLevel();
      elseif btnp(5) then
        gameState = MENU_GAMESTATE;
      end
      return;
    end
    
    -- pause
    if gameMode == PAUSED_GAMEMODE then
      rect(65, 35, 110, 66, 0);
      rectb(65, 35, 110, 66, 1);
      
      printMM("LEVEL " .. selectedLevel, 120, 45, 1, true, 1, true);
      printMM("PAUSED", 120, 56, 1, true, 2, false);
      
      print("(A) RESUME", 75, 88, 1, true, 1, true);
      printRM("(B) MENU", 165, 91, 1, true, 1, true);
      
      -- controls
      if btnp(4) then
        gameMode = PLAYING_GAMEMODE;
      elseif btnp(5) then
        gameState = MENU_GAMESTATE;
      end
      return;
    end
    
    if btnp(4) then
      gameMode = PAUSED_GAMEMODE;
    end
  end
end

function signLevelClear()
  gameMode = CLEARED_GAMEMODE;
  
  if selectedLevel == unlockedLevels then
    unlockedLevels = min(#levelData, unlockedLevels + 1);
    pmem(UNLOCKED_ADDRESS, unlockedLevels);
    
    local addr = STAR_ADDRESS + selectedLevel;
    pmem(addr, max(pmem(addr), 3 - #stars));
    selectedLevel = unlockedLevels;
  end
end
function signGameOver()
  gameMode = GAMEOVER_GAMEMODE;
end
function eraseLevel()
  clearMap();
  player.r = 1;
  player.moving = false;
  player.maskLink = false;
  player.trail = {};
  endingX, endingY = 0, 0;
  score, dots = 0, 0;
  
  spikes.instances,
  puffers.instances,
  archers.instances,
  masks.instances,
  arrows.instances,
  coins, stars =
  {}, {}, {}, {}, {}, {}, {};
end
function loadLevel()
  eraseLevel();
  
  local level = levelData[selectedLevel];
  for i = 1, #level[1] do
    local tile = level[1][i];
    local x = (i - 1) % level[2];
    local y = (i - 1) // level[2];
    if tile == PLAYER_TILE then
      player.x = x * 8;
      player.y = y * 8;
    elseif tile == ENDING_TILE then
      endingX = x * 8;
      endingY = y * 8;
    elseif tile == STAR_TILE then
      if #stars == 3 then
        exit(selectedLevel);
      end
      table.insert(stars, {x * 8, y * 8});
    elseif tile == PUFFER_TILE then
      puffers:create(x, y);
      mset(x, y, BARRIER_TILE);
    elseif tile >= ARCHER_TILE and tile <= ARCHER_TILE + 3 then
      archers:create(x, y, tile - ARCHER_TILE);
      mset(x, y, BARRIER_TILE);
    elseif tile >= MASK_TILE and tile <= MASK_TILE + 3 then
      masks:create(x, y, tile - MASK_TILE);
    elseif tile == DOT_TILE then
      dots = dots + 1;
      if random() > .88 then
        table.insert(coins, {x * 8, y * 8});
      else
        mset(x, y, tile);
      end
    else
      mset(x, y, tile);
    end
  end
  
  cameraX = player.x - 120;
  cameraY = player.y - 68;
  
  gameState = PLAY_GAMESTATE;
  gameMode = PLAYING_GAMEMODE;
end

-- tic

local lastNow = time();

function TIC()
  local now = time();
  delta = 1 / (now - lastNow);
  lastNow = now;
  
  cls(0);
  if gameState == PLAY_GAMESTATE then
    if gameMode == PLAYING_GAMEMODE then
      player:controls();
      player:update();
    end
    drawLevel();
  end
  ui();
  
  if DEBUG then
    print(floor(delta * 1000), 2, 2, 1);
  end
  
  frame = frame + 1;
end





floor, abs, cos, sin, sqrt, max, min, radians, random = math.floor, math.abs, math.cos, math.sin, math.sqrt, math.max, math.min, math.rad, math.random;

function lerp(x, y, t)
  return (1 - t) * x + t * y;
end
function sign(x)
  return x > 0 and 1 or (x < 0 and -1 or 0);
end
function distance(x, y, x2, y2)
  return sqrt((x - x2) * (x - x2) + (y - y2) * (y - y2));
end

function printMT(text, x, y, color, mono, scale, small)
  color = color or 15
  mono = mono or false
  scale = scale or 1
  small = small or false
  local width = print(text, 240, 255, 0, mono, scale, small);
  return print(text, x - width // 2, y, color, mono, scale, small);
end
function printRT(text, x, y, color, mono, scale, small)
  color = color or 15
  mono = mono or false
  scale = scale or 1
  small = small or false
  local width = print(text, 240, 255, 0, mono, scale, small);
  return print(text, x - width, y, color, mono, scale, small);
end
function printLM(text, x, y, color, mono, scale, small)
  color = color or 15
  mono = mono or false
  scale = scale or 1
  small = small or false
  local width = print(text, 240, 255, 0, mono, scale, small);
  return print(text, x, y - 3 * scale, color, mono, scale, small);
end
function printMM(text, x, y, color, mono, scale, small)
  color = color or 15
  mono = mono or false
  scale = scale or 1
  small = small or false
  local width = print(text, 240, 255, 0, mono, scale, small);
  return print(text, x - width // 2, y - 3 * scale, color, mono, scale, small);
end
function printRM(text, x, y, color, mono, scale, small)
  color = color or 15
  mono = mono or false
  scale = scale or 1
  small = small or false
  local width = print(text, 240, 255, 0, mono, scale, small);
  return print(text, x - width, y - 3 * scale, color, mono, scale, small);
end
function printLB(text, x, y, color, mono, scale, small)
  color = color or 15
  mono = mono or false
  scale = scale or 1
  small = small or false
  local width = print(text, 240, 255, 0, mono, scale, small);
  return print(text, x, y - 6 * scale, color, mono, scale, small);
end
function printMB(text, x, y, color, mono, scale, small)
  color = color or 15
  mono = mono or false
  scale = scale or 1
  small = small or false
  local width = print(text, 240, 255, 0, mono, scale, small);
  return print(text, x - width // 2, y - 6 * scale, color, mono, scale, small);
end
function printRB(text, x, y, color, mono, scale, small)
  color = color or 15
  mono = mono or false
  scale = scale or 1
  small = small or false
  local width = print(text, 240, 255, 0, mono, scale, small);
  return print(text, x - width, y - 6 * scale, color, mono, scale, small);
end

-- table
function table.indexof(tabl, value)
  local len = #tabl;
  for i = 1, len do
    if tabl[i] == value then
      return i;
    end
  end
  return 0;
end
function table.has(tabl, value)
  return table.indexof(tabl, value) > 0;
end

function rectVsRect(x, y, w, h, x2, y2, w2, h2)
  return x + w > x2 and y + h > y2 and x < x2 + w2 and y < y2 + h2;
end
function rectVsTile(x, y, w, h, tile)
  local ty, by = y // 8, (y + h - 1) // 8;
  local lx, rx = x // 8, (x + w - 1) // 8;
  local tl = mget(lx, ty);
  if tl == tile then return true, lx, ty; end
  local tr = mget(rx, ty);
  if tr == tile then return true, rx, ty; end
  local bl = mget(lx, by);
  if bl == tile then return true, lx, by; end
  local br = mget(rx, by);
  return br == tile, rx, by;
end
function rectVsTileFlag(x, y, w, h, flag)
  local ty, by = y // 8, (y + h - 1) // 8;
  local lx, rx = x // 8, (x + w - 1) // 8;
  local tl = mget(lx, ty);
  if fget(tl, flag) then return true, lx, ty, tl; end
  local tr = mget(rx, ty);
  if fget(tr, flag) then return true, rx, ty, tr; end
  local bl = mget(lx, by);
  if fget(bl, flag) then return true, lx, by, bl; end
  local br = mget(rx, by);
  return fget(br, flag), rx, by, br;
end
function dirToXY(dir)
  if dir == 0 then return 1, 0;
  elseif dir == 1 then return 0, 1;
  elseif dir == 2 then return -1, 0;
  end
  return 0, -1;
end

-- autotile
do
  local function friend(base, tile, friends)
    if tile >= base and tile < (base + 16) then
      return true;
    end
    if friends then
      for i = 1, #friends do
        local fbase = friends[i];
        if tile >= fbase and tile < (fbase + 16) then
          return true;
        end
      end
    end
    return false;
  end
  local TT = {0,14,12,7,13,10,8,4,11,6,9,3,5,2,1,15};
  local function retile(x, y, base, friends)
    if friend(base, mget(x, y)) then
      local id, j = 0, 0;
      for n = 1, 7, 2 do
        local nx = x + (n % 3) - 1;
        local ny = y + (n // 3) - 1;
        local isf = friend(base, mget(nx, ny), friends);
        id = id + 2 ^ j * (isf and 0 or 1);
        j = j + 1;
      end
      mset(x, y, base + TT[id + 1]);
    end
  end
  function autotile(base, friends)
    for x = 0, 239 do
      for y = 0, 135 do
        retile(x, y, base, friends);
      end
    end
  end
end
-- <TILES>
-- 001:9090090900999900999009990909909009099090999009990099990090900909
-- 002:9090090990999909909009099099990990900909909999090900009000999900
-- 003:9999990000000090999999090909090909090909999999090000009099999900
-- 004:0099999909000000909999999090909090909090909999990900000000999999
-- 005:0099990009000090909999099090090990999909909009099099990990900909
-- 006:0909090999009909009009099009090909009909999999090000009099999900
-- 007:9999999900000000999999990909909009099090999999990000000099999999
-- 008:0099999909000000909999999099009090909009909009009099009990909090
-- 009:9090090990999909909009099099990990999909909009099099990990900909
-- 010:9090909090990099909009009090900990990090909999990900000000999999
-- 011:9999990000000090999999090900990990090909009009099900990909090909
-- 012:9090090900999900999009990909909009099090999999990000000099999999
-- 013:9090090990999900909009999099909090999090909009999099990090900909
-- 014:9090090900999909999009090909990909099909999009090099990990900909
-- 015:9999999900000000999999990909909009099090999009990099990090900909
-- 016:0099990009000090900990099090990990990909900990090900009000999900
-- 017:0550050005555555555005550505505055055050555005550555555000500550
-- 018:0550050055555555005005500055550005555500555555550550055000500050
-- 019:0500050005500555555555500505550005055500555555555500555005000500
-- 020:0050005005550055555555550055505000555050055555555550055000500050
-- 021:0500050005500550555555550055555000555500055005005555555500500550
-- 022:0550050055555555555005500505550005055555555555500550055000500050
-- 023:0050005000550055555555550505505005055050555555550550055000500050
-- 024:0500050005500550055555555555505000555050055005555555555500500550
-- 025:0550050055555555005005500055550005555500555005550055555000500500
-- 026:0050055005555555555005550055505000555050055555555555055000050050
-- 027:0500500005505555555555500505550005055500555005555555555005500500
-- 028:0550050005555555555005550505505005055050555555550550055000500050
-- 029:0050050005555555555005550055505000555050055005555555555000500550
-- 030:0550050005555555555005500505550005055500555005555555555000500500
-- 031:0500050005500550555555550505505005055050555005555555555000500550
-- 032:0550005055550055005555500055550005555500555555550550055000500050
-- 033:5050050500555500555005550509905005099050555005550055550050500505
-- 034:5050050550599505505005055059950550500505505555050500005000555500
-- 035:5555550000000050555555050909050509090505555555050000005055555500
-- 036:0055555505000000505555555050909050509090505555550500000000555555
-- 037:0055550005000050505555055050050550599505505005055059950550500505
-- 038:0509050555009505009005059009050509009505555555050000005055555500
-- 039:5555555500000000555555550909909009099090555555550000000055555555
-- 040:0055555505000000505555555059009050509009505009005059005550509050
-- 041:5050050550599505505005055059950550599505505005055059950550500505
-- 042:5050905050590055505009005050900950590090505555550500000000555555
-- 043:5555550000000050555555050900950590090505009005055500950505090505
-- 044:5050050500599500555005550909909009099090555555550000000055555555
-- 045:5050050550599500505005555059909050599090505005555059950050500505
-- 046:5050050500599505555005050909950509099505555005050059950550500505
-- 047:5555555500000000555555550909909009099090555005550059950050500505
-- 048:0055550005000050500550055050950550590505500550050500005000555500
-- 049:9999999999999999999999999999999999999999999999999999999999999999
-- 050:9999999999999999999999999999999999999999999999999999999999999999
-- 051:9999999999999999999999999999999999999999999999999999999999999999
-- 052:9999999999999999999999999999999999999999999999999999999999999999
-- 053:9999999999999999999999999999999999999999999999999999999999999999
-- 054:9999999999999999999999999999999999999999999999999999999999999999
-- 055:9999999999999999999999999999999999999999999999999999999999999999
-- 056:9999999999999999999999999999999999999999999999999999999999999999
-- 057:9999999999999999999999999999999999999999999999999999999999999999
-- 058:9999999999999999999999999999999999999999999999999999999999999999
-- 059:9999999999999999999999999999999999999999999999999999999999999999
-- 060:9999999999999999999999999999999999999999999999999999999999999999
-- 061:9999999999999999999999999999999999999999999999999999999999999999
-- 062:9999999999999999999999999999999999999999999999999999999999999999
-- 063:9999999999999999999999999999999999999999999999999999999999999999
-- 064:9999999999999999999999999999999999999999999999999999999999999999
-- 065:9999999999999999999999999999999999999999999999999999999999999999
-- 066:9999999999999999999999999999999999999999999999999999999999999999
-- 067:9999999999999999999999999999999999999999999999999999999999999999
-- 068:9999999999999999999999999999999999999999999999999999999999999999
-- 069:9999999999999999999999999999999999999999999999999999999999999999
-- 070:9999999999999999999999999999999999999999999999999999999999999999
-- 071:9999999999999999999999999999999999999999999999999999999999999999
-- 072:9999999999999999999999999999999999999999999999999999999999999999
-- 073:9999999999999999999999999999999999999999999999999999999999999999
-- 074:9999999999999999999999999999999999999999999999999999999999999999
-- 075:9999999999999999999999999999999999999999999999999999999999999999
-- 076:9999999999999999999999999999999999999999999999999999999999999999
-- 077:9999999999999999999999999999999999999999999999999999999999999999
-- 078:9999999999999999999999999999999999999999999999999999999999999999
-- 079:9999999999999999999999999999999999999999999999999999999999999999
-- 080:9999999999999999999999999999999999999999999999999999999999999999
-- 081:9999999999999999999999999999999999999999999999999999999999999999
-- 082:9999999999999999999999999999999999999999999999999999999999999999
-- 083:9999999999999999999999999999999999999999999999999999999999999999
-- 084:9999999999999999999999999999999999999999999999999999999999999999
-- 085:9999999999999999999999999999999999999999999999999999999999999999
-- 086:9999999999999999999999999999999999999999999999999999999999999999
-- 087:9999999999999999999999999999999999999999999999999999999999999999
-- 088:9999999999999999999999999999999999999999999999999999999999999999
-- 089:9999999999999999999999999999999999999999999999999999999999999999
-- 090:9999999999999999999999999999999999999999999999999999999999999999
-- 091:9999999999999999999999999999999999999999999999999999999999999999
-- 092:9999999999999999999999999999999999999999999999999999999999999999
-- 093:9999999999999999999999999999999999999999999999999999999999999999
-- 094:9999999999999999999999999999999999999999999999999999999999999999
-- 095:9999999999999999999999999999999999999999999999999999999999999999
-- 096:9999999999999999999999999999999999999999999999999999999999999999
-- 097:9999999999999999999999999999999999999999999999999999999999999999
-- 098:9999999999999999999999999999999999999999999999999999999999999999
-- 099:9999999999999999999999999999999999999999999999999999999999999999
-- 100:9999999999999999999999999999999999999999999999999999999999999999
-- 101:9999999999999999999999999999999999999999999999999999999999999999
-- 102:9999999999999999999999999999999999999999999999999999999999999999
-- 103:9999999999999999999999999999999999999999999999999999999999999999
-- 104:9999999999999999999999999999999999999999999999999999999999999999
-- 105:9999999999999999999999999999999999999999999999999999999999999999
-- 106:9999999999999999999999999999999999999999999999999999999999999999
-- 107:9999999999999999999999999999999999999999999999999999999999999999
-- 108:9999999999999999999999999999999999999999999999999999999999999999
-- 109:9999999999999999999999999999999999999999999999999999999999999999
-- 110:9999999999999999999999999999999999999999999999999999999999999999
-- 111:9999999999999999999999999999999999999999999999999999999999999999
-- 112:9999999999999999999999999999999999999999999999999999999999999999
-- 113:9999999999999999999999999999999999999999999999999999999999999999
-- 114:9999999999999999999999999999999999999999999999999999999999999999
-- 115:9999999999999999999999999999999999999999999999999999999999999999
-- 116:9999999999999999999999999999999999999999999999999999999999999999
-- 117:9999999999999999999999999999999999999999999999999999999999999999
-- 118:9999999999999999999999999999999999999999999999999999999999999999
-- 119:9999999999999999999999999999999999999999999999999999999999999999
-- 120:9999999999999999999999999999999999999999999999999999999999999999
-- 121:9999999999999999999999999999999999999999999999999999999999999999
-- 122:9999999999999999999999999999999999999999999999999999999999999999
-- 123:9999999999999999999999999999999999999999999999999999999999999999
-- 124:9999999999999999999999999999999999999999999999999999999999999999
-- 125:9999999999999999999999999999999999999999999999999999999999999999
-- 126:9999999999999999999999999999999999999999999999999999999999999999
-- 127:9999999999999999999999999999999999999999999999999999999999999999
-- 128:9999999999999999999999999999999999999999999999999999999999999999
-- 129:9999999999999999999999999999999999999999999999999999999999999999
-- 130:9999999999999999999999999999999999999999999999999999999999999999
-- 131:9999999999999999999999999999999999999999999999999999999999999999
-- 132:9999999999999999999999999999999999999999999999999999999999999999
-- 133:9999999999999999999999999999999999999999999999999999999999999999
-- 134:9999999999999999999999999999999999999999999999999999999999999999
-- 135:9999999999999999999999999999999999999999999999999999999999999999
-- 136:9999999999999999999999999999999999999999999999999999999999999999
-- 137:9999999999999999999999999999999999999999999999999999999999999999
-- 138:9999999999999999999999999999999999999999999999999999999999999999
-- 139:9999999999999999999999999999999999999999999999999999999999999999
-- 140:9999999999999999999999999999999999999999999999999999999999999999
-- 141:9999999999999999999999999999999999999999999999999999999999999999
-- 142:9999999999999999999999999999999999999999999999999999999999999999
-- 143:9999999999999999999999999999999999999999999999999999999999999999
-- 144:9999999999999999999999999999999999999999999999999999999999999999
-- 145:9999999999999999999999999999999999999999999999999999999999999999
-- 146:9999999999999999999999999999999999999999999999999999999999999999
-- 147:9999999999999999999999999999999999999999999999999999999999999999
-- 148:9999999999999999999999999999999999999999999999999999999999999999
-- 149:9999999999999999999999999999999999999999999999999999999999999999
-- 150:9999999999999999999999999999999999999999999999999999999999999999
-- 151:9999999999999999999999999999999999999999999999999999999999999999
-- 152:9999999999999999999999999999999999999999999999999999999999999999
-- 153:9999999999999999999999999999999999999999999999999999999999999999
-- 154:9999999999999999999999999999999999999999999999999999999999999999
-- 155:9999999999999999999999999999999999999999999999999999999999999999
-- 156:9999999999999999999999999999999999999999999999999999999999999999
-- 157:9999999999999999999999999999999999999999999999999999999999999999
-- 158:9999999999999999999999999999999999999999999999999999999999999999
-- 159:9999999999999999999999999999999999999999999999999999999999999999
-- 160:9999999999999999999999999999999999999999999999999999999999999999
-- 161:9999999999999999999999999999999999999999999999999999999999999999
-- 162:9999999999999999999999999999999999999999999999999999999999999999
-- 163:9999999999999999999999999999999999999999999999999999999999999999
-- 164:9999999999999999999999999999999999999999999999999999999999999999
-- 165:9999999999999999999999999999999999999999999999999999999999999999
-- 166:9999999999999999999999999999999999999999999999999999999999999999
-- 167:9999999999999999999999999999999999999999999999999999999999999999
-- 168:9999999999999999999999999999999999999999999999999999999999999999
-- 169:9999999999999999999999999999999999999999999999999999999999999999
-- 170:9999999999999999999999999999999999999999999999999999999999999999
-- 171:9999999999999999999999999999999999999999999999999999999999999999
-- 172:9999999999999999999999999999999999999999999999999999999999999999
-- 173:9999999999999999999999999999999999999999999999999999999999999999
-- 174:9999999999999999999999999999999999999999999999999999999999999999
-- 175:9999999999999999999999999999999999999999999999999999999999999999
-- 176:9999999999999999999999999999999999999999999999999999999999999999
-- 177:9999999999999999999999999999999999999999999999999999999999999999
-- 178:9999999999999999999999999999999999999999999999999999999999999999
-- 179:9999999999999999999999999999999999999999999999999999999999999999
-- 180:9999999999999999999999999999999999999999999999999999999999999999
-- 181:9999999999999999999999999999999999999999999999999999999999999999
-- 182:9999999999999999999999999999999999999999999999999999999999999999
-- 183:9999999999999999999999999999999999999999999999999999999999999999
-- 184:9999999999999999999999999999999999999999999999999999999999999999
-- 185:9999999999999999999999999999999999999999999999999999999999999999
-- 186:9999999999999999999999999999999999999999999999999999999999999999
-- 187:9999999999999999999999999999999999999999999999999999999999999999
-- 188:0000000000099000009009000909009009009090009009000009900000000000
-- 189:9999999999999999999999999999999999999999999999999999999999999999
-- 190:1100001110111101011111100101101001011010011001101011110111000011
-- 191:0555555050000005505555055055550550555505505555055000000505555550
-- 192:9999999999999999999999999999999999999999999999999999999999999999
-- 193:9999999999999999999999999999999999999999999999999999999999999999
-- 194:9999999999999999999999999999999999999999999999999999999999999999
-- 195:9999999999999999999999999999999999999999999999999999999999999999
-- 196:9999999999999999999999999999999999999999999999999999999999999999
-- 197:9999999999999999999999999999999999999999999999999999999999999999
-- 198:9999999999999999999999999999999999999999999999999999999999999999
-- 199:9999999999999999999999999999999999999999999999999999999999999999
-- 200:9999999999999999999999999999999999999999999999999999999999999999
-- 201:9999999999999999999999999999999999999999999999999999999999999999
-- 202:9999999999999999999999999999999999999999999999999999999999999999
-- 203:9999999999999999999999999999999999999999999999999999999999999999
-- 204:0001100000100100010110101011110110111101010110100010010000011000
-- 205:0011111100111111000011000011111100010010100011001100000000110011
-- 206:0000000000000000000000000001100000011000000000000000000000000000
-- 207:0101101011111111011111101101101111100111011111101111111101011010
-- 208:0000000000005555000555550055555505555500055550000955555509955555
-- 209:0000000055550000555550005555550000555550000555505000555055000000
-- 210:0000000000000099000099990001990900199909001990000111900001110000
-- 211:0000000099000000009900000099900009009100000000000000001000000010
-- 212:9999999999999999999999999999999999999999999999999999999999999999
-- 213:9999999999999999999999999999999999999999999999999999999999999999
-- 214:9999999999999999999999999999999999999999999999999999999999999999
-- 215:9999999999999999999999999999999999999999999999999999999999999999
-- 216:9999999999999999999999999999999999999999999999999999999999999999
-- 217:9999999999999999999999999999999999999999999999999999999999999999
-- 218:9999999999999999999999999999999999999999999999999999999999999999
-- 219:9999999999999999999999999999999999999999999999999999999999999999
-- 220:1111110011110111111001011111110111111101111001011111011111111100
-- 221:1111111111111111111111111101101110011001111111110100001001111110
-- 222:0011111111101111101001111011111110111111101001111110111100111111
-- 223:0111111001000010111111111001100111011011111111111111111111111111
-- 224:0999999909999999099990000999990000999999000999990000999900000000
-- 225:9900000090009990000999900099999099999900999990009999000000000000
-- 226:0111900701119900009900000099000000990900009099000000000000000000
-- 227:0070091000009910000009000000090090090900090909009000000000000000
-- 228:9999999999999999999999999999999999999999999999999999999999999999
-- 229:9999999999999999999999999999999999999999999999999999999999999999
-- 230:9999999999999999999999999999999999999999999999999999999999999999
-- 231:9999999999999999999999999999999999999999999999999999999999999999
-- 232:9999999999999999999999999999999999999999999999999999999999999999
-- 233:9999999999999999999999999999999999999999999999999999999999999999
-- 234:9999999999999999999999999999999999999999999999999999999999999999
-- 235:9999999999999999999999999999999999999999999999999999999999999999
-- 236:0011110001000010110010011111100111111001110010010100001000111100
-- 237:0011110001111110100110011001100110111101100000010100001000111100
-- 238:0011110001000010100100111001111110011111100100110100001000111100
-- 239:0011110001000010100000011011110110011001100110010111111000111100
-- 240:333333333a33a3a33a33a3a33aa33a33333333333a33aa333aa3aaa33aa3aa33
-- 241:777777777a77a7a77a77a7a77aa77a77777777777a77aa777aa7aaa77aa7aa77
-- 242:dddddddddaddadaddaddadaddaaddadddddddddddaddaadddaadaaaddaadaadd
-- 243:9999999999999999999999999999999999999999999999999999999999999999
-- 244:9999999999999999999999999999999999999999999999999999999999999999
-- 245:9999999999999999999999999999999999999999999999999999999999999999
-- 246:9999999999999999999999999999999999999999999999999999999999999999
-- 247:9999999999999999999999999999999999999999999999999999999999999999
-- 248:9999999999999999999999999999999999999999999999999999999999999999
-- 249:9999999999999999999999999999999999999999999999999999999999999999
-- 250:9999999999999999999999999999999999999999999999999999999999999999
-- 251:9999999999999999999999999999999999999999999999999999999999999999
-- 252:5500550055055500005550000555000055500000550000000000000000000000
-- 253:0055005500555055000555000000555000000555000000550000000000000000
-- 254:0000000000000000000000550000055500005550000555000055505500550055
-- 255:0000000000000000550000005550000005550000005550005505550055005500
-- </TILES>

-- <SPRITES>
-- 000:9110119191111019911110199110119991101991999999919999919999991199
-- 001:1101999111011991111101991111019911011991110199919999991999999119
-- 002:9110199191101191911110199111101991101191911019919999919999991199
-- 003:1101199111110191111101991101199911019991999999919999991999999119
-- 004:9999999999991111999999999991111199911111999999999999991199999999
-- 005:9999999911111111999999991111111111111111999999991111111199999999
-- 006:9191191911911911999999991191191111911911999999991191191191911919
-- 007:9191191911111111911111191101101111100111911111191111111191911919
-- 008:9999999999999999999991919991911199991111991111119991100199111001
-- 009:9999999999999999191999991119199911119999111111991001199910011199
-- 010:9999999999999999999999999999999599999599999959559999955599959550
-- 011:9999999999999999999999999595595955555555555555555555555500555500
-- 012:9999999999999999999999995999999999599999559599995559999905595999
-- 013:9999995999959955999955559595555599555555995555005555505595550505
-- 014:5595595555555555555555555555555555555555005555005505505555055055
-- 015:9599999955995999555599995555595955555599005555995505555550505559
-- 016:0000000050000000550000005000000000000000500000005500000050000000
-- 017:0000000050000000555000005000000000000000500000005550000050000000
-- 018:0000000050000000555500005500000000000000550000005555000050000000
-- 019:0000000055000000555550005550000000000000555000005555500055000000
-- 020:9999999999999999999999999999999999999999999999999999999999999999
-- 021:9999999999999999999999999999999999999999999999999999999999999999
-- 022:9999999999999999999999999999999999999999999999999999999999999999
-- 023:9999999999999999999999999999999999999999999999999999999999999999
-- 024:9911111199911101991111009999110199919111999991919999999999999999
-- 025:1111119910111999001111991011999911191999191999999999999999999999
-- 026:9999550599955050999950559995550099955555999955559995555599995555
-- 027:5505505555055055505555050555555050555505550550555500005555055055
-- 028:5055999905055999550599990055599955555999555599995555599955559999
-- 029:5555055555550555955550005555555555555555955555555555555555555555
-- 030:5505505550555505055555505055550555055055550000555505505550555505
-- 031:5550555555505555000555595555555555555555555555595555555555555555
-- 032:0011110000011000101111011111111111111111101111010001100000111100
-- 033:1000111111000010101111001011110000111101001111010100001111110001
-- 034:1110011111000011101111010011110000111100101111011100001111100111
-- 035:1111000101000011001111010011110110111100101111001100001010001111
-- 036:9999999999999999999999999999999999999999999999999999999999999999
-- 037:9999999999999999999999999999999999999999999999999999999999999999
-- 038:9999999999999999999999999999999999999999999999999999999999999999
-- 039:9999999999999999999999999999999999999999999999999999999999999999
-- 040:9999999999999999999999999999999999999999999999999999999999999999
-- 041:9999999999999999999999999999999999999999999999999999999999999999
-- 042:9995955599999555999959559999959999999995999999999999999999999999
-- 043:5055550555555555555555555555555595955959999999999999999999999999
-- 044:5559599955599999559599999959999959999999999999999999999999999999
-- 045:9555555555555555995555559955555595955555999955559995995599999959
-- 046:0555555055555555555555555555555555555555555555555555555555959959
-- 047:5555555955555555555555995555559955555959555599995599599995999999
-- 048:1111111111111111100011100000111000001110000011100000111000001110
-- 049:1110001111100111001001110000011100000111000001110000010000000110
-- 050:1111111111111111111111111111111111111111111111110011000001111001
-- 051:0001100010011100100111101001111110011111100111011001110010011100
-- 052:0000011000001110000111100011111011111110111011101100111000001110
-- 053:0111111101111111011100000111000001110000011100000111000001111111
-- 054:1110000011110000011110000011100000111000001110000111000011100000
-- 055:0111100011001100110011001100110011001100110011001100110001111000
-- 056:0111100011001100110000001111000011000000110000001100000011000000
-- 057:0555555000055000000550000005500000055000000550000005500000055000
-- 058:0550055005500550055005500555555005500550055005500550055005500550
-- 059:0555555005500000055000000555555005500000055000000550000005555550
-- 060:0055555500555555005000550000005500000055000000550000005500000055
-- 061:5555500555555005500050005000000050000005500000055000000550000005
-- 062:5500005555000555000055550000555055005550550055505500555055005550
-- 063:5555550055555550000055550000055500000555000000000000000000000000
-- 064:0000111000001110000011100000111000001110000011100000111000011111
-- 065:0000011100000111000001110000000100000011000000010000000000000000
-- 066:1111111111001111111111111000011001111011110011101111110001111000
-- 067:1001110010011100100111000001110000011100000111000001110000011100
-- 068:0000111000001110000011100000111000001110000011100000111000001110
-- 069:0111111101110000011100000111000001110000011100000111111101111111
-- 070:1110000001110000001110000011100000111000011110001111000011100000
-- 076:0000005500000055000000550000005500000055000000550000005500000555
-- 077:5000000550000005500000055000000550000005500000055000000555000005
-- 078:5500555055005550550055505500555055005550550055555500055555000055
-- 079:0000000000000000000000000000055500000555000055555555555055555500
-- 080:9991199999100199910000191000000110000001910000199910019999911999
-- 081:9991199999100199910110191011110110111101910110199910019999911999
-- 082:9999999999911999991111999111111991111119991111999991199999999999
-- 083:9999999999999999999119999911119999111199999119999999999999999999
-- 084:9999999999911999991001999101101991011019991001999991199999999999
-- 085:9999999999999999999999999999999999999999999999999999999999999999
-- 086:9999999999999999999999999999999999999999999999999999999999999999
-- 087:9999999999999999999999999999999999999999999999999999999999999999
-- 088:0000000000555500055555500555555005555550055555500055550000000000
-- 089:0555555050000005505555055055550550555505505555055000000505555550
-- 090:0555555055555555550000555505505555055055550000555555555505555550
-- 091:0555555055555555555555555550055555500555555555555555555505555550
-- 092:9999999999999999999999999999999999999999999999999999999999999999
-- 093:9999999999999999999999999999999999999999999999999999999999999999
-- 094:9999999999999999999999999999999999999999999999999999999999999999
-- 095:9999999999999999999999999999999999999999999999999999999999999999
-- 096:9999999999999999999999999999999999999999999999999999999999999999
-- 097:9999999999911999991111999119911991199119991111999991199999999999
-- 098:9999999999999999999999999999999999999999999999999999999999999999
-- 099:9999999999999999999999999999999999999999999999999999999999999999
-- 100:9999999999999999999999999999999999999999999999999999999999999999
-- 101:9999999999999999999999999999999999999999999999999999999999999999
-- 102:9999999999999999999999999999999999999999999999999999999999999999
-- 103:9999999999999999999999999999999999999999999999999999999999999999
-- 104:0000000000555500055555500550055005500550055555500055550000000000
-- 105:0555555055555555550000555500005555000055550000555555555505555550
-- 106:0555555050000005500000055005500550055005500000055000000505555550
-- 107:0000000000000000000550000055550000555500000550000000000000000000
-- 108:9999999999999999999999999999999999999999999999999999999999999999
-- 109:9999999999999999999999999999999999999999999999999999999999999999
-- 110:9999999999999999999999999999999999999999999999999999999999999999
-- 111:9999999999999999999999999999999999999999999999999999999999999999
-- 112:0000000000000000000000500000505000005050000000500000000000000000
-- 113:0000000000000005000005050005050500050505000005050000000500000000
-- 114:0000000000000050000050500050505000505050000050500000005000000000
-- 115:0000000000000005000005050005050500050505000005050000000500000000
-- 116:9999999999999999999999999999999999999999999999999999999999999999
-- 117:9999999999999999999999999999999999999999999999999999999999999999
-- 118:9999999999999999999999999999999999999999999999999999999999999999
-- 119:9999999999999999999999999999999999999999999999999999999999999999
-- 120:9999999999999999999999999999999999999999999999999999999999999999
-- 121:9999999999999999999999999999999999999999999999999999999999999999
-- 122:9999999999999999999999999999999999999999999999999999999999999999
-- 123:9999999999999999999999999999999999999999999999999999999999999999
-- 124:9999999999999999999999999999999999999999999999999999999999999999
-- 125:9999999999999999999999999999999999999999999999999999999999999999
-- 126:9999999999999999999999999999999999999999999999999999999999999999
-- 127:9999999999999999999999999999999999999999999999999999999999999999
-- 128:9955559995500059555005055555550555555505555005059550005999555599
-- 129:9955559995000559550050055555500555555005550050059500055999555599
-- 130:9955559995005559500500055555000555550005500500059500555999555599
-- 131:9955559995000559550050055555500555555005550050059500055999555599
-- 132:9911119991100019111001011111110111111101111001019110001999111199
-- 133:9999999999999999999999999999999999999999999999999999999999999999
-- 134:9999999999999999999999999999999999999999999999999999999999999999
-- 135:9999999999999999999999999999999999999999999999999999999999999999
-- 136:0ee00ee0e00ee00ee0000e000e00eee00e0e0eeee0eee0e0e00eee0e0e00e0e0
-- 137:0ee00ee0e00ee00e0e000e00eee0eee00eee0eee00e000e0e00ee00e0ee00ee0
-- 138:0ee00ee0e00ee00e0e00000eeee000e00eee00e000eee00ee00eee0e0e00e0e0
-- 139:3333333330000000303300333030033030330033300330033000330030300303
-- 140:3333333300000000003300330330033000330033300330030000000033333333
-- 141:3333333300000003003300030330030300330003300330030000330330300303
-- 142:9999999999999999999999999999999999999999999999999999999999999999
-- 143:9999999999999999999999999999999999999999999999999999999999999999
-- 144:9955559995000059505500055055000550000005500005059500005999555599
-- 145:9977779997000079707700077077000770000007700007079700007999777799
-- 146:9999999999999999999999999999999999999999999999999999999999999999
-- 147:9999999999999999999999999999999999999999999999999999999999999999
-- 148:9999999999999999999999999999999999999999999999999999999999999999
-- 149:9999999999999999999999999999999999999999999999999999999999999999
-- 150:9999999999999999999999999999999999999999999999999999999999999999
-- 151:9999999999999999999999999999999999999999999999999999999999999999
-- 152:0e0e00e0e0eee00ee00eee0e0e00e0e00e0e00e0e0eee00ee00eee0e0e00e0e0
-- 153:0ee00ee0e00ee00ee000000e0e0ee0e00e0ee0e0e000000ee00ee00e0ee00ee0
-- 154:0e0e00e0e0eee00e0e0eee00eee0eee00eee0eee00eee0e0e00eee0e0e00e0e0
-- 155:3000330330033003303300033030030330330003300330033000330330300303
-- 156:3333333330000003303300033030030330330003300330033000000333333333
-- 157:3000330300033000003300330330033000330033300330030000330030300303
-- 158:9999999999999999999999999999999999999999999999999999999999999999
-- 159:9999999999999999999999999999999999999999999999999999999999999999
-- 160:1111119911100111110001011111110111111101110001011110011111111199
-- 161:5555500055085555500500055555000555550005500500055508555555555000
-- 162:0000000000000000000000000505055005050550000000000000000000000000
-- 163:9999999999999999999999999999999999999999999999999999999999999999
-- 164:9999999999999999999999999999999999999999999999999999999999999999
-- 165:9999999999999999999999999999999999999999999999999999999999999999
-- 166:9999999999999999999999999999999999999999999999999999999999999999
-- 167:9999999999999999999999999999999999999999999999999999999999999999
-- 168:0e0e00e0e0eee00ee00eee000e00eee00e000eeee00000e0e00ee00e0ee00ee0
-- 169:9999999999999999999999999999999999999999999999999999999999999999
-- 170:0e0e00e0e0eee00e0e0eee0eeee0e0e00eee00e000e0000ee00ee00e0ee00ee0
-- 171:3000330330033000303300333030033030330033300330033000000033333333
-- 172:9999999999999999999999999999999999999999999999999999999999999999
-- 173:3000330300033003003300030330030300330003300330030000000333333333
-- 174:9999999999999999999999999999999999999999999999999999999999999999
-- 175:9999999999999999999999999999999999999999999999999999999999999999
-- 176:1101110110100011010000011001101010011001100000010101000111101110
-- 177:9999999999999999999999999999999999999999999999999999999999999999
-- 178:9999999999999999999999999999999999999999999999999999999999999999
-- 179:9999999999999999999999999999999999999999999999999999999999999999
-- 180:9999999999999999999999999999999999999999999999999999999999999999
-- 181:9999999999999999999999999999999999999999999999999999999999999999
-- 182:9999999999999999999999999999999999999999999999999999999999999999
-- 183:9999999999999999999999999999999999999999999999999999999999999999
-- 184:0ee00ee0e00ee00ee0000e000e00eee00e000eeee00000e0e00ee00e0ee00ee0
-- 185:0ee00ee0e00ee00e0e00000eeee000e00eee00e000e0000ee00ee00e0ee00ee0
-- 186:0e0e00e0e0eee00e0e0eee0eeee0e0e00eee00e000eee00ee00eee0e0e00e0e0
-- 187:0ee00ee0e00ee00e0e000e00eee0eee00eee0eee00eee0e0e00eee0e0e00e0e0
-- 188:3333333330000000303300333030033030330033300330033000000033333333
-- 189:3333333300000003003300030330030300330003300330030000000333333333
-- 190:3000330300033003003300030330030300330003300330030000330330300303
-- 191:3333333300000000003300330330033000330033300330030000330030300303
-- 192:9991199999100199110110111011110110011001910000199101101991199119
-- 193:9999999999999999999999999999999999999999999999999999999999999999
-- 194:9999999999999999999999999999999999999999999999999999999999999999
-- 195:0000000000000500000055000005050500005050055505000050555000050000
-- 196:0000000005000500055055000505050550505050055000550050005000000000
-- 197:0000000005000000055000000505000050505550005505000050500000050000
-- 198:9090090900999900999009990909909009099090999009990099990090900909
-- 199:9999999999999999999999999999999999999999999999999999999999999999
-- 200:0ee00ee0e00ee00ee000000e0e0000e00e0e00e0e0eee00ee00eee0e0e00e0e0
-- 201:0e0e00e0e0eee00ee00eee0e0e00e0e00e0000e0e000000ee00ee00e0ee00ee0
-- 202:0e0e00e0e0eee00e0e0eee00eee0eee00eee0eee00e000e0e00ee00e0ee00ee0
-- 203:0e0e00e0e0eee00ee00eee000e00eee00e0e0eeee0eee0e0e00eee0e0e00e0e0
-- 204:3333333330000003303300033030030330330003300330033000330330300303
-- 205:3000330330033003303300033030030330330003300330033000000333333333
-- 206:3000330300033000003300330330033000330033300330030000000033333333
-- 207:3000330330033000303300333030033030330033300330033000330030300303
-- 208:9999999999999999999999999999999999999999999999999999999999999999
-- 209:9999999999999999999999999999999999999999999999999999999999999999
-- 210:9999999999999999999999999999999999999999999999999999999999999999
-- 211:0050500005550000000055500005050000005000055505000050555000050000
-- 212:0000000000550000005055500505050000505050055505000000550000000000
-- 213:9999999999999999999999999999999999999999999999999999999999999999
-- 214:9090090990999909909009099099990990999909909009099099990990900909
-- 215:9999999999999999999999999999999999999999999999999999999999999999
-- 216:9999999999999999999999999999999999999999999999999999999999999999
-- 217:9999999999999999999999999999999999999999999999999999999999999999
-- 218:9999999999999999999999999999999999999999999999999999999999999999
-- 219:9999999999999999999999999999999999999999999999999999999999999999
-- 220:9999999999999999999999999999999999999999999999999999999999999999
-- 221:9999999999999999999999999999999999999999999999999999999999999999
-- 222:9999999999999999999999999999999999999999999999999999999999999999
-- 223:9999999999999999999999999999999999999999999999999999999999999999
-- 224:9999999999999999999999999999999999999999999999999999999999999999
-- 225:9999999999999999999999999999999999999999999999999999999999999999
-- 226:9999999999999999999999999999999999999999999999999999999999999999
-- 227:0000500000050500005055000555050500005050000005500000005000000000
-- 228:9999999999999999999999999999999999999999999999999999999999999999
-- 229:0000500005550500005055500505000050505000005500000050000000000000
-- 230:9999999999999999999999999999999999999999999999999999999999999999
-- 231:9999999999999999999999999999999999999999999999999999999999999999
-- 232:9999999999999999999999999999999999999999999999999999999999999999
-- 233:9999999999999999999999999999999999999999999999999999999999999999
-- 234:9999999999999999999999999999999999999999999999999999999999999999
-- 235:9999999999999999999999999999999999999999999999999999999999999999
-- 236:9999999999999999999999999999999999999999999999999999999999999999
-- 237:9999999999999999999999999999999999999999999999999999999999999999
-- 238:9999999999999999999999999999999999999999999999999999999999999999
-- 239:9999999999999999999999999999999999999999999999999999999999999999
-- 240:9999999999999999999999999999999999999999999999999999999999999999
-- 241:9999999999999999999999999999999999999999999999999999999999999999
-- 242:9999999999999999999999999999999999999999999999999999999999999999
-- 243:9999999999999999999999999999999999999999999999999999999999999999
-- 244:9999999999999999999999999999999999999999999999999999999999999999
-- 245:7777777777777777777777777777777777777777777777777777777777777777
-- 246:9999999999999999999999999999999999999999999999999999999999999999
-- 247:9999999999999999999999999999999999999999999999999999999999999999
-- 248:9999999999999999999999999999999999999999999999999999999999999999
-- 249:9999999999999999999999999999999999999999999999999999999999999999
-- 250:9999999999999999999999999999999999999999999999999999999999999999
-- 251:9999999999999999999999999999999999999999999999999999999999999999
-- 252:9999999999999999999999999999999999999999999999999999999999999999
-- 253:9999999999999999999999999999999999999999999999999999999999999999
-- 254:9999999999999999999999999999999999999999999999999999999999999999
-- 255:9090909009090909909090900909090990909090090909099090909009090909
-- </SPRITES>

-- <MAP>
-- 000:0f2f2f2f2f2f2f2f2f2f2f2f2f2f2f1f0f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f1f0f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f1f0f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f1f0f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f1f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:008070707070b000000000000000002f0080707070707070b0000000000000000000002f0000000000000000000080707070b0000000002f00000000000000000000000000000000008070b00000002f000000000000000000000000000080707070b000000000002f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:0090ececccec9000807070707070b02f0090ecccececececa07070707070b0000000002f0000000000000000000090ececec90000000002f00000000000000008070b000000000000090dda070b0002f000000000000000000000000000090fbecec9000000000002f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:0090ec0000ec900090ececececfb902f00900000000050ec0000ecececec90000000002f008070707070b000000090ecfceca070b000002f000000000000807060ddd07070707070f0e0ececcc90002f000000000000000080707070b000a070b0cca070b00000002f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 004:0090ec0000eca07060ec80707070602f00900000000090ec0000ec80b0ec90000000002f0090ecececec9000000090ec00ec0000a070302f807070707070e0ececec90cdececececa060ec00ec90002f8030717171714070e0ececec9000000090ececec900000002f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 005:0090ecececececececec90000000002f00900000dc0090ececececd0e0eca0707070b02f0090ecfc00ec9000000090ec00ec000000cc912f90cdecececec20ec50ecd0b0ec80b0ecececececec90002f92ececececececec20ec00ec90000000d0f0b0ec900000002f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 006:00a07070b0ec00000040e0000000002f00d0f0f07070c070f07070c060ececececec902f0090ec0000eca070707060ec00ec000000ec912fa0b0ec0000ec00ec20eca060ecd0c07272b2ec0040c0b02f92ec0000000050ececec50eca0f07070c010e0ec900000002f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 007:0000000090ececececcc90000000002f80c0c060ecececcc20ecececececec4030ec902f0090ecccecececececececec50ececececec502f0090ec80b0ecececececccecec9000000090ec000000902f92ec00ce0000d070f0f0e0ecec20ecececa060ec207171502f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 008:80707070c070b00000ec90000000002f90ecececec0000ec00ec00814030ec0000ec902f00d0f0f0b0ec8070707070f0c070703000ec202f0090eca01070f070b0ec4232ec9000000090ec00dc00902f92ec000000cc9000d0c0c030ec91ec50ececececececec902f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 009:90ececececcca07030eca07070b0002f90ec00807070b0ec00ec00910091ec0000ec902f80c0c0c060ec90ecececec90ecececec00ec912f0090ecec20fb900090ecececec90000000a070707070602f92ec000000ec900090cc0000ec91ec90ecec50ec0000ec902f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 010:90ec000000ecececececececec90002f90ec0090000090ec00ec00910091ecececcc902f90ececececec90ec0000fb90ec0000ecfcec912f00a0b0cc00ec9000a070707070600000000000000000002f92ececdcecec900090ecee00ec01ecd07070e0ecfe00ec902f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 011:90ec00004070f070b0ec0000ec90002f90ec0090000090ec00ec009100a140707070602f90ec00000040e0ec00004060ec80b0ececec912f000090ec00ec90000000000000000000000000000000002fa07070707070600090ec0000ececec90000090ec0000ec902f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 012:90ec00000000900090ec0000ec90002f90fb8060000090ececec0091000000000000002f90ccfc00000090ececececececd0c0707070302f000090ec00eca0b00000000000000000000000000000002f000000000000000090ecececec807060000090ecececec902f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 013:90ec00000000900090ecececec90002fa07060000000a07070707030000000000000001f90ec00000000d07070707070706000000000002f000090ecececed900000000000000000000000000000002f0000000000000000a0707070706000000000a070707070602f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 014:90ec0000dc009000a07070707060002f000000000000000000000000000000000000000090ec0000dc00900000000000000000000000002f0000a070707070600000000000000000000000000000001f0000000000000000000000000000000000000000000000001f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 015:a070707070706000000000000000001f0000000000000000000000000000000000000000a07070707070600000000000000000000000001f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000304000000000
-- </SFX>

-- <TRACKS>
-- 000:100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </TRACKS>

-- <FLAGS>
-- 000:00101010101010101010101010101010102020202020202020202020202020202050505050505050505050505050505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080808080
-- 001:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000020202000000000000000000000000000202000000000000000000000000000002000200000000000000000000000000000000000000000000000000000
-- </FLAGS>

-- <SCREEN>
-- 020:000000000000000000000000000000000000000000000000000000000000000000000000000000000011111111111111111111111111111111111111111111111111111111111111111111111111110000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 021:000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 022:000000000000000000000000000000000000000000000000000000000000000000000000000000001011111111111111111111111111111111111111111111111111111111111111111111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 023:000000000000000000000000000000000000000000000000000000000000000000000000000000001011001001011010010110100101101001011010010110100101101001011010010110100100110100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 024:000000000000000000000000000000000000000000000000000000000000000000000000000000001010100101011010010110100101101001011010010110100101101001011010010110101001010100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 025:000000000000000000000000000000000000000000000000000000000000000000000000000000001010010011111111111111111111111111111111111111111111111111111111111111110010010100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 026:000000000000000000000000000000000000000000000000000000000000000000000000000000001011001100000000000000000000000000000000000000000000000000000000000000001100110100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 027:000000000000000000000000000000000000000000000000000000000000000000000000000000001010101011111111111111111111111111111111111111111111111111111111111111110101010100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 028:000000000000000000000000000000000000000000000000000000000000000000000000000000001010010100011000000000000000000000000000000000000000000000000000555555551010010100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 029:000000000000000000000000000000000000000000000000000000000000000000000000000000001011110100100100000000000000000000000000000110000000000000000000500000051011110100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 030:000000000000000000000000000000000000000000000000000000000000000000000000000000001010010101011010000000000000000000000000001111000000000000000000505555051010010100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 031:000000000000000000000000000000000000000000000000000000000000000000000000000000001011110110111101000220000002200000022000011001100002200000022000505555051011110100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 032:000000000000000000000000000000000000000000000000000000000000000000000000000000001011110110111101000220000002200000022000011001100002200000022000505555051011110100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 033:000000000000000000000000000000000000000000000000000000000000000000000000000000001010010101011010000000000000000000000000001111000000000000000000505555051010010100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 034:000000000000000000000000000000000000000000000000000000000000000000000000000000001011110100100100000000000000000000000000000110000000000000000000500000051011110100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 035:000000000000000000000000000000000000000000000000000000000000000000000000000000001010010100011000000000000000000000000000000000000000000000000000555555551010010100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 036:000000000000000000000000000000000000000000000000000000000011111111111111111111111010010111111111111111111111110000000000001111111111111111111111111111110101010100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 037:000000000000000000000000000000000000000000000000000000000100000000000000000000000011110000000000000000000000001000000000010000000000000000000000000000001100110100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 038:000000000000000000000000000000000000000000000000000000001011111111111111111111111110011111111111111111111111110100000000101111111111111111111111111111110010010100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 039:000000000000000000000000000000000000000000000000000000001011001001011010010110100101101001011010010110100100110100022000101100100101101001011010010110101001010100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 040:000000000000000000000000000000000000000000000000000000001010100101011010010110100101101001011010010110101001010100022000101010010101101001011010010110100100110100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 041:000000000000000000000000000000000000000000000000000000001010010011111111111111111111111111111111111111110010010100000000101001001111111111111111111111111111110100000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 042:000000000000000000000000000000000000000000000000000000001011001100000000000000000000000000000000000000001100110100000000101100110000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 043:000000000000000000000000000000000000000000000000000000001010101011111111111111111111111111111111111111110101010100000000101010101111111111111111111111111111110000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 044:000000000000000000000000000000000000000000000000000000001010010100011111000000000000000000000000000000001010010100000000101001010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 045:000000000000000000000000000000000000000000000000000000001011110100011111000110000000000000000000000000001011110100000000101111010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 046:000000000000000000000000000000000000000000000000000000001010010100000110001111000000000000000000000000001010010100000000101001010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 047:000000000000000000000000000000000000000000000000000000001011110100011111011001100002200000022000000220001011110100022000101111010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 048:000000000000000000000000000000000000000000000000000000001011110100001001011001100002200000022000000220001011110100022000101111010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 049:000000000000000000000000000000000000000000000000000000001010010110000110001111000000000000000000000000001010010100000000101001010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 050:000000000000000000000000000000000000000000000000000000001011110111000000000110000000000000000000000000001011110100000000101111010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 051:000000000000000000000000000000000000000000000000000000001010010100110011000000000000000000000000000000001010010100000000101001010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 052:000000000000000000000000000000000000000000000000000000001010101011111111111111111111111111111100000000001010010100000000101010101111111111111111111111111111111111111100000000000000000000000000000000000000000000000000000000000000000000000000
-- 053:000000000000000000000000000000000000000000000000000000001011001100000000000000000000000000000010000000001011110100000000101100110000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000
-- 054:000000000000000000000000000000000000000000000000000000001010010011111111111111111111111111111101000000001010010100000000101001001111111111111111111111111111111111111101000000000000000000000000000000000000000000000000000000000000000000000000
-- 055:000000000000000000000000000000000000000000000000000000001010100101011010010110100101101001001101000220001011110100022000101010010101101001011010010110100101101001001101000000000000000000000000000000000000000000000000000000000000000000000000
-- 056:000000000000000000000000000000000000000000000000000000001011001001011010010110100101101010010101000220001011110100022000101100100101101001011010010110100101101010010101000000000000000000000000000000000000000000000000000000000000000000000000
-- 057:000000000000000000000000000000000000000000000000000000001011111111111111111111111111111100100101000000001010010100000000101111111111111111111111111111111111111100100101000000000000000000000000000000000000000000000000000000000000000000000000
-- 058:000000000000000000000000000000000000000000000000000000000100000000000000000000000000000011001101000000001011110100000000010000000000000000000000000000000000000011001101000000000000000000000000000000000000000000000000000000000000000000000000
-- 059:000000000000000000000000000000000000000000000000000000000011111111111111111111111111111101010101000000001010010100000000001111111111111111111111111111111111111101010101000000000000000000000000000000000000000000000000000000000000000000000000
-- 060:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010100101000000001010010100000000000000000000000000000000000000000000000010100101000000000000000000000000000000000000000000000000000000000000000000000000
-- 061:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010111101000110001011110100000000000110000000000000000000000000000000000010111101000000000000000000000000000000000000000000000000000000000000000000000000
-- 062:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010100101001111001010010100000000001111000000000000000000000000000000000010100101000000000000000000000000000000000000000000000000000000000000000000000000
-- 063:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010111101011001101011110100022000011001100002200000022000000220000002200010111101000000000000000000000000000000000000000000000000000000000000000000000000
-- 064:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010111101011001101011110100022000011001100002200000022000000220000002200010111101000000000000000000000000000000000000000000000000000000000000000000000000
-- 065:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010100101001111001010010100000000001111000000000000000000000000000000000010100101000000000000000000000000000000000000000000000000000000000000000000000000
-- 066:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010111101000110001011110100000000000110000000000000000000000000000000000010111101000000000000000000000000000000000000000000000000000000000000000000000000
-- 067:000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010100101000000001010010100000000000000000000000000000000000000000000000010100101000000000000000000000000000000000000000000000000000000000000000000000000
-- 068:000000000000000000000000000000000000000000000000000000000000000000111111111111111111111101010101000000001010101011111111111111111111110000000000001111000000000010100101111111111111110000000000000000000000000000000000000000000000000000000000
-- 069:000000000000000000000000000000000000000000000000000000000000000001000000000000000000000011001101000000001011001100000000000000000000001000000000010000100000000010111100000000000000001000000000000000000000000000000000000000000000000000000000
-- 070:000000000000000000000000000000000000000000000000000000000000000010111111111111111111111100100101000000001010010011111111111111111111110100000000101111010000000010100111111111111111110100000000000000000000000000000000000000000000000000000000
-- 071:000000000000000000000000000000000000000000000000000000000000000010110010010110100101101010010101000220001010100101011010010110100100110100022000101001010002200010111010010110100100110100000000000000000000000000000000000000000000000000000000
-- 072:000000000000000000000000000000000000000000000000000000000000000010101001010110100101101001001101000220001011001001011010010110101001010100022000101111010002200010111010010110101001010100000000000000000000000000000000000000000000000000000000
-- 073:000000000000000000000000000000000000000000000000000000000000000010100100111111111111111111111101000000001011111111111111111111110010010100000000101001010000000010100111111111110010010100000000000000000000000000000000000000000000000000000000
-- 074:000000000000000000000000000000000000000000000000000000000000000010110011000000000000000000000010000000000100000000000000000000001100110100000000101111010000000010111100000000001100110100000000000000000000000000000000000000000000000000000000
-- 075:000000000000000000000000000000000000000000000000000000000000000010101010111111111111111111111100000000000011111111111111111111110101010100000000101001010000000010100101111111110101010100000000000000000000000000000000000000000000000000000000
-- 076:000000000000000000000000000000000000000000000000000000000000000010100101000000000000000000000000000000000000000000000000000000001010010100000000101001010000000010100101000110001010010100000000000000000000000000000000000000000000000000000000
-- 077:000000000000000000000000000000000000000000000000000000000000000010111101000000000001100000000000000110000001100000000000000000001011110100000000101111010000000010111101001001001011110100000000000000000000000000000000000000000000000000000000
-- 078:000000000000000000000000000000000000000000000000000000000000000010100101000000000011110000000000001111000011110000000000000000001010010100000000101001010000000010100101010110101010010100000000000000000000000000000000000000000000000000000000
-- 079:000000000000000000000000000000000000000000000000000000000000000010111101000220000110011000022000011001100110011000022000000220001011110100022000101111010002200010111101101111011011110100000000000000000000000000000000000000000000000000000000
-- 080:000000000000000000000000000000000000000000000000000000000000000010111101000220000110011000022000011001100110011000022000000220001011110100022000101111010002200010111101101111011011110100000000000000000000000000000000000000000000000000000000
-- 081:000000000000000000000000000000000000000000000000000000000000000010100101000000000011110000000000001111000011110000000000000000001010010100000000101001010000000010100101010110101010010100000000000000000000000000000000000000000000000000000000
-- 082:000000000000000000000000000000000000000000000000000000000000000010111101000000000001100000000000000110000001100000000000000000001011110100000000101111010000000010111101001001001011110100000000000000000000000000000000000000000000000000000000
-- 083:000000000000000000000000000000000000000000000000000000000000000010100101000000000000000000000000000000000000000000000000000000001010010100000000101001010000000010100101000110001010010100000000000000000000000000000000000000000000000000000000
-- 084:000000000000000000000000000000000000000000000000000000000000000010100101000000000011111111111111111111111111111111111100000000001010010100000000101001010000000010100101000000001010010100000000000000000000000000000000000000000000000000000000
-- 085:000000000000000000000000000000000000000000000000000000000000000010111101000000000100000000000000000000000000000000000010000000001011110100000000101111010000000010111101000000001011110100000000000000000000000000000000000000000000000000000000
-- 086:000000000000000000000000000000000000000000000000000000000000000010100101000000001011111111111111111111111111111111111101000000001010010100000000101001010000000010100101000000001010010100000000000000000000000000000000000000000000000000000000
-- 087:000000000000000000000000000000000000000000000000000000000000000010111101000220001011001001011010010110100101101001001101000220001011110100022000101111010002200010111101000220001011110100000000000000000000000000000000000000000000000000000000
-- 088:000000000000000000000000000000000000000000000000000000000000000010111101000220001010100101011010010110100101101010010101000220001011110100022000101111010002200010100101000220001011110100000000000000000000000000000000000000000000000000000000
-- 089:000000000000000000000000000000000000000000000000000000000000000010100101000000001010010011111111111111111111111100100101000000001010010100000000101001010000000010111101000000001010010100000000000000000000000000000000000000000000000000000000
-- 090:000000000000000000000000000000000000000000000000000000000000000010111101000000001011001100000000000000000000000011001101000000001011110100000000101111010000000001000010000000001011110100000000000000000000000000000000000000000000000000000000
-- 091:000000000000000000000000000000000000000000000000000000000000000010100101000000001010101011111111111111111111111101010101000000001010010100000000101001010000000000111100000000001010010100000000000000000000000000000000000000000000000000000000
-- 092:000000000000000000000000000000000000000000000000000000000000000010100101000000001010010100000000000000000000000010100101000000001010010100000000101001010000000000000000000000001010010100000000000000000000000000000000000000000000000000000000
-- 093:000000000000000000000000000000000000000000000000000000000000000010111101000000001011110100000000000000000000000010111101000000001011110100011000101111010000000000011000000000001011110100000000000000000000000000000000000000000000000000000000
-- 094:000000000000000000000000000000000000000000000000000000000000000010100101000000001010010100000000000000000000000010100101000000001010010100111100101001010000000000111100000000001010010100000000000000000000000000000000000000000000000000000000
-- 095:000000000000000000000000000000000000000000000000000000000000000010111101000220001011110100000000000000000000000010111101000220001011110101100110101111010002200001100110000220001011110100000000000000000000000000000000000000000000000000000000
-- 096:000000000000000000000000000000000000000000000000000000000000000010111101000220001011110100000000000000000000000010111101000220001010010101100110101111010002200001100110000220001011110100000000000000000000000000000000000000000000000000000000
-- 097:000000000000000000000000000000000000000000000000000000000000000010100101000000001010010100000000000000000000000010100101000000001011110100111100101001010000000000111100000000001010010100000000000000000000000000000000000000000000000000000000
-- 098:000000000000000000000000000000000000000000000000000000000000000010111101000000001011110100000000000000000000000010111101000000000100001000011000101111010000000000011000000000001011110100000000000000000000000000000000000000000000000000000000
-- 099:000000000000000000000000000000000000000000000000000000000000000010100101000000001010010100000000000000000000000010100101000000000011110000000000101001010000000000000000000000001010010100000000000000000000000000000000000000000000000000000000
-- 100:000000000000000000000000000000000000000000000000000000000000000010100101000110001010010100000000000000000000000010100101000000000000000000000000101001011111111111111111111111110101010100000000000000000000000000000000000000000000000000000000
-- 101:000000000000000000000000000000000000000000000000000000000000000010111101001001001011110100000000000000000000000010111101000000000000000000000000101111000000000000000000000000001100110100000000000000000000000000000000000000000000000000000000
-- 102:000000000000000000000000000000000000000000000000000000000000000010100101010110101010010100000000000000000000000010100101000000000000000000000000101001111111111111111111111111110010010100000000000000000000000000000000000000000000000000000000
-- 103:000000000000000000000000000000000000000000000000000000000000000010111101101111011011110100000000000000000000000010111101000220000002200000022000101110100101101001011010010110101001010100000000000000000000000000000000000000000000000000000000
-- 104:000000000000000000000000000000000000000000000000000000000000000010111101101111011011110100000000000000000000000010111101000220000002200000022000101110100101101001011010010110100100110100000000000000000000000000000000000000000000000000000000
-- 105:000000000000000000000000000000000000000000000000000000000000000010100101010110101010010100000000000000000000000010100101000000000000000000000000101001111111111111111111111111111111110100000000000000000000000000000000000000000000000000000000
-- 106:000000000000000000000000000000000000000000000000000000000000000010111101001001001011110100000000000000000000000010111101000000000000000000000000101111000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000
-- 107:000000000000000000000000000000000000000000000000000000000000000010100101000110001010010100000000000000000000000010100101000000000000000000000000101001011111111111111111111111111111110000000000000000000000000000000000000000000000000000000000
-- 108:000000000000000000000000000000000000000000000000000000000000000010101010111111110101010100000000000000000000000010101010111111111111111111111111010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 109:000000000000000000000000000000000000000000000000000000000000000010110011000000001100110100000000000000000000000010110011000000000000000000000000110011010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 110:000000000000000000000000000000000000000000000000000000000000000010100100111111110010010100000000000000000000000010100100111111111111111111111111001001010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 111:000000000000000000000000000000000000000000000000000000000000000010101001010110101001010100000000000000000000000010101001010110100101101001011010100101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 112:000000000000000000000000000000000000000000000000000000000000000010110010010110100100110100000000000000000000000010110010010110100101101001011010010011010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 113:000000000000000000000000000000000000000000000000000000000000000010111111111111111111110100000000000000000000000010111111111111111111111111111111111111010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 114:000000000000000000000000000000000000000000000000000000000000000001000000000000000000001000000000000000000000000001000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 115:000000000000000000000000000000000000000000000000000000000000000000111111111111111111110000000000000000000000000000111111111111111111111111111111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </SCREEN>

-- <PALETTE>
-- 000:000000ffcf4000000000bf3000000000e1ff000000e91b1b000000cf40ffffffffbfbfbf8080804040406060bf000000
-- 001:ffcf40826a2900bf3003632100e1ff037388e91b1b731016e01be0700d79ffffffbfbfbf808089404040000000000000
-- </PALETTE>

