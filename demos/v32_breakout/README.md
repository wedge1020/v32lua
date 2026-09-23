# V32 Breakout - Milestone 3.1

Revision of milestone 3 after a full playtest.

## Changes in this revision

- The score is now shown with exactly five digits (`00100`, `01200`, etc.).
- The score has a fixed HUD position instead of being right-aligned against the screen edge.
- The real gameplay area is now bounded horizontally from x=24 to x=616.
- The ceiling remains at y=36, matching the bottom of the HUD strip.
- The inaccessible top strip and both side strips are drawn as solid black temporary borders.
- Paddle and ball collisions use those same visible side boundaries.
- The current 12-column level CSV is unchanged: its blocks occupy x=32..604, so they still fit inside the new playfield (x=24..616).

These black strips are intentionally temporary. Later they can be replaced by proper border artwork without changing the gameplay coordinates.

## Expected test

1. Build with `make` and run `bin/breakout.v32`.
2. Verify score starts as `SCORE 00000` and becomes `SCORE 00100`, `SCORE 00200`, etc.
3. Verify the score never approaches the right edge as the digit count grows.
4. Verify the ball visibly touches the black top border before bouncing.
5. Verify the ball visibly touches the black left/right borders before bouncing.
6. Verify the paddle cannot enter either black side border.
7. Complete the test level and confirm the layout has not been clipped by the narrower playfield.

## Build

Requires the Vircon32 development tools and `v32lua` in `PATH` (same requirements as the previous milestone):

```sh
make
```

The ROM is written to:

```text
bin/breakout.v32
```

Use `make clean` to remove generated files.


## 0.3.2 - GPU color-state fix

The temporary black playfield borders are drawn by tinting a one-pixel white sprite.
Vircon32's GPU multiply color is persistent, so after those draws the built-in font
was also being multiplied by black. `draw_playfield_borders()` now performs one
off-screen `spr()` call with default arguments, which restores the multiply color to
white (`0xFFFFFFFF`) and the normal alpha blend mode before HUD or overlay text is
drawn.
