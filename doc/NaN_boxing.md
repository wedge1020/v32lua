# NaN boxing for fun and profit

The  NaN-boxing architecture  implemented in  the Vircon32  runtime takes
full advantage of  IEEE 754 floating-point mechanics to  pack data types,
memory addresses, and primitives into single 32-bit words.

---

## Overview of the Vircon32 NaN-Boxing Architecture

In standard  IEEE 754 single-precision floating-point  numbers, any value
where the 8-bit exponent field is  set entirely to `1`s (`0x7F800000`) is
treated  as  Not-a-Number (NaN)  or  infinity.  By  testing if  a  word's
exponent  bits equal  `0x7F800000`, the  runtime instantly  distinguishes
standard unboxed floating-point numbers from boxed Lua objects.

When a word is tagged as  NaN, the remaining lower 22 bits (`0x003FFFFF`)
act  as  the  payload.  This  22-bit  payload  conveniently  provides  an
addressable range of 4 Mega-Words  (4MW), which aligns perfectly with the
memory window  limits for both  RAM (`0x00000000` to `0x003FFFFF`)  and a
narrowed ROM addressing window (`0x20000000` to `0x203FFFFF`).

NOTE: This means that, depending on compensating schemes implemented:

**none**: the  current scheme. There  will be reduced effective  size for
CART ROMs,  or at least the  addresses where string and  function offsets
can reside. But also, short of  some really, really big game, this likely
won't  become an  issue. So  yes, this  means the  compiler will  produce
broken output should the start of  ROM functions and ROM strings exist in
the CART ROM beyond the first 4MW/16MB of space.

**near ROM  vs far ROM  string data**: a middle-ground  approach, getting
more mileage  out of  things but  still having that  size bound  that, if
crossed, will break things. Instead  of appending string constants at the
end of the  generated assembly, we could intentionally place  it near the
start of  the address space.  This would prioritize the  accessibility of
ROM string data potentially at the  cost of ROM function access using the
NaN-boxing scheme (as,  if the CART was big enough  to cause problems for
one, it likely would also cause problems for the other).

**trampolining**:  among  the  best  cases for  ensuring  maximum  string
and/or function  access in  the ROM. Here  we have  intentional, near-ROM
collections of  string and/or subroutine  starting points, each  of which
contains just an address/pointer to the actual data (which can then be in
far-ROM, not  impacted by the 22-bit  addressing NaN-boxing constraints).
This is sort  of like "compressing" our strings or  functions- instead of
needing to  deal with the sum  total of all the  string/function data, we
just deal with its starting address. That means we can pack more into our
limited space, further  reducing the likelihood of  exceeding our limited
22-bit addressing window.

## Detailed introduction to IEEE 754 NaN boxing

To implement  NaN boxing within  a standard 32-bit word  while respecting
IEEE  754 floating-point  mechanics, the  bits must  be partitioned  very
specifically:

| Bit Range | Field Name | Size    | Purpose in NaN Boxing              |
| --------- | ---------- | ------- | ---------------------------------- |
| **31**    | Sign Bit   | 1 bit   | RAM/ROM bit                        |
| **30–23** | Exponent   | 8 bits  | always/all 1s. A `NaN` in IEEE 754 |
| **22**    | quiet NaN  | 1 bit   | string/function mode bit           |
| **21–0**  | Payload    | 22 bits | addressable space (`0x003FFFFF`)   |

We  take  advantage  of  the  definition  of  what  constitutes  a  `NaN`
(not-a-number) designation in IEEE 754  floats (which is not one singular
bit pattern!)  As a  result, we  know that no  valid numerical  data will
occur in any 32-bit unit of float data. We will instead overload that for
our uses, hence the name "NaN boxing".

Since  we  cannot alter  those  8  exponent bits,  we  are  left with  24
remaining  bits to  effectively repurpose  for  our uses.  There are  two
competing  needs  here:  different  categories   of  data  we'd  like  to
encapsulate, and  in the  case of pointers/memory  addresses: addressable
range.

Since we'd  like to  get as much  mileage as possible  out of  our memory
resources, we look at the constraints of RAM and CART ROM:

| Page     | Starting Address | Ending Address | Capacity    | Type       |
| -------- | ---------------- | -------------- | ----------- | ---------- |
| RAM      | `0x00000000`     | `0x003FFFFF`   | 4MW/16MB    | Read/Write |
| CART ROM | `0x20000000`     | `0x27FFFFFF`   | 128MW/512MB | Read Only  |

If we limit our types of data  to just strings and functions (1 bit), and
use  the other  available bit  as a  RAM/ROM selector,  we are  left with
22-bits to use for memory addressing.

As  it turns  out  (sheer coincidence/luck?)  22-bits represents  exactly
4194304 addressable  values. Since  Vircon32 uses  word-based addressing,
that  is a  1:1 match  with  our RAM  capacity. Meaning:  our NaN  boxing
scheme's MAXIMUM addressable range,  if we use only 2 of  our 24 bits for
mode selections, happens to fully cover our RAM address space.

This  is obviously  fantastic for  RAM transactions.  CART ROM's  address
range is far too massive to fully  fit within our NaN-boxing scheme, so a
sacrifice is  being made: only  allow accesses  to the first  4MW/16MB of
CART ROM using  this scheme. This does put certain  hard limits on usable
CART  size (ie  16MB for  the binary  code section),  but one  that seems
reasonable.  Not  to mention,  there  are  strategies for  extending  our
mileage  with respect  to this  limit. That  is to  say: it  is a  limit,
restricting our full access, but have  we regularly hit this limit in any
sort of regular basis (if at all).

And note:  that CART  ROM limit  is on the  code/data, NOT  the VTEX/VSND
resources. They aren't impacted by this in the slightest.

The **quiet NaN  flag** is typically set  to `1` to create  a "quiet NaN"
(qNaN), preventing hardware FPU exceptions.

Because the IEEE 754 standard strictly requires all 8 exponent bits to be
set to `1`  to represent a NaN,  you are permanently stripped  of those 8
bits right out of the gate. That leaves only 24 bits total for everything
else (the sign bit, quiet/signaling flags, and the payload).

If you attempted to pack a **27-bit  ROM offset** into the word (the full
address range  of a Vircon32 CART  ROM), 27 address bits  plus 8 exponent
bits would demand 35 bits—completely overflowing a 32-bit register!

## The Real Maximum Bounds in Vircon32

In the Vircon32  architecture, the CPU is a 32-bit  processor with native
floating-point  support. When  boxing  pointers into  32-bit floats,  the
maximum  addressable payload  for *both*  RAM  and ROM  is strictly  **22
bits**:

**22-Bit Payload  Limit:** Bits  0 through 21  provide a  maximum integer
value  of `0x003FFFFF`.  This gives  an  addressable range  of exactly  4
Mega-Words (4MW, aka 16MB).

**ROM Memory Mapping:** While physical  Vircon32 hardware maps ROM into a
higher memory  page starting at  `0x20000000`, that full  32-bit hardware
address is never stored inside the NaN box itself.

**Runtime Reconstruction:** Instead, the  compiler stores only a **22-bit
offset** inside  the NaN payload. When  the runtime unboxes a  ROM string
literal (tag  `0x7FC00000`), it strips  the upper tag  (`AND 0x003FFFFF`)
and then bitwise-ORs the result with  the ROM page base (`OR 0x20000000`)
to reconstruct the ROM hardware address  on the fly (letting us work with
the first 4MW/16MB of CART ROM data).

## Supported Tags & Type Representations

The compiler  uses specific bit  patterns in  the upper byte/tag  mask to
categorize values  while preserving  the lower 22  bits for  addresses or
primitive identifiers:

| Type                 | Tag Mask     | Payload Meaning | Description                  |
| -------------------- | ------------ | --------------- | ---------------------------- |
| **Float**            | none         | unboxed float   | standard 32-bit float        |
| **Table**            | `0x7F800000` | RAM data offset | pointer to table structures  |
| **ROM String**       | `0x7FC00000` | ROM offset      | string data in CART ROM      |
| **RAM String**       | `0xFFC00000` | RAM offset      | malloc'ed string data in RAM |
| **Function Pointer** | `0xFF800000` | ROM code offset | function addresses in ROM    |
| **Nil**              | `0xFFC00000` | `0x0`           | The canonical Lua `nil`      |
| **False**            | `0xFFC00001` | `0x1`           | Boolean `false`              |
| **True**             | `0xFFC00002` | `0x2`           | Boolean `true`               |

As `0x7F800000`  contains set bits across  ALL the tags, and  in IEEE 754
represents  a  NaN value,  simply  bitwise  AND'ing `0x7F800000`  by  the
payload and  getting a  result of `0x00000000`  indicates we  are dealing
with a standard  floating point number (and we can  then skip any further
determination of what sort of boxed NaN value we are dealing with).

The **RAM  String** payload is  being overloaded: the  lowest-most values
are reserved for  things like nil and the booleans,  likely a `TOMBSTONE`
value  for eventually  memory  freeing functionality.  This sacrifice  is
small in the grand scheme of things,  and works around the limited set of
broad NaN-type categories only have two mode bits to work with.

The "payload" is  either a 22-bit memory address (covering  either ALL of
RAM, or the  lowest 4MW/16MB of the  CART ROM address space),  or used to
indicate the Lua `nil`, `false`, or `true` values.

---

## Usage Scenarios & Runtime Mechanics

### RAM vs. ROM String Handling (bit 31)

To differentiate between strings located  in dynamic RAM versus immutable
cartridge ROM,  the runtime inspects Bit  31 of the boxed  pointer inside
the `__unbox_string` routine.

If Bit 31 is set to `1` (as seen in tag `0xFFC0xxxx`), the string resides
in RAM. Stripping  the tag with `AND 0x003FFFFF` yields  the raw hardware
heap address directly within the 4MW RAM limit.

If  Bit  31  is  `0`  (as  seen   in  tag  `0x7FC0xxxx`),  it  is  a  ROM
string  literal. The  runtime strips  the  tag and  applies the  Vircon32
cartridge   page  bit   (`OR   0x20000000`)  to   properly  address   the
`0x20000000-0x203FFFFF` ROM memory space.

### Function Calling & Execution (bit 22)

When  executing  a  boxed  function  pointer  via  `__builtin_exec`,  the
compiler isolates the upper bits with `AND 0xFF800000` and validates that
they match the function tag `0xFF800000`.

If validation succeeds, the runtime strips the NaN tag (`AND 0x003FFFFF`)
and  restores the  Vircon32 code  memory  page bit  (`OR 0x20000000`)  to
reconstruct the true hardware ROM address.

Rather than issuing a standard call,  it executes a direct tail-call jump
(`JMP R0`), allowing the target  function's eventual `RET` instruction to
return cleanly to the original caller.

### Coexistence of Primitives and RAM Strings

Because `nil`, `false`, `true`, and RAM Heap Strings share the exact same
upper  tag mask  (`0xFFC00000`),  the runtime  separates primitives  from
memory pointers by inspecting the value of the 22-bit payload.

Any payload value $<  4$ is treated as a primitive  boolean or nil (e.g.,
during  string  coercion in  `__print_check_tag`  or  equality checks  in
`__builtin_eq`).

Payload values $\ge 4$ are guaranteed  to represent valid RAM heap string
addresses,  as the  memory allocator  maps heap  allocations above  those
reserved low primitive values.

### Fast-Path Table Operations & Indexing

During     table     reads     (`__builtin_table_get`)     and     writes
(`__builtin_table_set`),  zero-cost  bitwise  checks  immediately  detect
whether an index key is a NaN-boxed object or an unboxed float by testing
`AND 0x7F800000`.

If the  key is  an unboxed  float that represents  an integer  within the
table's active array capacity, the  runtime bypasses association list and
hash bucket scans entirely.

It converts the 1-based Lua index to a 0-based memory offset and performs
an O(1) contiguous  array memory read or write directly  against the heap
buffer.
