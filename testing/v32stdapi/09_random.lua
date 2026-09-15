--#title "v32lua rand/srand unit test"
--@ Vircon32 Lua random number unit test -- lib/misc.lua
--@ Exercises rand() and srand(), the two misc.h functions that are
--@ genuinely portable. Unlike Lua's math.random() (a float in [0,1)
--@ or a bounded integer), these follow the C contract exactly: rand()
--@ reads the raw RNG value register with no bounding at all, and
--@ srand() writes the seed register. v32sim emulates the RNG
--@ deterministically, so the actual register values for seed 12345
--@ are scraped below (confirmed stable across separate programs and
--@ runs) alongside the behavioral properties that would survive an
--@ RNG implementation change: successive reads advance the sequence,
--@ and re-seeding with the same seed replays it from the start.
--@ memset/memcpy/memcmp and the malloc/calloc/realloc/free family
--@ are NOT covered: they are deliberate NOT IMPLEMENTED stubs (no
--@ pointer type exists in v32lua) and are excluded by design. exit()
--@ needs no test either -- the compiler recognizes it natively.

--#include "../../lib/misc.lua"

function main()
    ioports.gpu.clear("black")

    -- === Test 1: rand returns a number, before any seeding ===
    boolean_rand_is_number = (type(rand()) == "number")

    -- === Test 2: srand(12345) then the first two reads of the ===
    -- === sequence (actual v32sim RNG register values) ===
    srand(12345)
    number_rand_first  = rand()   -- first value after this seed
    number_rand_second = rand()   -- next value: sequence advances per read

    -- === Test 3: the sequence actually moves between reads ===
    boolean_rand_advances = (number_rand_second ~= number_rand_first)

    -- === Test 4: re-seeding with the same seed replays the sequence ===
    srand(12345)
    number_rand_reseeded = rand()   -- same seed, same first value again
    boolean_rand_reseed_reproduces = (number_rand_reseeded == number_rand_first)

    print(10, 0,   "--- rand/srand unit test ---")
    print(10, 20,  "rand() is a number: " .. tostring(boolean_rand_is_number))
    print(10, 40,  "first after srand(12345): " .. number_rand_first)
    print(10, 60,  "second read differs: " .. tostring(boolean_rand_advances))
    print(10, 80,  "re-seed replays first: " .. tostring(boolean_rand_reseed_reproduces))
end

--[[
=== EXPECTED OUTPUT ===

boolean_rand_is_number: true
number_rand_first: 207482416.0000
number_rand_second: 1790989824.0000
boolean_rand_advances: true
number_rand_reseeded: 207482416.0000
boolean_rand_reseed_reproduces: true

--]]
