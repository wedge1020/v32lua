--#title "[v32lua] __asm__() / __rawasm__() unit test"
--@ Vircon32 Lua __asm__() / __rawasm__() Unit Test
--@ Both are non-Lua language extensions for embedding raw Vircon32
--@ assembly directly in Lua source. Both support the SAME variable-
--@ interpolation syntax inside the code string: {name} textually
--@ expands to [var_name] -- a direct memory reference to that global
--@ Lua variable's storage slot -- before the text is fed to the
--@ assembler. This works identically for BOTH forms (they share the
--@ same emit_interpolated_asm() substitution step); what differs
--@ between them is unrelated to interpolation:
--@   - __asm__() is the PROTECTED form: it snapshots SP, BP, and every
--@     currently-in-use register before your code runs, then restores
--@     them all afterward -- your inline code can freely clobber
--@     anything without corrupting the surrounding compiler-generated
--@     code around it.
--@   - __rawasm__() is UNPROTECTED: your code runs with no safety net.
--@     If it clobbers a register the surrounding code still needed,
--@     that's on you. (Not exercised as a register-clobbering test
--@     here -- which specific registers are live at any given point is
--@     an internal compiler-allocator detail that can change between
--@     builds, so a test asserting "register N survives/doesn't survive"
--@     would be testing an implementation detail, not a language
--@     guarantee.)
--@
--@ IMPORTANT LIMITATION, confirmed from source (emit_interpolated_asm
--@ hardcodes "[var_%s]" with no fallback path): {name} interpolation
--@ ONLY works for GLOBAL Lua variables. A LOCAL variable referenced via
--@ {name} would try to access a [var_localname] label that was never
--@ emitted anywhere in the compiled output -- a hard assembly-time
--@ "undefined label" failure, not a subtle runtime bug. Not exercised
--@ as a runnable test below for exactly that reason: it wouldn't
--@ produce a wrong-but-buildable result to check against, it would
--@ just fail to assemble.
--@
--@ Interpolation is type-agnostic at the machine level -- {name} just
--@ reads/writes whatever 32-bit boxed value currently sits in that
--@ global's slot, regardless of whether the Lua-level value is a
--@ number, string, or anything else. Test 04 demonstrates this with a
--@ string global.

function test_asm_rawasm()
    -- === Test 00: __rawasm__ -- read a global into a register, modify ===
    -- === it, write back to the SAME global via {name} ===
    asm_var_a = 10
    __rawasm__("MOV R1, {asm_var_a}\nFADD R1, R1\nMOV {asm_var_a}, R1")
    number_result00 = asm_var_a  -- Expected: 20 (10 doubled)
    __rawasm__("__debug0:")

    -- === Test 01: __asm__ (protected form) -- same interpolation syntax, ===
    -- === confirms it works identically through the protected wrapper ===
    asm_var_b = 100
    __asm__("MOV R1, {asm_var_b}\nFMUL R1, 2.0\nMOV {asm_var_b}, R1")
    number_result01 = asm_var_b  -- Expected: 200
    __rawasm__("__debug1:")

    -- === Test 02: Multiple DIFFERENT globals interpolated in one block -- ===
    -- === read two, combine, write to a third ===
    asm_var_c = 5
    asm_var_d = 7
    asm_var_e = 0
    __rawasm__("MOV R1, {asm_var_c}\nMOV R2, {asm_var_d}\nFADD R1, R2\nMOV {asm_var_e}, R1")
    number_result02 = asm_var_e  -- Expected: 12 (5 + 7)
    __rawasm__("__debug2:")

    -- === Test 03: Read the SAME global twice within one block (confirms ===
    -- === repeated {name} occurrences in a single string all interpolate ===
    -- === correctly, not just the first one) ===
    asm_var_f = 4
    __rawasm__("MOV R1, {asm_var_f}\nMOV R2, {asm_var_f}\nFMUL R1, R2\nMOV {asm_var_f}, R1")
    number_result03 = asm_var_f  -- Expected: 16 (4 * 4)
    __rawasm__("__debug3:")

    -- === Test 04: Interpolation is type-agnostic -- works the same for a ===
    -- === STRING global as it does for a number, since {name} just moves ===
    -- === whatever boxed value is in that memory slot, untouched ===
    asm_str_src = "hello"
    asm_str_dst = ""
    __rawasm__("MOV R1, {asm_str_src}\nMOV {asm_str_dst}, R1")
    string_result04 = asm_str_dst  -- Expected: "hello"
    __rawasm__("__debug4:")

    -- === Test 05: A value modified via asm is then used in ordinary Lua ===
    -- === code afterward, confirming the write-back is a real, ordinary ===
    -- === Lua value the rest of the program can use normally ===
    asm_var_g = 3
    __rawasm__("MOV R1, {asm_var_g}\nMOV R2, 100.0\nFADD R1, R2\nMOV {asm_var_g}, R1")
    number_result05 = asm_var_g + 1  -- Expected: 104 (3 + 100, then +1 in plain Lua)
    __rawasm__("__debug5:")
end

function main()
    ioports.gpu.clear("black")
    test_asm_rawasm()

    print(  0,   0, "--- __asm__/__rawasm__ Test ---")
    print(  0,  20, "Test 00 - rawasm double: "     .. number_result00)
    print(  0,  40, "Test 01 - asm double: "        .. number_result01)
    print(  0,  60, "Test 02 - Multi global: "      .. number_result02)
    print(  0,  80, "Test 03 - Repeated {name}: "   .. number_result03)
    print(  0, 100, "Test 04 - String round-trip: " .. string_result04)
    print(  0, 120, "Test 05 - Asm then Lua: "      .. number_result05)
end

--[[
=== EXPECTED OUTPUT ===
number_result00: 20.0000
number_result01: 200.0000
number_result02: 12.0000
number_result03: 16.0000
string_result04: "hello"
number_result05: 104.0000
]]
