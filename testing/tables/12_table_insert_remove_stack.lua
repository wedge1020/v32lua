--@ Vircon32 Lua table.insert()/table.remove() Stack Integration Unit Test
--@ Tests that repeated, interleaved table.insert() and table.remove()
--@ calls keep the array length and contents correct over many operations
--@ -- not just a single isolated call, but a whole push/pop sequence used
--@ as a stack.
--@ Results stored in global variables for automated memory scraping.

function test_table_insert_remove_stack()
    -- === Test 1: Push several values, then pop them all back off in order ===
    local stack1 = {}
    table.insert(stack1, "a")
    table.insert(stack1, "b")
    table.insert(stack1, "c")
    number_result1 = #stack1  -- Expected: 3

    local popped1 = table.remove(stack1)
    local popped2 = table.remove(stack1)
    local popped3 = table.remove(stack1)
    string_result1 = popped1  -- Expected: "c" (LIFO)
    string_result2 = popped2  -- Expected: "b"
    string_result3 = popped3  -- Expected: "a"
    number_result2 = #stack1  -- Expected: 0
    __rawasm__("__debug1:")

    -- === Test 2: Interleaved push/pop (not a clean push-all-then-pop-all) ===
    local stack2 = {}
    table.insert(stack2, 1)
    table.insert(stack2, 2)
    table.remove(stack2)         -- removes 2
    table.insert(stack2, 3)
    table.insert(stack2, 4)
    table.remove(stack2)         -- removes 4
    number_result3 = #stack2     -- Expected: 2
    number_result4 = stack2[1]   -- Expected: 1
    number_result5 = stack2[2]   -- Expected: 3
    __rawasm__("__debug2:")

    -- === Test 3: Push, fully drain, then push again (table reuse after empty) ===
    local stack3 = {}
    table.insert(stack3, "first")
    table.remove(stack3)
    number_result6 = #stack3  -- Expected: 0
    table.insert(stack3, "second")
    string_result4 = stack3[1]  -- Expected: "second"
    number_result7 = #stack3    -- Expected: 1
    __rawasm__("__debug3:")

    -- === Test 4: table.insert at a specific position, then table.remove
    --             from a different position, several times in a row ===
    local stack4 = {"a", "b", "c", "d"}
    table.insert(stack4, 1, "x")       -- {"x","a","b","c","d"}
    table.remove(stack4, 3)            -- removes "b" -> {"x","a","c","d"}
    table.insert(stack4, "y")          -- {"x","a","c","d","y"}
    number_result8 = #stack4           -- Expected: 5
    string_result5 = stack4[1]         -- Expected: "x"
    string_result6 = stack4[3]         -- Expected: "c"
    string_result7 = stack4[5]         -- Expected: "y"
    __rawasm__("__debug4:")

    -- === Test 5: A longer sequence of pushes and pops, checking the
    --             running length stays correct at every step ===
    local stack5 = {}
    local length_ok = true
    for i = 1, 10 do
        table.insert(stack5, i)
        if #stack5 ~= i then length_ok = false end
    end
    for i = 1, 5 do
        table.remove(stack5)
    end
    if #stack5 ~= 5 then length_ok = false end
    boolean_result1 = length_ok  -- Expected: true
    number_result9 = stack5[5]   -- Expected: 5 (top of what remains)
    __rawasm__("__debug5:")
end

function main()
    ioports.gpu.clear("black")
    test_table_insert_remove_stack()

    print(100, 00,  "--- table.insert/remove Stack Test ---")
    print(100, 20,  "Test 1 - Pushed len: " .. number_result1)
    print(100, 40,  "Test 1 - Pop 1: " .. string_result1)
    print(100, 60,  "Test 1 - Pop 2: " .. string_result2)
    print(100, 80,  "Test 1 - Pop 3: " .. string_result3)
    print(100, 100, "Test 1 - Drained len: " .. number_result2)
    print(100, 120, "Test 2 - Interleaved len: " .. number_result3)
    print(100, 140, "Test 2 - stack2[1]: " .. number_result4)
    print(100, 160, "Test 2 - stack2[2]: " .. number_result5)
    print(100, 180, "Test 3 - Drained again: " .. number_result6)
    print(100, 200, "Test 3 - Reused val: " .. string_result4)
    print(100, 220, "Test 3 - Reused len: " .. number_result7)
    print(100, 240, "Test 4 - Mixed pos len: " .. number_result8)
    print(100, 260, "Test 4 - stack4[1]: " .. string_result5)
    print(100, 280, "Test 4 - stack4[3]: " .. string_result6)
    print(100, 300, "Test 4 - stack4[5]: " .. string_result7)
    print(100, 320, "Test 5 - Length tracked ok: " .. tostring(boolean_result1))
    print(100, 340, "Test 5 - Remaining top: " .. number_result9)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 3.0000
string_result1: "c"
string_result2: "b"
string_result3: "a"
number_result2: 0.0000
number_result3: 2.0000
number_result4: 1.0000
number_result5: 3.0000
number_result6: 0.0000
string_result4: "second"
number_result7: 1.0000
number_result8: 5.0000
string_result5: "x"
string_result6: "c"
string_result7: "y"
boolean_result1: true
number_result9: 5.0000
]]
