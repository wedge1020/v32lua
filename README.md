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

### assembly

Various test runs  have been performed to evaluate  the assembly language
generated. Currently  things are rather  heavily stack based,  `R0` being
heavily used.

I do want to try register allocation functionality in time.

### function return values

Lua functions  support multiple return  values. That should  currently be
implemented in my compiler. R0, R2, and R3 for the first 3 return values,
then any additional ones get placed on the stack.
