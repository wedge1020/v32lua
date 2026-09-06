--#title "[v32lua] tilemap.render() scroll demo"
--#texture SPRITES  "assets/apidemo_tilemap.png"
--#tilemap CORRIDOR "assets/corridor.map"

--@ Demonstration of tilemap.render(): a 30-column dungeon corridor, only
--@ 12 columns of which fit the 640px-wide screen at once (53px tiles),
--@ scrolling back and forth by walking tilemap.render()'s sx argument
--@ up and down between 0 and (30-12). This is CELL-granularity scrolling,
--@ not sub-pixel -- render() has no fractional source offset, same as
--@ TIC-80's map(). Still reads fine at this tile size.
--@
--@ Region layout (found by scanning the sheet's alpha channel for gaps,
--@ not eyeballed):
--@   1 = WALL   53x53  (6,156)-(58,208)
--@   2 = FLOOR  53x53  (218,156)-(270,208)  -- trimmed 1px off its natural
--@                     54px width so it tiles flush against WALL
--@   3 = EDGE   26x53  (186,156)-(211,208)  -- narrower than a full cell;
--@                     sits flush-left within its 53px slot, which reads
--@                     as a nice deliberate accent, not a bug
--@   4 = WIZARD 45x63  (6,6)-(50,68)        -- static, not part of the map

MAP_COLS   = 30
VIEW_COLS  = 12
MAX_SCROLL = MAP_COLS - VIEW_COLS   -- 18
SCROLL_HOLD_FRAMES = 6              -- lower = faster scroll

function init()
    ioports.gpu.texture = SPRITES

    ioports.gpu.region = 1
    ioports.gpu.minX = 6
    ioports.gpu.minY = 156
    ioports.gpu.maxX = 58
    ioports.gpu.maxY = 208

    ioports.gpu.region = 2
    ioports.gpu.minX = 218
    ioports.gpu.minY = 156
    ioports.gpu.maxX = 270
    ioports.gpu.maxY = 208

    ioports.gpu.region = 3
    ioports.gpu.minX = 186
    ioports.gpu.minY = 156
    ioports.gpu.maxX = 211
    ioports.gpu.maxY = 208

    ioports.gpu.region = 4
    ioports.gpu.minX = 6
    ioports.gpu.minY = 6
    ioports.gpu.maxX = 50
    ioports.gpu.maxY = 68

    scroll_x     = 0
    scroll_dir   = 1
    frame_count  = 0
end

function game_loop()
    ioports.gpu.clear("black")

    frame_count = frame_count + 1
    if frame_count >= SCROLL_HOLD_FRAMES then
        frame_count = 0
        scroll_x = scroll_x + scroll_dir
        if scroll_x >= MAX_SCROLL then
            scroll_x   = MAX_SCROLL
            scroll_dir = -1
        elseif scroll_x <= 0 then
            scroll_x   = 0
            scroll_dir = 1
        end
    end

    -- source: 12 cols x 6 rows starting at column scroll_x
    -- screen: top-left of the drawn region, 53px cells
    tilemap.render(CORRIDOR, scroll_x, 0, VIEW_COLS, 6, 0, 0, 53, 53)

    -- wizard stands fixed on screen -- the corridor scrolls past him
    spr(4, 294, 110)

    print(0, 0, "sx=" .. scroll_x .. (scroll_dir > 0 and " ->" or " <-"))
end
