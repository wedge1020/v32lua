paddle_x = 0
ball_x = 0
ball_y = 0
ball_vx = BALL_START_VX
ball_vy = BALL_START_VY
ball_launched = false
ball_visible = true

function reset_playfield()
    paddle_x = PLAYFIELD_LEFT + (PLAYFIELD_RIGHT - PLAYFIELD_LEFT - PADDLE_WIDTH) / 2
    ball_launched = false
    ball_visible = true
    ball_vx = BALL_START_VX
    ball_vy = BALL_START_VY
    attach_ball_to_paddle()
end

function attach_ball_to_paddle()
    ball_x = paddle_x + (PADDLE_WIDTH - BALL_SIZE) / 2
    ball_y = PADDLE_Y - BALL_SIZE - BALL_ATTACH_GAP
end

function update_paddle()
    if btn(BUTTON_LEFT) then
        paddle_x = paddle_x - PADDLE_SPEED
    end

    if btn(BUTTON_RIGHT) then
        paddle_x = paddle_x + PADDLE_SPEED
    end

    if paddle_x < PLAYFIELD_LEFT then
        paddle_x = PLAYFIELD_LEFT
    end

    if paddle_x > PLAYFIELD_RIGHT - PADDLE_WIDTH then
        paddle_x = PLAYFIELD_RIGHT - PADDLE_WIDTH
    end
end

function launch_ball()
    if not ball_launched then
        ball_launched = true
        ball_vx = BALL_START_VX
        ball_vy = BALL_START_VY
    end
end

function ball_overlaps_paddle()
    if ball_x + BALL_SIZE <= paddle_x then
        return false
    end

    if ball_x >= paddle_x + PADDLE_WIDTH then
        return false
    end

    if ball_y + BALL_SIZE <= PADDLE_Y then
        return false
    end

    if ball_y >= PADDLE_Y + PADDLE_HEIGHT then
        return false
    end

    return true
end

function absolute_value(value)
    if value < 0 then
        return -value
    end

    return value
end

-- Select one of a few fixed outgoing angles. Every pair has a total speed
-- very close to BALL_SPEED (4 px/frame), so hitting near the edge changes
-- direction without making the ball progressively faster.
function bounce_ball_from_paddle_top()
    local ball_center = ball_x + BALL_SIZE / 2
    local paddle_center = paddle_x + PADDLE_WIDTH / 2
    local offset = (ball_center - paddle_center) / (PADDLE_WIDTH / 2)
    local direction = 1
    local amount = offset

    if amount < 0 then
        direction = -1
        amount = -amount
    elseif amount == 0 then
        if ball_vx < 0 then
            direction = -1
        end
    end

    if amount < 0.20 then
        ball_vx = direction * 0.80
        ball_vy = -3.92
    elseif amount < 0.50 then
        ball_vx = direction * 1.80
        ball_vy = -3.57
    elseif amount < 0.80 then
        ball_vx = direction * 2.60
        ball_vy = -3.04
    else
        ball_vx = direction * 3.20
        ball_vy = -2.40
    end

    -- This correction is only for a collision with the TOP face.
    ball_y = PADDLE_Y - BALL_SIZE
end

function bounce_ball_from_paddle_left()
    -- A lateral hit reflects only the horizontal component. Do not move the
    -- ball above the paddle: keep it beside the face that was actually hit.
    ball_vx = -absolute_value(ball_vx)
    ball_x = paddle_x - BALL_SIZE
end

function bounce_ball_from_paddle_right()
    ball_vx = absolute_value(ball_vx)
    ball_x = paddle_x + PADDLE_WIDTH
end

function collide_ball_with_paddle(old_x, old_y)
    if not ball_overlaps_paddle() then
        return
    end

    local old_right = old_x + BALL_SIZE
    local old_bottom = old_y + BALL_SIZE
    local paddle_right = paddle_x + PADDLE_WIDTH

    -- Swept-face test: determine through which face the ball entered during
    -- this frame. Top has priority at a true upper corner, which produces the
    -- familiar Breakout corner rebound without treating side impacts as top
    -- impacts.
    if ball_vy > 0 and old_bottom <= PADDLE_Y then
        bounce_ball_from_paddle_top()
        return
    end

    if ball_vx > 0 and old_right <= paddle_x then
        bounce_ball_from_paddle_left()
        return
    end

    if ball_vx < 0 and old_x >= paddle_right then
        bounce_ball_from_paddle_right()
        return
    end

    -- Fallback for an overlap caused by paddle movement or exact boundary
    -- rounding. Resolve along the shallowest penetration instead of always
    -- teleporting the ball to the top face.
    local penetration_top = ball_y + BALL_SIZE - PADDLE_Y
    local penetration_left = ball_x + BALL_SIZE - paddle_x
    local penetration_right = paddle_right - ball_x

    if ball_vy > 0 and penetration_top <= penetration_left and penetration_top <= penetration_right then
        bounce_ball_from_paddle_top()
    elseif penetration_left < penetration_right then
        bounce_ball_from_paddle_left()
    else
        bounce_ball_from_paddle_right()
    end
end

function begin_ball_loss()
    if game_state ~= STATE_DYING then
        lives = lives - 1
        ball_visible = false
        set_state(STATE_DYING)
    end
end

function update_ball()
    if not ball_launched then
        attach_ball_to_paddle()
        return
    end

    local old_x = ball_x
    local old_y = ball_y

    ball_x = ball_x + ball_vx
    ball_y = ball_y + ball_vy

    -- Left gameplay wall.
    if ball_x < PLAYFIELD_LEFT then
        ball_x = PLAYFIELD_LEFT
        ball_vx = -ball_vx
    end

    -- Right gameplay wall.
    if ball_x + BALL_SIZE > PLAYFIELD_RIGHT then
        ball_x = PLAYFIELD_RIGHT - BALL_SIZE
        ball_vx = -ball_vx
    end

    -- Ceiling: the HUD strip is outside the gameplay collision area.
    if ball_y < PLAYFIELD_TOP then
        ball_y = PLAYFIELD_TOP
        ball_vy = -ball_vy
    end

    -- Only one block can be consumed by a ball in one frame. The collision
    -- routine resolves the correct face before deactivating that block.
    collide_ball_with_blocks(old_x, old_y)

    if game_state ~= STATE_PLAYING then
        return
    end

    collide_ball_with_paddle(old_x, old_y)

    -- Missing the paddle costs one life after the whole ball leaves screen.
    if ball_y > SCREEN_HEIGHT then
        begin_ball_loss()
    end
end
