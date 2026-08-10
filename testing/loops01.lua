--@ Vircon32 Lua Loop Test Suite - Part 01
--@ Tests generic for loops with pairs() and ipairs()

-- Global helper to format test results
function format_result(label, value)
    return label .. ": " .. tostring(value)
end

-- --- TEST 5: ipairs() with Arrays ---
function test_ipairs_arrays()
    print(10, 10, "--- TEST 5: ipairs() Arrays ---")

    -- Simple array iteration
    local arr = {"A", "B", "C", "D"}
    local result = ""
    for i, v in ipairs(arr) do
        result = result .. v
    end
    print(10, 30, format_result("ipairs simple", result))

    -- Array with gaps (ipairs stops at first nil)
    local sparse = {10, 20, nil, 40}
    local count = 0
    for i, v in ipairs(sparse) do
        count = count + 1
    end
    print(10, 50, format_result("ipairs stops at nil", count))

    -- Numeric array
    local nums = {1, 2, 3, 4, 5}
    local sum = 0
    for i, v in ipairs(nums) do
        sum = sum + v
    end
    print(10, 70, format_result("ipairs sum", sum))

    -- Empty array
    local empty = {}
    local empty_count = 0
    for i, v in ipairs(empty) do
        empty_count = empty_count + 1
    end
    print(10, 90, format_result("ipairs empty", empty_count))

    return 0
end

-- --- TEST 6: pairs() with Tables ---
function test_pairs_tables()
    print(320, 10, "--- TEST 6: pairs() Tables ---")

    -- Table with string keys
    local t = {name = "Hero", class = "Warrior", level = 10}
    local keys = ""
    for k, v in pairs(t) do
        keys = keys .. k .. "="
    end
    print(320, 30, format_result("pairs string keys", keys))

    -- Mixed table (array + hash)
    local mixed = {"A", "B", name = "Test", value = 42}
    local mixed_count = 0
    for k, v in pairs(mixed) do
        mixed_count = mixed_count + 1
    end
    print(320, 50, format_result("pairs mixed count", mixed_count))

    -- Table with numeric and string keys
    local combined = {10, 20, ["key1"] = "val1", ["key2"] = "val2"}
    local combined_result = ""
    for k, v in pairs(combined) do
        combined_result = combined_result .. tostring(k) .. ":" .. tostring(v) .. ";"
    end
    print(320, 70, format_result("pairs combined", combined_result))

    return 0
end

-- --- TEST 7: ipairs() vs pairs() Comparison ---
function test_ipairs_vs_pairs()
    print(10, 130, "--- TEST 7: ipairs vs pairs ---")

    -- Table with both array and hash parts
    local t = {"X", "Y", "Z", name = "Test", value = 99}

    -- ipairs only gets array part
    local ipairs_count = 0
    for i, v in ipairs(t) do
        ipairs_count = ipairs_count + 1
    end
    print(10, 150, format_result("ipairs count", ipairs_count))

    -- pairs gets everything
    local pairs_count = 0
    for k, v in pairs(t) do
        pairs_count = pairs_count + 1
    end
    print(10, 170, format_result("pairs count", pairs_count))

    return 0
end

-- --- TEST 8: Generic For with Multiple Variables ---
function test_multi_var_for()
    print(320, 130, "--- TEST 8: Multi-Var For ---")

    -- Two variables from pairs
    local t = {a = 1, b = 2, c = 3}
    local first_key = nil
    local first_val = nil
    for k, v in pairs(t) do
        if first_key == nil then
            first_key = k
            first_val = v
        end
    end
    print(320, 150, format_result("first pair", first_key .. "=" .. first_val))

    -- Three variables (pairs returns 2, third is nil)
    for k, v, w in pairs(t) do
        if k == "a" then
            print(320, 170, format_result("three vars", k .. "," .. tostring(v) .. "," .. tostring(w)))
        end
    end

    return 0
end

-- --- PROGRAM ENTRY POINT ---
function main()
    ioports.gpu.clear("black")

    test_ipairs_arrays()
    test_pairs_tables()
    test_ipairs_vs_pairs()
    test_multi_var_for()

    print(10, 290, "--- PART 01 COMPLETE ---")
end
