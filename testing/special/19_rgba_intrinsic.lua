--#title "[v32lua] rgba() intrinsic unit test"
--@ Vircon32 Lua rgba() Intrinsic Unit Test
--@ rgba(r, g, b [, a]) gives the RAW packed 0xAABBGGRR word (not a Lua
--@ number) for spr()'s color_mult, ioports.gpu.clear(color),
--@ ioports.gpu.multiply ... Components are clamped to 0..255 and
--@ truncated; a missing or nil alpha is 255 (as clear(r, g, b [, a])).
--@ All-literal calls fold to one word at compile time.
--@ Results that are raw words go in hex_ globals (memory scraping).
--@ None of the words below collides with a NaN-box tag (0xFF8..., 0xFFC...,
--@ 0x7F8..., 0x7FC...): see the caveat in doc/API.md.

local function twice(x) return x * 2 end
local function f255() return 255 end

function test_rgba()
    -- === Test 00: literal folds ===
    hex_result00a = rgba(255, 0, 0)          -- opaque red
    hex_result00b = rgba(1, 2, 3, 4)
    hex_result00c = rgba(16, 32, 48)         -- alpha defaults to 255
    hex_result00d = rgba(16, 32, 48, nil)    -- explicit nil alpha: 255
    __rawasm__("__debug0:")

    -- === Test 01: runtime components give the same words ===
    local r, g, b, a = 255, 0, 0, 255
    hex_result01a = rgba(r, g, b)
    local w, x, y, z = 1, 2, 3, 4
    hex_result01b = rgba(w, x, y, z)
    local na = nil
    hex_result01c = rgba(16, 32, 48 + x - x, na)
    __rawasm__("__debug1:")

    -- === Test 02: clamping and truncation at run time ===
    local lo, hi, fr = -5, 300, 127.9
    hex_result02a = rgba(lo, hi, fr, 10)     -- 0, 255, 127, 10
    hex_result02b = rgba(0.5, 1.99, 254.99, 0)
    __rawasm__("__debug2:")

    -- === Test 03: components that CALL (register safety) ===
    hex_result03a = rgba(twice(10), twice(twice(5)), f255(), twice(3))
    hex_result03b = rgba(twice(1), 2, twice(1) + 1, twice(2))
    __rawasm__("__debug3:")

    -- === Test 04: into the GPU, read back from the port ===
    ioports.gpu.multiply = rgba(r, 128, 64, 32)
    __rawasm__("IN R0, GPU_MultiplyColor")
    __rawasm__("MOV [var_hex_result04a], R0")
    ioports.gpu.multiply = rgba(1, 2, 3, 4)
    __rawasm__("IN R0, GPU_MultiplyColor")
    __rawasm__("MOV [var_hex_result04b], R0")
    ioports.gpu.clear(rgba(8, 16, 24))
    __rawasm__("IN R0, GPU_ClearColor")
    __rawasm__("MOV [var_hex_result04c], R0")
    ioports.gpu.multiply = rgba(255, 255, 255)
    __rawasm__("__debug4:")
end

hex_result04a = 0
hex_result04b = 0
hex_result04c = 0

function main()
    ioports.gpu.clear("black")
    test_rgba()
end

--[[
=== EXPECTED OUTPUT ===

hex_result00a: 0xFF0000FF
hex_result00b: 0x04030201
hex_result00c: 0xFF302010
hex_result00d: 0xFF302010
hex_result01a: 0xFF0000FF
hex_result01b: 0x04030201
hex_result01c: 0xFF302010
hex_result02a: 0x0A7FFF00
hex_result02b: 0x00FE0100
hex_result03a: 0x06FF1414
hex_result03b: 0x04030202
hex_result04a: 0x204080FF
hex_result04b: 0x04030201
hex_result04c: 0xFF181008

--]]
