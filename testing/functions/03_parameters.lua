--@ Vircon32 Lua Function Parameters Unit Test
--@ Tests parameter passing semantics: value vs. reference, defaults,
--@ shadowing, and variadics mixed with fixed parameters.
--@ Results are stored in global variables for automated memory scraping.

function test_parameters()
    -- === Test 00: Numeric parameter mutation does NOT leak to caller ===
    -- === (numbers are passed by value) ===
    local function try_mutate_number(n)
        n = n + 100
        return n
    end
    local original = 5
    local returned = try_mutate_number(original)
    number_result00a = original   -- still 5
    number_result00b = returned   -- 105
    __rawasm__("__debug0:")

    -- === Test 01: Table field mutation DOES leak to caller (tables ===
    -- === are passed by reference -- boxed pointers) ===
    local function mutate_table(t)
        t.value = t.value + 100
    end
    local box = {value = 5}
    mutate_table(box)
    number_result01 = box.value   -- 105
    __rawasm__("__debug1:")

    -- === Test 02: Default-parameter idiom via 'or' ===
    local function greet(name)
        name = name or "world"
        return name
    end
    string_result02a = greet("Lua")
    string_result02b = greet(nil)
    __rawasm__("__debug2:")

    -- === Test 03: Parameter shadows an outer local of the same name ===
    local shadow_target = 1
    local function shadow_test(shadow_target)
        return shadow_target * 10
    end
    number_result03a = shadow_test(9)     -- 90 (parameter, not outer local)
    number_result03b = shadow_target      -- 1 (outer local untouched)
    __rawasm__("__debug3:")

    -- === Test 04: Variadic mixed with fixed leading parameters ===
    local function labeled_sum(label_num, ...)
        local args = {...}
        local total = 0
        for i, v in ipairs(args) do
            total = total + v
        end
        return label_num + total
    end
    number_result04 = labeled_sum(1000, 1, 2, 3)   -- 1006
    __rawasm__("__debug4:")

    -- === Test 05: Variadic arguments forwarded into another call via ===
    -- === an explicit table capture ===
    local function sum_all(...)
        local args = {...}
        local total = 0
        for i, v in ipairs(args) do
            total = total + v
        end
        return total
    end
    local function forward_variadic(...)
        local args = {...}
        return sum_all(args[1], args[2], args[3])
    end
    number_result05 = forward_variadic(7, 8, 9)   -- 24
    __rawasm__("__debug5:")

    -- === Test 06: Variadic function called with zero arguments ===
    local function count_args(...)
        local args = {...}
        return #args
    end
    number_result06 = count_args()   -- 0
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_parameters()

    print(000, 00,  "--- Parameters Test ---")
    print(000, 020, "Test 00 - Original unchanged: " .. number_result00a)
    print(000, 040, "Test 00 - Returned mutated: " ..   number_result00b)
    print(000, 060, "Test 01 - Table leaked: " ..       number_result01)
    print(000, 080, "Test 02 - Explicit name: " ..      string_result02a)
    print(000, 100, "Test 02 - Default name: " ..       string_result02b)
    print(000, 120, "Test 03 - Shadowed param: " ..     number_result03a)
    print(000, 140, "Test 03 - Outer untouched: " ..    number_result03b)
    print(000, 160, "Test 04 - Labeled sum: " ..        number_result04)
    print(000, 180, "Test 05 - Forwarded variadic: " .. number_result05)
    print(000, 200, "Test 06 - Zero args: " ..          number_result06)
end

--[[
=== EXPECTED OUTPUT ===
number_result00a: 5.0000
number_result00b: 105.0000
number_result01: 105.0000
string_result02a: "Lua"
string_result02b: "world"
number_result03a: 90.0000
number_result03b: 1.0000
number_result04: 1006.0000
number_result05: 24.0000
number_result06: 0.0000
--]]
