--#title  "[TIC80 API] pong (circ/rect flash demo)"
--#api tic80

-- Quick and dirty single-player Pong: you control the left paddle, the
-- right paddle is a simple ball-tracking "AI". Ball is circ()/circb(),
-- paddles are rect()/rectb(). Whenever the ball hits a wall or a paddle,
-- that shape switches to border-only (circb/rectb) for a few frames
-- instead of filled, as a quick "flash" so the collision is easy to spot.

SCREEN_W = 240;
SCREEN_H = 136;

BALL_R      = 3;
BALL_R_MAX  = 7; -- radius when the ball is right over the net (screen center)
PADDLE_W    = 4;
PADDLE_H    = 24;
PADDLE_SPD  = 2;
AI_SPD      = 1.6;
FLASH_TIME  = 6; -- frames a shape stays border-only after a hit

bx = 0; by = 0; bdx = 0; bdy = 0;
ball_flash = 0;

p1x = 8;              p1y = 0; p1_flash = 0;
p2x = 0;               p2y = 0; p2_flash = 0;

score1 = 0;
score2 = 0;

function reset_ball(dir)
  bx = SCREEN_W / 2;
  by = SCREEN_H / 2;
  bdx = 1.5 * dir;
  bdy = 1.0;
end

function BOOT()
  p1y = (SCREEN_H - PADDLE_H) / 2;
  p2x = SCREEN_W - 8 - PADDLE_W;
  p2y = (SCREEN_H - PADDLE_H) / 2;
  reset_ball(1);
end

function hits_paddle(px, py)
  return bx - BALL_R <= px + PADDLE_W
     and bx + BALL_R >= px
     and by + BALL_R >= py
     and by - BALL_R <= py + PADDLE_H;
end

function TIC()
  -- --- Player 1 (left paddle): Up/Down ---
  if btn(0) then p1y = p1y - PADDLE_SPD; end
  if btn(1) then p1y = p1y + PADDLE_SPD; end
  if p1y < 0 then p1y = 0; end
  if p1y > SCREEN_H - PADDLE_H then p1y = SCREEN_H - PADDLE_H; end

  -- --- Player 2 (right paddle): dumb AI, just chases the ball ---
  local p2_center = p2y + PADDLE_H / 2;
  if by < p2_center - 2 then p2y = p2y - AI_SPD; end
  if by > p2_center + 2 then p2y = p2y + AI_SPD; end
  if p2y < 0 then p2y = 0; end
  if p2y > SCREEN_H - PADDLE_H then p2y = SCREEN_H - PADDLE_H; end

  -- --- Move ball ---
  bx = bx + bdx;
  by = by + bdy;

  -- --- Top / bottom wall bounce ---
  if by - BALL_R <= 0 then
    by = BALL_R;
    bdy = -bdy;
    ball_flash = FLASH_TIME;
  end
  if by + BALL_R >= SCREEN_H then
    by = SCREEN_H - BALL_R;
    bdy = -bdy;
    ball_flash = FLASH_TIME;
  end

  -- --- Paddle collisions ---
  if bdx < 0 and hits_paddle(p1x, p1y) then
    bdx = -bdx * 1.05;
    bx = p1x + PADDLE_W + BALL_R;
    ball_flash = FLASH_TIME;
    p1_flash = FLASH_TIME;
  end
  if bdx > 0 and hits_paddle(p2x, p2y) then
    bdx = -bdx * 1.05;
    bx = p2x - BALL_R;
    ball_flash = FLASH_TIME;
    p2_flash = FLASH_TIME;
  end

  -- --- Scoring ---
  if bx < 0 then
    score2 = score2 + 1;
    reset_ball(1);
  end
  if bx > SCREEN_W then
    score1 = score1 + 1;
    reset_ball(-1);
  end

  -- --- Countdown the flash timers ---
  if ball_flash > 0 then ball_flash = ball_flash - 1; end
  if p1_flash   > 0 then p1_flash   = p1_flash - 1; end
  if p2_flash   > 0 then p2_flash   = p2_flash - 1; end

  -- --- Ball "grows" as it crosses the net, shrinks back near either edge ---
  local half_w = SCREEN_W / 2;
  local dist_from_net = math.abs(bx - half_w);
  local grow_t = 1 - (dist_from_net / half_w); -- 1.0 at the net, 0.0 at the edges
  if grow_t < 0 then grow_t = 0; end
  local ball_vis_r = BALL_R + (BALL_R_MAX - BALL_R) * grow_t;

  -- --- Draw ---
  cls(0);

  -- dashed center line
  local y = 0;
  while y < SCREEN_H do
    rect(SCREEN_W / 2 - 1, y, 2, 4, 13);
    y = y + 8;
  end

  -- paddles: filled normally, border-only for a few frames after a hit
  if p1_flash > 0 then
    rectb(p1x, p1y, PADDLE_W, PADDLE_H, 12);
  else
    rect(p1x, p1y, PADDLE_W, PADDLE_H, 12);
  end

  if p2_flash > 0 then
    rectb(p2x, p2y, PADDLE_W, PADDLE_H, 6);
  else
    rect(p2x, p2y, PADDLE_W, PADDLE_H, 6);
  end

  -- ball: same idea, drawn at its "grown" visual radius (collision above
  -- still uses the fixed BALL_R, so gameplay feel doesn't change)
  if ball_flash > 0 then
    circb(bx, by, ball_vis_r, 15);
  else
    circ(bx, by, ball_vis_r, 15);
  end

  print(SCREEN_W / 2 - 20, 4, score1);
  print(SCREEN_W / 2 + 16, 4, score2);
end
