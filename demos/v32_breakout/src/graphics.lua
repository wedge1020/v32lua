function print_centered(y, text)
    local text_width = #text * FONT_CHAR_WIDTH
    local x = (SCREEN_WIDTH - text_width) / 2
    print(x, y, text)
end

function print_right_aligned(x_right, y, text)
    local text_width = #text * FONT_CHAR_WIDTH
    print(x_right - text_width, y, text)
end

function format_score(value)
    if value < 10 then
        return "0000" .. value
    elseif value < 100 then
        return "000" .. value
    elseif value < 1000 then
        return "00" .. value
    elseif value < 10000 then
        return "0" .. value
    elseif value < 100000 then
        return "" .. value
    end

    -- Five display digits are intentional. The planned game does not need
    -- more, but saturating keeps the HUD width stable if scores are tuned up.
    return "99999"
end

function draw_solid_rect(x, y, width, height, color)
    spr(REGION_SOLID, x, y, width, height, 0, color)
end

function draw_playfield_borders()
    draw_solid_rect(0, 0, SCREEN_WIDTH, PLAYFIELD_TOP, 0xFF000000)
    draw_solid_rect(0, PLAYFIELD_TOP, PLAYFIELD_LEFT, SCREEN_HEIGHT - PLAYFIELD_TOP, 0xFF000000)
    draw_solid_rect(PLAYFIELD_RIGHT, PLAYFIELD_TOP, SCREEN_WIDTH - PLAYFIELD_RIGHT, SCREEN_HEIGHT - PLAYFIELD_TOP, 0xFF000000)

    -- spr() leaves its multiply color and blend mode as persistent GPU state.
    -- The three border draws above therefore leave the multiply color black,
    -- which also tints the built-in font drawn afterwards. An off-screen draw
    -- with the default spr() arguments restores multiply color to white and
    -- alpha blending without changing any visible pixel.
    spr(REGION_SOLID, -2, -2)
end

function graphics_init()
    ioports.gpu.texture = sprites

    -- Paddle: atlas rectangle (0,0)-(79,11).
    ioports.gpu.region = REGION_PADDLE
    ioports.gpu.minX = 0
    ioports.gpu.minY = 0
    ioports.gpu.maxX = 79
    ioports.gpu.maxY = 11
    ioports.gpu.hotX = 0
    ioports.gpu.hotY = 0

    -- Ball: atlas rectangle (82,0)-(91,9).
    ioports.gpu.region = REGION_BALL
    ioports.gpu.minX = 82
    ioports.gpu.minY = 0
    ioports.gpu.maxX = 91
    ioports.gpu.maxY = 9
    ioports.gpu.hotX = 82
    ioports.gpu.hotY = 0

    -- Normal block: atlas rectangle (96,0)-(139,15).
    ioports.gpu.region = REGION_BLOCK
    ioports.gpu.minX = 96
    ioports.gpu.minY = 0
    ioports.gpu.maxX = 139
    ioports.gpu.maxY = 15
    ioports.gpu.hotX = 96
    ioports.gpu.hotY = 0

    -- One opaque white pixel, scaled and tinted to draw temporary borders.
    ioports.gpu.region = REGION_SOLID
    ioports.gpu.minX = 142
    ioports.gpu.minY = 0
    ioports.gpu.maxX = 142
    ioports.gpu.maxY = 0
    ioports.gpu.hotX = 142
    ioports.gpu.hotY = 0
end

function draw_hud()
    print(HUD_LIVES_X, 12, "LIVES " .. lives)
    print(HUD_SCORE_X, 12, "SCORE " .. format_score(score))
end

function draw_playfield()
    ioports.gpu.clear(0xFF101018)
    draw_blocks()
    spr(REGION_PADDLE, paddle_x, PADDLE_Y)

    if ball_visible then
        spr(REGION_BALL, ball_x, ball_y)
    end

    -- Draw borders after gameplay sprites, so the visual wall exactly masks
    -- anything outside the collision area. HUD text is then drawn on top.
    draw_playfield_borders()
    draw_hud()
end
