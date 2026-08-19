--@ Vircon32 Lua Methods Unit Test
--@ Tests colon-call methods, dot-syntax method definitions, dynamic
--@ string-key invocation, local-dot-method definitions, and independent-
--@ instance construction.
--@ Results are stored in global variables for automated memory scraping.
--@
--@ NOTE: Test 08 (local-dot-method) requires the local-dot-method grammar
--@ rule to be added to parser.y first -- see accompanying discussion.
--@ Everything else here compiles against the existing grammar.

local obj = {value = 42, name = "test"}

function obj:get_value()
    return self.value
end

function obj:set_value(new_val)
    self.value = new_val
end

function obj:add(x)
    return self.value + x
end

function test_methods()
    -- === Test 00: Colon call -- get/set ===
    obj:set_value(10)
    number_result00 = obj:get_value()   -- 10
    __rawasm__("__debug0:")

    -- === Test 01: Colon call with arithmetic ===
    number_result01 = obj:add(5)   -- 15
    __rawasm__("__debug1:")

    -- === Test 02: Colon call with string concatenation ===
    function obj:describe()
        return self.name .. "=" .. self.value
    end
    string_result02 = obj:describe()   -- "test=10"
    __rawasm__("__debug2:")

    -- === Test 03: Colon call with boolean return + comparison ===
    function obj:is_bigger_than(other)
        return self.value > other
    end
    boolean_result03 = obj:is_bigger_than(5)   -- true
    __rawasm__("__debug3:")

    -- === Test 04: Chained method calls ===
    obj:set_value(3)
    number_result04 = obj:add(obj:get_value())   -- 3 + 3 = 6
    __rawasm__("__debug4:")

    -- === Test 05: Dot-syntax method DEFINITION, invoked via colon CALL ===
    -- === (dot-defined methods take 'self' as an explicit first param; ===
    -- === a colon call site still auto-supplies it) ===
    function obj.compute(self, y)
        return self.value + y
    end
    number_result05 = obj:compute(100)   -- 103
    __rawasm__("__debug5:")

    -- === Test 06: Dynamic string-key invocation -- no colon sugar, so ===
    -- === 'self' must be passed explicitly ===
    local result06 = obj["get_value"](obj)
    number_result06 = result06   -- 3
    __rawasm__("__debug6:")

    -- === Test 07: Constructor pattern -- two independent instances ===
    -- === with no shared state between them ===
    local function new_counter()
        local self = {count = 0}
        function self:increment()
            self.count = self.count + 1
            return self.count
        end
        return self
    end
    local counter1 = new_counter()
    local counter2 = new_counter()
    counter1:increment()
    counter1:increment()
    counter2:increment()
    number_result07a = counter1:increment()   -- 3
    number_result07b = counter2.count         -- 1
    __rawasm__("__debug7:")

    -- === Test 08: Local dot-syntax method definition (no colon) -- ===
    -- === requires the local-dot-method grammar rule ===
    local function obj.scale(self, factor)
        return self.value * factor
    end
    number_result08 = obj:scale(10)   -- value is still 3 -> 30
    __rawasm__("__debug8:")
end

function main()
    ioports.gpu.clear("black")
    test_methods()

    print(000, 00,  "--- Methods Test ---")
    print(000, 020, "Test 00 - Get/set: " ..        number_result00)
    print(000, 040, "Test 01 - Add: " ..            number_result01)
    print(000, 060, "Test 02 - Describe: " ..       string_result02)
    print(000, 080, "Test 03 - Compare: " ..        tostring(boolean_result03))
    print(000, 100, "Test 04 - Chained: " ..        number_result04)
    print(000, 120, "Test 05 - Dot-defined: " ..    number_result05)
    print(000, 140, "Test 06 - Dynamic key: " ..    number_result06)
    print(000, 160, "Test 07 - Instance 1: " ..     number_result07a)
    print(000, 180, "Test 07 - Instance 2: " ..     number_result07b)
    print(000, 200, "Test 08 - Local dot method: " .. number_result08)
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 10.0000
number_result01: 15.0000
string_result02: "test=10"
boolean_result03: true
number_result04: 6.0000
number_result05: 103.0000
number_result06: 3.0000
number_result07a: 3.0000
number_result07b: 1.0000
number_result08: 30.0000
--]]
