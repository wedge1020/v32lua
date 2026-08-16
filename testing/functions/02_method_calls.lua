--#title "v32lua method calls unit test"
--@ Vircon32 Lua Method Calls Unit Test
--@ Tests method call syntax (colon operator), implicit self parameter.
--@ Results are stored in global variables for automated memory scraping.

-- Create a simple object table for method testing
local obj = {
    value = 42,
    name = "test"
}

-- Method definitions
function obj:get_value()
    return self.value
end

function obj:set_value(new_val)
    self.value = new_val
end

function obj:double()
    return self.value * 2
end

function obj:add(x)
    return self.value + x
end

function obj:concat_suffix(suffix)
    return self.name .. suffix
end

function obj:is_positive()
    return self.value > 0
end

function obj:compare(other)
    return self.value > other.value
end

function obj:to_string()
    return "value=" .. self.value .. ", name=" .. self.name
end

function test_method_calls()
    -- === Test 00: Method call - get_value ===
    number_result00 = obj:get_value()

    -- === Test 01: Method call with parameter - set_value ===
    obj:set_value(100)
    number_result01 = obj.value

    -- === Test 02: Method call with return - double ===
    number_result02 = obj:double()

    -- === Test 03: Method call with arithmetic - add ===
    number_result03 = obj:add(50)

    -- === Test 04: Method call with string operation - concat_suffix ===
    string_result04 = obj:concat_suffix("_modified")

    -- === Test 05: Method call with boolean return - is_positive ===
    boolean_result05 = obj:is_positive()

    -- === Test 06: Method call with comparison - compare ===
    local obj2 = {value = 50}
    function obj2:compare(other)
        return self.value > other.value
    end
    boolean_result06 = obj:compare(obj2)

    -- === Test 07: Method call with string return - to_string ===
    string_result07 = obj:to_string()

    -- === Test 08: Chained method calls ===
    obj:set_value(10)
    number_result08 = obj:double()

    -- === Test 09: Method call with multiple parameters ===
    local function obj:add_multiple(a, b, c)
        return self.value + a + b + c
    end
    number_result09 = obj:add_multiple(1, 2, 3)

    -- === Test 10: Method call returning method ===
    local function obj:get_doubler()
        return function(self, x)
            return self.value * x
        end
    end
    local doubler = obj:get_doubler()
    number_result10 = doubler(obj, 3)

    -- === Test 11: Method call with nil self (should work with explicit self) ===
    local function standalone_method(self, x)
        return (self or {}).value + x
    end
    number_result11 = standalone_method(obj, 5)

    -- === Test 12: Method call with expression as parameter ===
    number_result12 = obj:add(10 + 20)

    -- === Test 13: Method call with variable as parameter ===
    local increment = 15
    number_result13 = obj:add(increment)

    -- === Test 14: Method call with another method's result ===
    number_result14 = obj:add(obj:double())

    -- === Test 15: Method call in conditional ===
    if obj:is_positive() then
        number_result15 = 1
    else
        number_result15 = 0
    end

    -- === Test 16: Method call with boolean parameter ===
    local function obj:set_positive(flag)
        self.value = flag and 1 or -1
    end
    obj:set_positive(true)
    number_result16 = obj.value

    -- === Test 17: Method call with nil parameter ===
    local function obj:set_to_nil_or_value(x)
        self.value = x or 0
    end
    obj:set_to_nil_or_value(nil)
    number_result17 = obj.value

    -- === Test 18: Method modifying self and returning ===
    local function obj:increment_and_get()
        self.value = self.value + 1
        return self.value
    end
    number_result18 = obj:increment_and_get()

    -- === Test 19: Method with local variable ===
    local function obj:calculate_with_local()
        local temp = self.value * 2
        return temp + 10
    end
    number_result19 = obj:calculate_with_local()

    -- === Test 20: Method calling another method ===
    local function obj:add_and_double(x)
        return self:add(x) * 2
    end
    number_result20 = obj:add_and_double(5)

    -- === Test 21: Method with early return ===
    local function obj:check_and_return(x)
        if x > 0 then
            return self.value + x
        end
        return self.value
    end
    number_result21 = obj:check_and_return(10)

    -- === Test 22: Method with conditional return ===
    local function obj:conditional_return(x)
        if x > self.value then
            return "greater"
        elseif x < self.value then
            return "less"
        else
            return "equal"
        end
    end
    string_result22 = obj:conditional_return(20)

    -- === Test 23: Method with multiple returns ===
    local function obj:min_max(x)
        if x < self.value then
            return x, self.value
        else
            return self.value, x
        end
    end
    local min, max = obj:min_max(5)
    number_result23 = min
    number_result24 = max
end

function main()
    ioports.gpu.clear("black")
    test_method_calls()

    print(000, 00,  "--- Method Calls Test ---")
    print(000, 020, "Test 00 - Get value: " ..       number_result00)
    print(000, 040, "Test 01 - Set value: " ..       number_result01)
    print(000, 060, "Test 02 - Double: " ..           number_result02)
    print(000, 080, "Test 03 - Add: " ..             number_result03)
    print(000, 100, "Test 04 - Concat: " ..          string_result04)
    print(000, 120, "Test 05 - Is positive: " ..      tostring(boolean_result05))
    print(000, 140, "Test 06 - Compare: " ..          tostring(boolean_result06))
    print(000, 160, "Test 07 - To string: " ..       string_result07)
    print(000, 180, "Test 08 - Chained: " ..         number_result08)
    print(000, 200, "Test 09 - Add multiple: " ..     number_result09)
    print(000, 220, "Test 10 - Get doubler: " ..     number_result10)
    print(000, 240, "Test 11 - Standalone: " ..      number_result11)
    print(000, 260, "Test 12 - Expr param: " ..       number_result12)
    print(200, 020, "Test 13 - Var param: " ..        number_result13)
    print(200, 040, "Test 14 - Method result: " ..    number_result14)
    print(200, 060, "Test 15 - Conditional: " ..      number_result15)
    print(200, 080, "Test 16 - Set positive: " ..     number_result16)
    print(200, 100, "Test 17 - Set nil: " ..         number_result17)
    print(200, 120, "Test 18 - Incr & get: " ..      number_result18)
    print(200, 140, "Test 19 - Local var: " ..       number_result19)
    print(200, 160, "Test 20 - Call method: " ..     number_result20)
    print(200, 180, "Test 21 - Early ret: " ..       number_result21)
    print(200, 200, "Test 22 - Cond ret: " ..       string_result22)
    print(200, 220, "Test 23 - Multi min: " ..       number_result23)
    print(200, 240, "Test 24 - Multi max: " ..       number_result24)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 42.0000 (or 100.0000 after set_value)
number_result01: 100.0000
number_result02: 200.0000 (100 * 2)
number_result03: 150.0000 (100 + 50)
string_result04: "test_modified"
boolean_result05: true
boolean_result06: true (100 > 50)
string_result07: "value=100, name=test"
number_result08: 20.0000 (10 * 2)
number_result09: 16.0000 (10 + 1 + 2 + 3)
number_result10: 30.0000 (10 * 3)
number_result11: 47.0000 (42 + 5)
number_result12: 30.0000 (10 + 30)
number_result13: 25.0000 (10 + 15)
number_result14: 30.0000 (10 + 20)
number_result15: 1.0000
number_result16: 1.0000
number_result17: 0.0000
number_result18: 11.0000 (10 + 1)
number_result19: 30.0000 (10 * 2 + 10)
number_result20: 30.0000 ((10 + 5) * 2)
number_result21: 20.0000 (10 + 10)
string_result22: "greater"
number_result23: 10.0000
number_result24: 20.0000

--]]
