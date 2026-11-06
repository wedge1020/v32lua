"""oracle.py -- find v32sim's headless runner (v32orun) and the stock assembler, as oracle.sh does.

    import oracle; orun, asm = oracle.find()     # exits with a message when they are missing
"""
import os, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))

def find(need_asm=True):
    cands = []
    if os.environ.get("V32SIM_HOME"):
        cands.append(os.path.join(os.environ["V32SIM_HOME"], "tools", "oracle", "bin"))
    cands += [os.path.expanduser("~/share/v32sim/tools/oracle/bin"), "/usr/local/share/v32sim/tools/oracle/bin"]
    top = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
    if os.path.isdir(top):
        cands += [os.path.join(top, d, "tools", "oracle", "bin") for d in sorted(os.listdir(top)) if d.startswith("v32sim")]
    orun = os.environ.get("V32ORUN")
    if not (orun and os.access(orun, os.X_OK)):
        orun = next((os.path.join(c, "v32orun") for c in cands if os.access(os.path.join(c, "v32orun"), os.X_OK)), None) or shutil.which("v32orun")
    if not orun:
        sys.exit("oracle.py: v32orun not found. Build v32sim's oracle tools (make oracle COMPUTERSOFTWARE=...) and set V32SIM_HOME or V32ORUN.")
    asm = os.environ.get("V32ASM")
    if not (asm and os.access(asm, os.X_OK)):
        asm = os.path.join(os.path.dirname(orun), "assemble")
        if not os.access(asm, os.X_OK): asm = shutil.which("assemble")
    if need_asm and not asm:
        sys.exit("oracle.py: the stock assembler (assemble) not found beside %s or on PATH" % orun)
    return orun, asm
