--#api pico8
-- sqrt(), and an _init()-only cart driving its own loop with flip()
function _init()
  r_sqrt = sqrt(16)        -- 4
  r_sqrtneg = sqrt(-4)     -- 0 (PICO-8)
  r_frames = 0
  while r_frames < 10 do
    cls()
    r_frames += 1
    flip()
  end
  r_done = true            -- true after 10 flips (20 frames at 30 fps)
end
