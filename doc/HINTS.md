# Compiler hints and source markers v32lua writes

v32lua writes `;@` comment lines in its assembly for `v32opt` (optimization facts) and for
debuggers (source locations). They are comments: the assembled cartridge is identical with
or without them (`tests/audit/hints/check_hints.py` checks this). `--no-hints` leaves out
the optimizer hints; the source markers are written only with `-g`.
The optimizer hints are `v32opt`'s `doc/hints.md`; the debug markers (`;@src`, `;@var`,
`;@scope`) are the V32DBG spec, which is kept with `v32sim` (`docs/V32DBG-SPEC.md`). A tool
ignores any `;@` line it does not know.

| Line | Written | Meaning |
|---|---|---|
| `;@hints 1 abi=caller-save lang=lua` | once, at the top | v32opt's header. `lang=lua` is new (ignored by older v32opt) |
| `;@fn __function_f escapes=none` | after each function | nothing in the function took a frame address (no `LEA`, no copy of `BP` into an operand; `MOV SP, BP` of the epilogue does not count). Functions that copy `BP` (those using `...`) get no line |
| `;@fn __function_f returns=N` | after each function whose body has no inline assembly and no `return f(...)` or `return ...` | no `return` of the function produces more than N values (a bare `return` and falling off the end are 0). Callers read R2/R3 only after checking `[RET_COUNT]`, so with N <= 1 nothing reads them after the `RET` |
| `;@fn LABEL clobbers=R0,R6-R13` | directly above the label of a runtime routine | registers the routine or anything it calls may change (see below) |
| `;@loop kind=for counter=-9 limit=-7 step=-8 [stepval=K] [from=A to=B]` | before the start label of a numeric `for` | the three hidden frame words (BP-relative), and the integer constants when known (`-1` is a constant: `stepval=-1`). Facts: the body never writes them, limit and step are written once before the loop |
| `;@cold` | before the label of a slow-path block | rarely taken. Today the table index slow path (`__F_idx_slow_N`) |
| `;@cold {` ... `;@cold }` | around the `__arith_coerce` call | an inline block (the code falls into it) that is rarely run: an operand that is not a number |
| `;@var NAME loc=BP-3 type=lua [boxed]` (`-g`) | where a local or parameter is registered | the variable's frame word (`BP-n` local, `BP+n` parameter); `boxed`: the word holds a box pointer (captured by a closure), not the value. Compiler temporaries (`__...`) are not listed. In the main chunk (`__global_scope_initialization`) the locals of nested blocks are listed; a chunk-level `local` lives in a RAM word (`var_NAME`), not a frame slot, and is listed with the globals (next row) |
| `;@var NAME loc=BP+N type=lua boxed upvalue` (`-g`) | inside a closure, where the captured variable arrives | the hidden leading parameter that holds the box shared with the enclosing function (always `boxed`; a debugger follows the box); the enclosing function lists the same variable as an ordinary `boxed` local |
| `;@var NAME loc=@0xADDR type=lua global` (`-g`) | once per global and per chunk-level `local`, before the code | the RAM word (the `%define var_NAME` address). A chunk-level `local` is a global RAM word, so the two are not told apart; `type=lua` because a global can hold any value. Functions (`func_NAME`) and `__` names are not listed |
| `;@scope {` / `;@scope }` (`-g`) | around each block | lexical scope, so a debugger shows the variables in scope at a line. A function's own scope has no braces. The main chunk's blocks are bracketed too |
| `;@src FILE:LINE` (`-g`) | before the first instruction of each source line | the following instructions come from that line |
| `;@src -` (`-g`) | before the runtime, startup and global setup | no Lua source |

## `-g`

`v32lua -g x.lua -o x.asm` writes `x.asm` with the `;@src` markers and `x.asm.debug`
(`asmfile,asmline,luafile,lualine,function`, one entry per change of line or function, the function on every row; code outside any function, such as the main chunk and the start-up code, is `__chunk`; made from
the markers in the finished file so the line numbers are exact). Then
`v32as -g --map x.asm.debug x.asm` writes the address -> Lua line file that `v32sim` reads.
The old map was estimated while generating and was wrong (an entry said line 32720; about 11
entries for an 11,000-line program); the AST also had nodes with no line number
(`make_node_*` used `malloc`), which is fixed.

A compound statement (`for`, `while`, `if`, `do`, `function`) is attributed to its header
line for the first instructions and the loop's test and increment; the body's statements
have their own lines. The first instructions of a function are attributed to its first body
line, not the `function` line (the parser knows only where the statement ended).

## `clobbers=` on the runtime helpers

`;@fn LABEL clobbers=R0,R6-R13` is written above the label of each runtime routine in the
output that `tools/check_clobbers.py` could analyse (217 of 237). The list is every register
the routine or anything it calls may change at `RET` (saved-and-restored ones are not
listed; `SP`/`BP` never are). The table is `src/runtime_clobbers.h`, generated by

    python3 tools/check_clobbers.py --write      # regenerate after editing src/runtime/*.s
    python3 tools/check_clobbers.py --check      # what the test runs; -v for the reasons

`--check` fails when the header is stale. The tool also compares each routine with the
`Clobbers:` / `Preserves` line in its comment and prints the differences (the comments of
the table routines were wrong and are fixed; remaining differences are results in R0/R1
that a comment calls "output" rather than "clobbered").

## `var=` on `;@loop`

The numeric `for` keeps the visible variable (`i`) in its own frame word and copies the hidden counter into it at
the top of every iteration (so an assignment to `i` in the body cannot change the loop). `var=N` names that word; it is written after `step=N` and before `stepval=`, e.g. `;@loop kind=for counter=-4 limit=-2 step=-3 var=-5 stepval=1 from=1 to=10`.
It means: **between the loop's start label and its end label the word holds a copy of the counter**: it is
stored with the start value before the loop and with the counter at the top of each iteration, and nothing else
writes it. It is written only when v32lua can see that: the body has no assignment to a variable of that name
(a nested block, a shadowing `local i` and a nested loop on `i` all count), no closure captured the variable (it
would hold a box pointer, not the value), the body has no inline assembly, and the function is not variadic (it
copies `BP`). Otherwise the attribute is left out. Nothing is promised after the end label: the word is free for
the next local of the enclosing block, and the variable is out of scope there. An older `v32opt` skips the
attribute and keeps the rest of the line.

## Contract

* Every `;@` line is a comment. The instructions are the same with and without them
  (`--no-hints` removes the optimizer hints; without `-g` there are no debug markers). A test
  checks this.
* A hint is a fact about the code as v32lua wrote it, never a request. If a pass changes the
  code so a fact no longer holds, the pass must drop or fix the hint (`escapes=none` after
  introducing a `LEA`, `loc=` after promoting a slot to a register).
* Versioning: the number in `;@hints 1 ...` changes only when the meaning of an existing line
  changes. New lines and new `key=value` attributes do not bump it; a reader ignores lines and
  attributes it does not know.
* `clobbers=` is regenerated from the runtime source by `check_clobbers.py`; a routine it
  cannot analyse has no hint, which means "may clobber anything".

## Stock C compiler output

The stock `compile -g` writes a side file whose line numbers drift inside functions that save
registers. `v32srcmark.py`, hosted with `v32opt` (`scripts/`), reads `prog.asm` and
`prog.asm.debug`, writes `;@src` lines and an exact `prog.asm.debug`. It is not part of
v32lua and has nothing to do with Lua programs. Stock C gets lines and functions, no locals.

## Still to do in v32lua

* `;@loop` for `while`, `repeat` and generic `for`.
* `;@fn __function_f lines=A..B`.
* `clobbers=` for the 23 routines the checker cannot analyse (printing and formatting,
  `__builtin_len`, the memcard helpers, `__builtin_exec`, the `__shapes_init` callers,
  `__pico8_add`'s conditional tail call).

Waiting on other tools: `v32opt` carrying `;@src` through its passes and using `;@cold {}` and
`clobbers=`; `v32as -g` reading the markers; `v32sim` showing Lua lines and locals.
