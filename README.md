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

I chose lua as a target for my compiler efforts (in this iteration) for a
couple reasons:

  - generally perceived as a lower-cost-of-entry language, making it more
    accessible to a broader audience
  - my experiences on TIC80 using lua seems like a neat parallel to draw
  - perhaps it is just a coincidence, but many other fantasy consoles use
    lua as their main coding language, so perhaps this will contribute to
    Vircon32's accessibility by the broader fantasy console audience

As I occasionally find myself doing Computer Science outreach events, and
during such I  end up using TIC80  to walk a group through  a quick demo,
this would have the potential of being a drop-in replacement.

More to come  once I attempt to  put together the various  pieces and see
just how much more the AI has hallucinated than I realized.

This has been a very rewarding, fun, and insightful experience. I've been
wanting to attempt my own compiler (but TIME!); it is great to see all my
reading paying off. I am also impressed  that I've been able to work with
AI to actually produce something functional so quickly.

I  do feel  that I  have to  say that  I did  not exclusively  write this
compiler:  AI use  was extensive.  I  was more  a senior  dev /  manager,
letting  AI do  all the  running  around and  grunt-work. I  even let  it
propose and present ideas to me that I signed off on or gave direction. A
different role  than I usually have  played in my development  efforts. I
certainly have been in and out of the code, implementing various features
and edge cases  that I didn't want  to bother having AI  refactor code on
and potentially drop  context and break what previously  worked (that did
happen on more than  one occasion). But I must say I  am impressed that I
was able  to use this  new tool to accomplish  a task within  a timeframe
previously unthoughtof.

Simultaneously,  I  also don't  feel  as  if  I've  NOT been  heavily  or
centrally involved  or NOT  engaged with the  creation of  this compiler.
Perhaps that is adding to  the inspiration: development is happening, I'm
just not  on the groundlevel curating  all the foundational details  as I
usually do. That is different, unfamiliar, but also not unwelcome.

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

There are various testing programs available, run `make tests` to compile
them (with the lua compiler!)

An extra check: "will it actually  assemble?" can be performed by running
`make asmcheck`.

## lua compiler

I  am pleased  to report  that  some good  progress has  been made.  This
endeavour  seems to  work better  as a  partnership with  AI rather  than
viewing it merely as a tool.

I have a working program. It  takes lua source and spits out increasingly
capable Vircon32 assembly on the  other side, including Vircon32 assembly
that the official assembler can assemble to VBIN format!

Currently  working  on  many   language  basics:  declaring  and  setting
variables,  dealing  with  global  vs local  (lookup  and  whatnot).  The
inimitable `if`  statement and  variations, `while` loop,  and functions.
Quite impressively, I  not only got `lua` tables going,  but seem to have
functions  as a  first class  citizen, allowing  some manner  of OOP-like
transactions to happen (I basically have function pointers).

There are many things still missing. Probably even many basic things (for
loops are  not yet  implemented, for  instance). At  this point  in time,
consider this a  technical demo. Functional within the  domain of support
that  exists. I  certainly have  targeted features  that should  enable a
simple pong-like or snake-like game to be possible.

A nice feature  I quite enjoy is  how I integrated the  IOPorts into lua,
via  function  and variable  intrinsics.  You  have this  namespace  with
various values  hanging off of it.  The compiler checks for  these values
and drops in the corresponding assembly language.

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
  * CART hints (compiler will produce an XML file)
    * `--#title "V32 CART TITLE"`
    * `--#texture background background.png`
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
    * takes x and y value as first two arguments
    * basic output
  * IOPorts and related built-in functions / tables:
    * ioports.gpu.texture - treat as a variable you can read and write to, will transact GPU_SelectedTexture
      * tested and works
    * ioports.gpu.clear() - pass in a color to clear the screen (or empty will use current GPU_ClearColor)
    * the full gamut of INP ports, and additional GPU ports to basically allow for sprites and screen drawing

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
