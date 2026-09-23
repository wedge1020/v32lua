--#title "V32 Breakout"
--#version "0.3.2"
--#texture sprites "assets/sprites.png"
--#tilemap LEVEL1 "levels/level1.csv"

-- Milestone 3 revision: fixed HUD score, visible borders, and GPU color-state reset.

--#include "src/constants.lua"
--#include "src/state.lua"
--#include "src/graphics.lua"
--#include "src/blocks.lua"
--#include "src/gameplay.lua"
--#include "src/screens.lua"

function init()
    graphics_init()
    game_state = STATE_TITLE
    state_frame = 0
    lives = STARTING_LIVES
    score = 0
    current_level = 1
    clear_blocks()
    reset_playfield()
end

function game_loop()
    state_frame = state_frame + 1

    if game_state == STATE_TITLE then
        update_title()
        draw_title()
    elseif game_state == STATE_READY then
        update_ready()
        draw_ready()
    elseif game_state == STATE_PLAYING then
        update_playing()
        draw_playing()
    elseif game_state == STATE_DYING then
        update_dying()
        draw_dying()
    elseif game_state == STATE_GAME_OVER then
        update_game_over()
        draw_game_over()
    elseif game_state == STATE_LEVEL_CLEAR then
        update_level_clear()
        draw_level_clear()
    end
end
