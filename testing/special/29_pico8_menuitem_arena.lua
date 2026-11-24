--#api pico8
--#gc arena
--#gc-check
--@ Vircon32 Lua PICO-8 menuitem() inside an arena
--@ menuitem() keeps its five slots in fixed globals, so it allocates
--@ nothing: called from a frame wrapped in an arena (with --gc-check on) it
--@ does not panic, and after the release the slots still hold their labels
--@ and callbacks. (It used to make its slot table, and a {label, cb} table
--@ per item, on first use -- inside the arena -- and --gc-check stopped on
--@ the store; without the check the menu read freed memory.)
--@ Results are stored in global variables for automated memory scraping.

local frame = 0
local function cb_one(b) return true end

function _update()
    frame = frame + 1
    local m = arena.mark()
    if frame == 2 then
        menuitem(1, "one", cb_one)
        menuitem(2, "two")
        menuitem(3, "three")
        menuitem(2)                 -- removed again
    end
    if frame == 3 then
        -- the arena's memory is reused: anything left in it is overwritten
        for i = 1, 200 do local junk = { "junk" .. i, { i } } end
    end
    arena.release(m)
end

function _draw()
    if frame ~= 4 then return end
    local l1, c1 = __p8_menuitem_get(1)
    local l2, c2 = __p8_menuitem_get(2)
    local l3, c3 = __p8_menuitem_get(3)
    string_label_1 = l1
    boolean_callback_1 = c1 == cb_one
    boolean_slot_2_empty = l2 == nil and c2 == nil
    string_label_3 = l3
    boolean_callback_3_nil = c3 == nil
end

--[[
=== EXPECTED OUTPUT ===
string_label_1: "one"
boolean_callback_1: true
boolean_slot_2_empty: true
string_label_3: "three"
boolean_callback_3_nil: true
]]
