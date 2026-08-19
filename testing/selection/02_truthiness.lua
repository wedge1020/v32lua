--@ Vircon32 Lua Truthiness Semantics Unit Test
--@ Tests Lua's actual truthy/falsy rules: ONLY nil and false are falsy --
--@ 0, the empty string, and an empty table are all truthy. This is a
--@ common compiler-implementation gotcha (easy to accidentally treat 0
--@ or "" as falsy, matching C/JS conventions instead of Lua's).
--@ Results are stored in global variables for automated memory scraping.

function test_truthiness()
    -- === Test 00: The number 0 is TRUTHY (unlike C/JS) ===
    local hit00 = false
    if 0 then
        hit00 = true
    end
    boolean_result00 = hit00
    __rawasm__("__debug0:")

    -- === Test 01: The empty string is TRUTHY (unlike some languages) ===
    local hit01 = false
    if "" then
        hit01 = true
    end
    boolean_result01 = hit01
    __rawasm__("__debug1:")

    -- === Test 02: An empty table is TRUTHY ===
    local hit02 = false
    if {} then
        hit02 = true
    end
    boolean_result02 = hit02
    __rawasm__("__debug2:")

    -- === Test 03: nil is FALSY ===
    local hit03 = false
    if nil then
        hit03 = true
    end
    boolean_result03 = hit03
    __rawasm__("__debug3:")

    -- === Test 04: false is FALSY ===
    local hit04 = false
    if false then
        hit04 = true
    end
    boolean_result04 = hit04
    __rawasm__("__debug4:")

    -- === Test 05: 'not 0' is false, since 0 is truthy ===
    boolean_result05 = not 0
    __rawasm__("__debug5:")

    -- === Test 06: 'not nil' and 'not false' are both true ===
    boolean_result06a = not nil
    boolean_result06b = not false
    __rawasm__("__debug6:")

    -- === Test 07: A local variable holding a truthy non-boolean value ===
    -- === used directly as an if-condition ===
    local msg = "hello"
    local hit07 = false
    if msg then
        hit07 = true
    end
    boolean_result07 = hit07
    __rawasm__("__debug7:")
end

function main()
    ioports.gpu.clear("black")
    test_truthiness()

    print(000, 00,  "--- Truthiness Test ---")
    print(000, 020, "Test 00 - Zero is truthy: " ..     tostring(boolean_result00))
    print(000, 040, "Test 01 - Empty str truthy: " ..   tostring(boolean_result01))
    print(000, 060, "Test 02 - Empty table truthy: " .. tostring(boolean_result02))
    print(000, 080, "Test 03 - Nil is falsy: " ..       tostring(boolean_result03))
    print(000, 100, "Test 04 - False is falsy: " ..     tostring(boolean_result04))
    print(000, 120, "Test 05 - Not zero: " ..           tostring(boolean_result05))
    print(000, 140, "Test 06 - Not nil: " ..            tostring(boolean_result06a))
    print(000, 160, "Test 06 - Not false: " ..          tostring(boolean_result06b))
    print(000, 180, "Test 07 - Truthy var: " ..         tostring(boolean_result07))
end

--[[
=== EXPECTED OUTPUT ===
boolean_result00: true
boolean_result01: true
boolean_result02: true
boolean_result03: false
boolean_result04: false
boolean_result05: false
boolean_result06a: true
boolean_result06b: true
boolean_result07: true
--]]
