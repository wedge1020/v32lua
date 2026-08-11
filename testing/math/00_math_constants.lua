--@ Vircon32 Lua Math Constants Unit Test
--@ Tests ONLY math library constants (pi, e, huge).
--@ Results stored in global variables for automated memory scraping.

function test_math_constants()
    -- === Test 1: math.pi ===
    number_result1 = math.pi  -- Expected: ~3.141592653589793

    -- === Test 2: math.e ===
    number_result2 = math.e  -- Expected: ~2.718281828459045

    -- === Test 3: math.huge ===
    number_result3 = math.huge  -- Expected: ~3.4028235e+38 (max float)
end

function main()
    ioports.gpu.clear("black")
    test_math_constants()

    print(100, 00,  "--- Math Constants Test ---")
    print(100, 20,  "math.pi: " .. number_result1)
    print(100, 40,  "math.e: " .. number_result2)
    print(100, 60,  "math.huge: " .. number_result3)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
number_result1: 3.141592653589793
number_result2: 2.718281828459045
number_result3: 3402823466385288.0 (or similar large value)
]]
