# --- Configuration ---
DEMO          = apidemo_spu
LUA_COMPILER  = ../../bin/v32lua
ASSEMBLER     = assemble
TEXTURE_TOOL  = png2vircon
SOUND_TOOL    = wav2vircon
FFMPEG_TOOL   = ffmpeg
PACKER        = packrom

# This variable is empty by default, but is set to -g during a debug build
DEBUG_FLAGS   =
ASM_DEBUG_FLAGS =

# --- Phony Targets ---
.PHONY: all asm vbin v32 debug clean

# Default target: Performs all steps in order
all: prep asm vbin vsnd v32

# Debug target: Sets the debug flags and builds all targets
debug: DEBUG_FLAGS = -g
debug: ASM_DEBUG_FLAGS = -g program
debug: all

# --- Build Rules ---
prep:
	@mkdir -p bin obj

# Compile Lua to Assembly
asm: obj/$(DEMO).asm

obj/$(DEMO).asm: $(DEMO).lua
	@mkdir -p bin obj
	$(LUA_COMPILER) --no-build-scripts $(DEBUG_FLAGS) -o obj/$(DEMO).asm $(DEMO).lua

# The XML names blip.vsnd and music.vsnd (the --#sound hints) beside itself, in obj/.
vsnd: obj/blip.vsnd obj/music.vsnd

obj/blip.vsnd: blip.wav | prep
	$(SOUND_TOOL) -o obj/blip.vsnd blip.wav

# music.wav is made from music.mp3 at build time (48 kHz, 16-bit stereo) and removed by 'make clean',
# so the source tree only carries the 3 MB mp3 and not a 27 MB wav.
music.wav: music.mp3
	$(FFMPEG_TOOL) -y -loglevel error -i music.mp3 -ar 48000 -ac 2 -c:a pcm_s16le music.wav

obj/music.vsnd: music.wav | prep
	$(SOUND_TOOL) -o obj/music.vsnd music.wav

# Assemble Assembly to Binary
vbin: obj/$(DEMO).vbin

obj/$(DEMO).vbin: obj/$(DEMO).asm
	$(ASSEMBLER) $(ASM_DEBUG_FLAGS) -o obj/$(DEMO).vbin obj/$(DEMO).asm

# Process PNG sprite sheet to Vircon texture
#vtex: textures/$(DEMO)_sprites.vtex

#textures/$(DEMO)_sprites.vtex: textures/$(DEMO)_sprites.png
#	$(TEXTURE_TOOL) textures/$(DEMO)_sprites.png -o textures/$(DEMO)_sprites.vtex

# Pack ROM cartridge (Depends on the binary and texture to ensure they are built first)
v32: bin/$(DEMO).v32

bin/$(DEMO).v32: obj/$(DEMO).vbin obj/blip.vsnd obj/music.vsnd
	$(PACKER) obj/$(DEMO).xml -o bin/$(DEMO).v32

# --- Clean Up ---
clean:
	rm -f bin/*.v32 obj/* music.wav
