--@ --gc arena: filling the heap reaches the out-of-memory panic (__oom_handler)
--@ instead of corrupting RAM. Needs ~570 frames (about 2 s), hence the cap.
--@ Results are not scraped: the test passes when the cart reaches the label below
--@ (run with --expect-reach by tools/headless/unittest.py; run_tests.sh skips it).
--@ frames: 700
--#gc arena

function main()
    local t = {}
    for i = 1, 100000000 do
        t[i] = {i, i}
    end
    system.wait()
end

--[[
=== EXPECTED TRAP ===
label: __oom_handler
]]
