--#title "v32lua generic for loops unit test"
--@ Vircon32 Lua Generic For Loops Unit Test - Comprehensive Coverage
--@ Tests ipairs, pairs, and custom iterators with exhaustive edge cases.
--@ Results are stored in global variables for automated memory scraping.

function test_generic_for_loops()
    -- === Test 00: ipairs on array ===
    local t1 = {"a", "b", "c"}
    local count1 = 0
    for i, v in ipairs(t1) do
        count1 = count1 + 1
        if i == 1 then string_result00 = v end
        if i == 3 then string_result01 = v end
    end
    number_result00 = count1
    __rawasm__("__debug0:")

    -- === Test 01: pairs on hash table ===
    local t2 = {x = 10, y = 20, z = 30}
    local sum2 = 0
    for k, v in pairs(t2) do
        sum2 = sum2 + v
        if k == "y" then number_result01 = v end
    end
    number_result02 = sum2
    __rawasm__("__debug1:")

    -- === Test 02: ipairs with mixed table ===
    local t3 = {"first", "second", key = "value"}
    local array_count = 0
    for i, v in ipairs(t3) do
        array_count = array_count + 1
    end
    number_result03 = array_count
    __rawasm__("__debug2:")

    -- === Test 03: pairs counts all keys ===
    local t4 = {"arr", key1 = "val1", key2 = "val2"}
    local total_keys = 0
    for k, v in pairs(t4) do
        total_keys = total_keys + 1
    end
    number_result04 = total_keys
    __rawasm__("__debug3:")

    -- === Test 04: ipairs on empty table ===
    local t5 = {}
    local empty_ipairs_count = 0
    for i, v in ipairs(t5) do
        empty_ipairs_count = empty_ipairs_count + 1
    end
    number_result05 = empty_ipairs_count
    __rawasm__("__debug4:")

    -- === Test 05: pairs on empty table ===
    local t6 = {}
    local empty_pairs_count = 0
    for k, v in pairs(t6) do
        empty_pairs_count = empty_pairs_count + 1
    end
    number_result06 = empty_pairs_count
    __rawasm__("__debug5:")

    -- === Test 06: ipairs with gaps in array ===
    local t7 = {1, nil, 3, nil, 5}
    local gap_count = 0
    local gap_sum = 0
    for i, v in ipairs(t7) do
        gap_count = gap_count + 1
        gap_sum = gap_sum + (v or 0)
    end
    number_result07 = gap_count
    number_result08 = gap_sum
    __rawasm__("__debug6:")

    -- === Test 07: pairs with numeric keys ===
    local t8 = {1, 2, 3}
    t8[10] = 100
    local numeric_key_count = 0
    local numeric_key_sum = 0
    for k, v in pairs(t8) do
        numeric_key_count = numeric_key_count + 1
        numeric_key_sum = numeric_key_sum + v
    end
    number_result09 = numeric_key_count
    number_result10 = numeric_key_sum
    __rawasm__("__debug7:")

    -- === Test 08: ipairs with non-array table ===
    local t9 = {a = 1, b = 2, c = 3}
    local non_array_count = 0
    for i, v in ipairs(t9) do
        non_array_count = non_array_count + 1
    end
    number_result11 = non_array_count
    __rawasm__("__debug8:")

    -- === Test 09: pairs with nil values ===
    local t10 = {1, nil, 3, nil, 5}
    local nil_val_count = 0
    for k, v in pairs(t10) do
        if v == nil then
            nil_val_count = nil_val_count + 1
        end
    end
    number_result12 = nil_val_count
    __rawasm__("__debug9:")

    -- === Test 10: Break in ipairs loop ===
    local t11 = {1, 2, 3, 4, 5}
    local break_ipairs_val = 0
    for i, v in ipairs(t11) do
        if v == 3 then
            break_ipairs_val = v
            break
        end
    end
    number_result13 = break_ipairs_val
    __rawasm__("__debug10:")

    -- === Test 11: Break in pairs loop ===
    local t12 = {a = 1, b = 2, c = 3}
    local break_pairs_key = ""
    for k, v in pairs(t12) do
        if v == 2 then
            break_pairs_key = k
            break
        end
    end
    string_result02 = break_pairs_key
    __rawasm__("__debug11:")

    -- === Test 12: Nested ipairs loops ===
    local t13 = {{1, 2}, {3, 4}, {5, 6}}
    local nested_ipairs_sum = 0
    for i, sub_t in ipairs(t13) do
        for j, val in ipairs(sub_t) do
            nested_ipairs_sum = nested_ipairs_sum + val
        end
    end
    number_result14 = nested_ipairs_sum
    __rawasm__("__debug12:")

    -- === Test 13: Nested pairs loops ===
    local t14 = {
        {x = 1, y = 2},
        {x = 3, y = 4},
        {x = 5, y = 6}
    }
    local nested_pairs_sum = 0
    for i, sub_t in ipairs(t14) do
        for k, v in pairs(sub_t) do
            nested_pairs_sum = nested_pairs_sum + v
        end
    end
    number_result15 = nested_pairs_sum
    __rawasm__("__debug13:")

    -- === Test 14: Custom iterator - simple ===
    local function simple_iter(t, i)
        i = i + 1
        local v = t[i]
        if v ~= nil then
            return i, v
        end
    end

    local t15 = {10, 20, 30}
    local custom_sum = 0
    for i, v in simple_iter, t15, 0 do
        custom_sum = custom_sum + v
    end
    number_result16 = custom_sum
    __rawasm__("__debug14:")

    -- === Test 15: Custom iterator - reverse ===
    local function reverse_iter(t, i)
        i = i - 1
        local v = t[i]
        if v ~= nil and i >= 1 then
            return i, v
        end
    end

    local t16 = {10, 20, 30, 40}
    local reverse_sum = 0
    for i, v in reverse_iter, t16, #t16 + 1 do
        reverse_sum = reverse_sum + v
    end
    number_result17 = reverse_sum
    __rawasm__("__debug15:")

    -- === Test 16: Modifying a DIFFERENT table during ipairs iteration ===
    local t17 = {1, 2, 3, 4, 5}
    local t17_extra = {}
    local mod_ipairs_count = 0
    for i, v in ipairs(t17) do
        mod_ipairs_count = mod_ipairs_count + 1
        table.insert(t17_extra, 100)  -- mutate a separate table, not the one being iterated
    end
    number_result18 = mod_ipairs_count
    __rawasm__("__debug16:")

    -- === Test 17: Modifying table during pairs iteration (safe pattern) ===
    local t18 = {a = 1, b = 2, c = 3}
    local mod_pairs_count = 0
    local pending = {}  -- collect the mutations, apply them after traversal
    for k, v in pairs(t18) do
        mod_pairs_count = mod_pairs_count + 1
        pending[k .. "_mod"] = v * 10
    end
    for k, v in pairs(pending) do
        t18[k] = v
    end
    number_result19 = mod_pairs_count
    __rawasm__("__debug17:")

    -- === Test 18: ipairs with single element ===
    local t19 = {42}
    local single_ipairs_val = 0
    for i, v in ipairs(t19) do
        single_ipairs_val = v
    end
    number_result20 = single_ipairs_val
    __rawasm__("__debug18:")

    -- === Test 19: pairs with single element ===
    local t20 = {x = 99}
    local single_pairs_val = 0
    for k, v in pairs(t20) do
        single_pairs_val = v
    end
    number_result21 = single_pairs_val
    __rawasm__("__debug19:")

    -- === Test 20: ipairs with string keys (should be ignored) ===
    local t21 = {1, 2, 3, name = "test"}
    local string_key_ipairs_count = 0
    for i, v in ipairs(t21) do
        string_key_ipairs_count = string_key_ipairs_count + 1
    end
    number_result22 = string_key_ipairs_count
    __rawasm__("__debug20:")

    -- === Test 21: pairs with string keys ===
    local t22 = {name = "test", value = 42}
    local string_key_pairs_count = 0
    for k, v in pairs(t22) do
        string_key_pairs_count = string_key_pairs_count + 1
    end
    number_result23 = string_key_pairs_count
    __rawasm__("__debug21:")

    -- === Test 22: Multiple variables in generic for ===
    local t23 = {1, 2, 3}
    local multi_var_sum = 0
    for k, v in pairs(t23) do
        multi_var_sum = multi_var_sum + k + (v or 0)
    end
    number_result24 = multi_var_sum
    __rawasm__("__debug22:")

    -- === Test 23: ipairs with 0 index (should be ignored) ===
    local t24 = {[0] = 0, 1, 2, 3}
    local zero_index_count = 0
    for i, v in ipairs(t24) do
        zero_index_count = zero_index_count + 1
    end
    number_result25 = zero_index_count
    __rawasm__("__debug23:")
end

function main()
    ioports.gpu.clear("black")
    test_generic_for_loops()

    print(000, 00,  "--- Generic For Loops Expanded Test ---")
    print(000, 020, "Test 00 - ipairs count: " ..     number_result00)
    print(000, 040, "Test 00 - ipairs[1]: " ..       string_result00)
    print(000, 060, "Test 00 - ipairs[3]: " ..       string_result01)
    print(000, 080, "Test 01 - pairs sum: " ..       number_result02)
    print(000, 100, "Test 01 - pairs y: " ..         number_result01)
    print(000, 120, "Test 02 - ipairs mixed: " ..    number_result03)
    print(000, 140, "Test 03 - pairs all: " ..       number_result04)
    print(000, 160, "Test 04 - ipairs empty: " ..    number_result05)
    print(000, 180, "Test 05 - pairs empty: " ..     number_result06)
    print(000, 200, "Test 06 - ipairs gaps c: " ..  number_result07)
    print(000, 220, "Test 06 - ipairs gaps s: " ..  number_result08)
    print(000, 240, "Test 07 - pairs num k c: " ..  number_result09)
    print(000, 260, "Test 07 - pairs num k s: " ..  number_result10)
    print(200, 020, "Test 08 - ipairs non-arr: " ..  number_result11)
    print(200, 040, "Test 09 - pairs nil: " ..      number_result12)
    print(200, 060, "Test 10 - ipairs break: " ..   number_result13)
    print(200, 080, "Test 11 - pairs break: " ..    string_result02)
    print(200, 100, "Test 12 - nested ipairs: " ..   number_result14)
    print(200, 120, "Test 13 - nested pairs: " ..   number_result15)
    print(200, 140, "Test 14 - custom iter: " ..    number_result16)
    print(200, 160, "Test 15 - reverse iter: " ..   number_result17)
    print(200, 180, "Test 16 - mod ipairs: " ..    number_result18)
    print(200, 200, "Test 17 - mod pairs: " ..     number_result19)
    print(200, 220, "Test 18 - single ipairs: " ..  number_result20)
    print(200, 240, "Test 19 - single pairs: " ..  number_result21)
    print(200, 260, "Test 20 - str key ipairs: " .. number_result22)
    print(200, 280, "Test 21 - str key pairs: " .. number_result23)
    print(200, 300, "Test 22 - multi var: " ..     number_result24)
    print(200, 320, "Test 23 - zero index: " ..    number_result25)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 3.0000
number_result02: 60.0000
number_result03: 2.0000
number_result04: 3.0000
number_result05: 0.0000
number_result06: 0.0000
number_result07: 1.0000
number_result08: 1.0000
number_result09: 4.0000
number_result10: 106.0000
number_result11: 0.0000
number_result12: 0.0000
number_result13: 3.0000
string_result02: "b"
number_result14: 21.0000
number_result15: 21.0000
number_result16: 60.0000
number_result17: 100.0000
number_result18: 5.0000
number_result19: 3.0000
number_result20: 42.0000
number_result21: 99.0000
number_result22: 3.0000
number_result23: 2.0000
number_result24: 12.0000
number_result25: 3.0000
string_result00: "a"
string_result01: "c"
number_result01: 20.0000

--]]
