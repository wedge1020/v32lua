--#title "[v32lua] integer ioport literal unit test"
--@ Vircon32 Lua integer IO-port literal Unit Test
--@ A numeric literal written to an integer port is folded to its 32-bit
--@ word at compile time. `ioports.gpu.bgcolor = 0xFF003366` used to go
--@ through a float32 CFI, which is out of range for values >= 2^31
--@ (host-dependent: 0x80000000 on x86), so the color was wrong.
--@ Results are raw words read back from the ports (hex_ globals).

hex_result00a = 0
hex_result00b = 0
hex_result00c = 0
hex_result00d = 0
hex_result00e = 0

function main()
    ioports.gpu.bgcolor = 0xFF003366
    __rawasm__("IN R0, GPU_ClearColor")
    __rawasm__("MOV [var_hex_result00a], R0")
    ioports.gpu.multiply = 0x80FFFFFF
    __rawasm__("IN R0, GPU_MultiplyColor")
    __rawasm__("MOV [var_hex_result00b], R0")
    ioports.gpu.x = -5
    __rawasm__("IN R0, GPU_DrawingPointX")
    __rawasm__("MOV [var_hex_result00c], R0")
    ioports.gpu.y = 12.7                     -- truncated, like CFI
    __rawasm__("IN R0, GPU_DrawingPointY")
    __rawasm__("MOV [var_hex_result00d], R0")
    ioports.gpu.multiply = color(0x7FFFFFFF)
    __rawasm__("IN R0, GPU_MultiplyColor")
    __rawasm__("MOV [var_hex_result00e], R0")
    ioports.gpu.multiply = 0xFFFFFFFF
end

--[[
=== EXPECTED OUTPUT ===

hex_result00a: 0xFF003366
hex_result00b: 0x80FFFFFF
hex_result00c: 0xFFFFFFFB
hex_result00d: 0x0000000C
hex_result00e: 0x7FFFFFFF

--]]
