--@ Vircon32 Lua Function Returns Unit Test
--@ Tests bare return, explicit return nil, absent return, early return,
--@ return-from-inside-loop, and branch-dependent return values.
--@ Results are stored in global variables for automated memory scraping.

function test_returns()
    -- === Test 00: Bare 'return' with no expression ===
    local function bare_return()
        return
    end
    local r00 = bare_return()
    boolean_result00 = (r00 == nil)
    __rawasm__("__debug0:")

    -- === Test 01: Explicit 'return nil' ===
    local function explicit_nil()
        return nil
    end
    local r01 = explicit_nil()
    boolean_result01 = (r01 == nil)
    __rawasm__("__debug1:")

    -- === Test 02: No return statement at all ===
    local function no_return_stmt()
        local unused = 1 + 1
    end
    local r02 = no_return_stmt()
    boolean_result02 = (r02 == nil)
    __rawasm__("__debug2:")

    -- === Test 03: Early return -- code after it must not execute ===
    local function early_return(x)
        if x > 0 then
            return "early"
        end
        return "late"
    end
    string_result03 = early_return(5)
    __rawasm__("__debug3:")

    -- === Test 04: Return from inside a while loop ===
    local function find_first_over(limit)
        local i = 1
        while true do
            if i > limit then
                return i
            end
            i = i + 1
        end
    end
    number_result04 = find_first_over(7)
    __rawasm__("__debug4:")

    -- === Test 05: Return from inside a numeric for loop ===
    local function find_index_of(target)
        local values = {10, 20, 30, 40}
        for i = 1, 4 do
            if values[i] == target then
                return i
            end
        end
        return -1
    end
    number_result05 = find_index_of(30)
    __rawasm__("__debug5:")

    -- === Test 06: Three-way branch selects the correct return value ===
    local function classify(x)
        if x > 0 then
            return "positive"
        elseif x < 0 then
            return "negative"
        else
            return "zero"
        end
    end
    string_result06a = classify(5)
    string_result06b = classify(-5)
    string_result06c = classify(0)
    __rawasm__("__debug6:")

    -- === Test 07: Arithmetic expression as the return value ===
    local function midpoint(a, b)
        return (a + b) / 2
    end
    number_result07 = midpoint(10, 20)
    __rawasm__("__debug7:")
end

function main()
    ioports.gpu.clear("black")
    test_returns()

    print(000, 00,  "--- Returns Test ---")
    print(000, 020, "Test 00 - Bare return nil: " ..   tostring(boolean_result00))
    print(000, 040, "Test 01 - Explicit nil: " ..      tostring(boolean_result01))
    print(000, 060, "Test 02 - No return stmt: " ..    tostring(boolean_result02))
    print(000, 080, "Test 03 - Early return: " ..      string_result03)
    print(000, 100, "Test 04 - While loop ret: " ..    number_result04)
    print(000, 120, "Test 05 - For loop ret: " ..      number_result05)
    print(000, 140, "Test 06 - Positive: " ..          string_result06a)
    print(000, 160, "Test 06 - Negative: " ..          string_result06b)
    print(000, 180, "Test 06 - Zero: " ..              string_result06c)
    print(000, 200, "Test 07 - Midpoint: " ..          number_result07)
end

--[[
=== EXPECTED OUTPUT ===
boolean_result00: true
boolean_result01: true
boolean_result02: true
string_result03: "early"
number_result04: 8.0000
number_result05: 3.0000
string_result06a: "positive"
string_result06b: "negative"
string_result06c: "zero"
number_result07: 15.0000
--]]
