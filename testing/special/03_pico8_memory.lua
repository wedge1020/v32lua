--#api pico8
--@ Vircon32 Lua PICO-8 Memory Unit Test
--@ peek/poke (8, 16, 32 bits), the @ % $ peek operators, memcpy/memset,
--@ reload, sget/sset, cartdata/dget/dset and time()/t() on the emulated
--@ 64 KB RAM. The map, sprite flags, pen and camera are live views of the
--@ mget/fget/color/camera state.
--@ Results are stored in global variables for automated memory scraping.

function _init()
    -- === Test 00: bytes, several values per poke ===
    poke(0x4300, 7, 8, 300)                        -- 300 is stored as 44
    number_result00 = peek(0x4300) + peek(0x4301) * 10 + peek(0x4302) * 100
    __rawasm__("__debug0:")

    -- === Test 01: poke2/peek2 are signed 16-bit, little-endian ===
    poke2(0x4310, -2)
    number_result01a = peek2(0x4310)
    number_result01b = peek(0x4310) + peek(0x4311) * 256
    __rawasm__("__debug1:")

    -- === Test 02: poke4/peek4 store 16.16 fixed point ===
    poke4(0x4320, -1.5)
    number_result02a = peek4(0x4320)
    number_result02b = peek(0x4323)
    __rawasm__("__debug2:")

    -- === Test 03: the peek operators ===
    number_result03 = @0x4300 + %0x4310 + $0x4320  -- 7 - 2 - 1.5
    __rawasm__("__debug3:")

    -- === Test 04: memset, and memcpy of an overlapping range ===
    memset(0x4400, 9, 4)
    number_result04a = peek(0x4403)
    poke(0x4500, 1, 2, 3, 4)
    memcpy(0x4501, 0x4500, 4)
    number_result04b = peek(0x4501) * 1000 + peek(0x4502) * 100 + peek(0x4503) * 10 + peek(0x4504)
    __rawasm__("__debug4:")

    -- === Test 05: the map is live at 0x2000 (rows 0-31) and 0x1000 (rows 32-63) ===
    mset(5, 3, 42)
    number_result05a = peek(0x2000 + 3 * 128 + 5)
    poke(0x2000 + 1 * 128 + 2, 17)
    number_result05b = mget(2, 1)
    poke(0x1000 + 4, 99)
    number_result05c = mget(4, 32)
    __rawasm__("__debug5:")

    -- === Test 06: sprite flags are live at 0x3000 ===
    fset(10, 0xa5)
    number_result06a = peek(0x3000 + 10)
    poke(0x3000 + 11, 3)
    number_result06b = fget(11)
    __rawasm__("__debug6:")

    -- === Test 07: pen (0x5f25) and camera (0x5f28) ===
    color(12)
    number_result07a = peek(0x5f25) & 15
    camera(-3, 260)
    number_result07b = peek2(0x5f28) * 1000 + peek2(0x5f2a)
    poke2(0x5f28, 17)
    number_result07c = peek2(0x5f28)
    camera()
    __rawasm__("__debug7:")

    -- === Test 08: draw state defaults, 16-bit address wrap ===
    number_result08a = peek(0x5f00) + peek(0x5f22)  -- 0x10 + 128
    poke(-32768, 5)
    number_result08b = peek(0x8000)
    __rawasm__("__debug8:")

    -- === Test 09: sget / sset on the sprite sheet ===
    sset(3, 2, 11)
    number_result09a = sget(3, 2)
    number_result09b = sget(200, 1)
    __rawasm__("__debug9:")

    -- === Test 10: cartdata / dget / dset ===
    boolean_result10a = cartdata("v32lua_unit_test")  -- a fresh card: false
    dset(3, 42.25)
    number_result10b = dget(3)
    number_result10c = peek4(0x5e00 + 12)
    number_result10d = dget(99)
    boolean_result10e = cartdata("v32lua_unit_test")  -- the card has it now
    number_result10f = dget(3)
    __rawasm__("__debug10:")

    -- === Test 11: several values from one peek ===
    local a, b, c = peek(0x4500, 3)
    number_result11 = a * 100 + b * 10 + c
    __rawasm__("__debug11:")

    -- === Test 12: reload() restores the cart's map ===
    reload(0x2000, 0x2000, 0x1000)
    number_result12 = mget(5, 3)
    __rawasm__("__debug12:")

    -- === Test 13: time() is 0 before the first frame ===
    number_result13 = time()
    __rawasm__("__debug13:")
end

function _update()
    -- === Test 14: one PICO-8 frame is 1/30 s ===
    if number_result14a == nil then
        number_result14a = t()
    elseif number_result14b == nil then
        number_result14b = t() - number_result14a
    end
end

function _draw()
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 4487.0000
number_result01a: -2.0000
number_result01b: 65534.0000
number_result02a: -1.5000
number_result02b: 255.0000
number_result03: 3.5000
number_result04a: 9.0000
number_result04b: 1234.0000
number_result05a: 42.0000
number_result05b: 17.0000
number_result05c: 99.0000
number_result06a: 165.0000
number_result06b: 3.0000
number_result07a: 12.0000
number_result07b: -2740.0000
number_result07c: 17.0000
number_result08a: 144.0000
number_result08b: 5.0000
number_result09a: 11.0000
number_result09b: 0.0000
boolean_result10a: false
number_result10b: 42.2500
number_result10c: 42.2500
number_result10d: 0.0000
boolean_result10e: true
number_result10f: 42.2500
number_result11: 112.0000
number_result12: 0.0000
number_result13: 0.0000
number_result14a: 0.0333
number_result14b: 0.0333

--]]
