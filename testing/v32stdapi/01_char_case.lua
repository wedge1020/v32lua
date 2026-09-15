--#title "v32lua character case/whitespace unit test"
--@ Vircon32 Lua ctype unit test -- lib/string.lua half 2 of 3
--@ Exercises the case/whitespace half of the string.h character
--@ functions: islower, isupper, isspace, tolower and toupper. The
--@ Windows-1252 extensions get special attention here because the C
--@ originals (and this port) accept accented letters: lowercase runs
--@ 224-254 and uppercase 192-222, with 247 (division sign) and 215
--@ (multiplication sign) punched out of the ranges, and 223 (sharp s)
--@ falling in the gap between the two ranges. tolower/toupper must
--@ leave every excluded code untouched, exactly like the C versions.

--#include "../../lib/string.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: islower -- a-z plus Windows-1252 224-254 (not 247) ===
    boolean_islower_a        = islower(97)   -- 'a': first accepted
    boolean_islower_z        = islower(122)  -- 'z': last ascii accepted
    boolean_islower_upper_A  = islower(65)   -- 'A': uppercase, not lower
    boolean_islower_agrave   = islower(224)  -- Windows-1252 a-grave: first extended accepted
    boolean_islower_thorn    = islower(254)  -- thorn: last extended accepted
    boolean_islower_division = islower(247)  -- division sign: punched out of the range
    boolean_islower_yuml     = islower(255)  -- y-diaeresis: one past the range end
    boolean_islower_sz       = islower(223)  -- sharp s: in the gap below 224

    -- === Test 2: isupper -- A-Z plus Windows-1252 192-222 (not 215) ===
    boolean_isupper_upper_a  = isupper(65)   -- 'A': first accepted
    boolean_isupper_upper_z  = isupper(90)   -- 'Z': last ascii accepted
    boolean_isupper_a        = isupper(97)   -- 'a': lowercase, not upper
    boolean_isupper_agrave   = isupper(192)  -- Windows-1252 A-grave: first extended accepted
    boolean_isupper_thorn    = isupper(222)  -- THORN: last extended accepted
    boolean_isupper_multiply = isupper(215)  -- multiplication sign: punched out of the range
    boolean_isupper_sz       = isupper(223)  -- sharp s: one past the range end

    -- === Test 3: isspace -- exactly ' ', '\n', '\r', '\t' ===
    boolean_isspace_space    = isspace(32)   -- ' '
    boolean_isspace_newline  = isspace(10)   -- '\n'
    boolean_isspace_cr       = isspace(13)   -- '\r'
    boolean_isspace_tab      = isspace(9)    -- '\t'
    boolean_isspace_vtab     = isspace(11)   -- '\v': NOT in the C set
    boolean_isspace_nbsp     = isspace(160)  -- Windows-1252 nbsp: not in the set
    boolean_isspace_letter   = isspace(65)   -- 'A': not whitespace

    -- === Test 4: tolower -- +32 on uppers, everything else unchanged ===
    number_tolower_upper_a = tolower(65)    -- 'A' -> 'a' (97)
    number_tolower_upper_z = tolower(90)    -- 'Z' -> 'z' (122)
    number_tolower_agrave  = tolower(192)   -- A-grave -> a-grave (224)
    number_tolower_thorn   = tolower(222)   -- THORN -> thorn (254)
    number_tolower_a       = tolower(97)    -- 'a': already lower, unchanged
    number_tolower_digit   = tolower(53)    -- '5': not a letter, unchanged
    number_tolower_mult    = tolower(215)   -- multiplication sign: excluded, unchanged

    -- === Test 5: toupper -- -32 on lowers, everything else unchanged ===
    number_toupper_a       = toupper(97)    -- 'a' -> 'A' (65)
    number_toupper_z       = toupper(122)   -- 'z' -> 'Z' (90)
    number_toupper_agrave  = toupper(224)   -- a-grave -> A-grave (192)
    number_toupper_thorn   = toupper(254)   -- thorn -> THORN (222)
    number_toupper_upper_a = toupper(65)    -- 'A': already upper, unchanged
    number_toupper_digit   = toupper(53)    -- '5': not a letter, unchanged
    number_toupper_div     = toupper(247)   -- division sign: excluded, unchanged

    print(10, 0,   "--- char case/whitespace unit test ---")
    print(10, 20,  "islower 224/247/254: " .. tostring(boolean_islower_agrave)
                   .. "/" .. tostring(boolean_islower_division)
                   .. "/" .. tostring(boolean_islower_thorn))
    print(10, 40,  "isupper 192/215/222: " .. tostring(boolean_isupper_agrave)
                   .. "/" .. tostring(boolean_isupper_multiply)
                   .. "/" .. tostring(boolean_isupper_thorn))
    print(10, 60,  "isspace sp/nl/cr/tab: " .. tostring(boolean_isspace_space)
                   .. tostring(boolean_isspace_newline)
                   .. tostring(boolean_isspace_cr)
                   .. tostring(boolean_isspace_tab))
    print(10, 80,  "tolower 'A': " .. number_tolower_upper_a)
    print(10, 100, "toupper 'a': " .. number_toupper_a)
end

--[[
=== EXPECTED OUTPUT ===

boolean_islower_a: true
boolean_islower_z: true
boolean_islower_upper_A: false
boolean_islower_agrave: true
boolean_islower_thorn: true
boolean_islower_division: false
boolean_islower_yuml: false
boolean_islower_sz: false
boolean_isupper_upper_a: true
boolean_isupper_upper_z: true
boolean_isupper_a: false
boolean_isupper_agrave: true
boolean_isupper_thorn: true
boolean_isupper_multiply: false
boolean_isupper_sz: false
boolean_isspace_space: true
boolean_isspace_newline: true
boolean_isspace_cr: true
boolean_isspace_tab: true
boolean_isspace_vtab: false
boolean_isspace_nbsp: false
boolean_isspace_letter: false
number_tolower_upper_a: 97.0000
number_tolower_upper_z: 122.0000
number_tolower_agrave: 224.0000
number_tolower_thorn: 254.0000
number_tolower_a: 97.0000
number_tolower_digit: 53.0000
number_tolower_mult: 215.0000
number_toupper_a: 65.0000
number_toupper_z: 90.0000
number_toupper_agrave: 192.0000
number_toupper_thorn: 222.0000
number_toupper_upper_a: 65.0000
number_toupper_digit: 53.0000
number_toupper_div: 247.0000

--]]
