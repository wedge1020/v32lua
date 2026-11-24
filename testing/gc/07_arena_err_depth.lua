--@ --gc arena: marks nest at most 16 deep; the 17th open arena.mark()
--@ shows the ARENA ERROR screen (__arena_err_depth).
--@ Results are not scraped: the test passes when the cart reaches the label below
--@ (run with --expect-reach by tools/headless/unittest.py; run_tests.sh skips it).
--#gc arena

function main()
    for i = 1, 17 do
        local m = arena.mark()
    end
    system.wait()
end

--[[
=== EXPECTED TRAP ===
label: __arena_err_depth
]]
