--#title "[v32lua] string.match() / string.gmatch() unit test"
--@ Vircon32 Lua string.match() / string.gmatch() Unit Test
--@ STILL NOT IMPLEMENTED -- deliberately, unlike everything else in this
--@ patch. Both depend on a real Lua pattern-matching engine (character
--@ classes like %a/%d/%s, quantifiers */+/-/?, anchors ^/$, captures,
--@ balanced-match %b, frontier %f). string.find and string.gsub were
--@ implementable this pass as PLAIN substring operations because Lua
--@ allows that as a degenerate case of pattern matching; match/gmatch
--@ don't have an equivalent plain-substring fallback that's still useful,
--@ so there's no partial version worth shipping here.
--@
--@ Until a pattern engine exists, calling string.match(...) or
--@ string.gmatch(...) will hit the "Unknown string method" hard
--@ compiler_error added in this patch (see AUDIT section 2 and the
--@ try_emit_call_intrinsic patch) -- a clean BUILD FAILURE, not a runtime
--@ hang or silent corruption. That's the intended, safe behavior for an
--@ unimplemented method now that the dispatch-chain guard is in place;
--@ this file is kept as a placeholder so it's easy to swap in real test
--@ cases (see below) the moment a pattern engine lands, without having to
--@ re-derive expected semantics from scratch.

function test_string_match()
    -- Once implemented, this block should look like:
    --
    -- string_result1 = string.match("Hello World", "%a+")    -- "Hello"
    -- __rawasm__("__debug1:")
    -- string_result2 = string.match("abc123", "%d+")         -- "123"
    -- __rawasm__("__debug2:")
    -- string_result3 = string.match("Hello", "^Hello$")      -- "Hello"
    -- __rawasm__("__debug3:")
    -- string_result4 = string.match("Hello", "^xyz$")        -- nil
    -- __rawasm__("__debug4:")
    --
    -- string.gmatch's iterator-return form deserves its own test once
    -- it's closer to real -- it depends on how `for ... in` integrates
    -- with a closure-returning builtin, a separate design question from
    -- the pattern engine itself.
end

function main()
    ioports.gpu.clear("black")
    test_string_match()
    print(100, 00, "--- string.match/gmatch: not yet implemented ---")
    print(100, 20, "See AUDIT_string_functionality.md section 2.")
end

--[[
=== EXPECTED OUTPUT ===
(no globals set yet -- this file is a placeholder until a pattern engine
exists; see the commented-out block above for the intended test cases)
]]
