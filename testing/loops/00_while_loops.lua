--#title "v32lua while loops unit test"
--@ Vircon32 Lua While Loops Unit Test - Comprehensive Coverage
--@ Tests all while loop scenarios including edge cases and interactions.
--@ Results are stored in global variables for automated memory scraping.

function test_while_loops()
    -- === Test 00: Basic while loop (count up) ===
    local i = 1
    local sum = 0
    while i <= 5 do
        sum = sum + i
        i = i + 1
    end
    number_result00 = sum
	__rawasm__("__debug0:")

    -- === Test 01: While loop with break ===
    local j = 1
    while true do
        if j >= 3 then
            break
        end
        j = j + 1
    end
    number_result01 = j
	__rawasm__("__debug1:")

    -- === Test 02: While loop countdown ===
    local k = 10
    local iterations = 0
    while k > 0 do
        iterations = iterations + 1
        k = k - 2
    end
    number_result02 = iterations
	__rawasm__("__debug2:")

    -- === Test 03: Nested while loops ===
    local outer = 1
    local inner_sum = 0
    while outer <= 3 do
        local inner = 1
        while inner <= 2 do
            inner_sum = inner_sum + 1
            inner = inner + 1
        end
        outer = outer + 1
    end
    number_result03 = inner_sum
	__rawasm__("__debug3:")

    -- === Test 04: While with complex condition (AND) ===
    local a, b = 5, 10
    local complex_count = 0
    while a < 10 and b > 5 do
        complex_count = complex_count + 1
        a = a + 1
        b = b - 1
    end
    number_result04 = complex_count
	__rawasm__("__debug4:")

    -- === Test 05: While with complex condition (OR) ===
    local x, y = 0, 10
    local or_count = 0
    while x == 0 or y > 0 do
        or_count = or_count + 1
        x = x + 1
        y = y - 1
        if or_count >= 5 then break end
    end
    number_result05 = or_count
	__rawasm__("__debug5:")

    -- === Test 06: While with function call in condition ===
    local counter = 0
    local function get_value()
        counter = counter + 1
        return counter
    end
    local func_count = 0
    while get_value() <= 3 do
        func_count = func_count + 1
    end
    number_result06 = func_count
	__rawasm__("__debug6:")

    -- === Test 07: While with side effects in condition ===
    local side_effect = 0
    local val = 0
    while (function() val = val + 1; return val end)() <= 5 do
        side_effect = side_effect + 1
    end
    number_result07 = side_effect
	__rawasm__("__debug7:")

    -- === Test 08: While true (infinite) with break ===
    local infinite_counter = 0
    while true do
        infinite_counter = infinite_counter + 1
        if infinite_counter >= 10 then
            break
        end
    end
    number_result08 = infinite_counter
	__rawasm__("__debug8:")

    -- === Test 09: Empty while loop body ===
    local empty_var = 5
    while empty_var > 0 do
        empty_var = empty_var - 1
    end
    number_result09 = empty_var
	__rawasm__("__debug9:")

    -- === Test 10: While with no body (just condition) ===
    local no_body = 3
    while no_body > 0 do
        no_body = no_body - 1
    end
    number_result10 = no_body
	__rawasm__("__debug10:")

    -- === Test 11: Multiple breaks in different branches ===
    local multi_break = 1
    while multi_break <= 10 do
        if multi_break == 3 then
            break
        elseif multi_break == 5 then
            break
        end
        multi_break = multi_break + 1
    end
    number_result11 = multi_break
	__rawasm__("__debug11:")

    -- === Test 12: Break in nested while loops (inner) ===
    local outer2 = 1
    local inner_break = 0
    while outer2 <= 5 do
        local inner2 = 1
        while inner2 <= 5 do
            inner_break = outer2 * 10 + inner2
            if inner2 == 3 then
                break
            end
            inner2 = inner2 + 1
        end
        outer2 = outer2 + 1
    end
    number_result12 = inner_break
	__rawasm__("__debug12:")

    -- === Test 13: Break in nested while loops (outer) ===
    local outer3 = 1
    local outer_break_val = 0
    while outer3 <= 5 do
        local inner3 = 1
        while inner3 <= 5 do
            if outer3 == 2 and inner3 == 2 then
                outer_break_val = outer3 * 100 + inner3
                break
            end
            inner3 = inner3 + 1
        end
        if outer3 == 2 then
            break
        end
        outer3 = outer3 + 1
    end
    number_result13 = outer_break_val
	__rawasm__("__debug13:")

    -- === Test 14: While with comparison operators ===
    local comp = 1
    local comp_count = 0
    while comp ~= 10 do
        comp_count = comp_count + 1
        comp = comp + 1
    end
    number_result14 = comp_count
	__rawasm__("__debug14:")

    -- === Test 15: While with less than or equal ===
    local le = 1
    local le_count = 0
    while le <= 5 do
        le_count = le_count + 1
        le = le + 1
    end
    number_result15 = le_count
	__rawasm__("__debug15:")

    -- === Test 16: While with greater than or equal ===
    local ge = 10
    local ge_count = 0
    while ge >= 5 do
        ge_count = ge_count + 1
        ge = ge - 1
    end
    number_result16 = ge_count
	__rawasm__("__debug16:")

    -- === Test 17: While with string length condition ===
    local str = ""
    local str_count = 0
    while #str < 5 do
        str_count = str_count + 1
        str = str .. "x"
    end
    number_result17 = str_count
	__rawasm__("__debug17:")

    -- === Test 18: While with boolean flag ===
    local flag = true
    local flag_count = 0
    while flag do
        flag_count = flag_count + 1
        if flag_count >= 3 then
            flag = false
        end
    end
    number_result18 = flag_count
	__rawasm__("__debug18:")

    -- === Test 19: While with nil check ===
    local nil_val = {1, 2, 3}
    local nil_count = 0
    while nil_val[1] ~= nil do
        nil_count = nil_count + 1
        table.remove(nil_val, 1)
    end
    number_result19 = nil_count
	__rawasm__("__debug19:")

    -- === Test 20: While with arithmetic in condition ===
    local arith = 1
    local arith_count = 0
    while arith * arith <= 25 do
        arith_count = arith_count + 1
        arith = arith + 1
    end
    number_result20 = arith_count
	__rawasm__("__debug20:")

    -- === Test 21: While with modulo condition ===
    local mod = 0
    local mod_count = 0
    while mod % 3 ~= 0 or mod == 0 do
        mod_count = mod_count + 1
        mod = mod + 1
        if mod >= 10 then break end
    end
    number_result21 = mod_count
	__rawasm__("__debug21:")

    -- === Test 22: While with table iteration pattern ===
    local tbl = {1, 2, 3, 4, 5}
    local idx = 1
    local tbl_sum = 0
    while tbl[idx] ~= nil do
        tbl_sum = tbl_sum + tbl[idx]
        idx = idx + 1
    end
    number_result22 = tbl_sum
	__rawasm__("__debug22:")

    -- === Test 23: While with variable modification in condition ===
    local mod_cond = 1
    local mod_cond_count = 0
    while mod_cond <= 5 do
        mod_cond_count = mod_cond_count + mod_cond
        mod_cond = mod_cond + 1
    end
    number_result23 = mod_cond_count
	__rawasm__("__debug23:")

    -- === Test 24: Condition false on the VERY FIRST check -- body ===
    -- === must never execute ===
    local never_ran = 0
    local zero_start = 100
    while zero_start < 0 do
        never_ran = never_ran + 1
    end
    number_result24 = never_ran   -- 0
	__rawasm__("__debug24:")

    -- === Test 25: break as the VERY FIRST statement in the loop body ===
    local immediate_break_count = 0
    while true do
        break
    end
    number_result25 = immediate_break_count   -- 0
	__rawasm__("__debug25:")

    -- === Test 26: Three-level-deep nested while loops ===
    local level1 = 1
    local triple_count = 0
    while level1 <= 2 do
        local level2 = 1
        while level2 <= 2 do
            local level3 = 1
            while level3 <= 2 do
                triple_count = triple_count + 1
                level3 = level3 + 1
            end
            level2 = level2 + 1
        end
        level1 = level1 + 1
    end
    number_result26 = triple_count   -- 2*2*2 = 8
	__rawasm__("__debug26:")
end

function main()
    ioports.gpu.clear("black")
    test_while_loops()

    print(  0,   0, "--- While Loops Expanded Test ---")
    print(  0,  20, "Test 00 - Count up sum: " ..    number_result00)
    print(  0,  40, "Test 01 - Break at 3: " ..      number_result01)
    print(  0,  60, "Test 02 - Countdown iter: " ..   number_result02)
    print(  0,  80, "Test 03 - Nested sum: " ..     number_result03)
    print(  0, 100, "Test 04 - AND cond: " ..        number_result04)
    print(  0, 120, "Test 05 - OR cond: " ..         number_result05)
    print(  0, 140, "Test 06 - Func call: " ..       number_result06)
    print(  0, 160, "Test 07 - Side effect: " ..      number_result07)
    print(  0, 180, "Test 08 - While true: " ..      number_result08)
    print(  0, 200, "Test 09 - Empty body: " ..      number_result09)
    print(  0, 220, "Test 10 - No body: " ..        number_result10)
    print(  0, 240, "Test 11 - Multi break: " ..     number_result11)
    print(  0, 260, "Test 12 - Inner break: " ..     number_result12)
    print(320,  20, "Test 13 - Outer break: " ..     number_result13)
    print(320,  40, "Test 14 - Not equal: " ..      number_result14)
    print(320,  60, "Test 15 - Less/equal: " ..     number_result15)
    print(320,  80, "Test 16 - Greater/equal: " ..   number_result16)
    print(320, 100, "Test 17 - Str length: " ..      number_result17)
    print(320, 120, "Test 18 - Bool flag: " ..      number_result18)
    print(320, 140, "Test 19 - Nil check: " ..      number_result19)
    print(320, 160, "Test 20 - Arithmetic: " ..      number_result20)
    print(320, 180, "Test 21 - Modulo: " ..         number_result21)
    print(320, 200, "Test 22 - Table iter: " ..      number_result22)
    print(320, 220, "Test 23 - Mod in cond: " ..     number_result23)
    print(320, 240, "Test 24 - Zero iterations: " .. number_result24)
    print(320, 260, "Test 25 - Immediate break: " .. number_result25)
    print(320, 280, "Test 26 - Triple nested: " ..   number_result26)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 15.0000
number_result01: 3.0000
number_result02: 5.0000
number_result03: 6.0000
number_result04: 5.0000
number_result05: 5.0000
number_result06: 3.0000
number_result07: 5.0000
number_result08: 10.0000
number_result09: 0.0000
number_result10: 0.0000
number_result11: 3.0000
number_result12: 53.0000
number_result13: 202.0000
number_result14: 9.0000
number_result15: 5.0000
number_result16: 6.0000
number_result17: 5.0000
number_result18: 3.0000
number_result19: 3.0000
number_result20: 5.0000
number_result21: 3.0000
number_result22: 15.0000
number_result23: 15.0000
number_result24: 0.0000
number_result25: 0.0000
number_result26: 8.0000

--]]
