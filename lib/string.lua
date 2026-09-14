-- char_helpers.lua
--
-- v32lua port of the character classification/conversion functions
-- from the Vircon32 C standard library's string.h. These fill a real
-- gap: v32lua's built-in string.* namespace (string.upper, .lower,
-- .find, .sub, etc.) operates on whole boxed strings, but has no
-- per-character-code predicates. These take a character CODE (an
-- integer, e.g. from string.byte(s, i)), exactly like the C originals
-- took an int -- not a one-character string.
--
-- Pure arithmetic and comparisons throughout, so unlike spu_helpers.lua
-- these need no ioports and no runtime CALL beyond ordinary codegen.
--
-- v32lua has no character-literal syntax ('x') -- the lexer only
-- recognizes double-quoted strings -- so every boundary below is
-- written as its numeric ASCII/Windows-1252 code, commented with the
-- character it represents.
--
-- Not ported: string.h's strchr/strstr, since the C header itself
-- leaves them unimplemented (just comments, no bodies). itoa/ftoa ARE
-- ported (bottom of file) as returning-string versions -- see their
-- section header for the buffer-pointer adaptation.

function isdigit(c)
    return c >= 48 and c <= 57  -- '0'-'9'
end

function isxdigit(c)
    if c >= 48 and c <= 57  then return true end  -- '0'-'9'
    if c >= 97 and c <= 102 then return true end  -- 'a'-'f'
    return c >= 65 and c <= 70                     -- 'A'-'F'
end

function isalpha(c)
    if c >= 97 and c <= 122 then return true end  -- 'a'-'z'
    return c >= 65 and c <= 90                      -- 'A'-'Z'
end

function isascii(c)
    return c >= 0 and c <= 127
end

function isalphanum(c)
    if c >= 48 and c <= 57  then return true end  -- '0'-'9'
    if c >= 97 and c <= 122 then return true end  -- 'a'-'z'
    return c >= 65 and c <= 90                      -- 'A'-'Z'
end

function islower(c)
    if c >= 97 and c <= 122 then return true end  -- standard ascii 'a'-'z'
    return c >= 224 and c <= 254 and c ~= 247       -- Windows-1252, excluding '÷'
end

function isupper(c)
    if c >= 65 and c <= 90 then return true end   -- standard ascii 'A'-'Z'
    return c >= 192 and c <= 222 and c ~= 215       -- Windows-1252, excluding '×'
end

function isspace(c)
    return c == 32 or c == 10 or c == 13 or c == 9  -- ' ', '\n', '\r', '\t'
end

function tolower(c)
    if not isupper(c) then return c end
    return c + 32
end

function toupper(c)
    if not islower(c) then return c end
    return c - 32
end

-- ---------------------------------------------------------------------------
--   STRING HANDLING FUNCTIONS
-- ---------------------------------------------------------------------------
--
-- v32lua strings are boxed, immutable Lua values, not null-terminated
-- int arrays -- so these three port over as genuine algorithms (via
-- string.len/string.byte), while the buffer-mutating half of string.h
-- (strcpy, strncpy, strcat, strncat) has no faithful target: there is
-- no destination buffer to write into. Where you'd have called those,
-- v32lua's native ".." concatenation and plain "=" assignment already
-- do the job more directly -- e.g. `buf = strcat_result .. suffix`
-- instead of `strcat(buf, suffix)`.

function strlen(text)
    return string.len(text)
end

-- Both of these are index-for-index translations of the C control
-- flow, treating "index past the string's length" as the implicit
-- null terminator (byte value 0) the C version walks off into.

function strcmp(text1, text2)
    local len1 = string.len(text1)
    local len2 = string.len(text2)
    local i = 1

    while i <= len1 and i <= len2 do
        local c1 = string.byte(text1, i)
        local c2 = string.byte(text2, i)

        if c1 ~= c2 then break end
        i = i + 1
    end

    local b1 = 0
    if i <= len1 then b1 = string.byte(text1, i) end

    local b2 = 0
    if i <= len2 then b2 = string.byte(text2, i) end

    return b1 - b2
end

function strncmp(text1, text2, maxCharacters)
    if maxCharacters < 1 then return 0 end

    local len1 = string.len(text1)
    local len2 = string.len(text2)
    local i = 1

    while i <= len1 and i <= len2 do
        -- check max characters before anything else, or we'd
        -- compare 1 too many -- same order as the C original
        maxCharacters = maxCharacters - 1
        if maxCharacters <= 0 then break end

        local c1 = string.byte(text1, i)
        local c2 = string.byte(text2, i)

        if c1 ~= c2 then break end
        i = i + 1
    end

    local b1 = 0
    if i <= len1 then b1 = string.byte(text1, i) end

    local b2 = 0
    if i <= len2 then b2 = string.byte(text2, i) end

    return b1 - b2
end

-- ---------------------------------------------------------------------------
--   STUBS: NOT PORTABLE, BUT PRESENT SO CALLS STILL COMPILE
-- ---------------------------------------------------------------------------
--
-- strcpy/strncpy/strcat/strncat all mutate a destination buffer in
-- place and return nothing -- there is no destination buffer in
-- v32lua's string model to mutate. These stand-ins exist only so a
-- ported call site still compiles and flags itself at runtime; each
-- one needs to be rewritten by hand as a plain "=" assignment or ".."
-- concatenation, which is what v32lua actually wants here.

function strcpy(destText, srcText)
    print(0, 0, "NOT IMPLEMENTED")
end

function strncpy(destText, srcText, maxCharacters)
    print(0, 0, "NOT IMPLEMENTED")
end

function strcat(initialText, addedText)
    print(0, 0, "NOT IMPLEMENTED")
end

function strncat(initialText, addedText, maxCharacters)
    print(0, 0, "NOT IMPLEMENTED")
end

-- ---------------------------------------------------------------------------
--   CONVERSION OF NUMBERS TO STRING
-- ---------------------------------------------------------------------------
--
-- Both of these RETURN their result instead of writing through the C
-- versions' result_text buffer pointer -- Lua strings are immutable
-- values, not writable int arrays, so there is nothing to write
-- through. Ported call sites need one small edit: capture the return
-- value where the C version later read its buffer back, e.g.
--     itoa( score, buffer, 10 )   -->   text = itoa( score, nil, 10 )
-- itoa keeps the C parameter positions (the unused buffer slot is
-- still argument 2), so a textually-ported call still hands its base
-- over correctly; the Lua-natural itoa(value, base) spelling is
-- accepted too.
--
-- CAVEAT: v32lua numbers are 32-bit floats with 24 mantissa bits, so
-- a few int32 values cannot be EXPRESSED as input in the first place
-- (0xFFFFFFFF as a positive literal reads as 2^32 before itoa ever
-- runs; pass such values as negatives, e.g. -1, which convert exactly
-- below). itoa itself is exact for every int32 input that arrives
-- exactly: its digit loop works on 16-bit halves, never on a quantity
-- float32 cannot hold. ftoa inherits the float32 precision of the
-- value it is handed, the same as the C original.

function itoa(value, result_text, base)
    -- also accept the Lua-natural spelling itoa(value, base)
    if base == nil and type(result_text) == "number" then
        base = result_text
    end

    -- do nothing if base is not in range [2-16], same as the C original
    if base == nil or base < 2 or base > 16 then
        return nil
    end

    local hex_characters = "0123456789ABCDEF"

    -- for base 10 numbers, prepend the sign if needed
    local is_negative = false
    if base == 10 and value < 0 then
        -- special treatment for -2147483648, kept from the C original:
        -- C has to write this one directly because its magnitude cannot
        -- be negated inside an int32. v32lua floats CAN hold it, and the
        -- halves arithmetic below would convert it exactly -- but the
        -- special case preserves the C version's structure and skips
        -- the loop for this single value.
        if value == -2147483648 then
            return "-2147483648"
        end

        is_negative = true
        value = -value
    end

    -- for every other base the C original treats the value as an
    -- unsigned 32-bit integer, using a two-part split only because C
    -- int32 cannot hold the magnitude. Floats can -- 2^31 is exactly
    -- representable -- so a plain value + 2^32 would seem to give the
    -- same unsigned reading, BUT the result rounds to a multiple of
    -- 256 near 2^32 (float32 has only 24 mantissa bits), silently
    -- corrupting the low digits: itoa(-1, nil, 16) would print
    -- "100000000" instead of "FFFFFFFF". So the unsigned reading is
    -- built as two's-complement arithmetic on 16-bit halves instead --
    -- every quantity below stays under 2^24 and therefore exact.
    local hi, lo

    if base ~= 10 and value < 0 then
        local m    = -value
        local m_hi = m // 65536
        local m_lo = m % 65536

        if m_lo == 0 then
            hi = 65536 - m_hi
            lo = 0
        else
            hi = 65536 - m_hi - 1
            lo = 65536 - m_lo
        end
    else
        hi = value // 65536
        lo = value % 65536
    end

    -- keep adding digits starting from the right. This is long
    -- division in the requested base on the 2-limb number hi*65536+lo;
    -- 'mid' stays under 2^21 and every other quantity under 2^24, so
    -- every operation is exact for any int32 input in any base --
    -- the float32 analog of the C original's careful int32 split.
    local result = ""
    repeat
        local mid = (hi % base) * 65536 + lo
        local digit = mid % base
        lo = mid // base
        hi = hi // base
        result = string.sub(hex_characters, digit + 1, digit + 1) .. result
    until hi <= 0 and lo <= 0

    -- now prepend the sign, if one was needed
    if is_negative then
        result = "-" .. result
    end

    return result
end

-- careful! no control of buffer length is done
-- (moot here: Lua strings grow on their own)
function ftoa(value, result_text)
    -- v32lua's string.format implements plain %.Nf through the same
    -- rounding ftoa pipeline the compiler uses elsewhere, so this
    -- reproduces the C original's shape directly: sign, integer part,
    -- '.', then a fraction of up to 5 digits. (One deliberate
    -- divergence: a fraction that rounds up to a whole unit carries
    -- into the integer part here -- e.g. 0.999999 -> "1" -- where the
    -- C original's separate decimal_part arithmetic instead produced
    -- the malformed "0.1".)
    local text = string.format("%.5f", value)

    -- remove rightmost decimal zeroes when needed. string.sub's
    -- negative indices give the same right-to-left trim the C version
    -- does (v32lua's string.gsub is plain-substring only, so there is
    -- no "0+$" pattern trick available instead)
    while string.sub(text, -1) == "0" do
        text = string.sub(text, 1, -2)
    end

    -- if the number was integer, drop the separator too, matching the
    -- C version's early exit -- the trim above never leaves a bare
    -- '.' behind it either
    if string.sub(text, -1) == "." then
        text = string.sub(text, 1, -2)
    end

    return text
end
