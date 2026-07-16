Current identified project tasks that need to be done:

  * calculate local variables in current scope, use to calculate stack space for storage
    * this may involve storing another variable in the as.function_def struct
  * leaf optimizations may need some work
  * runtime.s needs to be audited for destructive comparison data hazards
    * and general logic errors, especially `_to_string` and `_print`
  * reimplement peephole optimization
  * assemble DEVLOG
  * write some simple game in lua (snake?)
    * ideally write a C version for comparison
  * finish monolith.sh to process the .c files into `monolithic_program.c`

Seemingly quite close, these bugs both  familiar and perhaps not all that
big. Hopefully there's not something big lurking.
