# v32lua

An attempt  at a  Vircon32-assembly targeting  lua compiler;  the current
focus is more on my personal  exploration of parsing, compilers, doing so
in C, and exploring various parsing tools: in the vein of `lex`, `yacc` -
I am  currently utilizing  `flex` and  `bison` to  handle the  lexing and
parsing for this endeavour.

If  successful, this  will  allow  one to  take  `lua`  code and  compile
it  to  Vircon32 assembly,  to  be  inserted  into the  typical  Vircon32
cartridge-building pipeline  (just swapping out  the C compiler  for this
lua compiler).

NOTE: In  this project  I am  also actively making  use of  AI (currently
Google's Gemini  (Thinking and Pro- Flash  doesn't seem up to  the task),
available via  its search  engine and  gemini interfaces).  I'm basically
making queries and  then going on deep  dives with it. This  is partly to
acclimate myself with AI output patterns.

I can't  say I'm too  surprised, beyond the  fact that since  I attempted
some efforts  over the past few  years, at least at  present, Google's AI
seems  to be  maintaining context  for me  a heck  of a  lot better  than
AI's  I've interacted  with  in the  past. That  is  allowing for  longer
interactions, where it remembers my constraints over time.

It has certainly hallucinated, a  ton. While it demonstrates an awareness
of Vircon32 and  its ecosystem, it also liberally  dishes out assumptions
that just  aren't true (it  has called the  Vircon32 assembler by  half a
dozen different  names since starting,  for instance), and while  it gets
many assembly instructions correct, it also catastrophically falls short,
especially in  relation to  comparisons. Since  I know  Vircon32 assembly
rather well, that isn't a problem: I didn't want AI to write the assembly
for me anyway, just help me bounce some ideas to code off it with respect
to compiler logic.

I chose lua as a target for my compiler efforts (in this iteration) for a
couple reasons:

  - generally perceived as a lower-cost-of-entry language, making it more
    accessible to a broader audience
  - my experiences on TIC80 using lua seems like a neat parallel to draw

As I occasionally find myself doing Computer Science outreach events, and
during such I  end up using TIC80  to walk a group through  a quick demo,
this would have the potential of being a drop-in replacement.

More to come  once I attempt to  put together the various  pieces and see
just how much more the AI has hallucinated than I realized.

This has been a very rewarding, fun, and insightful experience. I've been
wanting to attempt my own compiler (but TIME!); it is great to see all my
reading paying off. I am also impressed  that I've been able to work with
AI to actually produce something functional. I do feel that I have to say
that I  did not write this  compiler: AI did. I  was more a senior  dev /
manager, letting AI do all the  running around and grunt-work. I even let
it  propose  and present  ideas  to  me that  I  signed  off on  or  gave
direction. A different role than I  usually have played in my development
efforts.

Simultaneously, I  also don't feel  as if I've  NOT been involved  or NOT
engaged with the creation of this compiler. Perhaps that is adding to the
inspiration: development  is happening, I'm  just not on  the groundlevel
curating all the foundational details as I usually do. That is different,
unfamiliar, but also not unwelcome.

Interested in seeing this journey continue.

## dependencies

Currently, the dependencies are few:

  * C99 compatible C compiler
  * GNU make
  * flex
  * bison

Primary  development environment  is Linux,  so there  may be  unexpected
issues on Windows or macOS- both will need testing at some point.

## building

To build this compiler, go into the `src/` directory and run `make`.

The usual `make clean` is also available.

Compiled binary  will be stored  in the `bin/`  directory at the  base of
this repository.

## lua compiler

I  am pleased  to report  that  some good  progress has  been made.  This
endeavour  seems to  work better  as  a partnership.  The AI  can NOT  be
trusted  to manage  things  on its  own, yet,  when  given direction  and
preference, seems  to be  handle task  to task  well. Over  time, context
slips a bit  and it tries to rename  things on me, so one has  to stay on
top of that.

But:  I  have a  working  program.  It takes  lua  source  and spits  out
increasingly  capable  Vircon32 assembly  on  the  other side,  including
Vircon32  assembly  that the  official  assembler  can assemble  to  VBIN
format!

Currently  working  on  many   language  basics:  declaring  and  setting
variables,  dealing  with  global  vs local  (lookup  and  whatnot).  The
inimitable `if`  statement and  variations, `while` loop,  and functions.
Quite impressively, I  not only got `lua` tables going,  but seem to have
functions  as a  first class  citizen, allowing  some manner  of OOP-like
transactions to happen (I basically have function pointers).

There are many things still missing.  Just today I realized I hadn't even
gotten around  to basic  arithmetic ('+'  now works, but  it is  the only
thing that is hooked up).

Absolutely no IOPort stuff has yet  been implemented (although I am eager
to explore the implementation).

### operational features

At this  point, the following lua  functionality should be online  in the
compiler:

  * functions
    * declarations (parameterless, parametered)
    * calls (including return values)
  * variables (of which functions are technically a type of in lua)
    * declarations, initializations, manipulations
      * basic math operations should be available
    * `local` keyword is available, and the compiler understands
      local vs global scope (global is the default, as per lua)
    * floats most tested, strings coming online (not fully complete)
  * if statements and their variants
    * if
    * if else
    * if elseif
    * if elseif else
    * although, may only currently work for floats
  * while loops
    * may only work for floats at present
  * tables
    * initialization, construction
    * floats, functions, even possibly strings
    * accessing members via `.`, `:`, and `[`/`]` notations
  * comments
    * `--` standard one-line lua comment
    * `--[[` through `--]]` standard multi-line lua comment
    * `--@` transpositional single comment (pass comment through to assembly output)
    * `--@[[` through `--]]` transpositional multi-line comment
  * inline assembly (two variants):
    * `__asm__("newline-delimited list of instructions")`
      * this is a "safe mode" or "bubble" inline assembly, where the full register array
        is preserved, then restored on exit.
    * `__rawasm__("newline-delimited list of instructions")`
      * this is a pure in-line assembly, nothing backed up, you have full control
      * this is similar to the Vircon32 C compiler inline assembly`
    * both should support lua variable referencing via `{`/`}`
      * although, still needs to be tested
  * `print()` built-in function
    * basic output
    * buffers up to 16 lines to display on the screen
    * still needs work (does not currently display)
  * IOPorts and related built-in functions / tables:
    * ioports.gpu.texture - treat as a variable you can read and write to, will transact GPU_SelectedTexture
      * tested and works
    * ioports.gpu.clear() - pass in a color to clear the screen (or empty will use current GPU_ClearColor)

## NaN-boxing scheme

I found this fascinating: apparently  there's a bithack involving various
bit patterns  of float  "NaN"s which  we can take  advantage of  to store
other important data. In this case: data type information.

When writing the assembly, the use of these base bitmasks to assemble and
disassemble values using `AND` and `OR` instructions:

| Base NaN Mask | 0x7F800000 | Exponent all 1s, everything else 0 |
| String Tag Mask | 0x00400000 | Sets Bit 22 |
| Function Tag Mask | 0x80000000 | Sets Bit 31 |
| Special Tag Mask | 0x80400000 | Sets Bit 31 and Bit 22 |
| Payload Extraction Mask | 0x003FFFFF | Isolates the 22-bit pointer |

### "NaN-Boxing" (The High-Performance Way)

This is a  famous trick used by heavily optimized  dynamic languages like
JavaScript  (SpiderMonkey) and  Lua (LuaJIT).  It exploits  the IEEE  754
32-bit floating-point format.

A  standard float  uses a  sign  bit, 8  exponent bits,  and 23  fraction
(mantissa) bits.

If the exponent bits are all 1s, the hardware considers it "Not a Number"
(NaN).

Because there are  millions of possible bit combinations  that equal NaN,
we can hide  our Type Tags and  our Memory Pointers inside  the 23 unused
fraction bits of a NaN value.

How it changes the compiler:

Variables remain exactly  1 word wide, meaning the [BP  - offset] logic,
register allocator, and global RAM mapping stay completely intact.

Whenever  a string  pointer is  loaded,  bitwise instructions  to OR  the
pointer  are emitted  with a  specific NaN  bitmask (e.g.,  `0x7F800000 |
(TAG_STRING << 20) | Pointer`).

To check a type, use bitwise AND masks to extract the tag.

The 4MW NaN-Box Layout

In  a standard  32-bit IEEE  754 float,  to trigger  a NaN  state, the  8
exponent bits (bits 30–23) must be  all 1s. That leaves us with exactly
24 bits to play with:

| Bit 31 | The Sign bit |
| Bits 22–0 | The 23 mantissa (fraction) bits |

For the Vircon32 environment 22 bits  are needed to cover the 4MW pointer
payload (Bits  21–0), leaving exactly 2  bits for our Type  Tag (Bit 31
and Bit 22).  Two bits give exactly 4 distinct  Boxed Types, which covers
the dynamic types Lua needs perfectly:

| Tag Layout (Bit 31, Bit 22) |    Type | Payload (Bits 21-0) |
| 0, 0 | Table    | 22-bit RAM Pointer |
| 0, 1 | String   | 22-bit RAM Pointer |
| 1, 0 | Function | 22-bit RAM Pointer / Code Address |
| 1, 1 | Special  |  0 = Nil, 1 = False, 2 = True |


### IOPorts in lua: an idea

I  think  what  I might  want  to  do  is  to create  (on  initialization
bootstrap- external of any user-supplied  code), a lua table that creates
an  IOPort structure,  with the  necessary fiddling  to make  the various
`IN`s and `OUT`s happen.

I am envisioning either:

  * ioports base table
    * tim, rng, gpu, spu, inp, car, and mem sub-table
      * variables and functions within each

or:

  * drop the `ioports` base table

So,     potentially:     `ioports.gpu.xpos`    or     `gpu.xpos`     (for
`GPU_DrawingPointX`), which  can be read or  written to in the  usual lua
manners.

### main() function

The compiler  expects there to be  a main() function, and  quite notably,
main()  is a  "magical" function,  in that  it will  automatically repeat
itself (after  a `WAIT` is  issued). This is intended  to be akin  to the
`TIC()` function in TIC-80.

### produced assembly

Various test runs  have been performed to evaluate  the assembly language
generated. Currently  things are rather  heavily stack based,  `R0` being
heavily used.

I do want to try register allocation functionality in time.

### inline assembly

For convenience, this lua compiler supports inline assembly, in a fashion
similar to that of the official Vircon32 C compiler.

In fact, there are TWO inline assembly variants:

  * `__asm__` - preserves register states around inline asm "bubble"
  * `__rawasm__` - does not preserve register states (dangerous)

To use either, simply  embed it in your lua code as  you would a function
call:

```
    ___asm___("
        MOV   R4, {value}
        IADD  R4, 14"
        MOV   {value}, R4
    ")
```

You can embed  assembly comments, labels, etc. And yes,  it even supports
the use of curly braces around lua variables.

The intention is that, if you need  to do something quick, like an IOPort
transaction, you  can use the  relatively "safe" inline assembly  to pull
that off.

If  instead  you  are  doing   something  more  involved  (like  manually
manipulating the  stack), you need  any and all protections  removed, and
the **___rawasm___** inline variant is available for those scenarios.

Furthermore, to improve safety (whenever  you have access to assembly you
can  always cause  damage  if  you're not  careful),  the "safer"  inline
assembly variant (`___asm___`) will back up the entire register inventory
to memory,  and restoring it  when done. So even  if one messes  with the
stack pointers  or the  stack, at  least those  registers will  revert to
their previous states upon exiting the safer inline asm bubble.

### commenting plus documenting

This lua compiler supports both the single and multi-line comment styles,
and with the addition of an `@` to the opening comment symbol, will cause
the entirety of the lua comment to be transposed as assembly comments.

```
    --@ check for collisions
```

will show up in place on the generated assembly:

```
;; lua comment: check for collisions
```

The `--@[[`  through `]]`  will do the  same pass-through  for multi-line
comments.

### function return values

Lua functions  support multiple return  values. That should  currently be
implemented in my compiler. R0, R2, and R3 for the first 3 return values,
then any additional ones get placed on the stack.

### compiler error reporting

There is a minimal, but evolving  error reporting ability in place. There
are  4 categories  of  error: LEXICAL,  SYNTAX,  SEMANTIC, and  INTERNAL.
Associated line numbers and actual  line of content, as appropriate, will
be displayed on any error.

Processing proceeds to the first encountered error, then forcibly exits.
