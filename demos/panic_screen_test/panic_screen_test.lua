-- panic_screen_test.lua
--
-- A (id 5) -> attempt to call a non-function value  -> __runtime_error_not_callable
-- B (id 6) -> attempt to index a non-table value     -> __runtime_error_not_table
-- X (id 7) -> exhaust the heap                        -> __oom_handler
--
-- Y is deliberately not wired up: __runtime_error_hash_overflow has no
-- call site anywhere in the runtime or compiler right now (superseded by
-- the dynamic hash-bucket fallback), so there's currently no way to
-- reach it from Lua at all.

local not_a_function = nil
local not_a_table    = 42

function init()
    ioports.gpu.clear("black")
end

function game_loop()
    if btnp(5) then
        not_a_function()
    end

    if btnp(6) then
        local x = not_a_table.field
    end

    if btnp(8) then
        __rawasm__("MOV R0, SP\nISUB R0, 8\nMOV [HEAP_POINTER], R0\n")
        local junk = {}   -- __malloc's very next request now collides immediately
    end

    print(20, 100, "A: not callable   B: not a table   Y: out of memory")
end
