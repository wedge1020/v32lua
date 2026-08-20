--#title "[TIC80 API] basic drawing routines demo"
--#api tic80
-- test_draw.lua
-- Minimal exercise of pix(), rect(), rectb(), and line()

function TIC()
  cls(0)

  -- pix(): one pixel per palette color (0-15), spaced out along the
  -- top of the screen. Good sanity check that the swatch bank
  -- (regions 512-527) and the color clamp are both wired up right --
  -- you should see 16 distinct colors in a row, not 16 copies of one.
  for i = 0, 15 do
    pix(4 + i * 4, 4, i)
  end

  -- rect(): one filled rectangle
  rect(10, 20, 40, 24, 6)

  -- rectb(): one bordered (unfilled) rectangle, off to the side so
  -- it's easy to tell apart from the filled one
  rectb(60, 20, 40, 24, 9)

  -- line(): horizontal, vertical, and both diagonals -- deliberately
  -- includes the axis-aligned cases (0 degrees, 90 degrees) since
  -- those are the edge cases most likely to expose an atan2/rotozoom
  -- sign or hotspot mistake, alongside two ordinary diagonals
  line(10, 60, 100, 60, 12)   -- horizontal
  line(10, 60, 10, 100, 12)   -- vertical
  line(10, 60, 100, 100, 5)   -- diagonal, down-right
  line(100, 60, 10, 100, 8)   -- diagonal, down-left
end
