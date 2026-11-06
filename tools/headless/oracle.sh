# oracle.sh -- sourced by runlua and trap: finds v32sim's headless runner and the stock assembler.
#   V32ORUN   v32orun (tools/oracle/bin of a v32sim tree built with `make oracle COMPUTERSOFTWARE=...`)
#   V32ASM    the stock `assemble` built beside it
# Looked for, in this order: $V32ORUN / $V32ASM, $V32SIM_HOME/tools/oracle/bin, ~/share/v32sim/tools/oracle/bin,
# /usr/local/share/v32sim/tools/oracle/bin, a v32sim checkout next to this one, then $PATH.
# v32lua does not carry a runner of its own: v32sim is the one place that tests, profiles and runs carts headless.
_oh=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -z "$V32ORUN" ] || [ ! -x "$V32ORUN" ]; then
  V32ORUN=
  for _c in "${V32SIM_HOME:+$V32SIM_HOME/tools/oracle/bin}" "$HOME/share/v32sim/tools/oracle/bin" \
            /usr/local/share/v32sim/tools/oracle/bin "$_oh"/../../../v32sim*/tools/oracle/bin; do
    [ -n "$_c" ] && [ -x "$_c/v32orun" ] && { V32ORUN=$_c/v32orun; break; }
  done
  [ -z "$V32ORUN" ] && V32ORUN=$(command -v v32orun)
fi
if [ -z "$V32ORUN" ]; then
  echo "oracle.sh: v32orun not found. Build v32sim's oracle tools (in v32sim: make oracle COMPUTERSOFTWARE=/path/to/ComputerSoftware)" >&2
  echo "           and set V32SIM_HOME to that v32sim tree (or V32ORUN to the binary)." >&2
  return 2 2>/dev/null || exit 2
fi
if [ -z "$V32ASM" ] || [ ! -x "$V32ASM" ]; then
  V32ASM=$(dirname "$V32ORUN")/assemble
  [ -x "$V32ASM" ] || V32ASM=$(command -v assemble)
fi
if [ -z "$V32ASM" ]; then echo "oracle.sh: the stock assembler (assemble) not found beside $V32ORUN or on PATH" >&2; return 2 2>/dev/null || exit 2; fi
export V32ORUN V32ASM
