-- misc_compat.lua
--
-- v32lua port of misc.h's random-number functions.
--
-- v32lua already has math.random()/math.randomseed(), but those follow
-- Lua's convention: math.random() returns a float in [0,1), and
-- math.random(m [, n]) returns a bounded integer. C's rand() has
-- neither behavior -- it just reads the raw RNG_CurrentValue register
-- (full 32-bit range, whatever that means for a given seed) with no
-- bounding at all. So rather than alias rand()/srand() onto
-- math.random()/math.randomseed() and quietly change their range,
-- these read/write ioports.rng.* directly -- exactly what the C
-- version's inline asm did.

function rand()
    return ioports.rng.value
end

-- value 0 is never actually set as the seed on real hardware (the
-- request is silently ignored) -- same caveat as the C original.
function srand(seed)
    ioports.rng.seed = seed
end

-- ---------------------------------------------------------------------------
--   STUBS: NOT PORTABLE, BUT PRESENT SO CALLS STILL COMPILE
-- ---------------------------------------------------------------------------
--
-- memset/memcpy/memcmp and the whole malloc/calloc/realloc/free family
-- operate on raw pointers into a flat address space. v32lua has no
-- pointer type and no user-facing raw memory access -- tables are
-- heap-boxed and managed by the compiler's own allocator internally,
-- not exposed as addressable memory -- so there's no faithful target
-- for these without new compiler-level support (a peek/poke primitive,
-- at minimum). These stand-ins exist only so that ported C code
-- calling them still compiles and makes the gap visible at runtime,
-- rather than failing at compile time with no clue why. Anywhere one
-- of these actually fires, that call site needs to be rewritten by
-- hand -- there's no generic fix to apply here.

function memset(destination, value, size)
    print(0, 0, "NOT IMPLEMENTED")
end

function memcpy(destination, source, size)
    print(0, 0, "NOT IMPLEMENTED")
end

function memcmp(region1, region2, size)
    print(0, 0, "NOT IMPLEMENTED")
    return 0
end

function malloc(size)
    print(0, 0, "NOT IMPLEMENTED")
    return nil
end

function free(ptr)
    print(0, 0, "NOT IMPLEMENTED")
end

function calloc(number, size)
    print(0, 0, "NOT IMPLEMENTED")
    return nil
end

function realloc(ptr, size)
    print(0, 0, "NOT IMPLEMENTED")
    return nil
end

-- ---------------------------------------------------------------------------
--   NOT PORTED, AND WHY
-- ---------------------------------------------------------------------------
--
-- exit() needs no wrapper at all -- v32lua already recognizes a bare
-- exit() call natively (it compiles straight to HLT), so ported code
-- calling it works completely unchanged.
