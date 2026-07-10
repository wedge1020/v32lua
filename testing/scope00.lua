-- test_scopes.lua
x = 100  -- Global variable

function test_scopes()
    local x = 50  -- Local variable (Shadows the global 'x' inside this function)
    
    if x > 10 then
        local x = 25  -- Another local 'x' (Shadows the function-level 'x' inside this IF block)
        y = x + 5     -- 'y' (global) should become 30 (25 + 5)
    end
    
    z = x + 5         -- 'z' (global) should become 55 (50 + 5), NOT 105 or 30!
end
