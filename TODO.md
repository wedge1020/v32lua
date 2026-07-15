Current identified project tasks that need to be done:

  * runtime.s needs to be audited for destructive comparison data hazards
    * and general logic errors, especially `_to_string` and `_print`
  * reimplement peephole optimization
  * global variable memory map a '`next_ram_address`' kludge needs proper fixing
    * currently adding 2 to make it work for digdug, but testing/ programs do not have the problem
  * assemble DEVLOG
  * write some simple game in lua (snake?)
    * ideally write a C version for comparison
  * finish monolith.sh to process the .c files into `monolithic_program.c`

Seemingly quite close, these bugs both  familiar and perhaps not all that
big. Hopefully there's not something big lurking.
