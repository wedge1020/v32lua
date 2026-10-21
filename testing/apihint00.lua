-- A native cart whose comments and strings MENTION --#api pico8 / --#p8.
-- Only a "--#" that opens a comment is a hint; these must not switch on the
-- PICO-8 front end (shorthand pass + prelude), which used to fail with
-- "Undeclared function: '__p8_cursor_get'".
--[[ long comment: --#api pico8 ]]
--[==[ and --#p8 "cart.p8" ]==]
local s = "--#api pico8"
local t = [[ --#api pico8 ]]

function main()
    -- cursor (the word alone pulls cursor() out of the PICO-8 prelude)
    local x = 1
    if x == 1 then x = 2 end
    system.wait()
end
