#!/usr/bin/env python3
# profile.py prog.vbin.debug prof.txt [N]  -- cycles per routine from v32run -P
# A "routine" is the nearest preceding label that starts a function body
# (a label followed by PUSH BP), so loop/branch labels roll up into it.
import sys, bisect, collections
dbg, prof = sys.argv[1], sys.argv[2]
n = int(sys.argv[3]) if len(sys.argv) > 3 else 25
asm = None
addrs, labs = [], []
last = '?'
rows = [l.strip().split(',') for l in open(dbg)]
asmf = rows[0][1] if rows and len(rows[0]) > 1 else None
import os
src = open(os.path.join(os.path.dirname(dbg), asmf)).read().split('\n') if asmf else []
for p in rows:
    if len(p) < 3: continue
    if len(p) >= 4 and p[3]:
        ln = int(p[2])
        nxt = src[ln-1].strip() if 0 < ln <= len(src) else ''
        if (nxt.startswith('PUSH') and 'BP' in nxt) or p[3].startswith('__function_') or p[3].startswith('__builtin_') or p[3] in ('__unbox_string','__table_key_streq','__malloc'):
            last = p[3]
        elif last == '?':
            last = p[3]
    addrs.append(int(p[0], 16)); labs.append(last)
tot = collections.Counter(); total = 0
for l in open(prof):
    a, c = l.split(); a = int(a, 16); c = int(c)
    total += c
    i = bisect.bisect_right(addrs, a) - 1
    tot[labs[i] if i >= 0 else '?'] += c
for lab, c in tot.most_common(n):
    print(f"{100.0*c/total:6.2f}%  {c:12d}  {lab}")
print(f"total {total}")
