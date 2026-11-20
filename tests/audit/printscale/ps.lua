-- print() with scale / smallfont: glyphs are zoomed and advance 6 (small: 4) px * scale;
-- the returned width is #text * 6 * scale (small font: * 4).
function TIC()
 cls(0)
 print("HH",20,10,12)
 print("HH",20,40,12,false,3)
 print("HH",120,10,12,false,1,true)
 local w=print("abc",0,-20,15,false,2)
 rect(10,110,w,4,9)
 local w2=print("abcd",0,-20,15,false,1,true)
 rect(10,120,w2,4,11)
end
