--@ Vircon32 Lua Functions Basic Unit Test
--@ Tests basic function declaration/call forms: global, local, parameter
--@ counts, forward references, and arity mismatches (extra/missing args).
--@ Results are stored in global variables for automated memory scraping.

function later_defined()
    return 777
end

function test_functions_basic()
    -- === Test 00: Global function, no params, side-effect only ===
    function set_flag()
        number_result00 = 1
    end
    set_flag()
    __rawasm__("__debug0:")

    -- === Test 01: Local function, no params, with return ===
    local function no_params_with_return()
        return 100
    end
    number_result01 = no_params_with_return()
    __rawasm__("__debug1:")

    -- === Test 02: Function with a single parameter ===
    local function single_param(x)
        return x * 2
    end
    number_result02 = single_param(25)
    __rawasm__("__debug2:")

    -- === Test 03: Function with multiple parameters ===
    local function multi_param(a, b, c)
        return a + b + c
    end
    number_result03 = multi_param(1, 2, 3)
    __rawasm__("__debug3:")

    -- === Test 04: Function calling another function ===
    local function helper(x)
        return x * x
    end
    local function caller(x)
        return helper(x) + 1
    end
    number_result04 = caller(5)
    __rawasm__("__debug4:")

    -- === Test 05: Forward reference -- call a global function defined ===
    -- === textually AFTER this one in the file ===
    number_result05 = later_defined()
    __rawasm__("__debug5:")

    -- === Test 06: Extra arguments are silently discarded, not an error ===
    local function takes_two(a, b)
        return a + b
    end
    number_result06 = takes_two(3, 4, 5, 6)   -- 5, 6 discarded
    __rawasm__("__debug6:")

    -- === Test 07: Missing arguments become nil ===
    local function takes_two_optional(a, b)
        return a, b or 0
    end
    local a7, b7 = takes_two_optional(9)
    number_result07a = a7
    number_result07b = b7
    __rawasm__("__debug7:")
end

function main()
    ioports.gpu.clear("black")
    test_functions_basic()

    print(000, 00,  "--- Functions Basic Test ---")
    print(000, 020, "Test 00 - Global fn flag: " ..   number_result00)
    print(000, 040, "Test 01 - Local w/ret: " ..      number_result01)
    print(000, 060, "Test 02 - Single param: " ..     number_result02)
    print(000, 080, "Test 03 - Multi param: " ..      number_result03)
    print(000, 100, "Test 04 - Caller: " ..           number_result04)
    print(000, 120, "Test 05 - Forward ref: " ..      number_result05)
    print(000, 140, "Test 06 - Extra args: " ..       number_result06)
    print(000, 160, "Test 07 - Missing a: " ..        number_result07a)
    print(000, 180, "Test 07 - Missing b: " ..        number_result07b)
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 1.0000
number_result01: 100.0000
number_result02: 50.0000
number_result03: 6.0000
number_result04: 26.0000
number_result05: 777.0000
number_result06: 7.0000
number_result07a: 9.0000
number_result07b: 0.0000
--]]
