--@ Vircon32 Lua Logical Operators Unit Test
--@ Tests 'and'/'or'/'not' as EXPRESSIONS, not just as if-conditions --
--@ they return the actual operand value, not a coerced boolean. Also
--@ covers short-circuit laziness (the untaken side is never evaluated)
--@ and the classic 'x and false or y' footgun.
--@ Results are stored in global variables for automated memory scraping.

function test_logical_operators()
    -- === Test 00: 'and' returns the RIGHT operand when the left is ===
    -- === truthy -- not just 'true' ===
    number_result00 = 1 and 2   -- 2, not true
    __rawasm__("__debug0:")

    -- === Test 01: 'and' returns the LEFT operand (short-circuits) ===
    -- === when it's falsy, and never evaluates the right side ===
    local right_evaluated01 = false
    local function mark01()
        right_evaluated01 = true
        return 2
    end
    local result01 = false and mark01()
    boolean_result01a = (result01 == false)
    boolean_result01b = right_evaluated01   -- must be false: never called
    __rawasm__("__debug1:")

    -- === Test 02: 'or' returns the LEFT operand when it's truthy ===
    number_result02 = 5 or 10   -- 5, not true
    __rawasm__("__debug2:")

    -- === Test 03: 'or' returns the RIGHT operand (short-circuits) ===
    -- === when the left is falsy, and never evaluates the left again ===
    string_result03 = nil or "default"
    __rawasm__("__debug3:")

    -- === Test 04: 'not' on a chained expression ===
    boolean_result04 = not (5 > 10)   -- true
    __rawasm__("__debug4:")

    -- === Test 05: Chained 'and' across three operands ===
    boolean_result05 = true and true and true    -- true
    local chain_result = true and false and true
    boolean_result05b = chain_result              -- false
    __rawasm__("__debug5:")

    -- === Test 06: Classic footgun -- 'x and false or y' does NOT ===
    -- === reliably pick 'false' when x is truthy, because 'false' ===
    -- === itself is falsy to the trailing 'or': this must fall through ===
    -- === to y regardless of x ===
    local x = true
    local footgun_result = x and false or "fallback"
    string_result06 = footgun_result   -- "fallback", NOT false
    __rawasm__("__debug6:")

    -- === Test 07: Short-circuit laziness on 'or' -- the right side ===
    -- === must never be evaluated when the left is truthy ===
    local right_evaluated07 = false
    local function mark07()
        right_evaluated07 = true
        return "unused"
    end
    local result07 = "already truthy" or mark07()
    boolean_result07 = right_evaluated07   -- must be false: never called
    __rawasm__("__debug7:")
end

function main()
    ioports.gpu.clear("black")
    test_logical_operators()

    print(000, 00,  "--- Logical Operators Test ---")
    print(000, 020, "Test 00 - And returns 2: " ..    number_result00)
    print(000, 040, "Test 01a - And short result: " .. tostring(boolean_result01a))
    print(000, 060, "Test 01b - Right unevaluated: " .. tostring(boolean_result01b))
    print(000, 080, "Test 02 - Or returns 5: " ..     number_result02)
    print(000, 100, "Test 03 - Or default: " ..       string_result03)
    print(000, 120, "Test 04 - Not chained: " ..      tostring(boolean_result04))
    print(000, 140, "Test 05 - Chained and true: " .. tostring(boolean_result05))
    print(000, 160, "Test 05 - Chained and false: " .. tostring(boolean_result05b))
    print(000, 180, "Test 06 - Footgun fallback: " .. string_result06)
    print(000, 200, "Test 07 - Or laziness: " ..      tostring(boolean_result07))
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 2.0000
boolean_result01a: true
boolean_result01b: false
number_result02: 5.0000
string_result03: "default"
boolean_result04: true
boolean_result05: true
boolean_result05b: false
string_result06: "fallback"
boolean_result07: false
--]]
