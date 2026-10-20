--@ Vircon32 Lua color words from Lua numbers Unit Test
--@ A Lua number is a float32. Written to a color port it used to go through
--@ a bare CFI, which is out of range from 2^31 on (alpha >= 128): 0x80000000
--@ on x86-64, 0x7FFFFFFF on ARM64. As a clear color or color_mult it was
--@ passed as its float32 BIT PATTERN. Now a Lua number is floored and wrapped
--@ into 32 bits (as color(n)); only 24 bits survive a float32, so the values
--@ here are exact ones. A raw word from hex() or rgba() is never converted.
--@ Results are raw words in hex_ global variables, read back from the ports.

hex_result00 = 0
hex_result01 = 0
hex_result02 = 0
hex_result03 = 0
hex_result04 = 0
hex_result05 = 0
hex_result06 = 0

-- (a function of its own: inline asm turns off the "this local is a number" analysis)
function read_mul(n)
    if n == 0 then __rawasm__("IN R0, GPU_MultiplyColor") __rawasm__("MOV [var_hex_result00], R0") end
    if n == 1 then __rawasm__("IN R0, GPU_MultiplyColor") __rawasm__("MOV [var_hex_result01], R0") end
    if n == 2 then __rawasm__("IN R0, GPU_ClearColor")    __rawasm__("MOV [var_hex_result02], R0") end
    if n == 3 then __rawasm__("IN R0, GPU_ClearColor")    __rawasm__("MOV [var_hex_result03], R0") end
    if n == 4 then __rawasm__("IN R0, GPU_ClearColor")    __rawasm__("MOV [var_hex_result04], R0") end
    if n == 5 then __rawasm__("IN R0, GPU_ClearColor")    __rawasm__("MOV [var_hex_result05], R0") end
    if n == 6 then __rawasm__("IN R0, GPU_MultiplyColor") __rawasm__("MOV [var_hex_result06], R0") end
end

function test_colors()
    -- 00: a number >= 2^31 written to an integer color port
    local alpha = 0x80000000
    ioports.gpu.multiply = alpha
    read_mul(0)
    -- 01: computed (alpha 0xC0 as a power-of-two multiple)
    local a = 192
    ioports.gpu.multiply = a * 0x1000000
    read_mul(1)
    -- 02: bgcolor from a number (0xFF000000 is exact in a float32)
    local black = 0xFF000000
    ioports.gpu.bgcolor = black
    read_mul(2)
    -- 03: ioports.gpu.clear() of a number expression: the word, not float bits
    local c = 0x41000000
    ioports.gpu.clear(c)
    read_mul(3)
    -- 04: a computed alpha-only clear color
    ioports.gpu.clear(a * 0x1000000)
    read_mul(4)
    -- 05: a raw word (hex) is passed through untouched
    local raw = hex("0xFF0000FF")
    ioports.gpu.clear(raw)
    read_mul(5)
    -- 06: a negative number is two's complement (-1 is 0xFFFFFFFF)
    local m1 = -1
    ioports.gpu.multiply = m1
    read_mul(6)
end

function main()
    test_colors()
    ioports.gpu.multiply = 0xFFFFFFFF
end

--[[
=== EXPECTED OUTPUT ===

hex_result00: 0x80000000
hex_result01: 0xC0000000
hex_result02: 0xFF000000
hex_result03: 0x41000000
hex_result04: 0xC0000000
hex_result05: 0xFF0000FF
hex_result06: 0xFFFFFFFF

--]]
