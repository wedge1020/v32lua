Current identified project tasks that need to be done:

  * leaf optimizations may need some work
  * runtime.s needs to be audited for destructive comparison data hazards
    * and general logic errors, especially `_to_string` and `_print`
  * reimplement peephole optimization
  * assemble DEVLOG
  * update README files

Seemingly quite close, these bugs both  familiar and perhaps not all that
big. Hopefully there's not something big lurking.
