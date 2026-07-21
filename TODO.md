Current identified project tasks that need to be done:

  * compiler optimizations all need to be tested
    * an earlier quick test did prove things got broken
    * some `constant folding` is now working (but needs to be wrapped in `o_optflag`)
  * `ioports.gpu.draw()` intrinsic likely still needs work
  * chase down potential bug with table methods (undraw() method for enemies in blang)
  * verify non-string data can be processed by `print()`
    * I attempted to `print()` a number, got a nil and blue screen. So no, not yet working
  * with `hex()` working, implement bitwise logic
  * consider an `int()` for similar applications
  * do we have a `.tostring()` ? might be worth considering
  * V32FFI!
  * table logic hardening and testing
  * explore some sort of `.free()` intrinsic to use with tables
  * test, test, test (digdug demo still doesn't work)
  * finish **blang!** demo
  * assemble DEVLOG
