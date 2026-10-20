--@ Vircon32 Lua Nested Field / Index Unit Test
--@ Field reads whose key is itself a field read, inside methods -- the
--@ pattern of warm_wheels' menu (`s.selected[s.current] = ...`). The
--@ inline t.field lookup could be handed the key's own register as its
--@ scratch register, so its key check compared a register with itself,
--@ always "matched", and returned whatever the probed hash slot held
--@ (often nil -> "attempt to index a non-table value").
--@ Results are stored in global variables for automated memory scraping.

function incw(val, max)
    if val == max then return 1 else return val + 1 end
end

function decw(val, max)
    if val == 1 then return max else return val - 1 end
end

menu = {
    init = function(s, items)
        s.items = items
        s.current = 1
        s.selected = {}
        for i = 1, #s.items do
            s.selected[i] = s.items[i].def or 1
        end
    end,
    right = function(s)
        s.selected[s.current] = incw(s.selected[s.current], (#s.items[s.current].values))
    end,
    left = function(s)
        s.selected[s.current] = decw(s.selected[s.current], #s.items[s.current].values)
    end,
    down = function(s)
        s.current = incw(s.current, #s.items)
    end,
    value = function(s, i)
        return s.items[i].values[s.selected[i]]
    end,
}

function test_nested_field_index()
    menu:init({
        { values = { 1, 2, 3, 4 }, def = 1 },
        { values = { 0, 1, 2, 3 }, def = 4 },
        { values = { 1, 3, 5, 10 }, def = 2 },
    })

    -- === Test 00: right on the first item ===
    menu:right()
    menu:right()
    number_result00 = menu:value(1)        -- 3
    __rawasm__("__debug0:")

    -- === Test 01: left wraps from the default ===
    menu:down()
    menu:left()
    number_result01 = menu:value(2)        -- 2
    __rawasm__("__debug1:")

    -- === Test 02: right wraps around ===
    menu:down()
    menu:right()
    menu:right()
    menu:right()
    number_result02 = menu:value(3)        -- 1
    __rawasm__("__debug2:")

    -- === Test 03: current wrapped back to 1 ===
    menu:down()
    number_result03 = menu.current         -- 1
    __rawasm__("__debug3:")

    -- === Test 04: a field keyed by another table's field, read directly ===
    local names = { a = "alpha", b = "beta" }
    local pick = { key = "b" }
    string_result04 = names[pick.key]      -- "beta"
    __rawasm__("__debug4:")

    -- === Test 05: chained field reads in one expression ===
    local cfg = { player = { car = { speed = 7 } }, mult = 3 }
    number_result05 = cfg.player.car.speed * cfg.mult   -- 21
    __rawasm__("__debug5:")
end

function main()
    ioports.gpu.clear("black")
    test_nested_field_index()

    print(000, 000, "--- Nested Field / Index Test ---")
    print(000, 020, "Test 00: " .. number_result00)
    print(000, 040, "Test 01: " .. number_result01)
    print(000, 060, "Test 02: " .. number_result02)
    print(000, 080, "Test 03: " .. number_result03)
    print(000, 100, "Test 04: " .. string_result04)
    print(000, 120, "Test 05: " .. number_result05)
end

--[[
=== EXPECTED OUTPUT ===

number_result00: 3.0000
number_result01: 2.0000
number_result02: 1.0000
number_result03: 1.0000
string_result04: "beta"
number_result05: 21.0000

--]]
