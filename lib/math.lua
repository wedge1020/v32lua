-- math_compat.lua
--
-- v32lua's math.* namespace already implements everything in the
-- Vircon32 C standard library's math.h (and then some), just under
-- Lua-style dotted names (math.sin, math.floor, ...) instead of C's
-- bare ones (sin, floor, ...). If you're bringing over existing
-- Vircon32 C code, or just used to writing it that way, --#include
-- this file and keep calling them exactly as before.
--
-- These are pure passthroughs -- each one compiles to the same
-- intrinsic call math.foo(...) already would, just spelled the C way.
-- No new runtime cost beyond a CALL if the compiler doesn't fold it.

pi      = 3.1415926
INT_MIN = 0x80000000  -- careful, same as in the C header: parsers won't
                       -- take a bare "-2147483648" as one literal
INT_MAX = 2147483647

function fmod(x, y)   return math.fmod(x, y) end

function min(a, b)    return math.min(a, b) end
function max(a, b)    return math.max(a, b) end
function abs(a)       return math.abs(a) end

-- v32lua's numbers have no separate int/float register types the way
-- Vircon32 C does, so there's no behavioral difference between the
-- C header's integer min/max/abs and its float fmin/fmax/fabs -- these
-- three are the exact same intrinsics as above, just under their
-- float-flavored C names.
function fmin(x, y)   return math.min(x, y) end
function fmax(x, y)   return math.max(x, y) end
function fabs(x)      return math.abs(x) end

function floor(x)     return math.floor(x) end
function ceil(x)      return math.ceil(x) end
-- NOTE: math.h's round() has no v32lua equivalent (no math.round
-- intrinsic exists). floor(x + 0.5) is NOT a safe substitute -- it
-- diverges from the hardware ROUND instruction's behavior on negative
-- inputs -- so it's deliberately left out rather than guessed at.

function sin(angle)   return math.sin(angle) end
function cos(angle)   return math.cos(angle) end
function tan(angle)   return math.tan(angle) end
function asin(x)      return math.asin(x) end
function acos(x)      return math.acos(x) end
function atan2(y, x)  return math.atan2(y, x) end

function sqrt(x)      return math.sqrt(x) end
function pow(x, y)    return math.pow(x, y) end
function exp(x)       return math.exp(x) end
function log(x)       return math.log(x) end
