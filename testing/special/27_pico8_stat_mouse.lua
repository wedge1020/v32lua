--#api pico8
--@ Vircon32 Lua PICO-8 stat() with the devkit mouse Unit Test
--@ A literal stat(32) / stat(33) / stat(34) makes the cart a mouse cart: the
--@ compiler then routes ids 32-34 to the v32mouse decoder and every other id
--@ to the general stat(), by an inline range test on the id. With no mouse
--@ device plugged in the pointer stays at (64, 64) with no buttons.
--@ Results are stored in global variables for automated memory scraping.

local frame = 0

function _update()
    frame = frame + 1
end

function _draw()
    if frame ~= 5 then return end

    -- the mouse ids, by literal and by variable (the variable form goes
    -- through the range test at run time)
    number_mouse_x = stat(32)
    number_mouse_y = stat(33)
    number_mouse_buttons = stat(34)
    local id = 32
    number_mouse_x_var = stat(id)
    id = 34
    number_mouse_b_var = stat(id)
    id = 33.9
    number_mouse_y_frac = stat(id)

    -- the ids next to the range, and non-numbers, are not the mouse
    number_far = stat(31 + 6)
    id = 31
    string_key_var = stat(id)
    id = 35
    number_after_var = stat(id)
    number_version = stat(5)
    number_fps = stat(8)
    id = nil
    number_nil_var = stat(id)
    id = "x"
    number_str_var = stat(id)

    -- stat as a value still reaches both
    local g = stat
    number_value_mouse = g(32)
    number_value_version = g(5)
end

--[[
=== EXPECTED OUTPUT ===

number_mouse_x: 64.0000
number_mouse_y: 64.0000
number_mouse_buttons: 0.0000
number_mouse_x_var: 64.0000
number_mouse_b_var: 0.0000
number_mouse_y_frac: 64.0000
number_far: 0.0000
string_key_var: ""
number_after_var: 0.0000
number_version: 43.0000
number_fps: 30.0000
number_nil_var: 0.0000
number_str_var: 0.0000
number_value_mouse: 64.0000
number_value_version: 43.0000

--]]
