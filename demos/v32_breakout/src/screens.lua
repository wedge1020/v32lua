function update_title()
    if btnp(BUTTON_A) or btnp(BUTTON_START) then
        start_new_game()
    end
end

function draw_title()
    ioports.gpu.clear(0xFF081020)

    print_centered(118, "V32 BREAKOUT")
    print_centered(166, "A LUA GAME FOR VIRCON32")

    if (state_frame % 60) < 30 then
        print_centered(230, "PRESS A OR START")
    end

    print_centered(330, "MILESTONE 3 - FIRST BLOCKS")
end

function update_ready()
    update_paddle()
    attach_ball_to_paddle()

    if state_frame >= READY_TOTAL_FRAMES then
        set_state(STATE_PLAYING)
    end
end

function draw_ready()
    draw_playfield()
    print_centered(214, "LEVEL 1")

    if (state_frame % (READY_BLINK_FRAMES * 2)) < READY_BLINK_FRAMES then
        print_centered(246, "READY")
    end
end

function update_playing()
    update_paddle()

    if not ball_launched then
        attach_ball_to_paddle()
        if btnp(BUTTON_A) then
            launch_ball()
        end
    end

    update_ball()
end

function draw_playing()
    draw_playfield()

    if not ball_launched then
        if (state_frame % 60) < 40 then
            print_centered(286, "PRESS A TO LAUNCH")
        end
    end
end

function update_dying()
    update_paddle()

    if state_frame >= DYING_TOTAL_FRAMES then
        if lives > 0 then
            -- Important: only paddle/ball are reset. Destroyed blocks remain
            -- destroyed until the level itself is loaded again.
            reset_playfield()
            set_state(STATE_READY)
        else
            set_state(STATE_GAME_OVER)
        end
    end
end

function draw_dying()
    draw_playfield()

    if (state_frame % (DYING_BLINK_FRAMES * 2)) < DYING_BLINK_FRAMES then
        print_centered(244, "BALL LOST")
    end
end

function update_game_over()
    if state_frame >= GAME_OVER_INPUT_DELAY then
        if btnp(BUTTON_A) or btnp(BUTTON_START) then
            set_state(STATE_TITLE)
        end
    end
end

function draw_game_over()
    ioports.gpu.clear(0xFF080810)
    draw_hud()
    print_centered(145, "GAME OVER")

    if state_frame >= GAME_OVER_INPUT_DELAY then
        if (state_frame % 60) < 30 then
            print_centered(205, "PRESS A OR START")
        end
    end
end

function update_level_clear()
    if state_frame >= LEVEL_CLEAR_INPUT_DELAY then
        if btnp(BUTTON_A) or btnp(BUTTON_START) then
            restart_test_level()
        end
    end
end

function draw_level_clear()
    draw_playfield()
    print_centered(150, "LEVEL CLEAR")
    print_centered(182, "SCORE " .. score)

    if state_frame >= LEVEL_CLEAR_INPUT_DELAY then
        if (state_frame % 60) < 30 then
            print_centered(230, "PRESS A TO REPLAY TEST LEVEL")
        end
    end
end
