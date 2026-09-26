#!/usr/bin/env python3
# where.py prog.vbin.debug prog.asm ADDR [ADDR...] -> asm line + enclosing label
import sys, bisect
dbg, asmf = sys.argv[1], sys.argv[2]
addrs, lines, labels = [], [], []
last_label = '?'
for l in open(dbg):
    p = l.strip().split(',')
    if len(p) < 3: continue
    if len(p) >= 4 and p[3]: last_label = p[3]
    addrs.append(int(p[0], 16)); lines.append(int(p[2])); labels.append(last_label)
src = open(asmf).read().split('\n')
for a in sys.argv[3:]:
    a = int(a, 16)
    i = bisect.bisect_right(addrs, a) - 1
    if i < 0: print(f"{a:08X}: ?"); continue
    ln = lines[i]
    print(f"{a:08X}: {asmf}:{ln} in {labels[i]}:  {src[ln-1].strip()}")
