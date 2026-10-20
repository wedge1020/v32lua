-- region_helpers.lua
--
-- v32lua port of the GPU texture-region helpers from the Vircon32 C
-- standard library's video.h. Meant to be --#include'd once by any
-- cart that uses region-editor-exported region definitions.
--
-- Unlike the C versions, these compile straight down to
-- ioports.gpu.* port writes -- no CALL, no runtime cost beyond the
-- OUTs themselves. select_texture/select_region are included mainly
-- so ported/generated code can keep calling them by name; feel free
-- to write ioports.gpu.texture / ioports.gpu.region directly instead.

VIRCON32_BLEND_ALPHA     = 0x20
VIRCON32_BLEND_ADD       = 0x21
VIRCON32_BLEND_SUBTRACT  = 0x22

function select_texture(textureId)
    ioports.gpu.texture = textureId
end

function select_region(regionId)
    ioports.gpu.region = regionId
end

-- Applies to the currently selected region.
function define_region(minX, minY, maxX, maxY, hotX, hotY)
    ioports.gpu.minX = minX
    ioports.gpu.minY = minY
    ioports.gpu.maxX = maxX
    ioports.gpu.maxY = maxY
    ioports.gpu.hotX = hotX
    ioports.gpu.hotY = hotY
end

-- Applies to the currently selected region; sets the hotspot at its
-- top left, i.e. (minX, minY). Relies on the compiler's minX->hotX /
-- minY->hotY auto-pairing, same as video.h's version relies on the
-- console writing GPU_RegionHotSpotX/Y right alongside MinX/MinY.
function define_region_topleft(minX, minY, maxX, maxY)
    ioports.gpu.minX = minX
    ioports.gpu.minY = minY
    ioports.gpu.maxX = maxX
    ioports.gpu.maxY = maxY
end

-- Applies to the currently selected region; sets the hotspot at its
-- center.
function define_region_center(minX, minY, maxX, maxY)
    ioports.gpu.minX = minX
    ioports.gpu.minY = minY
    ioports.gpu.maxX = maxX
    ioports.gpu.maxY = maxY
    ioports.gpu.hotX = (minX + maxX) // 2
    ioports.gpu.hotY = (minY + maxY) // 2
end

-- Defines a set of regions with consecutive ids starting at firstId,
-- laid out in a rectangular matrix of equally-sized regions. The
-- coordinates given are for the top-left region; every region's
-- hotspot sits at the same relative offset within its own region.
-- The gap between regions is assumed equal in x and y.
--
-- v32lua has no built-in equivalent of video.h's define_region_matrix,
-- so this is a straight Lua port of it.
function define_region_matrix(
    firstId,
    firstMinX, firstMinY,
    firstMaxX, firstMaxY,
    firstHotX, firstHotY,
    elementsX, elementsY,
    gap)

    local currentId = firstId
    local minX = firstMinX
    local minY = firstMinY
    local maxX = firstMaxX
    local maxY = firstMaxY
    local hotX = firstHotX
    local hotY = firstHotY

    local advanceX = (maxX - minX + 1) + gap
    local advanceY = (maxY - minY + 1) + gap

    for matrixY = 0, elementsY - 1 do
        for matrixX = 0, elementsX - 1 do
            select_region(currentId)
            define_region(minX, minY, maxX, maxY, hotX, hotY)
            currentId = currentId + 1

            minX = minX + advanceX
            maxX = maxX + advanceX
            hotX = hotX + advanceX
        end

        minY = minY + advanceY
        maxY = maxY + advanceY
        hotY = hotY + advanceY

        minX = firstMinX
        maxX = firstMaxX
        hotX = firstHotX
    end
end
