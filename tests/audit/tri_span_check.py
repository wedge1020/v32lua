# Checks tic80 tri() prelude algorithm (float32 span fill) against a port of TIC-80 drawTri (double, per pixel).
# Usage: python3 -I tri_span_check.py 600   -> expect ~0.03% of pixels differing (edge rounding only).
import math, random, sys
import numpy as np
f=np.float32
def ref(v, W=240,H=136):
    (x1,y1),(x2,y2),(x3,y3)=v
    V=[(x1,y1),(x2,y2),(x3,y3)]
    mnx=max(math.floor(min(p[0] for p in V)),0); mny=max(math.floor(min(p[1] for p in V)),0)
    mxx=min(math.ceil(max(p[0] for p in V)),W); mxy=min(math.ceil(max(p[1] for p in V)),H)
    if mnx>=mxx or mny>=mxy: return set()
    edge=lambda a,b,c:(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    area=edge(*V)
    if math.floor(area)==0: return set()
    if area<0: V[1],V[2]=V[2],V[1]; area=-area
    C=0.5-1.1920929e-07
    p=(mnx+C,mny+C)
    d=[];s=[]
    for i in range(3):
        c=(i+1)%3;n=(i+2)%3
        d.append(((V[c][1]-V[n][1])/area,(V[n][0]-V[c][0])/area))
        s.append(edge(V[c],V[n],p)/area)
    out=set()
    for y in range(mny,mxy):
        w=list(s)
        for x in range(mnx,mxx):
            if all(t>-2.220446049250313e-16 for t in w): out.add((x,y))
            for i in range(3): w[i]+=d[i][0]
        for i in range(3): s[i]+=d[i][1]
    return out
def mine(v, W=240,H=136):
    (x1,y1),(x2,y2),(x3,y3)=[(f(a),f(b)) for a,b in v]
    area=(x2-x1)*(y3-y1)-(y2-y1)*(x3-x1)
    if math.floor(area)==0: return set()
    if area<0: x2,y2,x3,y3=x3,y3,x2,y2; area=-area
    x0=max(math.floor(min(x1,x2,x3)),0); y0=max(math.floor(min(y1,y2,y3)),0)
    xe=min(math.ceil(max(x1,x2,x3)),W); ye=min(math.ceil(max(y1,y2,y3)),H)
    if x0>=xe or y0>=ye: return set()
    px=f(x0)+f(0.49999988); py=f(y0)+f(0.49999988)
    ax1=(y2-y3)/area; ay1=(x3-x2)/area; b1=((x3-x2)*(py-y2)-(y3-y2)*(px-x2))/area
    ax2=(y3-y1)/area; ay2=(x1-x3)/area; b2=((x1-x3)*(py-y3)-(y1-y3)*(px-x3))/area
    ax3=(y1-y2)/area; ay3=(x2-x1)/area; b3=((x2-x1)*(py-y1)-(y2-y1)*(px-x1))/area
    last=xe-x0-1; out=set()
    for row in range(ye-y0):
        lo,hi=0,last
        for (a,ay,b) in ((ax1,ay1,b1),(ax2,ay2,b2),(ax3,ay3,b3)):
            w=b+ay*f(row)
            if a>0: lo=max(lo,math.ceil(-w/a))
            elif a<0: hi=min(hi,math.floor(-w/a))
            elif w<0: hi=-1
        for k in range(lo,hi+1): out.add((x0+k,y0+row))
    return out
random.seed(7)
bad=0;tot=0;diffpix=0;npix=0
for t in range(int(sys.argv[1])):
    mode=t%3
    if mode==0: v=[(random.randint(-20,260),random.randint(-20,150)) for _ in range(3)]
    elif mode==1: v=[(random.randint(0,239),random.randint(0,135)) for _ in range(3)]
    else: v=[(random.uniform(0,239),random.uniform(0,135)) for _ in range(3)]
    a=ref(v); b=mine(v); tot+=1; npix+=len(a)
    if a!=b:
        bad+=1; diffpix+=len(a^b)
        if bad<=5: print("DIFF",v,len(a),len(b),len(a^b))
print("triangles",tot,"mismatching",bad,"pixels",npix,"differing pixels",diffpix)
