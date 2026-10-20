-- The tilemap is immutable level-design data in ROM. Runtime destruction is
-- tracked separately here so losing a life does not restore destroyed blocks.
block_active = {}
blocks_remaining = 0

function block_index(col, row)
    return row * BLOCK_COLS + col + 1
end

function clear_blocks()
    local row = 0
    blocks_remaining = 0

    while row < BLOCK_ROWS do
        local col = 0
        while col < BLOCK_COLS do
            block_active[block_index(col, row)] = false
            col = col + 1
        end
        row = row + 1
    end
end

function load_level1()
    local row = 0
    blocks_remaining = 0

    while row < BLOCK_ROWS do
        local col = 0
        while col < BLOCK_COLS do
            local index = block_index(col, row)
            local tile = tilemap.get(LEVEL1, col, row)

            if tile ~= 0 then
                block_active[index] = true
                blocks_remaining = blocks_remaining + 1
            else
                block_active[index] = false
            end

            col = col + 1
        end
        row = row + 1
    end
end

function draw_blocks()
    local row = 0

    while row < BLOCK_ROWS do
        local col = 0
        while col < BLOCK_COLS do
            local index = block_index(col, row)

            if block_active[index] then
                local x = BLOCK_ORIGIN_X + col * BLOCK_PITCH_X
                local y = BLOCK_ORIGIN_Y + row * BLOCK_PITCH_Y
                spr(REGION_BLOCK, x, y)
            end

            col = col + 1
        end
        row = row + 1
    end
end

function ball_overlaps_block(block_x, block_y)
    if ball_x + BALL_SIZE <= block_x then
        return false
    end

    if ball_x >= block_x + BLOCK_WIDTH then
        return false
    end

    if ball_y + BALL_SIZE <= block_y then
        return false
    end

    if ball_y >= block_y + BLOCK_HEIGHT then
        return false
    end

    return true
end

function destroy_block(index)
    if not block_active[index] then
        return
    end

    block_active[index] = false
    blocks_remaining = blocks_remaining - 1
    score = score + BLOCK_SCORE

    if blocks_remaining <= 0 then
        ball_launched = false
        set_state(STATE_LEVEL_CLEAR)
    end
end

function resolve_block_collision(block_x, block_y, old_x, old_y)
    local old_right = old_x + BALL_SIZE
    local old_bottom = old_y + BALL_SIZE
    local block_right = block_x + BLOCK_WIDTH
    local block_bottom = block_y + BLOCK_HEIGHT

    -- Prefer the face crossed during this frame. This mirrors the paddle
    -- collision approach and avoids treating a side hit as a top hit.
    if ball_vy > 0 and old_bottom <= block_y then
        ball_y = block_y - BALL_SIZE
        ball_vy = -absolute_value(ball_vy)
        return
    end

    if ball_vy < 0 and old_y >= block_bottom then
        ball_y = block_bottom
        ball_vy = absolute_value(ball_vy)
        return
    end

    if ball_vx > 0 and old_right <= block_x then
        ball_x = block_x - BALL_SIZE
        ball_vx = -absolute_value(ball_vx)
        return
    end

    if ball_vx < 0 and old_x >= block_right then
        ball_x = block_right
        ball_vx = absolute_value(ball_vx)
        return
    end

    -- Fallback for exact corners / rounding: resolve the shallowest overlap.
    local penetration_top = ball_y + BALL_SIZE - block_y
    local penetration_bottom = block_bottom - ball_y
    local penetration_left = ball_x + BALL_SIZE - block_x
    local penetration_right = block_right - ball_x

    local smallest = penetration_top
    local face = 0

    if penetration_bottom < smallest then
        smallest = penetration_bottom
        face = 1
    end

    if penetration_left < smallest then
        smallest = penetration_left
        face = 2
    end

    if penetration_right < smallest then
        face = 3
    end

    if face == 0 then
        ball_y = block_y - BALL_SIZE
        ball_vy = -absolute_value(ball_vy)
    elseif face == 1 then
        ball_y = block_bottom
        ball_vy = absolute_value(ball_vy)
    elseif face == 2 then
        ball_x = block_x - BALL_SIZE
        ball_vx = -absolute_value(ball_vx)
    else
        ball_x = block_right
        ball_vx = absolute_value(ball_vx)
    end
end

function collide_ball_with_blocks(old_x, old_y)
    local row = 0

    while row < BLOCK_ROWS do
        local col = 0
        while col < BLOCK_COLS do
            local index = block_index(col, row)

            if block_active[index] then
                local block_x = BLOCK_ORIGIN_X + col * BLOCK_PITCH_X
                local block_y = BLOCK_ORIGIN_Y + row * BLOCK_PITCH_Y

                if ball_overlaps_block(block_x, block_y) then
                    resolve_block_collision(block_x, block_y, old_x, old_y)
                    destroy_block(index)
                    return true
                end
            end

            col = col + 1
        end
        row = row + 1
    end

    return false
end
