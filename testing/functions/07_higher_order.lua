--@ Vircon32 Lua Higher-Order Functions Unit Test
--@ Tests functions as first-class values: passed as arguments, returned
--@ from other functions, composed, anonymous, immediately invoked, held
--@ in a table, and used as unbound method callbacks.
--@ Results are stored in global variables for automated memory scraping.

function test_higher_order()
    -- === Test 00: Function passed as an argument ===
    local function apply(f, x)
        return f(x)
    end
    local function double(x)
        return x * 2
    end
    number_result00 = apply(double, 25)   -- 50
    __rawasm__("__debug0:")

    -- === Test 01: Function returning a function ===
    local function make_multiplier(factor)
        return function(x)
            return x * factor
        end
    end
    local triple = make_multiplier(3)
    number_result01 = triple(10)   -- 30
    __rawasm__("__debug1:")

    -- === Test 02: Compose two functions ===
    local function compose(f, g)
        return function(x)
            return f(g(x))
        end
    end
    local function add_one(x)
        return x + 1
    end
    local function double_it(x)
        return x * 2
    end
    local composed = compose(add_one, double_it)
    number_result02 = composed(5)   -- 11
    __rawasm__("__debug2:")

    -- === Test 03: Anonymous function expression ===
    local anonymous = function(x, y)
        return x + y
    end
    number_result03 = anonymous(10, 20)   -- 30
    __rawasm__("__debug3:")

    -- === Test 04: Immediately invoked function expression (IIFE) ===
    local result = (function(x, y)
        return x * y
    end)(5, 6)
    number_result04 = result   -- 30
    __rawasm__("__debug4:")

    -- === Test 05: Array of functions in a table, invoked from a loop ===
    local function inc(x) return x + 1 end
    local function dec(x) return x - 1 end
    local function zero(x) return 0 end
    local ops = {inc, dec, zero}
    local total = 0
    for i, op in ipairs(ops) do
        total = total + op(10)
    end
    number_result05 = total   -- 11 + 9 + 0 = 20
    __rawasm__("__debug5:")

    -- === Test 06: Unbound method value passed as a callback and ===
    -- === invoked manually with an explicit self ===
    local obj = {value = 7}
    function obj:get_value()
        return self.value
    end
    local unbound = obj.get_value
    local function invoke_with(fn, self_arg)
        return fn(self_arg)
    end
    number_result06 = invoke_with(unbound, obj)   -- 7
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_higher_order()

    print(000, 00,  "--- Higher-Order Functions Test ---")
    print(000, 020, "Test 00 - Apply: " ..          number_result00)
    print(000, 040, "Test 01 - Make mult: " ..      number_result01)
    print(000, 060, "Test 02 - Compose: " ..        number_result02)
    print(000, 080, "Test 03 - Anonymous: " ..      number_result03)
    print(000, 100, "Test 04 - IIFE: " ..           number_result04)
    print(000, 120, "Test 05 - Fn table: " ..       number_result05)
    print(000, 140, "Test 06 - Unbound method: " .. number_result06)
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 50.0000
number_result01: 30.0000
number_result02: 11.0000
number_result03: 30.0000
number_result04: 30.0000
number_result05: 20.0000
number_result06: 7.0000
--]]
