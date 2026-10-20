--#title "[v32lua] __asm__ {var} interpolation unit test"
--@ Vircon32 Lua __asm__ / __rawasm__ Interpolation Unit Test
--@ {name} inside inline assembly becomes the variable's memory operand:
--@ [BP - n] for a local, [BP + n] for a parameter, [var_name] for a
--@ global. A local used to become [var_name] as well, so the assembly
--@ read and wrote a global of the same name instead of the local.

speed = 100          -- a global with the same name as the local below

function bump(p)
    __asm__("MOV R0, {p}\nFADD R0, 1.0\nMOV {p}, R0")
    return p
end

function test_interp()
    -- === Test 00: a local ===
    local speed = 5.0
    __asm__("MOV R0, {speed}\nFADD R0, 1.5\nMOV {speed}, R0")
    number_result00a = speed        -- 6.5
    number_result00b = _G_speed()   -- the global is untouched: 100
    __rawasm__("__debug0:")

    -- === Test 01: a parameter, and __rawasm__ on a local ===
    number_result01a = bump(41)     -- 42
    local n = 7
    __rawasm__("MOV R0, {n}\nFMUL R0, 3.0\nMOV {n}, R0")
    number_result01b = n            -- 21
    __rawasm__("__debug1:")

    -- === Test 02: a global ===
    __asm__("MOV R0, {speed_g}\nFADD R0, 2.0\nMOV {speed_g}, R0")
    number_result02a = speed_g      -- 12
    __rawasm__("__debug2:")
end

function _G_speed() return speed end

speed_g = 10

function main()
    test_interp()
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 6.5000
number_result00b: 100.0000
number_result01a: 42.0000
number_result01b: 21.0000
number_result02a: 12.0000

--]]
