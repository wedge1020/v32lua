#!/usr/bin/env python3
# padrand.py SEED FRAMES -> a random v32run -p pad script (A at frame 60, then
# random presses). Long random-input runs found bugs fixed-input runs missed:
#   runlua celeste.lua -f 3000 -q -p "$(padrand.py 1 3000)"
import random,sys; random.seed(int(sys.argv[1])); N=int(sys.argv[2])
ev=['60:A=1','64:A=0']; f=150
btns=['Left','Right','Up','Down','A','B']
while f<N:
  b=random.choice(btns); d=random.randint(3,40); ev.append(f'{f}:{b}=1'); ev.append(f'{f+d}:{b}=0'); f+=random.randint(2,20)
print(';'.join(ev))
