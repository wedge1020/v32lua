--#title  "[TIC80 API] circ() / circb() demo"
--#api tic80

-- Quick showcase of circ() (filled) and circb() (outline), animated with
-- a little pulsing radius and an orbiting ring of colored dots so you can
-- eyeball both the fill and the border under motion, not just one static
-- frame.

t = 0;

function BOOT()
  t = 0;
end

function TIC()
  t = t + 1;

  cls(0);

  -- Big filled circle, top-left, radius pulses between 10 and 26.
  local pulse = 18 + math.sin(t * 0.05) * 8;
  circ(60, 60, pulse, 12);

  -- Same size, drawn as an outline only, so you can compare fill vs. border
  -- side by side.
  circb(150, 60, pulse, 12);

  -- A static row showing off every swatch color as a small filled circle,
  -- so you can see circ() works cleanly across the whole palette.
  for i = 0, 15 do
    circ(20 + i * 14, 110, 5, i);
  end

  -- Same row again as outlines only, directly below, for comparison.
  for i = 0, 15 do
    circb(20 + i * 14, 130, 5, i);
  end

  -- A small ring of orbiting dots -- filled circles whose positions come
  -- from a bit of trig, to prove circ()/circb() behave correctly with
  -- non-integer, moving coordinates and not just fixed test spots.
  local cx, cy, orbit_r = 200, 160, 30;
  for i = 0, 7 do
    local angle = t * 0.03 + (i * 6.283185 / 8);
    local x = cx + math.cos(angle) * orbit_r;
    local y = cy + math.sin(angle) * orbit_r;
    circ(x, y, 4, 4 + i);
  end

  -- ...and the same ring traced as outlines, offset below, so filled vs.
  -- bordered motion is easy to compare at a glance.
  local cx2, cy2 = 200, 210;
  for i = 0, 7 do
    local angle = t * 0.03 + (i * 6.283185 / 8);
    local x = cx2 + math.cos(angle) * orbit_r;
    local y = cy2 + math.sin(angle) * orbit_r;
    circb(x, y, 4, 4 + i);
  end

  print(60, 4, "circ() / circb() demo");
end
