--#title "[v32lua] math.randomseed() unit test"
--@ Vircon32 Lua math.randomseed() Unit Test
--@ The seed used to go through a bare CFI. For a NaN-boxed value (the
--@ "HH:MM:SS" string system.time() returns first) or a float outside the
--@ int32 range, the emulator's (int32_t) cast is undefined: x86-64 gives
--@ 0x80000000, which the RNG port turns into state 0, and the generator
--@ then returns 0 forever (every math.random(m, n) is m). ARM64 gives 0,
--@ which the port refuses, so it worked there. Every seed below must now
--@ leave a running generator on any host.
--@ Test 02 also covers a register-allocator bug: system.time() force-
--@ spilled a free register and left its spill slot marked, so a later
--@ load of that register was overwritten with the stale word (02c used
--@ to compare number_result02a with junk).

local function running()
    local a = math.random(1, 1000000)
    local b = math.random(1, 1000000)
    local c = math.random(1, 1000000)
    return not (a == b and b == c)
end

function main()
    math.randomseed(system.time())       -- a string first
    boolean_result00a = running()
    math.randomseed("seed")
    boolean_result00b = running()
    math.randomseed(-2147483648)         -- CFI: 0x80000000 -> state 0
    boolean_result01a = running()
    math.randomseed(1e12)                -- outside int32
    boolean_result01b = running()
    math.randomseed(0)                   -- the port refuses 0
    boolean_result01c = running()
    math.randomseed(12345)
    boolean_result01d = running()
    local s = 12345
    math.randomseed(s)
    number_result02a = math.random(1, 1000000)
    math.randomseed(12345)
    number_result02b = math.random(1, 1000000)
    boolean_result02c = number_result02a == number_result02b  -- same seed, same sequence
    __rawasm__("__debug0:")
end

number_result02a = 0
number_result02b = 0

--[[
=== EXPECTED OUTPUT ===

boolean_result00a: true
boolean_result00b: true
boolean_result01a: true
boolean_result01b: true
boolean_result01c: true
boolean_result01d: true
boolean_result02c: true

--]]
