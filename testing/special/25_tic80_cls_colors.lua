--#api tic80
--@ Vircon32 Lua TIC-80 cls() colors Unit Test
--@ cls(c) takes a palette index like every TIC-80 color argument. With a
--@ VARIABLE it used to hand the value to the GPU as the clear color word, so
--@ a Lua number went in as its float32 bit pattern: c = 8 cleared with
--@ 0x41000000 (black at ~25% alpha), which the GPU draws as a blended quad,
--@ fading the last frame instead of erasing it (witchem_up's CRT streaks).
--@ Hex strings were also parsed wrongly ("0xRRGGBB" came out 0x00RRGGFF).
--@ The clear color is read back through GPU_ClearColor after each call.
--@ Results are raw words in hex_ global variables.

hex_result00 = 0
hex_result01 = 0
hex_result02 = 0
hex_result03 = 0
hex_result04 = 0
hex_result05 = 0
hex_result06 = 0
hex_result07 = 0
hex_result08 = 0
hex_result09 = 0

c1 = 8

local function clearcolor(n)
    if n == 0 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result00], R0") end
    if n == 1 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result01], R0") end
    if n == 2 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result02], R0") end
    if n == 3 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result03], R0") end
    if n == 4 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result04], R0") end
    if n == 5 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result05], R0") end
    if n == 6 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result06], R0") end
    if n == 7 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result07], R0") end
    if n == 8 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result08], R0") end
    if n == 9 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result09], R0") end
end

function TIC()
    c1 = 8                -- (TIC() runs every frame; test 08 changes it)
    -- 00: a variable is a palette index (default palette[8])
    cls(c1)
    clearcolor(0)
    -- 01: the same index as a literal
    cls(8)
    clearcolor(1)
    -- 02: an expression
    local k = 3
    cls(k + 1)
    clearcolor(2)
    -- 03: "0xRRGGBB" is opaque, RGB -> the GPU's 0xAABBGGRR
    cls("0x336699")
    clearcolor(3)
    -- 04: "#RRGGBB"
    cls("#FF8000")
    clearcolor(4)
    -- 05: 8 digits are the packed word as it is
    cls("0x80102030")
    clearcolor(5)
    -- 06: a numeric literal past 2^24 is a packed word
    cls(0xFF102030)
    clearcolor(6)
    -- 07: an index is masked with 15 (17 -> 1), as a literal or a variable
    cls(17)
    clearcolor(7)
    -- 08: a variable index past 15
    c1 = 33
    cls(c1)
    clearcolor(8)
    -- 09: nil is palette index 0
    cls(nil)
    clearcolor(9)
end

--[[
=== EXPECTED OUTPUT ===

hex_result00: 0xFF6F3629
hex_result01: 0xFF6F3629
hex_result02: 0xFF75CDFF
hex_result03: 0xFF996633
hex_result04: 0xFF0080FF
hex_result05: 0x80102030
hex_result06: 0xFF102030
hex_result07: 0xFF5D275D
hex_result08: 0xFF5D275D
hex_result09: 0xFF2C1C1A

--]]
