--#api pico8
--@ Vircon32 Lua PICO-8 stat(1) Unit Test
--@ stat(1) is the CPU used so far this tick as a fraction of the tick's frame
--@ budget. The idle wait the runtime inserts before _draw() (so a draw never
--@ straddles a frame) is not CPU, so a light _update() followed by a long
--@ _draw() must read low at the start of _draw() and high at the end of it.
--@ Results are stored in global variables for automated memory scraping.

local k = 0
local x = 0

function _update()
    k = k + 1
    for i = 1, 3000 do x = x + i end
    if k == 6 then u_end = stat(1) end
end

function _draw()
    if k ~= 6 then return end
    local d_start = stat(1)
    for i = 1, 2000 do pset(1, 1, i % 16) end
    local d_end = stat(1)

    boolean_update_light = u_end > 0 and u_end < 0.3
    -- without the idle exclusion this read 0.5 (the frame the update left unused)
    boolean_draw_start_matches = d_start >= u_end and d_start < u_end + 0.1
    boolean_draw_grows = d_end > d_start + 0.2
end

--[[
=== EXPECTED OUTPUT ===

boolean_update_light: true
boolean_draw_start_matches: true
boolean_draw_grows: true

--]]
