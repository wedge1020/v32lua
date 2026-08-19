--@ Vircon32 Lua Multiple Return Values Unit Test
--@ Tests functions returning more than one value, and multiple-assignment
--@ correctly consuming them. Also covers target/value count mismatches
--@ and passthrough chaining.
--@ Results are stored in global variables for automated memory scraping.
--@
--@ NOTE: Test 06 (passthrough) is EXPECTED TO CURRENTLY FAIL. node_return()
--@ has no special case for "a return statement whose single expression is
--@ itself a multi-return call" -- it captures only the first value (R0)
--@ via generate_asm()'s single dest_reg, the same way node_multiple_
--@ assignment() originally did for method calls before that was fixed.
--@ Flagging as a known gap rather than silently shipping a passing test.

function test_multi_return()
    -- === Test 00: Two return values, both consumed ===
    local function divmod(a, b)
        return a // b, a % b
    end
    local q, r = divmod(17, 5)
    number_result00 = q   -- 3
    number_result01 = r   -- 2
    __rawasm__("__debug0:")

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
    __rawasm__("__debug1:")

    -- === Test 02: Fewer targets than return values -- extras discarded ===
    local first_only = divmod(17, 5)
    number_result05 = first_only   -- 3
    __rawasm__("__debug2:")

    -- === Test 03: More targets than return values -- extra gets nil ===
    local function single_value()
        return 42
    end
    local a, b = single_value()
    number_result06 = a          -- 42
    number_result07 = b or 0     -- 0
    __rawasm__("__debug3:")

    -- === Test 04: No return statement -- every target gets nil ===
    local function no_return()
    end
    local x, y = no_return()
    number_result08 = x or 0   -- 0
    number_result09 = y or 0   -- 0
    __rawasm__("__debug4:")

    -- === Test 05: Return count differs by branch -- call site sizes to ===
    -- === the largest branch ===
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
    number_result13 = p4 or 0     -- 0
    __rawasm__("__debug5:")

    -- === Test 06: Passthrough -- forwarding another function's ===
    -- === multi-return directly as this function's own return. See the ===
    -- === file-header note: expected to fail until node_return() gains ===
    -- === multi-return-passthrough support. ===
    local function inner_pair()
        return 5, 6
    end
    local function passthrough()
        return inner_pair()
    end
    local pa, pb = passthrough()
    number_result14 = pa   -- 5
    number_result15 = pb   -- 6
    __rawasm__("__debug6:")
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
    print(200, 040, "Test 06 - passthrough a: " ..   number_result14)
    print(200, 060, "Test 06 - passthrough b: " ..   number_result15)
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
number_result14: 5.0000
number_result15: 6.0000
--]]
