--@ Vircon32 Lua Closures Unit Test
--@ Tests upvalue capture: basic counters, captured parameters, shared
--@ upvalues between sibling closures, external mutation of a captured
--@ variable, nested (multi-level) capture, per-iteration capture inside
--@ a loop, and recursive closures.
--@ Results are stored in global variables for automated memory scraping.

function test_closures()
    -- === Test 00: Basic counter closure ===
    local function make_counter()
        local count = 0
        return function()
            count = count + 1
            return count
        end
    end
    local counter = make_counter()
    number_result00a = counter()   -- 1
    number_result00b = counter()   -- 2
    number_result00c = counter()   -- 3
    __rawasm__("__debug0:")

    -- === Test 01: Closure capturing a function PARAMETER (not a local) ===
    local function make_adder(x)
        return function(y)
            return x + y
        end
    end
    local add10 = make_adder(10)
    number_result01 = add10(5)   -- 15
    __rawasm__("__debug1:")

    -- === Test 02: Two sibling closures sharing one upvalue ===
    local function make_counter_pair()
        local count = 0
        local function increment()
            count = count + 1
            return count
        end
        local function get()
            return count
        end
        return increment, get
    end
    local inc, get = make_counter_pair()
    inc()
    inc()
    number_result02 = get()   -- 2
    __rawasm__("__debug2:")

    -- === Test 03: Mutating a captured variable from OUTSIDE the ===
    -- === closure, after creation, is visible through the closure ===
    -- === (proves shared-cell aliasing, not copy-on-capture) ===
    local shared = 1
    local function read_shared()
        return shared
    end
    shared = 99
    number_result03 = read_shared()   -- 99
    __rawasm__("__debug3:")

    -- === Test 04: Three-level nested closure -- innermost captures a ===
    -- === grandparent's local, skipping straight past the middle level ===
    local function outer()
        local base = 1000
        local function middle()
            local function innermost()
                return base + 1
            end
            return innermost()
        end
        return middle()
    end
    number_result04 = outer()   -- 1001
    __rawasm__("__debug4:")

    -- === Test 05: Closures created inside a loop each capture their ===
    -- === OWN per-iteration value, not one shared final value ===
    local function make_closures_in_loop()
        local fns = {}
        for i = 1, 3 do
            fns[i] = function()
                return i
            end
        end
        return fns
    end
    local fns = make_closures_in_loop()
    number_result05a = fns[1]()   -- 1
    number_result05b = fns[2]()   -- 2
    number_result05c = fns[3]()   -- 3
    __rawasm__("__debug5:")

    -- === Test 06: Recursive closure via a forward-declared local ===
    local function recursive_factorial(n)
        local fact
        fact = function(k)
            if k <= 1 then
                return 1
            end
            return k * fact(k - 1)
        end
        return fact(n)
    end
    number_result06 = recursive_factorial(5)   -- 120
    __rawasm__("__debug6:")
end

function main()
    ioports.gpu.clear("black")
    test_closures()

    print(000, 00,  "--- Closures Test ---")
    print(000, 020, "Test 00 - Counter 1: " ..        number_result00a)
    print(000, 040, "Test 00 - Counter 2: " ..        number_result00b)
    print(000, 060, "Test 00 - Counter 3: " ..        number_result00c)
    print(000, 080, "Test 01 - Adder: " ..            number_result01)
    print(000, 100, "Test 02 - Shared state: " ..     number_result02)
    print(000, 120, "Test 03 - External mutate: " ..  number_result03)
    print(000, 140, "Test 04 - 3-level nested: " ..   number_result04)
    print(000, 160, "Test 05 - Loop closure 1: " ..   number_result05a)
    print(000, 180, "Test 05 - Loop closure 2: " ..   number_result05b)
    print(000, 200, "Test 05 - Loop closure 3: " ..   number_result05c)
    print(000, 220, "Test 06 - Rec closure: " ..      number_result06)
end

--[[
=== EXPECTED OUTPUT ===
number_result00a: 1.0000
number_result00b: 2.0000
number_result00c: 3.0000
number_result01: 15.0000
number_result02: 2.0000
number_result03: 99.0000
number_result04: 1001.0000
number_result05a: 1.0000
number_result05b: 2.0000
number_result05c: 3.0000
number_result06: 120.0000
--]]
