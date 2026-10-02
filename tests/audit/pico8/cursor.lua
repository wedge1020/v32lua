--#api pico8
-- cursor() and the text cursor of print(). Expected values in comments.
-- Draw positions: runlua pico8/cursor.lua -f 2 -g (canvas x = 144 + 2.75*x,
-- y = 2.75*y, rounded).
r_done = false
function _init()
 r_a1, r_a2, r_a3 = cursor(10, 20, 9)      -- 0, 0, 6 (start-up state)
 r_b1, r_b2, r_b3 = cursor(30, 40)         -- 10, 20, 9
 r_c1 = print("ab")                        -- 38   at (30,40), pen 9
 r_c2, r_c3 = cursor(30, 46)               -- 30, 46: one line down
 r_d1 = print("one\ntwo3", 12)             -- 46   2nd argument is the color
 r_d2, r_d3, r_d4 = cursor()               -- 30, 58, 12; cursor now 0,0
 r_e1 = print("xyz", 50, 60, 3)            -- 62   explicit position
 r_e2, r_e3, r_e4 = cursor(0, 120)         -- 50, 66, 3: it moved the cursor too
 print("bottom")                           -- at y 120
 r_f1, r_f2 = cursor(5, 5)                 -- 0, 122: no scrolling, stays on the last row
 cls()
 r_g1, r_g2 = cursor(7, 8)                 -- 0, 0: cls() resets it
 r_h1 = peek(0x5f26) * 100 + peek(0x5f27)  -- 708
 poke(0x5f26, 64) poke(0x5f27, 32)
 r_h2, r_h3 = cursor()                     -- 64, 32
 r_i1 = print("\x8e")                      -- 8    a wide glyph is 8 px
 local c = cursor                          -- a real function value
 r_j1, r_j2 = c(1, 2)                      -- 0, 6
 r_k1 = print(42)                          -- 9    1 + 2 characters
 r_done = true
end
function _update() end
function _draw()
 cls()
 cursor(4, 4, 7)
 print("first")
 print("second", 8)
 ?"third"
 camera(-10, 0)
 print("cam")
 camera()
end
