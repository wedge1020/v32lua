--@ --gc arena: releasing the same mark twice is not an open mark any more,
--@ so the second release shows the ARENA ERROR screen (__arena_err_mark).
--@ Results are not scraped: the test passes when the cart reaches the label below
--@ (run with --expect-reach by tools/headless/unittest.py; run_tests.sh skips it).
--#gc arena

function main()
    local m = arena.mark()
    arena.release(m)
    arena.release(m)
    system.wait()
end

--[[
=== EXPECTED TRAP ===
label: __arena_err_mark
]]
