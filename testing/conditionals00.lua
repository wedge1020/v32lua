-- test suite for v32lua if statements

function test_basic_if()
    local x = 10
    if x > 5 then
        -- This block should execute
        __asm__("write R0, 1  ; Success: basic if passed")
    end
end

function test_if_else()
    local x = 3
    if x > 5 then
        __asm__("write R0, 99 ; Fail: entered if branch in if-else")
    else
        -- This block should execute
        __asm__("write R0, 2  ; Success: if-else passed")
    end
end

function test_if_elseif()
    local x = 7
    if x < 5 then
        __asm__("write R0, 99 ; Fail: entered first if branch")
    elseif x == 7 then
        -- This block should execute
        __asm__("write R0, 3  ; Success: elseif branch passed")
    else
        __asm__("write R0, 99 ; Fail: entered else branch")
    end
end

function test_nested_if()
    local x = 20
    local y = 30
    
    if x > 10 then
        if y < 40 then
            -- Both conditions met
            __asm__("write R0, 4  ; Success: nested ifs passed")
        else
            __asm__("write R0, 99 ; Fail: inner else hit")
        end
    else
        __asm__("write R0, 99 ; Fail: outer else hit")
    end
end

function game_loop()
    -- Run all conditional scenarios
    test_basic_if()
    test_if_else()
    test_if_elseif()
    test_nested_if()
end
