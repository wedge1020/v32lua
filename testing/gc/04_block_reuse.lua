--@ Block reuse (every --gc mode): the array and hash blocks a table outgrows
--@ go back to __malloc, and tostring(number) keeps only the words its text
--@ needs. Checks that the memory IS reused (heap growth per table is about
--@ its final size, not the sum of every size it went through) and that a
--@ reused block never belongs to a live table (all contents intact).
--@ arena.used() is only the heap meter here: no arena is ever opened.
--@ Results stored in global variables for automated memory scraping.
--#gc arena

function test_block_reuse()
    -- === Test 1: 40 kept tables, each grown one element at a time to 64 ===
    -- Without reuse each costs 5 (header) + 8+16+32+64 = 125 words.
    local keep = {}
    for i = 1, 8 do keep[i] = 0 end         -- keep's own array settles first
    local start = arena.used()
    for n = 1, 40 do
        local t = {}
        for i = 1, 64 do t[#t + 1] = i + n end
        keep[n] = t
    end
    local per_table = (arena.used() - start) / 40
    number_result1 = per_table < 90 and 1 or 0                 -- Expected: 1
    local ok = 1
    for n = 1, 40 do
        local t = keep[n]
        if #t ~= 64 then ok = 0 end
        for i = 1, 64 do if t[i] ~= i + n then ok = 0 end end
    end
    number_result2 = ok                                        -- Expected: 1

    -- === Test 2: growing hash parts, kept and checked ===
    local hk = {}
    for n = 1, 20 do
        local h = {}
        for i = 1, 20 do h["k" .. i] = i * n end
        hk[n] = h
    end
    local hok = 1
    for n = 1, 20 do
        local h = hk[n]
        for i = 1, 20 do if h["k" .. i] ~= i * n then hok = 0 end end
    end
    number_result3 = hok                                       -- Expected: 1

    -- === Test 3: tostring keeps only what its text needs ===
    local strs = {}
    for i = 1, 64 do strs[i] = false end
    local s0 = arena.used()
    for i = 1, 64 do strs[i] = tostring(i + 0.5) end           -- "1.5" .. "64.5"
    local per_str = (arena.used() - s0) / 64
    number_result4 = per_str < 8 and 1 or 0                    -- Expected: 1
    number_result5 = (strs[1] == "1.5" and strs[64] == "64.5") and 1 or 0  -- Expected: 1
    string_result1 = strs[10] .. "|" .. tostring(-0.25)        -- Expected: "10.5|-0.25"

    -- === Test 4: mixed churn, then everything still intact ===
    local mix = {}
    for n = 1, 30 do
        local t = { name = tostring(n * 1.5) }
        for i = 1, 20 do t[i] = i end
        t.extra = "e" .. n
        mix[n] = t
    end
    local mok = 1
    for n = 1, 30 do
        local t = mix[n]
        if t.name ~= tostring(n * 1.5) or t.extra ~= "e" .. n or t[20] ~= 20 then mok = 0 end
    end
    number_result6 = mok                                       -- Expected: 1
end

function main()
    ioports.gpu.clear("black")
    test_block_reuse()
    print(100, 0, "--- block reuse ---")
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 1.0000
number_result2: 1.0000
number_result3: 1.0000
number_result4: 1.0000
number_result5: 1.0000
number_result6: 1.0000
string_result1: "10.5|-0.25"
]]
