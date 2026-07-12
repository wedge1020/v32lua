## Vircon32 Cartridge Hints (`--#`)

The compiler supports specialized top-level comment directives called **Cartridge Hints**. By prefixing a line with `--#`, you can define Vircon32 cartridge metadata and register multimedia resources (textures and audio) directly inside your Lua source code. 

When you compile your script, the compiler automatically generates the accompanying Vircon32 XML cartridge configuration file and binds your resources to global Lua variables.

---

### Supported Hints

| Hint | Syntax | Description |
| :--- | :--- | :--- |
| **Title** | `--#title "<string>"` | Sets the title of the Vircon32 cartridge. |
| **Version** | `--#version <string>` | Sets the version string of the cartridge (e.g., `1.0` or `0.9.5-beta`). |
| **Texture** | `--#texture <var_name> "<file_path>"` | Registers an image file, assigns it a sequential ID, and binds that ID to a global Lua variable. |
| **Audio** | `--#audio <var_name> "<file_path>"` | Registers a sound/music file, assigns it a sequential ID, and binds that ID to a global Lua variable. |

---

### Example Usage

You can place cartridge hints anywhere at the top level of your `.lua` file, though placing them at the very top is recommended for readability.

```lua
--#version 1.2
--#title "Space Invaders Vircon32"

-- Register textures (Automatically assigned IDs: 0, 1, 2...)
--#texture bg_space "assets/textures/background.png"
--#texture spr_player "assets/textures/ship.png"
--#texture spr_alien "assets/textures/invader.png"

-- Register audio (Automatically assigned IDs: 0, 1...)
--#audio sfx_laser "assets/sounds/laser.wav"
--#audio bgm_stage1 "assets/music/stage1.ogg"

function main()
    -- The variables defined above are automatically initialized as global integers!
    -- You can pass them directly to Vircon32 hardware I/O ports:
    
    -- Set the active GPU texture to 'bg_space' (ID 0)
    ioports.gpu.texture = bg_space
    ioports.gpu.clear()
    
    -- Play the background music (ID 1)
    ioports.spu.play_sound(bgm_stage1)
end
```

Here is a complete, Markdown-formatted documentation section designed to drop directly into your project's `USAGE.md` file. It covers the syntax, practical code examples, and an explanation of the compiler's under-the-hood behavior.

```markdown
## Vircon32 Cartridge Hints (`--#`)

The compiler supports specialized top-level comment directives called **Cartridge Hints**. By prefixing a line with `--#`, you can define Vircon32 cartridge metadata and register multimedia resources (textures and audio) directly inside your Lua source code. 

When you compile your script, the compiler automatically generates the accompanying Vircon32 XML cartridge configuration file and binds your resources to global Lua variables.

---

### Supported Hints

| Hint | Syntax | Description |
| :--- | :--- | :--- |
| **Title** | `--#title "<string>"` | Sets the title of the Vircon32 cartridge. |
| **Version** | `--#version <string>` | Sets the version string of the cartridge (e.g., `1.0` or `0.9.5-beta`). |
| **Texture** | `--#texture <var_name> "<file_path>"` | Registers an image file, assigns it a sequential ID, and binds that ID to a global Lua variable. |
| **Audio** | `--#audio <var_name> "<file_path>"` | Registers a sound/music file, assigns it a sequential ID, and binds that ID to a global Lua variable. |

---

### Example Usage

You can place cartridge hints anywhere at the top level of your `.lua` file, though placing them at the very top is recommended for readability.

```lua
--#version 1.2
--#title "Space Invaders Vircon32"

-- Register textures (Automatically assigned IDs: 0, 1, 2...)
--#texture bg_space "assets/textures/background.png"
--#texture spr_player "assets/textures/ship.png"
--#texture spr_alien "assets/textures/invader.png"

-- Register audio (Automatically assigned IDs: 0, 1...)
--#audio sfx_laser "assets/sounds/laser.wav"
--#audio bgm_stage1 "assets/music/stage1.ogg"

function main()
    -- The variables defined above are automatically initialized as global integers!
    -- You can pass them directly to Vircon32 hardware I/O ports:
    
    -- Set the active GPU texture to 'bg_space' (ID 0)
    ioports.gpu.texture = bg_space
    ioports.gpu.clear()
    
    -- Play the background music (ID 1)
    ioports.spu.play_sound(bgm_stage1)
end

```

---

### How It Works Under the Hood

When you compile a script using cartridge hints (e.g., `game.lua`), the compiler performs two automated tasks:

#### 1. Automatic Variable Initialization

You do not need to manually assign numerical IDs to your textures or sounds. The compiler indexes each resource sequentially (starting from `0` for textures and `0` for audio) and injects global variable assignments into your program's initialization routine.

By the time `main()` executes, your resource names (`bg_space`, `sfx_laser`, etc.) already exist in RAM as integer IDs ready for hardware intrinsics.

#### 2. Automatic XML Generation

Alongside your compiled assembly/binary output, the compiler automatically generates a Vircon32-compatible XML configuration file matching your input filename (e.g., compiling `game.lua` produces `game.xml`).

For the Lua example above, the generated `game.xml` will look like this:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<cartridge version="1.2">
  <title>Space Invaders Vircon32</title>
  <textures>
    <texture id="0" path="assets/textures/background.png" /> <!-- bg_space -->
    <texture id="1" path="assets/textures/ship.png" /> <!-- spr_player -->
    <texture id="2" path="assets/textures/invader.png" /> <!-- spr_alien -->
  </textures>
  <audio>
    <sound id="0" path="assets/sounds/laser.wav" /> <!-- sfx_laser -->
    <sound id="1" path="assets/music/stage1.ogg" /> <!-- bgm_stage1 -->
  </audio>
</cartridge>

```

> **Note:** File paths specified in `--#texture` and `--#audio` hints should be relative to the project root or the location where the Vircon32 build tools will be executed.

```

```
