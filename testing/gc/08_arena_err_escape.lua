--@ --gc arena --gc-check: storing a value made inside an arena into a global
--@ that outlives it panics at the store (__arena_err_escape).
--@ Results are not scraped: the test passes when the cart reaches the label below
--@ (run with --expect-reach by tools/headless/unittest.py; run_tests.sh skips it).
--#gc arena
--#gc-check

function main()
    local m = arena.mark()
    g = {1, 2}
    arena.release(m)
    system.wait()
end

--[[
=== EXPECTED TRAP ===
label: __arena_err_escape
]]
