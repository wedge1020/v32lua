--@ Vircon32 Lua Loop Test Suite - Part 00
--@ Tests while loops and numeric for loops

-- Global helper to format test results
function format_result(label, value)
    return label .. ": " .. tostring(value)
end

-- --- TEST 1: While Loops ---
function test_while_loops()
    print(10, 10, "--- TEST 1: While Loops ---")

    -- Basic while with counter
    local count = 0
    local sum = 0
    while count < 5 do
        sum = sum + count
        count = count + 1
    end
    print(10, 30, format_result("while sum 0-4", sum))

    -- While with break
    local i = 0
    local result = ""
    while true do
        result = result .. string.char(65 + i)
        i = i + 1
        if i >= 3 then break end
    end
    print(10, 50, format_result("while+break", result))

    -- While with condition
    local x = 10
    local iterations = 0
    while x > 0 do
        x = x - 3
        iterations = iterations + 1
    end
    print(10, 70, format_result("while condition", iterations))

    return 0
end

-- --- TEST 2: Numeric For Loops ---
function test_numeric_for()
    print(320, 10, "--- TEST 2: Numeric For ---")

    -- Simple for i = 1, 5
    local sum = 0
    for i = 1, 5 do
        sum = sum + i
    end
    print(320, 30, format_result("for 1,5 sum", sum))

    -- For with step
    local result = ""
    for i = 65, 68, 2 do
        result = result .. string.char(i)
    end
    print(320, 50, format_result("for step 2", result))

    -- For with negative step
    local countdown = ""
    for i = 3, 1, -1 do
        countdown = countdown .. tostring(i)
    end
    print(320, 70, format_result("for negative step", countdown))

    -- For with float step
    local float_result = 0
    for i = 1, 5, 0.5 do
        float_result = float_result + 1
    end
    print(320, 90, format_result("for float step", float_result))

    -- Nested for loops
    local nested = 0
    for i = 1, 3 do
        for j = 1, 2 do
            nested = nested + (i * j)
        end
    end
    print(320, 110, format_result("nested for", nested))

    return 0
end

-- --- TEST 3: While with Complex Conditions ---
function test_complex_while()
    print(10, 130, "--- TEST 3: Complex While ---")

    -- While with multiple variables
    local a, b = 1, 10
    local steps = 0
    while a < b do
        a = a * 2
        b = b - 1
        steps = steps + 1
    end
    print(10, 150, format_result("while a<b", steps))

    -- While with string building
    local s = ""
    local c = 65
    while #s < 5 do
        s = s .. string.char(c)
        c = c + 1
    end
    print(10, 170, format_result("while build string", s))

    return 0
end

-- --- TEST 4: For Loop Edge Cases ---
function test_for_edge_cases()
    print(320, 170, "--- TEST 4: For Edge Cases ---")

    -- For with step > limit (should not run)
    local no_run = 0
    for i = 1, 5, 10 do
        no_run = no_run + 1
    end
    print(320, 190, format_result("for step>limit", no_run))

    -- For with negative limit
    for i = -2, 2 do
        print(320, 210, format_result("for negative start", i))
    end

    -- For with all parameters
    local all_params = 0
    for i = 2, 8, 2 do
        all_params = all_params + i
    end
    print(320, 230, format_result("for all params", all_params))

    return 0
end

-- --- PROGRAM ENTRY POINT ---
function main()
    ioports.gpu.clear("black")

    test_while_loops()
    test_numeric_for()
    test_complex_while()
    test_for_edge_cases()

    print(10, 290, "--- PART 00 COMPLETE ---")
end
