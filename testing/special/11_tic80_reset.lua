--#api tic80
--@ Vircon32 Lua TIC-80 reset() Unit Test
--@ reset() starts the cart over: hardware defaults, a black frame, then the
--@ cart's first instruction with a fresh stack -- globals are re-created.
--@ A raw RAM word far above the heap (0x300000) counts the boots across
--@ restarts; the cart resets itself until it has booted three times.
--@ Results are stored in global variables for automated memory scraping.

number_result00a = 0      -- boots, read back from the raw counter
number_result00b = 0      -- a global set at start-up: re-created each boot
number_result00c = 0      -- stack pointer at start-up, the same every boot
number_first_sp = 0
__rawasm__("MOV R0, [0x300000]")
__rawasm__("IADD R0, 1")
__rawasm__("MOV [0x300000], R0")
__rawasm__("CIF R0")
__rawasm__("MOV [var_number_result00a], R0")
__rawasm__("MOV R0, SP")
__rawasm__("CIF R0")
__rawasm__("MOV [var_number_result00c], R0")
-- the first boot's stack pointer, kept in raw RAM too
__rawasm__("MOV R0, [0x300000]")
__rawasm__("IEQ R0, 1")
__rawasm__("JF R0, __reset_test_sp_kept")
__rawasm__("MOV R1, SP")
__rawasm__("MOV [0x300001], R1")
__rawasm__("__reset_test_sp_kept:")
__rawasm__("MOV R0, [0x300001]")
__rawasm__("CIF R0")
__rawasm__("MOV [var_number_first_sp], R0")
number_result00b = number_result00b + 1

local t = 0
function TIC()
    t = t + 1
    if t == 2 and number_result00a < 3 then
        number_result00b = 100    -- lost by the reset
        reset()
    end
    boolean_result01a = number_result00c == number_first_sp
end

--[[
=== EXPECTED OUTPUT ===

number_result00a: 3.0000
number_result00b: 1.0000
boolean_result01a: true

--]]
