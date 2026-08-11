--@ Vircon32 Lua table.move() Unit Test
--@ Tests ONLY the table.move() library function (Lua 5.3+).
--@ Results stored in global variables for automated memory scraping.

function test_table_move()
    -- === Test 1: Move within same table (non-overlapping) ===
    local t1 = {"a", "b", "c", "d", "e"}
    table.move(t1, 1, 3, 4)
    string_result1 = t1[4]  -- Expected: "a" (moved from 1->4)
    string_result2 = t1[5]  -- Expected: "b" (moved from 2->5)
    string_result3 = t1[6]  -- Expected: "c" (moved from 3->6)
    string_result4 = t1[1]  -- Expected: "d" (original at 4 shifted left)

    -- === Test 2: Move with overlap (forward) ===
    local t2 = {"a", "b", "c", "d"}
    table.move(t2, 1, 2, 2)
    string_result5 = t2[2]  -- Expected: "a" (overwrote "b")
    string_result6 = t2[3]  -- Expected: "b" (overwrote "c")

    -- === Test 3: Move between tables ===
    local t3 = {"x", "y", "z"}
    local t4 = {1, 2, 3, 4}
    table.move(t3, 1, 2, 2, t4)
    string_result7 = t4[2]  -- Expected: "x"
    string_result8 = t4[3]  -- Expected: "y"
    number_result1 = t4[4]  -- Expected: 3 (shifted right)

    -- === Test 4: Move to beginning ===
    local t5 = {"a", "b", "c"}
    table.move(t5, 2, 3, 1)
    string_result9 = t5[1]  -- Expected: "b"
    string_result10 = t5[2] -- Expected: "c"
    string_result11 = t5[3] -- Expected: "b" (from original pos 2)
end

function main()
    ioports.gpu.clear("black")
    test_table_move()

    print(100, 00,  "--- table.move() Test ---")
    print(100, 20,  "Test 1 - Dest[4]: " .. string_result1)
    print(100, 40,  "Test 1 - Dest[5]: " .. string_result2)
    print(100, 60,  "Test 1 - Dest[6]: " .. string_result3)
    print(100, 80,  "Test 1 - Src[1]: " .. string_result4)
    print(100, 100, "Test 2 - Overlap[2]: " .. string_result5)
    print(100, 120, "Test 2 - Overlap[3]: " .. string_result6)
    print(100, 140, "Test 3 - Dest[2]: " .. string_result7)
    print(100, 160, "Test 3 - Dest[3]: " .. string_result8)
    print(100, 180, "Test 3 - Shifted: " .. number_result1)
    print(100, 200, "Test 4 - To start[1]: " .. string_result9)
    print(100, 220, "Test 4 - To start[2]: " .. string_result10)
    print(100, 240, "Test 4 - To start[3]: " .. string_result11)
end

--[[
=== EXPECTED OUTPUT ===
Global Variables:
string_result1: "a"
string_result2: "b"
string_result3: "c"
string_result4: "d"
string_result5: "a"
string_result6: "b"
string_result7: "x"
string_result8: "y"
number_result1: 3
string_result9: "b"
string_result10: "c"
string_result11: "b"
]]
