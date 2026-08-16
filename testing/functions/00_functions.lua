--#title "v32lua functions basic unit test"
--@ Vircon32 Lua Functions Basic Unit Test
--@ Tests basic function features: definition, calls, parameters, returns.
--@ Results are stored in global variables for automated memory scraping.

function test_functions_basic()
    -- === Test 00: Parameterless function with no return ===
    local function no_params_no_return()
        -- Just sets a global
        number_result00 = 42
    end
    no_params_no_return()

    -- === Test 01: Parameterless function with return ===
    local function no_params_with_return()
        return 100
    end
    number_result01 = no_params_with_return()

    -- === Test 02: Function with single parameter ===
    local function single_param(x)
        return x * 2
    end
    number_result02 = single_param(25)

    -- === Test 03: Function with multiple parameters ===
    local function multi_param(a, b, c)
        return a + b + c
    end
    number_result03 = multi_param(1, 2, 3)

    -- === Test 04: Function with single return value ===
    local function single_return(x)
        return x + 10
    end
    number_result04 = single_return(5)

    -- === Test 05: Function with multiple return values ===
    local function multi_return(a, b)
        return a + b, a * b
    end
    local sum, product = multi_return(4, 5)
    number_result05 = sum
    number_result06 = product

    -- === Test 06: Function with no parameters, returns nil ===
    local function returns_nil()
        return nil
    end
    local result = returns_nil()
    boolean_result06 = (result == nil)

    -- === Test 07: Function with default parameter behavior (using local) ===
    local function with_local_param(x)
        local y = x + 5
        return y
    end
    number_result07 = with_local_param(10)

    -- === Test 08: Function calling another function ===
    local function helper(x)
        return x * x
    end
    local function caller(x)
        return helper(x) + 1
    end
    number_result08 = caller(5)

    -- === Test 09: Function with early return ===
    local function early_return(x)
        if x > 0 then
            return 1
        end
        return 0
    end
    number_result09 = early_return(10)

    -- === Test 10: Function with early return (false case) ===
    number_result10 = early_return(-5)

    -- === Test 11: Function with conditional return ===
    local function conditional_return(x)
        if x % 2 == 0 then
            return "even"
        else
            return "odd"
        end
    end
    string_result11 = conditional_return(4)

    -- === Test 12: Function with arithmetic operations ===
    local function arithmetic(a, b)
        return (a + b) * (a - b)
    end
    number_result12 = arithmetic(10, 3)

    -- === Test 13: Function with boolean return ===
    local function is_positive(x)
        return x > 0
    end
    boolean_result13 = is_positive(5)

    -- === Test 14: Function with boolean return (false) ===
    boolean_result14 = is_positive(-5)

    -- === Test 15: Function with string parameter ===
    local function string_length(s)
        return #s
    end
    number_result15 = string_length("hello")

    -- === Test 16: Function with string concatenation ===
    local function concat_strings(a, b)
        return a .. b
    end
    string_result16 = concat_strings("hello", "world")

    -- === Test 17: Function with comparison in return ===
    local function is_greater(a, b)
        return a > b
    end
    boolean_result17 = is_greater(10, 5)

    -- === Test 18: Function with logical operations ===
    local function logical_and(a, b)
        return a and b
    end
    boolean_result18 = logical_and(true, false)

    -- === Test 19: Function with multiple statements ===
    local function multiple_statements(x)
        local temp = x * 2
        temp = temp + 10
        return temp
    end
    number_result19 = multiple_statements(5)

    -- === Test 20: Function with local variable shadowing ===
    local outer = 10
    local function shadow_test(x)
        local outer = x
        return outer
    end
    number_result20 = shadow_test(20)

    -- === Test 21: Function returning function result ===
    local function get_value()
        return 42
    end
    local function return_function_result()
        return get_value()
    end
    number_result21 = return_function_result()

    -- === Test 22: Function with expression as parameter ===
    local function square(x)
        return x * x
    end
    number_result22 = square(2 + 3)

    -- === Test 23: Function with chained calls ===
    local function add_one(x)
        return x + 1
    end
    number_result23 = add_one(add_one(add_one(5)))
end

function main()
    ioports.gpu.clear("black")
    test_functions_basic()

    print(000, 00,  "--- Functions Basic Test ---")
    print(000, 020, "Test 00 - No param no ret: " ..    number_result00)
    print(000, 040, "Test 01 - No param w/ret: " ..    number_result01)
    print(000, 060, "Test 02 - Single param: " ..      number_result02)
    print(000, 080, "Test 03 - Multi param: " ..      number_result03)
    print(000, 100, "Test 04 - Single return: " ..    number_result04)
    print(000, 120, "Test 05 - Multi return a: " ..   number_result05)
    print(000, 140, "Test 06 - Multi return b: " ..   number_result06)
    print(000, 160, "Test 07 - Local param: " ..      number_result07)
    print(000, 180, "Test 08 - Caller: " ..           number_result08)
    print(000, 200, "Test 09 - Early ret T: " ..      number_result09)
    print(000, 220, "Test 10 - Early ret F: " ..      number_result10)
    print(000, 240, "Test 11 - Cond ret: " ..         string_result11)
    print(000, 260, "Test 12 - Arithmetic: " ..       number_result12)
    print(200, 020, "Test 13 - Bool ret T: " ..       tostring(boolean_result13))
    print(200, 040, "Test 14 - Bool ret F: " ..       tostring(boolean_result14))
    print(200, 060, "Test 15 - Str len: " ..          number_result15)
    print(200, 080, "Test 16 - Str concat: " ..        string_result16)
    print(200, 100, "Test 17 - Comparison: " ..        tostring(boolean_result17))
    print(200, 120, "Test 18 - Logical: " ..          tostring(boolean_result18))
    print(200, 140, "Test 19 - Multi stmt: " ..        number_result19)
    print(200, 160, "Test 20 - Shadow: " ..           number_result20)
    print(200, 180, "Test 21 - Ret func: " ..         number_result21)
    print(200, 200, "Test 22 - Expr param: " ..        number_result22)
    print(200, 220, "Test 23 - Chained: " ..          number_result23)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 42.0000
number_result01: 100.0000
number_result02: 50.0000
number_result03: 6.0000
number_result04: 15.0000
number_result05: 9.0000
number_result06: 20.0000
boolean_result06: true
number_result07: 15.0000
number_result08: 26.0000
number_result09: 1.0000
number_result10: 0.0000
string_result11: "even"
number_result12: 91.0000
boolean_result13: true
boolean_result14: false
number_result15: 5.0000
string_result16: "helloworld"
boolean_result17: true
boolean_result18: false
number_result19: 20.0000
number_result20: 20.0000
number_result21: 42.0000
number_result22: 25.0000
number_result23: 8.0000

--]]
