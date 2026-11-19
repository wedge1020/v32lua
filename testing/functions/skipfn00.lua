--#skip-fn skipped_one, obj.skipped_two
--@ Vircon32 Lua --#skip-fn: the named functions are compiled with an empty body.
--@ They still exist and are callable (returning nil); other functions are unaffected.
--@ Results stored in global variables for automated memory scraping.

counter = 0
obj = {}

function skipped_one(a)
    counter = counter + 100
    return a + 1
end

function obj.skipped_two()
    counter = counter + 1000
    return 5
end

function kept(a)
    counter = counter + 1
    return a + 1
end

function main()
    ioports.gpu.clear("black")
    local r1 = skipped_one(3)
    local r2 = obj.skipped_two()
    local r3 = kept(3)
    number_result1 = counter                -- Expected: 1
    number_result2 = (r1 == nil) and 1 or 0 -- Expected: 1
    number_result3 = (r2 == nil) and 1 or 0 -- Expected: 1
    number_result4 = r3                     -- Expected: 4
    print(100, 0, "skip-fn " .. number_result1)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 1.0000
number_result2: 1.0000
number_result3: 1.0000
number_result4: 4.0000
]]
