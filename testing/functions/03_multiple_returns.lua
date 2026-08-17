--#title "v32lua multiple return values unit test"
--@ Vircon32 Lua Multiple Return Values Unit Test
--@ Tests functions returning more than one value, and multiple-assignment
--@ correctly consuming them -- for user-defined functions specifically
--@ (as opposed to the small fixed set of builtin math functions, which
--@ has its own coverage in math/06_math_decomposition.lua). Also covers
--@ target/value count mismatches and passthrough via multiple calls.
--@ Results are stored in global variables for automated memory scraping.

function test_multi_return()
    -- === Test 00: A user-defined function returning two values, both ===
    -- === consumed ===
    local function divmod(a, b)
        return a // b, a % b
    end
    local q, r = divmod(17, 5)
    number_result00 = q   -- 3
    number_result01 = r   -- 2

    -- === Test 01: Three return values ===
    local function minmaxsum(a, b, c)
        local lo = a
        if b < lo then lo = b end
        if c < lo then lo = c end
        local hi = a
        if b > hi then hi = b end
        if c > hi then hi = c end
        return lo, hi, a + b + c
    end
    local lo, hi, total = minmaxsum(4, 9, 2)
    number_result02 = lo      -- 2
    number_result03 = hi      -- 9
    number_result04 = total   -- 15

    -- === Test 02: Fewer targets than return values -- extras are ===
    -- === simply discarded, not an error ===
    local first_only = divmod(17, 5)
    number_result05 = first_only   -- 3 (the second value, 2, is dropped)

    -- === Test 03: More targets than return values -- extra targets get ===
    -- === nil, which 'or 0' turns into a visible 0 for this test ===
    local function single_value()
        return 42
    end
    local a, b = single_value()
    number_result06 = a          -- 42
    number_result07 = b or 0     -- 0 (b is nil)

    -- === Test 04: A function with no return statement at all -- every ===
    -- === target gets nil ===
    local function no_return()
    end
    local x, y = no_return()
    number_result08 = x or 0   -- 0
    number_result09 = y or 0   -- 0

    -- === Test 05: Return count can differ by branch -- the call site ===
    -- === must size itself to the LARGEST branch, since which branch ===
    -- === actually runs isn't known until runtime ===
    local function maybe_pair(flag)
        if flag then
            return 1, 2
        end
        return 99
    end
    local p1, p2 = maybe_pair(true)
    number_result10 = p1   -- 1
    number_result11 = p2   -- 2
    local p3, p4 = maybe_pair(false)
    number_result12 = p3          -- 99
    number_result13 = p4 or 0     -- 0 (single-branch return, p4 is nil)
end

function main()
    ioports.gpu.clear("black")
    test_multi_return()

    print(000, 00,  "--- Multiple Return Values Test ---")
    print(000, 020, "Test 00 - divmod q: " ..        number_result00)
    print(000, 040, "Test 00 - divmod r: " ..        number_result01)
    print(000, 060, "Test 01 - min: " ..             number_result02)
    print(000, 080, "Test 01 - max: " ..             number_result03)
    print(000, 100, "Test 01 - sum: " ..             number_result04)
    print(000, 120, "Test 02 - truncated: " ..       number_result05)
    print(000, 140, "Test 03 - present: " ..         number_result06)
    print(000, 160, "Test 03 - padded nil: " ..      number_result07)
    print(000, 180, "Test 04 - no-return x: " ..     number_result08)
    print(000, 200, "Test 04 - no-return y: " ..     number_result09)
    print(000, 220, "Test 05 - branch A p1: " ..     number_result10)
    print(000, 240, "Test 05 - branch A p2: " ..     number_result11)
    print(000, 260, "Test 05 - branch B p3: " ..     number_result12)
    print(200, 020, "Test 05 - branch B p4: " ..     number_result13)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 3.0000
number_result01: 2.0000
number_result02: 2.0000
number_result03: 9.0000
number_result04: 15.0000
number_result05: 3.0000
number_result06: 42.0000
number_result07: 0.0000
number_result08: 0.0000
number_result09: 0.0000
number_result10: 1.0000
number_result11: 2.0000
number_result12: 99.0000
number_result13: 0.0000

--]]
