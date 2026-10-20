--#title "v32lua strlen/strcmp/strncmp unit test"
--@ Vircon32 Lua string handling unit test -- lib/string.lua half 3 of 3
--@ Exercises the string.h routines that survived the port as genuine
--@ algorithms: strlen, and the index-for-index strcmp/strncmp ports,
--@ which (unlike C, which only guarantees the SIGN of the result)
--@ return the exact byte difference at the first mismatch -- the
--@ documented behavior of these translations, so the exact values
--@ are asserted here. strncmp's quirky-but-faithful control flow is
--@ probed at its edges: the pre-comparison limit check (which makes
--@ strncmp(a, b, 1) compare zero characters but still report the
--@ FIRST byte pair in its result), the maxCharacters < 1 early exit,
--@ and running off the end of the shorter operand (the port treats
--@ index-past-length as the C versions' implicit null terminator).
--@ strcpy/strncpy/strcat/strncat are NOT covered: they are deliberate
--@ NOT IMPLEMENTED stubs (no destination buffer exists to mutate in
--@ v32lua's string model) and are excluded from this suite by design.

--#include "../../lib/string.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: strlen ===
    number_strlen_hello    = strlen("hello")       -- plain word
    number_strlen_empty    = strlen("")            -- empty string
    number_strlen_sentence = strlen("Vircon32 Lua") -- includes the space: 12 chars

    -- === Test 2: strcmp -- exact byte difference at first mismatch ===
    number_strcmp_equal   = strcmp("abc", "abc")  -- identical: 0
    number_strcmp_less    = strcmp("abc", "abd")  -- 'c'-'d' = -1
    number_strcmp_prefix  = strcmp("ab", "abc")   -- implicit null vs 'c': 0-99 = -99
    number_strcmp_longer  = strcmp("abc", "ab")   -- 'c' vs implicit null: 99-0 = 99
    number_strcmp_case    = strcmp("Z", "a")      -- 90-97 = -7 (uppercase sorts first)
    number_strcmp_empty   = strcmp("", "a")       -- 0-97 = -97
    number_strcmp_empty2  = strcmp("", "")        -- both empty: 0

    -- === Test 3: strncmp -- same comparison, bounded ===
    number_strncmp_eq3     = strncmp("abcde", "abcXe", 3)  -- first 3 equal: 0
    number_strncmp_diff4   = strncmp("abcde", "abcXe", 4)  -- loop stops at the limit, tail still reports 'd'-'X' = 12
    number_strncmp_limit2  = strncmp("abc", "abd", 2)      -- 'c' vs 'd' is beyond the limit: 0
    number_strncmp_limit1  = strncmp("a", "b", 1)          -- loop compares nothing, tail reports 'a'-'b' = -1
    number_strncmp_zero    = strncmp("abc", "xyz", 0)      -- maxCharacters < 1 early exit: 0
    number_strncmp_neg     = strncmp("abc", "xyz", -1)     -- negative limit, same early exit: 0
    number_strncmp_pastlen = strncmp("ab", "abzzzz", 10)   -- shorter operand ends first: 0-'z' = -122

    print(10, 0,   "--- strlen/strcmp/strncmp unit test ---")
    print(10, 20,  "strlen hello/empty/sentence: " .. number_strlen_hello
                   .. "/" .. number_strlen_empty
                   .. "/" .. number_strlen_sentence)
    print(10, 40,  "strcmp equal/less/longer: " .. number_strcmp_equal
                   .. "/" .. number_strcmp_less
                   .. "/" .. number_strcmp_longer)
    print(10, 60,  "strncmp eq3/diff4: " .. number_strncmp_eq3
                   .. "/" .. number_strncmp_diff4)
    print(10, 80,  "strncmp limit1/zero/neg: " .. number_strncmp_limit1
                   .. "/" .. number_strncmp_zero
                   .. "/" .. number_strncmp_neg)
end

--[[
=== EXPECTED OUTPUT ===

number_strlen_hello: 5.0000
number_strlen_empty: 0.0000
number_strlen_sentence: 12.0000
number_strcmp_equal: 0.0000
number_strcmp_less: -1.0000
number_strcmp_prefix: -99.0000
number_strcmp_longer: 99.0000
number_strcmp_case: -7.0000
number_strcmp_empty: -97.0000
number_strcmp_empty2: 0.0000
number_strncmp_eq3: 0.0000
number_strncmp_diff4: 12.0000
number_strncmp_limit2: 0.0000
number_strncmp_limit1: -1.0000
number_strncmp_zero: 0.0000
number_strncmp_neg: 0.0000
number_strncmp_pastlen: -122.0000

--]]
