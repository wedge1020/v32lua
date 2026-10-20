--#api tic80
--#allow-float-as-clearcolor
--@ Vircon32 Lua TIC-80 cls() with --#allow-float-as-clearcolor Unit Test
--@ The hint (and the --allow-float-as-clearcolor option) bring back the old
--@ cls(variable): the variable's float32 bit pattern is the clear color.
--@ c = 8.0 is 0x41000000, black at ~25% alpha: witchem_up's translucent
--@ clear. Literals and strings are unaffected by the option.
--@ The clear color is read back through GPU_ClearColor after each call.
--@ Results are raw words in hex_ global variables.

hex_result00 = 0
hex_result01 = 0
hex_result02 = 0

c1 = 8

local function clearcolor(n)
    if n == 0 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result00], R0") end
    if n == 1 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result01], R0") end
    if n == 2 then __rawasm__("IN R0, GPU_ClearColor") __rawasm__("MOV [var_hex_result02], R0") end
end

function TIC()
    cls(c1)
    clearcolor(0)
    cls(8)
    clearcolor(1)
    cls("#FF8000")
    clearcolor(2)
end

--[[
=== EXPECTED OUTPUT ===

hex_result00: 0x41000000
hex_result01: 0xFF6F3629
hex_result02: 0xFF0080FF

--]]
