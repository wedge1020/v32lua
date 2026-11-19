--#api tic80
-- tri(): filled triangle, drawn as one swatch blit per row (native).
-- Covers: normal winding, reversed winding, degenerate (nothing drawn),
-- partly off-screen, and a program that defines its own tri().
function TIC()
  cls(0)
  tri(10, 10, 60, 20, 30, 50, 12)     -- one winding
  tri(10, 10, 30, 50, 60, 20, 6)      -- the other
  tri(5, 5, 5, 5, 5, 5, 3)            -- degenerate
  tri(-20, 120, 100, 150, 260, 100, 9) -- clipped by the screen
end
