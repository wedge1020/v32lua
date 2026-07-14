from PIL import Image, ImageDraw

def create_sprite_sheet():
    # Create a 256x128 transparent canvas (32px grids)
    img = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Color Palette
    BROWN_DIRT = (139, 69, 19, 255)
    SKY_BLUE   = (135, 206, 235, 255)
    GRASS_GREEN = (34, 139, 34, 255)
    TAIZO_YELLOW = (255, 223, 0, 255)
    POOKA_RED  = (220, 20, 60, 255)
    GOGGLE_YELLOW = (255, 215, 0, 255)
    HARPOON_WHITE = (240, 240, 240, 255)
    
    # ---------------------------------------------------------
    # ROW 1 (y = 0): Environment & Player Sprites
    # ---------------------------------------------------------
    
    # 1. Dirt Tile (0, 0)
    draw.rectangle([0, 0, 31, 31], fill=BROWN_DIRT)
    # Add some quick dirt speckles
    draw.point([(4, 4), (12, 20), (24, 8), (28, 26)], fill=(205, 133, 63, 255))
    
    # 2. Sky/Grass Tile (32, 0)
    draw.rectangle([32, 0, 63, 31], fill=SKY_BLUE)
    draw.rectangle([32, 0, 63, 6], fill=GRASS_GREEN) # Grass line
    
    # 3. Taizo Hori (Player) - 4 Directions
    directions = [
        (64, "right"),  # Right
        (96, "down"),   # Down
        (128, "left"),  # Left
        (160, "up")     # Up
    ]
    for x_offset, dir_name in directions:
        # Base yellow suit
        draw.ellipse([x_offset + 4, 4, x_offset + 27, 27], fill=TAIZO_YELLOW)
        # Blue helmet visor
        if dir_name == "right":
            draw.rectangle([x_offset + 18, 8, x_offset + 25, 14], fill=(0, 191, 255, 255))
        elif dir_name == "left":
            draw.rectangle([x_offset + 6, 8, x_offset + 13, 14], fill=(0, 191, 255, 255))
        elif dir_name == "down":
            draw.rectangle([x_offset + 10, 18, x_offset + 21, 23], fill=(0, 191, 255, 255))
        elif dir_name == "up":
            draw.rectangle([x_offset + 10, 4, x_offset + 21, 9], fill=(0, 0, 0, 255)) # Back of head

    # ---------------------------------------------------------
    # ROW 2 (y = 32): Enemies (Pooka) & Inflation frames
    # ---------------------------------------------------------
    
    # 1. Normal Pooka (0, 32)
    draw.ellipse([4, 36, 27, 59], fill=POOKA_RED)
    draw.rectangle([8, 42, 23, 48], fill=GOGGLE_YELLOW) # Goggles
    draw.rectangle([12, 44, 14, 46], fill=(0, 0, 0, 255)) # Goggle lens left
    draw.rectangle([17, 44, 19, 46], fill=(0, 0, 0, 255)) # Goggle lens right
    
    # 2. Ghost Eyes Only (32, 32)
    draw.rectangle([40, 42, 55, 48], fill=GOGGLE_YELLOW)
    draw.rectangle([44, 44, 46, 46], fill=(0, 0, 0, 255))
    draw.rectangle([49, 44, 51, 46], fill=(0, 0, 0, 255))
    
    # 3. Pooka Inflation frames (64, 32) to (160, 32)
    for step in range(1, 5):
        x_offset = 32 + (step * 32)
        radius = 11 + (step * 2) # Get progressively fatter
        draw.ellipse([x_offset + 16 - radius, 48 - radius, x_offset + 16 + radius, 48 + radius], fill=POOKA_RED)
        # Shift goggles to stretch outward
        draw.rectangle([x_offset + 16 - (radius//2), 44, x_offset + 16 + (radius//2), 48], fill=GOGGLE_YELLOW)

    # ---------------------------------------------------------
    # ROW 3 (y = 64): Weapon Sprites
    # ---------------------------------------------------------
    
    # 1. Harpoon Tip (0, 64)
    draw.rectangle([4, 76, 27, 82], fill=HARPOON_WHITE)
    draw.polygon([(24, 73), (30, 79), (24, 85)], fill=HARPOON_WHITE)

    # Save to directory
    img.save("digdug_sprites.png")
    print("Success: 'digdug_sprites.png' generated successfully with perfect Vircon32 coordinate offsets.")

if __name__ == "__main__":
    create_sprite_sheet()
