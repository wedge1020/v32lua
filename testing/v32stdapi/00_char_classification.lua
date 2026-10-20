--#title "v32lua character classification unit test"
--@ Vircon32 Lua ctype unit test -- lib/string.lua half 1 of 3
--@ Exercises the per-character-CODE classification predicates ported
--@ from the Vircon32 C standard library's string.h: isdigit, isxdigit,
--@ isalpha, isascii and isalphanum. Like the C originals these take an
--@ integer character CODE (as from string.byte), not a 1-char string;
--@ every boundary below is probed from both sides (last accepted and
--@ first rejected code) so off-by-one range errors cannot hide.
--@ Windows-1252 territory (codes 128-255) is deliberately left to the
--@ islower/isupper/isalphanum edges covered by 01_char_case.lua.

--#include "../../lib/string.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: isdigit -- ASCII '0' (48) through '9' (57) ===
    boolean_isdigit_zero  = isdigit(48)   -- '0': first accepted
    boolean_isdigit_nine  = isdigit(57)   -- '9': last accepted
    boolean_isdigit_five  = isdigit(53)   -- '5': mid-range
    boolean_isdigit_slash = isdigit(47)   -- '/': one below '0'
    boolean_isdigit_colon = isdigit(58)   -- ':': one past '9'
    boolean_isdigit_alpha = isdigit(97)   -- 'a': letter, not a digit

    -- === Test 2: isxdigit -- 0-9, a-f, A-F, nothing else ===
    boolean_isxdigit_zero    = isxdigit(48)   -- '0'
    boolean_isxdigit_nine    = isxdigit(57)   -- '9'
    boolean_isxdigit_a       = isxdigit(97)   -- 'a'
    boolean_isxdigit_f       = isxdigit(102)  -- 'f': last lowercase accepted
    boolean_isxdigit_upper_a = isxdigit(65)   -- 'A'
    boolean_isxdigit_upper_f = isxdigit(70)   -- 'F': last uppercase accepted
    boolean_isxdigit_g       = isxdigit(103)  -- 'g': one past 'f'
    boolean_isxdigit_upper_g = isxdigit(71)   -- 'G': one past 'F'
    boolean_isxdigit_colon   = isxdigit(58)   -- ':': between '9' and 'A'
    boolean_isxdigit_backtick = isxdigit(96)  -- '`': between 'F' and 'a'

    -- === Test 3: isalpha -- a-z, A-Z ===
    boolean_isalpha_a        = isalpha(97)   -- 'a': first lowercase
    boolean_isalpha_z        = isalpha(122)  -- 'z': last lowercase
    boolean_isalpha_upper_a  = isalpha(65)   -- 'A': first uppercase
    boolean_isalpha_upper_z  = isalpha(90)   -- 'Z': last uppercase
    boolean_isalpha_backtick = isalpha(96)   -- '`': one below 'a'
    boolean_isalpha_lbrace   = isalpha(123)  -- '{': one past 'z'
    boolean_isalpha_at       = isalpha(64)   -- '@': one below 'A'
    boolean_isalpha_lbracket = isalpha(91)   -- '[': one past 'Z'
    boolean_isalpha_digit    = isalpha(53)   -- '5': digit, not alpha

    -- === Test 4: isascii -- 0 through 127 ===
    boolean_isascii_min      = isascii(0)    -- lowest accepted
    boolean_isascii_max      = isascii(127)  -- DEL: last accepted
    boolean_isascii_128      = isascii(128)  -- first rejected
    boolean_isascii_255      = isascii(255)  -- top of Windows-1252
    boolean_isascii_negative = isascii(-1)   -- negative code rejected

    -- === Test 5: isalphanum -- digits plus letters ===
    boolean_isalphanum_digit     = isalphanum(53)  -- '5'
    boolean_isalphanum_lower     = isalphanum(97)  -- 'a'
    boolean_isalphanum_upper     = isalphanum(65)  -- 'A'
    boolean_isalphanum_space     = isalphanum(32)  -- ' ': not alnum
    boolean_isalananum_underscore = isalphanum(95) -- '_': not alnum

    print(10, 0,   "--- char classification unit test ---")
    print(10, 20,  "isdigit boundaries: " .. tostring(boolean_isdigit_zero)
                   .. "/" .. tostring(boolean_isdigit_slash)
                   .. "/" .. tostring(boolean_isdigit_colon))
    print(10, 40,  "isxdigit f/F/g/G: " .. tostring(boolean_isxdigit_f)
                   .. "/" .. tostring(boolean_isxdigit_upper_f)
                   .. "/" .. tostring(boolean_isxdigit_g)
                   .. "/" .. tostring(boolean_isxdigit_upper_g))
    print(10, 60,  "isalpha z/{: " .. tostring(boolean_isalpha_z)
                   .. "/" .. tostring(boolean_isalpha_lbrace))
    print(10, 80,  "isascii 127/128: " .. tostring(boolean_isascii_max)
                   .. "/" .. tostring(boolean_isascii_128))
    print(10, 100, "isalphanum digit/underscore: " .. tostring(boolean_isalphanum_digit)
                   .. "/" .. tostring(boolean_isalananum_underscore))
end

--[[
=== EXPECTED OUTPUT ===

boolean_isdigit_zero: true
boolean_isdigit_nine: true
boolean_isdigit_five: true
boolean_isdigit_slash: false
boolean_isdigit_colon: false
boolean_isdigit_alpha: false
boolean_isxdigit_zero: true
boolean_isxdigit_nine: true
boolean_isxdigit_a: true
boolean_isxdigit_f: true
boolean_isxdigit_upper_a: true
boolean_isxdigit_upper_f: true
boolean_isxdigit_g: false
boolean_isxdigit_upper_g: false
boolean_isxdigit_colon: false
boolean_isxdigit_backtick: false
boolean_isalpha_a: true
boolean_isalpha_z: true
boolean_isalpha_upper_a: true
boolean_isalpha_upper_z: true
boolean_isalpha_backtick: false
boolean_isalpha_lbrace: false
boolean_isalpha_at: false
boolean_isalpha_lbracket: false
boolean_isalpha_digit: false
boolean_isascii_min: true
boolean_isascii_max: true
boolean_isascii_128: false
boolean_isascii_255: false
boolean_isascii_negative: false
boolean_isalphanum_digit: true
boolean_isalphanum_lower: true
boolean_isalphanum_upper: true
boolean_isalphanum_space: false
boolean_isalananum_underscore: false

--]]
