game_state = STATE_TITLE
state_frame = 0

lives = STARTING_LIVES
score = 0
current_level = 1

function set_state(new_state)
    game_state = new_state
    state_frame = 0
end

function start_new_game()
    lives = STARTING_LIVES
    score = 0
    current_level = 1
    load_level1()
    reset_playfield()
    set_state(STATE_READY)
end

function restart_test_level()
    load_level1()
    reset_playfield()
    set_state(STATE_READY)
end
