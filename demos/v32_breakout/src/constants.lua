-- Screen states.
STATE_TITLE       = 0
STATE_READY       = 1
STATE_PLAYING     = 2
STATE_DYING       = 3
STATE_GAME_OVER   = 4
STATE_LEVEL_CLEAR = 5
STATE_FADE_OUT    = 6
STATE_ENDING      = 7

-- Vircon32 native input button IDs.
BUTTON_LEFT  = 0
BUTTON_RIGHT = 1
BUTTON_START = 4
BUTTON_A     = 5

-- Screen / HUD.
SCREEN_WIDTH    = 640
SCREEN_HEIGHT   = 360
HUD_HEIGHT      = 36
FONT_CHAR_WIDTH = 8

-- Visible gameplay bounds. The top strip is reserved for the HUD and the
-- side strips narrow the 16:9 screen into a more traditional Breakout field.
PLAYFIELD_LEFT  = 24
PLAYFIELD_RIGHT = 616
PLAYFIELD_TOP   = HUD_HEIGHT

HUD_LIVES_X = 40
HUD_SCORE_X = 488

-- Paddle.
PADDLE_WIDTH  = 80
PADDLE_HEIGHT = 12
PADDLE_Y      = 330
PADDLE_SPEED  = 5

-- Ball.
BALL_SIZE       = 10
BALL_START_VX   = 2.4
BALL_START_VY   = -3.2
BALL_ATTACH_GAP = 2

-- Blocks. The 12-column layout is 576 px wide and centered in 640 px.
BLOCK_COLS    = 12
BLOCK_ROWS    = 7
BLOCK_WIDTH   = 44
BLOCK_HEIGHT  = 16
BLOCK_GAP_X   = 4
BLOCK_GAP_Y   = 4
BLOCK_PITCH_X = BLOCK_WIDTH + BLOCK_GAP_X
BLOCK_PITCH_Y = BLOCK_HEIGHT + BLOCK_GAP_Y
BLOCK_ORIGIN_X = 32
BLOCK_ORIGIN_Y = 60
BLOCK_SCORE    = 100

-- Game rules.
STARTING_LIVES = 3

-- Timings, in frames (Vircon32 normally runs at 60 FPS).
READY_TOTAL_FRAMES      = 120
READY_BLINK_FRAMES      = 15
DYING_TOTAL_FRAMES      = 75
DYING_BLINK_FRAMES      = 10
GAME_OVER_INPUT_DELAY   = 45
LEVEL_CLEAR_INPUT_DELAY = 60

-- GPU region IDs used by this milestone.
REGION_PADDLE = 1
REGION_BALL   = 2
REGION_BLOCK  = 3
REGION_SOLID  = 4
