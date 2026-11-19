--@ Vircon32 Lua bitwise operators: the inline fast path and its fallbacks.
--@ & | ~ << >> of whole numbers in [0, 2^24) are done inline (6 cycles instead
--@ of ~96); anything else (negative, fractional, large, big shift counts)
--@ still goes through __builtin_bitop. Both must give Lua's answer.
--@ Results stored in global variables for automated memory scraping.

local function id(x) return x end   -- keeps operands out of constant folding

function test_bitops_fast_path()
    local v255, v5, v12, v3, v256 = id(255), id(5), id(12), id(3), id(256)

    -- === fast path: variable and literal right operands ===
    number_result1 = v255 & 15          -- Expected: 15
    number_result2 = v5 | 2             -- Expected: 7
    number_result3 = v12 ~ 10           -- Expected: 6
    number_result4 = v3 << 4            -- Expected: 48
    number_result5 = v256 >> 4          -- Expected: 16
    number_result6 = v255 & id(60)      -- Expected: 60
    number_result7 = id(1) << id(7)     -- Expected: 128
    number_result8 = id(255) >> id(0)   -- Expected: 255

    -- === fallbacks: negative operand, shift count 8+, large values ===
    number_result9  = id(-1) & 255      -- Expected: 255
    number_result10 = id(1) << id(8)    -- Expected: 256
    number_result11 = id(1) << id(31)   -- Expected: 2147483648
    number_result12 = id(4294967295) & 0xF0F0  -- Expected: 61680
    number_result13 = id(2147483648) >> 4      -- Expected: 134217728
    number_result14 = id(65535) >> id(31)      -- Expected: 0
    number_result15 = id(0xFF00) | id(0x00FF)  -- Expected: 65535
end

function main()
    ioports.gpu.clear("black")
    test_bitops_fast_path()
    print(100, 0, "bitops: " .. number_result1 .. " " .. number_result9)
end

--[[
=== EXPECTED OUTPUT ===
number_result1: 15.0000
number_result2: 7.0000
number_result3: 6.0000
number_result4: 48.0000
number_result5: 16.0000
number_result6: 60.0000
number_result7: 128.0000
number_result8: 255.0000
number_result9: 255.0000
number_result10: 256.0000
number_result11: 2147483648.0000
number_result12: 61680.0000
number_result13: 134217728.0000
number_result14: 0.0000
number_result15: 65535.0000
]]
