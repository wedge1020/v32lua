-- memcard_compat.lua
--
-- CORRECTION from the previous pass: I'd claimed v32lua has no raw
-- memory access and stubbed all of memcard.h's data functions as
-- NOT IMPLEMENTED. That was wrong. memcard.save(value, position) /
-- memcard.load(position) / memcard[position], given an explicit
-- position, are exactly a raw single-word peek/poke at
-- VIRCON32_MEMCARD_BASE + title-block + position -- no tag, no
-- bookkeeping, same idea as card_read_data/card_write_data's raw
-- "movs" copy at an arbitrary card offset. That's a real port target.

function card_is_connected()
    return ioports.mem.connected
end

-- ---------------------------------------------------------------------------
--   RAW DATA ACCESS -- now genuinely implemented
-- ---------------------------------------------------------------------------
--
-- destination/source are v32lua TABLES here, not raw pointers -- that
-- part doesn't survive the port, since v32lua has no pointer type.
-- Indexed 0..size-1 (not the usual 1-based Lua convention) to mirror
-- the C original's pointer-arithmetic indexing as closely as possible;
-- tables accept 0 as an ordinary key, so this is just a convention,
-- not a language restriction.
--
-- "size" is a word count, not a byte count -- the whole VM, and
-- memcard.load/save along with it, is word-addressed throughout.

function card_read_data(destination, offsetInCard, size)
    for i = 0, size - 1 do
        destination[i] = memcard.load(offsetInCard + i)
    end
end

function card_write_data(source, offsetInCard, size)
    for i = 0, size - 1 do
        memcard.save(source[i], offsetInCard + i)
    end
end

-- ---------------------------------------------------------------------------
--   SIGNATURE FUNCTIONS -- implemented, but on a *relocated* convention
-- ---------------------------------------------------------------------------
--
-- On real hardware, game_signature lives at the literal first 20
-- words of the card: address VIRCON32_MEMCARD_BASE (0x30000000)
-- through 0x30000013. In v32lua's own position numbering (see
-- v32lua.h) that is EXACTLY positions -24..-5 -- the entire title-text
-- block memcard.title() owns, word for word, not merely adjacent to
-- it. Positions -4..-1 are the compiler's separate metadata region
-- (the auto-append cursor lives at -1); positions 0.. are the first
-- genuinely free data words. Writing a signature at -24..-5 would
-- silently corrupt whatever title the game has set. So this
-- reservation is moved into the ordinary, user-owned DATA region
-- instead: the first SIGNATURE_WORDS positions (0..19), which are
-- just as legitimately free as any offset card_read_data/
-- card_write_data would use -- this isn't a lesser or riskier target,
-- just a different address than the C original used.
--
-- Consequence worth being explicit about: a card written by this
-- convention is NOT signature-compatible with a real Vircon32 C build
-- of the same game -- same idea, different address, not the same
-- bytes on the card. It's an internally-consistent v32lua-only
-- convention for "does this card belong to my game", not a
-- byte-for-byte port. If you adopt it, keep your own actual save data
-- starting at position SIGNATURE_WORDS (20) or later so it doesn't
-- collide with the signature block, the same way the C original
-- expects card_read_data/card_write_data's offset_in_card to steer
-- clear of its own signature at the front of the card.

SIGNATURE_WORDS = 20

function card_read_signature(signature)
    for i = 0, SIGNATURE_WORDS - 1 do
        signature[i] = memcard.load(i)
    end
end

function card_write_signature(signature)
    for i = 0, SIGNATURE_WORDS - 1 do
        memcard.save(signature[i], i)
    end
end

function card_signature_matches(expectedSignature)
    for i = 0, SIGNATURE_WORDS - 1 do
        if memcard.load(i) ~= expectedSignature[i] then
            return false
        end
    end

    return true
end

-- a card is "empty" if its (relocated) signature block is all zeroes
function card_is_empty()
    for i = 0, SIGNATURE_WORDS - 1 do
        if memcard.load(i) ~= 0 then
            return false
        end
    end

    return true
end
