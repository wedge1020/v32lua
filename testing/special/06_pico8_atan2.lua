--#api pico8
--@ Vircon32 Lua PICO-8 atan2 Unit Test
--@ PICO-8's atan2(dx, dy): turns in [0, 1), screen space (y down), with
--@ atan2(0, 0) = 0.25. The CPU's ATAN2 raises a hardware error when both
--@ operands are zero -- which atan2(0, 0) and a zero-length line() (one
--@ pixel: line(x, y, x, y)) used to reach.
--@ Results are stored in global variables for automated memory scraping.

function _init()
    -- === Test 00: the four axes ===
    number_result00a = atan2(1, 0)
    number_result00b = atan2(0, -1)
    number_result00c = atan2(-1, 0)
    number_result00d = atan2(0, 1)
    __rawasm__("__debug0:")

    -- === Test 01: diagonals, magnitude doesn't matter ===
    number_result01a = atan2(1, -1)
    number_result01b = atan2(99, 99)
    __rawasm__("__debug1:")

    -- === Test 02: zero vectors (no hardware error) ===
    number_result02a = atan2(0, 0)
    local z = 0
    number_result02b = atan2(z, -z)
    number_result02c = atan2()
    __rawasm__("__debug2:")

    -- === Test 03: atan2(cos(a), sin(a)) == a all the way round ===
    local worst = 0
    for i = 0, 255 do
        local a = i / 256
        local d = abs(atan2(cos(a), sin(a)) - a)
        if d > 0.5 then d = 1 - d end
        if d > worst then worst = d end
    end
    boolean_result03 = worst < 0.0001
    __rawasm__("__debug3:")

    -- === Test 04: a zero-length line is a pixel, not a fault ===
    line(5, 5, 5, 5, 7)
    line(64, 64, 64, 64)
    boolean_result04 = true
    __rawasm__("__debug4:")

    -- === Test 05: the other CPU faults PICO-8 math can reach ===
    local n = -8
    number_result05a = 7 % z
    boolean_result05b = (7 \ z) > 32767
    number_result05c = n ^ 0.5
    number_result05d = sqrt(n)
    number_result05e = -7 \ 2
    __rawasm__("__debug5:")
end

function _draw()
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 0.0000
number_result00b: 0.2500
number_result00c: 0.5000
number_result00d: 0.7500
number_result01a: 0.1250
number_result01b: 0.8750
number_result02a: 0.2500
number_result02b: 0.2500
number_result02c: 0.2500
boolean_result03: true
boolean_result04: true
number_result05a: 0.0000
boolean_result05b: true
number_result05c: 0.0000
number_result05d: 0.0000
number_result05e: -4.0000

--]]
