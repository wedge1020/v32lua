-- frame commit (--tic80-commit): a deterministic scene using every queued primitive, a
-- print() whose width is used, and screen-memory writes between drawing calls (they
-- replay the queue first, so the drawing order is the program's). The screenshot with
-- and without the flag must be identical.
function TIC()
  cls(1)
  rect(10, 10, 60, 40, 2)
  rectb(8, 8, 64, 44, 15)
  circ(120, 30, 20, 6)
  circb(120, 30, 24, 14)
  line(0, 0, 239, 135, 9)
  tri(150, 60, 200, 60, 175, 100, 11)
  for i = 0, 15 do pix(200 + i, 10, i) end
  spr(1, 20, 80, 0, 2)
  map(0, 0, 4, 3, 100, 90)
  local w = print("HELLO", 30, 115, 12)
  rect(30, 125, w, 4, 3)                 -- as wide as the text: needs the returned width
  w = print("BIG", 150, 115, 13, false, 2)
  rect(150, 108, w, 3, 4)
  -- screen memory: the fill covers everything queued so far, the rect after it stays
  memset(0x0000, 5, 4 * 240)             -- the first four screen rows
  rect(100, 0, 20, 2, 7)
  poke4(0x2000 * 2, 8)                   -- somewhere on screen
  rectb(2, 2, 20, 20, 10)
end
