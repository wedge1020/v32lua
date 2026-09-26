--#api tic80
function TIC()
  cls(1)
  spr(1, 10, 20)
  spr(1, 10, 20, -1, 1, 1)
  spr(2, 0, 0, -1, 1, 0, 0, 2, 1)
  spr(1, 10, 20, -1, 2)
  rect(0, 0, 10, 5, 8)
  rectb(0, 0, 4, 3, 9)
  pix(1, 1, 7)
  line(0, 0, 10, 0, 7)
  circ(20, 20, 2, 11)
  print("hi", 4, 8, 12)
end
