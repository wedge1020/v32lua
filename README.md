# v32lua

An attempt  at a  Vircon32-assembly targeting  lua compiler;  the current
focus is more on my personal  exploration of parsing, compilers, doing so
in C, and exploring various parsing  tools (in the vein of `lex`, `yacc`,
or in this case: `peg`/`leg`).

If  successful, this  will  allow  one to  take  `lua`  code and  compile
it  to  Vircon32 assembly,  to  be  inserted  into the  typical  Vircon32
cartridge-building pipeline  (just swapping out  the C compiler  for this
lua compiler).

NOTE: In  this project  I am  also actively making  use of  AI (currently
Google's  Gemini,  available  via   its  search  engine  interface).  I'm
basically making  queries and then going  on deep dives with  it. This is
partly to acclimate myself with AI output patterns.

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
