-- title:  BlasTIC
-- author: Melancholy
-- desc:   4-player arena blast game (P1+P2 human, P3+P4 bots)
-- script: lua
-- input:  gamepad
W,H=32,18
TILE=8
MAX_BOMBS=1
BOMB_CAP=5
BOMB_TIMER=120
BLAST_LEN=2
LEN_CAP=6
BLAST_TIME=30
DEATH_TIME=20
SPEED=1
MOVE_PERIOD=2
POWERUP_CHANCE=0.25
POWERUP_KINDS={"B","R","S"}
SHIELD_INVUL=60
MATCH_WINS=3
MATCH_TIME=210
T_EMPTY,T_WALL,T_BLOCK=0,1,2
function setArena(w,h)
W,H=w,h
STARTS={{1,1},{W-2,1},{1,H-2},{W-2,H-2}}
end
setArena(W,H)
blockDensity=0.4
local COLORS={12,5,9,2}
local B_UP,B_DOWN,B_LEFT,B_RIGHT,B_BOMB=0,1,2,3,4
humans={true,true,false,false}
map,bombs,blasts,players,powerups={},{},{},{},{}
frame=0
state="intro"
winner=nil
score={0,0,0,0}
restartTimer=0
titleTimer=0
function mget(c,r)return map[r]and map[r][c]or T_WALL end
local function mset(c,r,v)if map[r]then map[r][c]=v end end
function gpx(c)return(c-1)*TILE end
function gpy(r)return r*TILE end
local function gcol(x)return math.floor(x/TILE)+1 end
local function grow(y)return math.floor(y/TILE)end
local function initMap()
map={}
for r=0,H-1 do
map[r]={}
for c=0,W-1 do
if r==0 or r==H-1 or c==0 or c==W-1 then
map[r][c]=T_WALL
elseif(r<H//2-1 and r%2==0 or r>H//2 and(H-1-r)%2==0)
and(c<W//2 and c%2==0 or c>=W//2 and(W-1-c)%2==0)then
map[r][c]=T_WALL
elseif math.random()<blockDensity then
local corner=false
for _,s in ipairs(STARTS)do
local sc,sr=s[1],s[2]
if(c==sc and r==sr)or
(c==sc+1 and r==sr)or(c==sc-1 and r==sr)or
(c==sc and r==sr+1)or(c==sc and r==sr-1)then
corner=true
end
end
map[r][c]=corner and T_EMPTY or T_BLOCK
else
map[r][c]=T_EMPTY
end
end
end
end
local function shuffledDirs()
local dirs={{0,-1},{0,1},{-1,0},{1,0}}
for i=#dirs,2,-1 do
local j=math.random(i)
dirs[i],dirs[j]=dirs[j],dirs[i]
end
return dirs
end
function newPlayer(id,c,r)
return{
c=c,r=r,
x=gpx(c),y=gpy(r),
alive=true,
stats={bombs=MAX_BOMBS,len=BLAST_LEN},
bombs=0,
shield=false,
invul=0,
color=COLORS[id],
id=id,
team=id,
human=humans[id],
dir={0,1},
walkAnim=0,
botDir={0,0},
botOrder=shuffledDirs(),
botDirTimer=0,
botBombTimer=0,
botEscape=0,
deathT=0,
}
end
local function initPlayers()
players={}
for i,s in ipairs(STARTS)do players[i]=newPlayer(i,s[1],s[2])end
end
local PCM,RATE,MUSIC_RAM=0x14E24,7680,0x04000
local ADPCM_STEPS={7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,
60,66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,
371,408,449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,
1707,1878,2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,
6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,
22385,24623,27086,29794,32767}
local ADPCM_INDEX={-1,-1,-1,-1,2,4,6,8}
local SAMPLE_NAMES={"bass","slap","ghost","kick","snare","hat","ohat","boom"}
local BASS_NOTE=40
SMP={}
local function ramWord(off)
return peek(MUSIC_RAM+off)|peek(MUSIC_RAM+off+1)<<8
end
local function decodeSample(off,len)
local pred,idx,out=ramWord(off),peek(MUSIC_RAM+off+2),{}
if pred>32767 then pred=pred-65536 end
for i=0,len-1 do
local code=peek(MUSIC_RAM+off+3+(i>>1))
if i&1==1 then code=code>>4 else code=code&15 end
local step=ADPCM_STEPS[idx+1]
local d=step>>3
if code&4~=0 then d=d+step end
if code&2~=0 then d=d+(step>>1)end
if code&1~=0 then d=d+(step>>2)end
if code&8~=0 then d=-d end
pred=math.max(-32768,math.min(32767,pred+d))
idx=math.max(0,math.min(88,idx+ADPCM_INDEX[(code&7)+1]))
out[i+1]=pred//256
end
return out
end
local function loadSamples()
if peek(MUSIC_RAM)~=#SAMPLE_NAMES then return end
for k,name in ipairs(SAMPLE_NAMES)do
SMP[name]=decodeSample(ramWord(1+(k-1)*4),ramWord(3+(k-1)*4))
end
end
SONGS={
{128,40,1,1,1,1},{124,43,2,2,1,2},{132,45,3,1,2,3},{120,38,1,3,3,4},
{136,40,4,2,2,5},{126,41,2,1,1,6},{130,43,3,3,1,7},{122,45,4,1,3,8},
{134,38,1,2,2,9},{128,36,2,3,1,10},{124,40,3,1,2,11},{132,43,4,2,1,12},
}
SONG_BARS=32
local CHORD={m={0,3,7},M={0,4,7},s={0,4,10}}
local PROGS={
{{0,"m"},{0,"m"},{-4,"M"},{-2,"M"},{0,"m"},{0,"m"},{5,"m"},{-5,"s"}},
{{0,"m"},{-2,"M"},{-4,"M"},{-5,"s"},{0,"m"},{-2,"M"},{-4,"M"},{-5,"s"}},
{{0,"m"},{5,"m"},{-2,"M"},{3,"M"},{0,"m"},{5,"m"},{-5,"s"},{-5,"s"}},
{{0,"m"},{-4,"M"},{5,"m"},{-2,"M"},{0,"m"},{-4,"M"},{-2,"M"},{-5,"s"}},
}
local RIFF_NOTE={n={0,"bass"},g={0,"ghost"},p={0,"slap"},b={-2,"bass"},f={-5,"bass"},d={-4,"bass"},
u={3,"bass"},w={2,"bass"},o={12,"slap"},B={-2,"slap"},F={-1,"slap"}}
local RIFFS={"n.gp.ngb.npgf.bp","n.n.gpn.b.npg.fp","n..gn.pgn..gb.op","n.......n.......","n..n..n.n..n..ng"}
local FILL="ngpgbdfpbfpuwnBF"
local DRUMS={{"K...S.K...K.S...","HhHhHhOhHhHhHhOh"},{"K...X...K...X...","..H...H...H...H."},
{"K.....K.S.....K.","HhHhHhHhHhHhHhHh"},{"................","........h......."},
{"K..KS..KK..KS.KS","H.H.H.H.H.H.H.H."}}
MOODS={calm={92,38,4,4,4,3},tension={140,36,1,5,5,7},joy={136,43,3,2,1,12}}
local RHYTHMS={{{0,3},{3,3},{6,2},{8,6}},{{0,2},{2,2},{4,4},{8,8}},{{0,3},{4,2},{6,2},{8,4},{12,4}}}
local voices,duck={},0
musicSeqs={}
local function midiStep(m)return 440*2^((m-69)/12)/RATE end
local function playSample(name,rate,gain,seq)
local s=SMP[name]
if not s then return nil end
local v={s=s,pos=1,rate=rate,g=gain,seq=seq}
voices[#voices+1]=v
return v
end
local function playOsc(saw,midi,len,gain,seq,alpha)
voices[#voices+1]={saw=saw,ph=0,inc=midiStep(midi),len=len,t=0,g=gain,seq=seq,lp=0,a=alpha}
end
local function melody(song)
local seed,mel=song[6]*7919,{}
local rhythm=RHYTHMS[song[6]%3+1]
for bar=1,8 do
local p=PROGS[song[3]][bar]
local tones=CHORD[p[2]]
mel[bar]={}
for _,r in ipairs(rhythm)do
seed=(seed*1103+12345)%65536
local k=seed%4
mel[bar][r[1]]={r[2],song[2]+24+p[1]+(k==3 and 12 or tones[k+1])}
end
end
return mel
end
function startSong(n,fadeIn,song)
song=song or SONGS[n]
local spb=RATE*60/song[1]/4
local seq={n=n,song=song,mood=song~=SONGS[n],bar=1,step=0,cnt=0,spb=spb,mel=melody(song),
gain=fadeIn and 0 or 1,fade=fadeIn and 1/(32*spb)or 0}
musicSeqs[#musicSeqs+1]=seq
return seq
end
local function trigger(seq)
local song,bar,step=seq.song,seq.bar,seq.step
local p=PROGS[song[3]][(bar-1)%8+1]
local root=song[2]+p[1]
if step==0 then
for _,i in ipairs(CHORD[p[2]])do playOsc(true,root+12+i,16*seq.spb,0.09,seq,0.08)end
end
local riff=bar%8==0 and FILL or RIFFS[song[4]]
local note=RIFF_NOTE[riff:sub(step+1,step+1)]
if note then
if seq.bass then seq.bass.rel=64 end
seq.bass=playSample(note[2],2^((root+note[1]-BASS_NOTE)/12),note[2]=="ghost"and 0.4 or 0.6,seq)
end
local d=DRUMS[song[5]]
local ks,hh=d[1]:sub(step+1,step+1),d[2]:sub(step+1,step+1)
if ks=="K"or ks=="X"then playSample("kick",1,0.55,seq)end
if ks=="S"or ks=="X"then playSample("snare",1,0.4,seq)end
if hh~="."then playSample(hh=="O"and"ohat"or"hat",1,hh=="h"and 0.12 or 0.2,seq)end
local pass=(bar-1)//8
local m=pass%2==1 and seq.mel[(bar-1)%8+1][step]
if m then playOsc(false,m[2],m[1]*seq.spb,0.14,seq,0.3)end
end
local function tickSeq(seq)
seq.cnt=seq.cnt-1
if seq.cnt<=0 then
seq.cnt=seq.cnt+seq.spb
if seq.bar<=SONG_BARS then trigger(seq)end
seq.step=seq.step+1
if seq.step==16 then
seq.step=0
seq.bar=seq.bar+1
if seq.bar==SONG_BARS-1 and not seq.next then
seq.next=seq.mood and startSong(seq.n,true,seq.song)or startSong(seq.n%#SONGS+1,true)
seq.fade=-1/(32*seq.spb)
end
end
end
seq.gain=math.max(0,math.min(1,seq.gain+seq.fade))
end
function musicMood(name)
local cur=musicSeqs[#musicSeqs]
if not cur or(cur.mood and MOODS[name]==cur.song)or(not name and not cur.mood)then return end
for _,s in ipairs(musicSeqs)do s.next,s.stop,s.fade=true,true,-1/(16*s.spb)end
if name then startSong(cur.n,true,MOODS[name])else startSong(cur.n%#SONGS+1,true)end
end
function startMusic()
loadSamples()
voices,musicSeqs,duck={},{},0
if SMP.bass then startSong(1,false)end
end
function sndExplosion()
if SMP.boom then
playSample("boom",1,0.6,nil)
duck=#SMP.boom
end
end
local function updateMusic()
if#voices==0 and#musicSeqs==0 then return end
for k=0,127 do
for _,s in ipairs(musicSeqs)do tickSeq(s)end
local mus,fx=0,0
for _,v in ipairs(voices)do
local x=0
if v.s then
x=v.s[v.pos//1]or 0
v.pos=v.pos+v.rate
if v.rel then v.rel=v.rel-1 x=x*v.rel/64 end
if v.pos>#v.s+1 or(v.rel and v.rel<=0)then v.dead=true end
else
v.t=v.t+1
v.ph=(v.ph+v.inc)%1
local raw=v.saw and v.ph*2-1 or(v.ph<0.3 and 1 or-1)
v.lp=v.lp+v.a*(raw-v.lp)
x=v.lp*127*math.min(1,v.t/200,(v.len-v.t)/300)
if v.t>=v.len then v.dead=true end
end
if v.seq then mus=mus+x*v.g*v.seq.gain else fx=fx+x*v.g end
end
if duck>0 then duck=duck-1 mus=mus/2 end
poke(PCM+k,math.max(-128,math.min(127,(mus+fx)//1))+128)
end
local live={}
for _,v in ipairs(voices)do if not v.dead then live[#live+1]=v end end
voices=live
local playing={}
for _,s in ipairs(musicSeqs)do
if s.gain>0 or(s.bar<=SONG_BARS and not s.stop)then playing[#playing+1]=s end
end
musicSeqs=playing
end
local WAVES,SFX_RAM=0x0FFE4,0x100E4
local NOISE,SAW,TRI=0,1,3
local function putSfx(n,ticks,wave,octave,note)
local b=SFX_RAM+66*n
for i=0,29 do
local t=ticks[i+1]or{0,0}
poke(b+i*2,(15-t[1])|wave<<4)
poke(b+i*2+1,t[2])
end
poke(b+60,octave)
poke(b+61,note)
for i=62,65 do poke(b+i,0)end
end
SKIN,WOOD,WOOD_DARK=10,1,8
local function setColour(i,r,g,b)
poke(0x03FC0+i*3,r);poke(0x03FC0+i*3+1,g);poke(0x03FC0+i*3+2,b)
end
function initPalette()
setColour(SKIN,0xFF,0xCC,0xAA)
setColour(WOOD,0xC8,0x92,0x52)
setColour(WOOD_DARK,0x5C,0x3A,0x1A)
end
LANG_SLOT=1
LANG=pmem and pmem(LANG_SLOT)==1 and"pl"or"en"
local FONT=0x14604
local PL_LETTERS="ąćęłńóśźżĄĆĘŁŃÓŚŹŻ"
local PL_BASE="acelnoszzACELNOSZZ"
local PL_MARK="oaosaaaadoaosaaaad"
local plCode,plCache={},{}
for k=1,#PL_LETTERS//2 do plCode[PL_LETTERS:sub(2*k-1,2*k)]=string.char(k)end
local function markGlyph(code,base,mark)
local rows,top,bottom,minc,maxc={},8,-1,8,-1
for r=0,7 do
local b=peek(FONT+base*8+r)
rows[r]=b
for i=0,7 do
if(b>>i)&1==1 then top,bottom=math.min(top,r),math.max(bottom,r)minc,maxc=math.min(minc,i),math.max(maxc,i)end
end
end
local function set(c,r)if r>=0 and r<8 and c>=0 and c<8 then rows[r]=rows[r]|(1<<c)end end
local mid=(minc+maxc+1)//2
local drop=(mark=="a"or mark=="d")and math.min(math.max(0,2-top),7-bottom)or 0
for r=7,0,-1 do rows[r]=r>=drop and rows[r-drop]or 0 end
top,bottom=top+drop,bottom+drop
if mark=="o"then set(maxc,bottom+1)set(maxc+1,bottom+2)
elseif mark=="a"then set(mid+1,math.max(0,top-2))
elseif mark=="d"then set(mid,math.max(0,top-2))
else
local r=(top+bottom)//2
set(minc-1,r)set(minc+1+((rows[r]>>(minc+1))&1),r)
end
for r=0,7 do poke(FONT+code*8+r,rows[r])end
end
function initFont()
for k=1,#PL_BASE do
local base,mark=PL_BASE:byte(k),PL_MARK:sub(k,k)
markGlyph(k,base,mark)
markGlyph(128+k,128+base,mark)
end
end
function L(en,pl)
if LANG~="pl"or not pl then return en end
local c=plCache[pl]
if not c then
c=pl:gsub("[\xC3-\xC5][\x80-\xBF]",plCode)
plCache[pl]=c
end
return c
end
local audioReady=false
function initAudio()
if audioReady then return end
audioReady=true
for i=0,15 do poke(WAVES+i,0)end
for i=0,15 do
poke(WAVES+16+i,(15-i*2%16)|((15-(i*2+1)%16)<<4))
end
for i=0,7 do poke(WAVES+32+i,0x00)end
for i=8,15 do poke(WAVES+32+i,0xFF)end
local tri={0x10,0x32,0x54,0x76,0x98,0xBA,0xDC,0xFE,
0xEF,0xCD,0xAB,0x89,0x67,0x45,0x23,0x01}
for i=0,15 do poke(WAVES+48+i,tri[i+1])end
putSfx(1,{{13,12},{13,10},{12,7},{11,5},{10,3},{8,1},{6,0},{4,0},{2,0}},SAW,3,9)
putSfx(5,{{12,0},{10,0},{7,0},{4,0}},TRI,2,0)
putSfx(6,{{11,0},{11,0},{11,4},{11,4},{11,7},{11,7},{10,12},{7,12},{4,12}},TRI,4,0)
putSfx(8,{{9,0},{6,0},{3,0}},TRI,5,0)
putSfx(7,{{13,0},{11,0},{8,0},{5,0},{2,0}},NOISE,4,0)
end
function sndPickup()sfx(6,-1,24,3,15)end
function sndShield()sfx(7,-1,24,3,15)end
function init()
hideBackdrop()
math.randomseed(time())
mode,camX,camY,boss,monsters,hidden="pvp",0,0,nil,{},{}
setArena(32,18)
blockDensity=0.4
bombs={}
blasts={}
powerups={}
initMap()
initPlayers()
initAudio()
initPalette()
resetShrink()
frame=0
state="game"
winner=nil
restartTimer=0
end
local QUEST_ITEM={X=true,K=true,E=true}
local function removePowerupAt(c,r)
for i=#powerups,1,-1 do
local pu=powerups[i]
if pu.c==c and pu.r==r and not QUEST_ITEM[pu.kind]then table.remove(powerups,i)end
end
end
BOSS_FIRE={bombs=0}
local function addBlast(c,r,owner)
blasts[#blasts+1]={c=c,r=r,t=BLAST_TIME,owner=owner}
removePowerupAt(c,r)
end
local function dropPowerup(c,r)
local quest=hidden[c*100+r]
if quest then
powerups[#powerups+1]={c=c,r=r,kind=quest}
elseif math.random()<POWERUP_CHANCE then
powerups[#powerups+1]={c=c,r=r,kind=POWERUP_KINDS[math.random(#POWERUP_KINDS)]}
end
end
local function explode(b)
sndExplosion()
local bc,br=b.c,b.r
local len=b.len or BLAST_LEN
local hit={}
addBlast(bc,br,b.owner)
hit[bc*100+br]=true
local dirs={{0,-1},{0,1},{-1,0},{1,0}}
for _,d in ipairs(dirs)do
for i=1,len do
local nc,nr=bc+d[1]*i,br+d[2]*i
local t=mget(nc,nr)
if t==T_WALL then break end
addBlast(nc,nr,b.owner)
hit[nc*100+nr]=true
if t==T_BLOCK then mset(nc,nr,T_EMPTY)dropPowerup(nc,nr)break end
end
end
if b.owner then b.owner.bombs=math.max(0,b.owner.bombs-1)end
return hit
end
local function updateBombs()
local queue,keep={},{}
for _,b in ipairs(bombs)do
b.t=b.t-1
if b.t<=0 then queue[#queue+1]=b else keep[#keep+1]=b end
end
bombs=keep
local k=1
while k<=#queue do
local hit=explode(queue[k])
k=k+1
local rest={}
for _,b in ipairs(bombs)do
if hit[b.c*100+b.r]then queue[#queue+1]=b else rest[#rest+1]=b end
end
bombs=rest
end
end
local function updateBlasts()
local keep={}
for _,bl in ipairs(blasts)do
bl.t=bl.t-1
if bl.t>0 then keep[#keep+1]=bl end
end
blasts=keep
end
local function isBlast(c,r)
for _,bl in ipairs(blasts)do
if bl.c==c and bl.r==r then return true end
end
return false
end
local function blastHurts(p)
for _,bl in ipairs(blasts)do
local o=bl.owner
if bl.c==p.c and bl.r==p.r and not(mode=="camp"and o and o~=p and o.team==p.team)then
return true
end
end
return false
end
local function isBomb(c,r)
for _,b in ipairs(bombs)do
if b.c==c and b.r==r then return true end
end
return false
end
local function collectPowerup(p)
for i,pu in ipairs(powerups)do
if pu.c==p.c and pu.r==p.r and(p.team==1 or not QUEST_ITEM[pu.kind])then
if pu.kind=="K"then camp.keys=camp.keys+1
elseif pu.kind=="X"then camp.done=true
elseif pu.kind=="E"then camp.friend=true
elseif pu.kind=="B"then p.stats.bombs=math.min(BOMB_CAP,p.stats.bombs+1)
elseif pu.kind=="R"then p.stats.len=math.min(LEN_CAP,p.stats.len+1)
elseif pu.kind=="S"then p.shield=true end
table.remove(powerups,i)
sndPickup()
return
end
end
end
local function movePlayer(p,dc,dr)
local nx=p.x+dc*SPEED
local ny=p.y+dr*SPEED
local margin=1
local passable={}
for _,b in ipairs(bombs)do
if b.owner==p then
local ox0=gcol(p.x+margin);local ox1=gcol(p.x+TILE-margin-1)
local oy0=grow(p.y+margin);local oy1=grow(p.y+TILE-margin-1)
if b.c>=ox0 and b.c<=ox1 and b.r>=oy0 and b.r<=oy1 then
passable[b.c*100+b.r]=true
end
end
end
local function blocked(x,y)
local cs={
{gcol(x+margin),grow(y+margin)},
{gcol(x+TILE-margin-1),grow(y+margin)},
{gcol(x+margin),grow(y+TILE-margin-1)},
{gcol(x+TILE-margin-1),grow(y+TILE-margin-1)},
}
for _,co in ipairs(cs)do
local t=mget(co[1],co[2])
if t==T_WALL or t==T_BLOCK then return true end
if isBomb(co[1],co[2])and not passable[co[1]*100+co[2]]then return true end
end
return false
end
local hx=not blocked(nx,p.y)
local hy=not blocked(p.x,ny)
if hx then p.x=nx end
if hy then p.y=ny end
local function assist(pos,aheadFree,stepFree)
local a=pos-pos%TILE
if pos==a then return pos end
local near,far=a,a+TILE
if pos-a>TILE//2 then near,far=far,near end
for _,t in ipairs({near,far})do
if aheadFree(t)then
local s=t>pos and SPEED or-SPEED
if stepFree(pos+s)then return pos+s end
return pos
end
end
return pos
end
if dc~=0 then
p.y=assist(p.y,function(t)return not blocked(nx,t)end,function(v)return not blocked(p.x,v)end)
end
if dr~=0 then
p.x=assist(p.x,function(t)return not blocked(t,ny)end,function(v)return not blocked(v,p.y)end)
end
p.c=gcol(p.x+TILE//2)
p.r=grow(p.y+TILE//2)
collectPowerup(p)
end
local function placeBomb(p)
if p.bombs<p.stats.bombs then
local bc=gcol(p.x+TILE//2)
local br=grow(p.y+TILE//2)
if not isBomb(bc,br)then
bombs[#bombs+1]={c=bc,r=br,t=BOMB_TIMER,owner=p,len=p.stats.len}
p.bombs=p.bombs+1
sfx(5,-1,20,3,15)
return true
end
end
return false
end
local function killPlayer(p)
p.alive=false
p.deathT=DEATH_TIME
sfx(1,-1,15,1,15)
end
local function updateDeaths()
for _,p in ipairs(players)do
if p.deathT>0 then p.deathT=p.deathT-1 end
end
end
local function blastHit(p)
if not p.alive or p.invul>0 then return end
if p.shield then
p.shield=false
p.invul=SHIELD_INVUL
sndShield()
else
killPlayer(p)
end
end
local function updateInvul()
for _,p in ipairs(players)do
if p.invul>0 then p.invul=p.invul-1 end
end
end
local function updatePlayer(p)
if not p.alive then return end
local off=(p.id-1)*8
local ox,oy=p.x,p.y
if frame%MOVE_PERIOD==0 then
if btn(off+B_UP)then movePlayer(p,0,-1);p.dir={0,-1}end
if btn(off+B_DOWN)then movePlayer(p,0,1);p.dir={0,1}end
if btn(off+B_LEFT)then movePlayer(p,-1,0);p.dir={-1,0}end
if btn(off+B_RIGHT)then movePlayer(p,1,0);p.dir={1,0}end
end
if p.x~=ox or p.y~=oy then p.walkAnim=p.walkAnim+1 end
if btnp(off+B_BOMB)then placeBomb(p)end
if blastHurts(p)then blastHit(p)end
end
local BOT_DIRS={{0,-1},{0,1},{-1,0},{1,0}}
local botOrder=BOT_DIRS
local BOT_FLEE_FRAMES=BOMB_TIMER
local BOT_PICKUP_RANGE=10
local function botPassable(c,r)
return mget(c,r)==T_EMPTY and not isBomb(c,r)
end
function botPath(sc,sr,isOpen,isGoal)
local came={}
local seen={[sr*W+sc]=true}
local qc,qr={sc},{sr}
local head=1
while head<=#qc do
local c,r=qc[head],qr[head]
head=head+1
if(c~=sc or r~=sr)and isGoal(c,r)then
local path={}
while came[r*W+c]do
table.insert(path,1,{c=c,r=r})
c,r=came[r*W+c][1],came[r*W+c][2]
end
return path
end
for _,d in ipairs(botOrder)do
local nc,nr=c+d[1],r+d[2]
local nk=nr*W+nc
if not seen[nk]and isOpen(nc,nr)then
seen[nk]=true
came[nk]={c,r}
qc[#qc+1]=nc;qr[#qr+1]=nr
end
end
end
return nil
end
local function botDanger(horizon,extra)
local list={}
for _,b in ipairs(bombs)do list[#list+1]=b end
if extra then list[#list+1]=extra end
local fire={}
for _,bl in ipairs(blasts)do fire[bl.r*W+bl.c]=true end
local closing=shrinkClosing()
for _,cell in ipairs(closing or{})do fire[cell[2]*W+cell[1]]=true end
local going={}
local changed=true
while changed do
changed=false
for i,b in ipairs(list)do
if not going[i]and(b.t<=horizon or fire[b.r*W+b.c])then
going[i]=true
changed=true
fire[b.r*W+b.c]=true
for _,d in ipairs(BOT_DIRS)do
for k=1,b.len or BLAST_LEN do
local nc,nr=b.c+d[1]*k,b.r+d[2]*k
local t=mget(nc,nr)
if t==T_WALL then break end
fire[nr*W+nc]=true
if t==T_BLOCK then break end
end
end
end
end
end
return fire
end
local BOT_STEP=TILE*MOVE_PERIOD
local function botFireTimes(extra)
local list={}
for _,b in ipairs(bombs)do list[#list+1]={c=b.c,r=b.r,len=b.len,t=b.t}end
if extra then list[#list+1]={c=extra.c,r=extra.r,len=extra.len,t=extra.t}end
local from,to={},{}
local function burn(k,s)
if not from[k]or s<from[k]then from[k]=s end
if not to[k]or s+BLAST_TIME>to[k]then to[k]=s+BLAST_TIME end
end
for _,bl in ipairs(blasts)do
local k=bl.r*W+bl.c
from[k]=0
to[k]=math.max(to[k]or 0,bl.t)
end
local closing,left=shrinkClosing()
for _,cell in ipairs(closing or{})do
local k=cell[2]*W+cell[1]
from[k]=math.min(from[k]or left,left)
to[k]=math.huge
end
for _,b in ipairs(list)do
local s=from[b.r*W+b.c]
if s and s<b.t then b.t=s end
end
local changed=true
while changed do
changed=false
for _,b in ipairs(list)do
local cells={{b.c,b.r}}
for _,d in ipairs(BOT_DIRS)do
for k=1,b.len or BLAST_LEN do
local nc,nr=b.c+d[1]*k,b.r+d[2]*k
local t=mget(nc,nr)
if t==T_WALL then break end
cells[#cells+1]={nc,nr}
if t==T_BLOCK then break end
end
end
for _,cell in ipairs(cells)do
local k=cell[2]*W+cell[1]
if not from[k]or b.t<from[k]or to[k]<b.t+BLAST_TIME then
burn(k,b.t)
changed=true
end
for _,o in ipairs(list)do
if o.c==cell[1]and o.r==cell[2]and o.t>b.t then o.t=b.t;changed=true end
end
end
end
end
return from,to
end
local function botEscapePath(sc,sr,from,to,blocked)
local function burning(k,a)return from[k]~=nil and from[k]<=a+BOT_STEP//2 and to[k]>a end
local function safeEnd(k,a)return from[k]==nil or to[k]<=a end
local came={}
local seen={[sr*W+sc]=true}
local qc,qr,qd={sc},{sr},{0}
local head=1
while head<=#qc do
local c,r,d=qc[head],qr[head],qd[head]
head=head+1
if d>0 and safeEnd(r*W+c,d*BOT_STEP)then
local path={}
while came[r*W+c]do
table.insert(path,1,{c=c,r=r})
c,r=came[r*W+c][1],came[r*W+c][2]
end
return path
end
for _,dir in ipairs(botOrder)do
local nc,nr=c+dir[1],r+dir[2]
local nk=nr*W+nc
if not seen[nk]and nk~=blocked and botPassable(nc,nr)and not burning(nk,(d+1)*BOT_STEP)then
seen[nk]=true
came[nk]={c,r}
qc[#qc+1]=nc;qr[#qr+1]=nr;qd[#qd+1]=d+1
end
end
end
return nil
end
function foeAt(p,c,r)
for _,op in ipairs(players)do
if op.alive and op.team~=p.team and op.c==c and op.r==r then return true end
end
if p.team==1 and mode=="camp"then
for _,m in ipairs(monsters)do if m.c==c and m.r==r then return true end end
local b=boss
if b and b.hp>0 and c>=b.c and c<=b.c+1 and r>=b.r and r<=b.r+1 then return true end
end
return false
end
local function botEnemySpot(p,c,r)
for _,d in ipairs(BOT_DIRS)do
for k=1,p.stats.len do
local nc,nr=c+d[1]*k,r+d[2]*k
local t=mget(nc,nr)
if t~=T_EMPTY then break end
if foeAt(p,nc,nr)then return true end
end
end
return false
end
local function botTrapSpot(p,c,r)
if not botEnemySpot(p,c,r)then return false end
local from,to=botFireTimes({c=c,r=r,t=BOMB_TIMER,len=p.stats.len})
if not botEscapePath(c,r,from,to)then return false end
for _,op in ipairs(players)do
local k=op.r*W+op.c
if op.alive and op.team~=p.team and from[k]and not botEscapePath(op.c,op.r,from,to,r*W+c)then
return true
end
end
return false
end
local function botIsTargetSpot(p,c,r)
for _,d in ipairs(BOT_DIRS)do
if mget(c+d[1],r+d[2])==T_BLOCK then return true end
end
return botEnemySpot(p,c,r)
end
local function botPickupDir(p,danger)
if#powerups==0 then return nil end
local item={}
for _,pu in ipairs(powerups)do
if p.team==1 or not QUEST_ITEM[pu.kind]then item[pu.r*W+pu.c]=pu.kind end
end
local path=botPath(p.c,p.r,
function(c,r)return botPassable(c,r)and not danger[r*W+c]end,
function(c,r)return item[r*W+c]end)
if not path then return nil end
local last=path[#path]
if#path<=BOT_PICKUP_RANGE or QUEST_ITEM[item[last.r*W+last.c]]then
return{path[1].c-p.c,path[1].r-p.r}
end
return nil
end
local function botStepOk(p,d,danger)
local nc,nr=p.c+d[1],p.r+d[2]
return botPassable(nc,nr)and not danger[nr*W+nc]
end
local function botSafeDir(p,danger)
for _=1,8 do
local d=BOT_DIRS[math.random(4)]
if botStepOk(p,d,danger)then return d end
end
return{0,0}
end
local function botSign(v)return v>0 and 1 or(v<0 and-1 or 0)end
local function botSteer(p,dc,dr)
if dr~=0 and p.x~=gpx(p.c)then return botSign(gpx(p.c)-p.x),0 end
if dc~=0 and p.y~=gpy(p.r)then return 0,botSign(gpy(p.r)-p.y)end
return dc,dr
end
local function botBombSafe(p,c,r)
local from,to=botFireTimes({c=c,r=r,t=BOMB_TIMER,len=p.stats.len})
return botEscapePath(c,r,from,to)~=nil
end
local function botTryBomb(p)
if not botIsTargetSpot(p,p.c,p.r)or not botBombSafe(p,p.c,p.r)then return false end
return placeBomb(p)
end
function botQuestDir(p,danger)
local quests={}
for k in pairs(hidden)do
if mget(k//100,k%100)==T_BLOCK then quests[#quests+1]={k//100,k%100}end
end
if#quests==0 then return nil end
local function dist(c,r)
local m=math.huge
for _,q in ipairs(quests)do m=math.min(m,math.abs(c-q[1])+math.abs(r-q[2]))end
return m
end
local function open(c,r)return botPassable(c,r)and not danger[r*W+c]end
local spots,seen,queue,i={},{[p.r*W+p.c]=true},{{p.c,p.r}},1
while queue[i]do
local c,r=queue[i][1],queue[i][2]
i=i+1
if botIsTargetSpot(p,c,r)then spots[#spots+1]={c,r,dist(c,r),i}end
for _,d in ipairs(BOT_DIRS)do
local nc,nr=c+d[1],r+d[2]
if not seen[nr*W+nc]and open(nc,nr)then seen[nr*W+nc]=true queue[#queue+1]={nc,nr}end
end
end
table.sort(spots,function(a,b)return a[3]<b[3]or a[3]==b[3]and a[4]<b[4]end)
for _,sp in ipairs(spots)do
if botBombSafe(p,sp[1],sp[2])then
if sp[1]==p.c and sp[2]==p.r then return nil end
local path=botPath(p.c,p.r,open,function(c,r)return c==sp[1]and r==sp[2]end)
return path and{path[1].c-p.c,path[1].r-p.r}
end
end
return nil
end
local function updateBot(p)
if not p.alive then return end
botOrder=p.botOrder
p.botDirTimer=p.botDirTimer-1
local danger=botDanger(BOT_FLEE_FRAMES)
if mode=="camp"and p.team==1 then
for _,m in ipairs(monsters)do
danger[m.r*W+m.c]=true
for _,d in ipairs(BOT_DIRS)do danger[(m.r+d[2])*W+m.c+d[1]]=true end
end
local wn=boss and boss.warn
if wn then
for k=1,(wn.row and W or H)-2 do danger[(wn.row and wn.r or k)*W+(wn.row and k or wn.c)]=true end
end
end
local dir
local pickup=not danger[p.r*W+p.c]and botPickupDir(p,danger)
if danger[p.r*W+p.c]then
local from,to=botFireTimes()
local path=botEscapePath(p.c,p.r,from,to)
local stop=path and path[#path]
if not path or(stop and danger[stop.r*W+stop.c])then
path=botPath(p.c,p.r,botPassable,function(c,r)return not danger[r*W+c]end)or path
end
if path then dir={path[1].c-p.c,path[1].r-p.r}else dir=BOT_DIRS[math.random(4)]end
elseif botTryBomb(p)then
dir={0,0}
elseif pickup then
dir=pickup
elseif p.bombs<p.stats.bombs then
local function huntStep(isSpot)
local path=botPath(p.c,p.r,
function(c,r)return botPassable(c,r)and not danger[r*W+c]end,
function(c,r)return isSpot(p,c,r)and botBombSafe(p,c,r)end)
return path and{path[1].c-p.c,path[1].r-p.r}
end
dir=(p.team==1 and botQuestDir(p,danger))or huntStep(botTrapSpot)or huntStep(botEnemySpot)
or huntStep(botIsTargetSpot)
end
if not dir then
if p.botDirTimer<=0 or not botStepOk(p,p.botDir,danger)then
p.botDir=botSafeDir(p,danger)
p.botDirTimer=15+math.random(25)
end
dir=p.botDir
end
p.botDir=dir
if frame%MOVE_PERIOD==0 then
local dc,dr=botSteer(p,dir[1],dir[2])
local ox,oy=p.x,p.y
if dc~=0 or dr~=0 then p.dir={dc,dr}end
movePlayer(p,dc,dr)
if p.x==ox and p.y==oy then
p.botDirTimer=0
else
p.walkAnim=p.walkAnim+1
end
end
if blastHurts(p)then blastHit(p)end
end
SHRINK_DELAY=1800
SHRINK_PAUSE=120
SHRINK_WARN=300
SHRINK_CYCLE=SHRINK_PAUSE+SHRINK_WARN
local WARN_COL=9
local WARN_SLOWEST,WARN_FASTEST=24,4
function resetShrink()
zoneCycle,zoneSteps=SHRINK_CYCLE,0
shrinkBox={x0=1,y0=1,x1=W-2,y1=H-2}
shrinkAt=SHRINK_DELAY+SHRINK_CYCLE-1
roundFrames=0
end
resetShrink()
local function shrinkTile(c,r)
mset(c,r,T_WALL)
for i=#monsters,1,-1 do
if monsters[i].c==c and monsters[i].r==r then table.remove(monsters,i)end
end
local items={}
for _,pu in ipairs(powerups)do
if pu.c~=c or pu.r~=r then items[#items+1]=pu end
end
powerups=items
for _,p in ipairs(players)do
if p.alive and p.c==c and p.r==r then killPlayer(p)end
end
local keep={}
for _,b in ipairs(bombs)do
if b.c==c and b.r==r then
b.owner.bombs=math.max(0,b.owner.bombs-1)
else
keep[#keep+1]=b
end
end
bombs=keep
end
local ZONE_MIN_W,ZONE_MIN_H=4,2
local function thin(box)
return box.y1-box.y0+1<=ZONE_MIN_H
end
local function stepCells(box)
local cells={}
local function add(c,r)
if mget(c,r)~=T_WALL then cells[#cells+1]={c,r}end
end
for r=box.y0,box.y1 do
add(box.x0,r)
if box.x1>box.x0 then add(box.x1,r)end
end
if not thin(box)then
for c=box.x0+1,box.x1-1 do
add(c,box.y0)
if box.y1>box.y0 then add(c,box.y1)end
end
end
return cells
end
local function advanceBox(box)
local sides=thin(box)
box.x0,box.x1=box.x0+1,box.x1-1
if not sides then box.y0,box.y1=box.y0+1,box.y1-1 end
end
local function nextStepCells()
local box=shrinkBox
while not(thin(box)and box.x1-box.x0+1<=ZONE_MIN_W)do
local cells=stepCells(box)
if#cells>0 then return cells end
advanceBox(box)
end
return nil
end
function updateShrink()
roundFrames=roundFrames+1
if roundFrames<shrinkAt then return end
local cells=nextStepCells()
if not cells then return end
for _,cell in ipairs(cells)do shrinkTile(cell[1],cell[2])end
zoneSteps=zoneSteps+1
advanceBox(shrinkBox)
shrinkAt=roundFrames+zoneCycle
end
function shrinkClosing()
local left=shrinkAt-roundFrames
if left>SHRINK_WARN then return nil end
local cells=nextStepCells()
if not cells then return nil end
return cells,left
end
local function shrinkWarnTiles()
local warn={}
local cells,left=shrinkClosing()
if not cells then return warn end
local progress=1-left/SHRINK_WARN
local period=math.floor(WARN_SLOWEST-(WARN_SLOWEST-WARN_FASTEST)*progress)
if roundFrames%period>=period//2 then return warn end
for _,cell in ipairs(cells)do warn[cell[1]*100+cell[2]]=true end
return warn
end
local WALL_COL=13
local BLOCK_COL=WOOD
local FLOOR_COL=0
local BOMB_COL=2
local function drawMap()
local warn=shrinkWarnTiles()
local c0,r0=camX//TILE+1,camY//TILE+1
for r=r0,math.min(H-2,r0+16)do
for c=c0,math.min(W-2,c0+30)do
local t=mget(c,r)
local col=FLOOR_COL
if t==T_WALL then col=WALL_COL
elseif t==T_BLOCK then col=BLOCK_COL end
if warn[c*100+r]then col=WARN_COL end
local x,y=gpx(c)-camX,gpy(r)-camY
rect(x,y,TILE,TILE,col)
if t==T_WALL then
rectb(x,y,TILE,TILE,15)
elseif t==T_BLOCK and not warn[c*100+r]then
rectb(x,y,TILE,TILE,WOOD_DARK)
end
end
end
rectb(-camX,TILE-camY,(W-2)*TILE,(H-2)*TILE,WALL_COL)
end
local function drawBlasts()
for _,bl in ipairs(blasts)do
local age=BLAST_TIME-bl.t
local r=math.min(TILE//2-1,1+age//3)
local frac=bl.t/BLAST_TIME
local col=frac>0.66 and 4 or frac>0.33 and 3 or 2
circ(gpx(bl.c)+TILE//2-camX,gpy(bl.r)+TILE//2-camY,r,col)
end
end
local function drawBombs()
for _,b in ipairs(bombs)do
local blink=(b.t<40 and frame%6<3)
local col=blink and 7 or BOMB_COL
local bx,by=gpx(b.c)+TILE//2-camX,gpy(b.r)+TILE//2-camY
circ(bx,by,3,col)
local fx,fy=bx+2,by-TILE//2-1
line(bx,by-3,fx,fy,7)
circ(fx,fy,1,(frame//2)%2==0 and 9 or 14)
end
end
local SPR={
{0,2,2,2,2,2,2,0,
2,2,2,2,2,2,2,2,
2,2,1,1,1,1,2,2,
2,2,3,1,1,3,2,2,
2,2,1,1,1,1,2,2,
0,2,2,2,2,2,2,0,
0,0,2,2,2,2,0,0,
0,0,4,0,0,4,0,0},
{0,2,2,2,2,2,2,0,
2,2,2,2,2,2,2,2,
2,2,1,1,1,1,2,2,
2,2,3,1,1,3,2,2,
2,2,1,1,1,1,2,2,
0,2,2,2,2,2,2,0,
0,2,2,2,2,2,2,0,
0,0,0,4,4,0,0,0},
{0,2,2,2,2,2,2,0,
2,2,2,2,2,2,2,2,
2,2,2,2,2,2,2,2,
2,2,2,2,2,2,2,2,
2,2,2,2,2,2,2,2,
0,2,2,2,2,2,2,0,
0,0,2,2,2,2,0,0,
0,0,4,0,0,4,0,0},
{0,2,2,2,2,2,2,0,
2,2,2,2,2,2,2,2,
2,2,2,2,2,2,2,2,
2,2,2,2,2,2,2,2,
2,2,2,2,2,2,2,2,
0,2,2,2,2,2,2,0,
0,2,2,2,2,2,2,0,
0,0,0,4,4,0,0,0},
{0,2,2,2,2,2,2,0,
2,2,2,2,2,2,2,2,
2,2,2,2,1,1,1,2,
2,2,2,2,1,1,3,2,
2,2,2,2,1,1,1,2,
0,2,2,2,2,2,2,0,
0,0,2,2,2,2,0,0,
0,0,4,0,4,0,0,0},
{0,2,2,2,2,2,2,0,
2,2,2,2,2,2,2,2,
2,2,2,2,1,1,1,2,
2,2,2,2,1,1,3,2,
2,2,2,2,1,1,1,2,
0,2,2,2,2,2,2,0,
0,2,2,2,2,0,0,0,
0,4,0,0,0,4,0,0},
}
local function drawSp(id,x,y,col,flipH)
local sp=SPR[id]
local skin=SKIN
for i=0,63 do
local c=sp[i+1]
if c~=0 then
local px=flipH and(x+7-(i%8))or(x+(i%8))
local py=y+math.floor(i/8)
if c==1 then pix(px,py,skin)
elseif c==2 then pix(px,py,col)
elseif c==4 then pix(px,py,13)
else pix(px,py,0)end
end
end
end
local function drawPlayer(p)
local dir=p.dir or{0,1}
local dx,dy=dir[1],dir[2]
local step=math.floor(p.walkAnim/4)%2
local id,flip=1,false
if dy>0 then id=1+step
elseif dy<0 then id=3+step
elseif dx>0 then id=5+step;flip=false
else id=5+step;flip=true end
drawSp(id,p.x-camX,p.y-camY,p.color,flip)
end
local ICON_COL={g=5,w=12,y=4,o=3,l=13,c=11,b=9,n=8}
local ICONS={
X={"nnnnnnnn",
"nyyyyyyn",
"nynnnnyn",
"nynnnnyn",
"nynnnyyn",
"nynnnnyn",
"nynnnnyn",
"nnnnnnnn"},
K={"........",
".yyy....",
"y...y...",
"y...yyyy",
"y...y.y.",
".yyy..y.",
"........",
"........"},
E={"...ww...",
"..wwww..",
".wwgwww.",
".wwwwww.",
"wwwgwwww",
".wwwwww.",
".wwwww..",
"..www..."},
B={"......g.",
".y...ggg",
"..l...g.",
".llll...",
"lwllll..",
"llllll..",
"llllll..",
".llll..."},
R={"...oo...",
"...yy...",
"o..yy..o",
".oywwyo.",
".oywwyo.",
"o..yy..o",
"...yy...",
"...oo..."},
S={"cccccccc",
"cwcccccb",
"cwccccbb",
"ccccccbb",
".cccccb.",
".cccccb.",
"..cccb..",
"...cb..."},
}
local HUD_ICONS={
B={"...g.",
".lll.",
"lwlll",
"lllll",
".lll."},
R={"..o..",
".oyo.",
"oywyo",
".oyo.",
"..o.."},
S={"ccccb",
"cwccb",
"ccccb",
".ccb.",
"..b.."},
}
local function drawIcon(rows,x,y)
for j=1,#rows do
local row=rows[j]
for i=1,#row do
local col=ICON_COL[row:sub(i,i)]
if col then pix(x+i-1,y+j-1,col)end
end
end
end
local function drawPowerups()
local bob=(frame//10)%2
for _,pu in ipairs(powerups)do
drawIcon(ICONS[pu.kind],gpx(pu.c)-camX,gpy(pu.r)-bob-camY)
end
end
local function drawPlayers()
for _,p in ipairs(players)do
local blinking=p.invul>0 and frame%8<4
local dying=p.deathT>0 and p.deathT%4<2
if(p.alive and not blinking)or dying then
drawPlayer(p)
if p.alive and p.shield then circb(p.x+3-camX,p.y+3-camY,5+(frame//12)%2,ICON_COL.c)end
end
end
end
local function countAlive()
local n,last=0,nil
for _,p in ipairs(players)do
if p.alive then n=n+1;last=p end
end
return n,last
end
function titleMenu()
local saved=pmem(SAVE_SLOT)
if saved>1 then
return{{L("CONTINUE","DALEJ").." ("..L("STAGE","ETAP").." "..saved..")",false},{L("CONTINUE 2P","DALEJ 2P"),true},
{L("NEW STORY","NOWA GRA"),"new"},{L("BATTLE","BITWA"),"battle"},{L("LANGUAGE: ENGLISH","JĘZYK: POLSKI"),"lang"}}
end
return{{L("STORY","OPOWIEŚĆ"),false},{L("STORY 2P","OPOWIEŚĆ 2P"),true},{L("BATTLE","BITWA"),"battle"},
{L("LANGUAGE: ENGLISH","JĘZYK: POLSKI"),"lang"}}
end
menuSel=1
TITLE_IDLE=900
local LOGO,LOGO_X,LOGO_Y="BLASTIC",57,22
function textW(s,scale)return print(s,0,-20,0,false,scale,true)or 0 end
local function drawLogo(dy)
for i=1,#LOGO do
local x,y=LOGO_X+(i-1)*18,LOGO_Y+(dy and dy(i)or 0)
print(LOGO:sub(i,i),x+2,y+2,2,true,3)
print(LOGO:sub(i,i),x,y,4,true,3)
end
end
local function nightSky(t,cx)
cls(0)
for i=1,40 do pix((i*53-(cx or 0)//4)%240,(i*29)%90,(i+t//40)%9==0 and 14 or 13)end
circ(204,30,9,12)circ(209,27,8,0)
end
local function castle(x,y,c,lit)
rect(x,y+20,80,40,c)rect(x-10,y,18,60,c)rect(x+72,y,18,60,c)rect(x+30,y-10,20,30,c)
for i=0,5 do rect(x+i*14,y+16,8,4,c)end
for i=0,1 do rect(x-10+i*82,y-4,4,4,c)rect(x+4+i*82,y-4,4,4,c)end
if lit then for i=0,2 do rect(x+8+i*28,y+30,4,6,lit)end rect(x+38,y,4,6,lit)end
end
local function drawTitle()
titleTimer=titleTimer+1
if titleTimer==1 then initPalette()initFont()startMusic()end
local t=titleTimer
cls(0)
if not showBackdrop("night")then
nightSky(t)
castle(80,104,15,4)
rect(0,126,240,10,15)
end
drawLogo()
local sub=L("THE SULPHUR LEGEND","LEGENDA O SIARCE")
print(sub,120-textW(sub,1)//2,48,13,false,1,true)
local menu=titleMenu()
local top=60+(5-#menu)*5
rect(62,top,116,#menu*11+6,0)rectb(62,top,116,#menu*11+6,3)rectb(64,top+2,112,#menu*11+2,8)
for i,item in ipairs(menu)do
local label=item[1]
local y=top-7+i*11
local w=textW(label,1)
local x=120-w//2
if i==menuSel then
rect(x-14,y-3,w+20,11,0)rectb(x-14,y-3,w+20,11,4)
circ(x-7,y+2,3,15)pix(x-5,y-2,t%10<5 and 4 or 3)
end
print(label,x,y,i==menuSel and 12 or 14,false,1,true)
end
local keys=L("P1: ARROWS + Z     P2: WASD + TAB","P1: STRZAŁKI + Z     P2: WASD + TAB")
print(keys,120-textW(keys,1)//2,128,14,false,1,true)
if btnp(0)or btnp(1)then
menuSel=(menuSel+(btnp(0)and-2 or 0))%#menu+1
titleTimer=2
end
if btnp(4)or btnp(12)then
local act=menu[menuSel][2]
if act=="battle"then state="game"init()
elseif act=="new"then pmem(SAVE_SLOT,0)menuSel=1
elseif act=="lang"then LANG=LANG=="pl"and"en"or"pl"pmem(LANG_SLOT,LANG=="pl"and 1 or 0)
else startCampaign(act)end
elseif titleTimer>TITLE_IDLE then
state="game"
init()
end
end
function addRoundWin(sc,winnerId)
local out={sc[1],sc[2],sc[3],sc[4]}
if winnerId then out[winnerId]=out[winnerId]+1 end
return out
end
function matchWinner(sc)
for i=1,4 do
if sc[i]>=MATCH_WINS then return i end
end
return nil
end
local HUD_HEAD={".222.","22222","23132","22222",".222."}
local function drawHead(x,y,col)
for j,row in ipairs(HUD_HEAD)do
for i=1,5 do
local k=row:sub(i,i)
if k=="2"then pix(x+i-1,y+j-1,col)
elseif k=="1"then pix(x+i-1,y+j-1,SKIN)
elseif k=="3"then pix(x+i-1,y+j-1,0)end
end
end
end
local HUD_X={2,58,128,184}
function drawPlayerStats(p,x,gap)
local col=p.alive and p.color or 13
local txt=p.alive and 12 or 13
drawHead(x,1,col)
if not p.alive then
line(x,1,x+4,5,BOMB_COL)
line(x+4,1,x,5,BOMB_COL)
end
x=x+gap
drawIcon(HUD_ICONS.B,x,1)
print(p.stats.bombs,x+6,1,txt,false,1,true)
drawIcon(HUD_ICONS.R,x+10,1)
print(p.stats.len,x+16,1,txt,false,1,true)
if p.shield then drawIcon(HUD_ICONS.S,x+21,1)end
end
local function drawHUD()
rect(0,0,W*TILE,7,0)
for i,p in ipairs(players)do
local x=HUD_X[i]
drawPlayerStats(p,x,25)
print(p.human and"P"or"C",x+6,1,p.alive and p.color or 13,false,1,true)
for k=1,MATCH_WINS do
if score[i]>=k then rect(x+8+k*4,2,3,3,4)else rectb(x+8+k*4,2,3,3,13)end
end
end
local left=shrinkAt-roundFrames
local warning=left<=SHRINK_WARN
if left>0 and not(warning and frame%20<10)then
local secs=tostring(left//60+1)
print(secs,120-#secs*2,1,warning and WARN_COL or 12,false,1,true)
end
end
BOSS_HP={utopek=3,jaga=3,dragon=4,devil=6}
local CH_BOSS={"utopek","jaga","dragon","devil"}
local GOAL_CYCLE={"exit","enemies","keys","survive"}
local SCROLLS={"h","v",false}
STAGE_COUNT,CHAPTER_LEN=100,25
function stageDef(n)
local ch,i=(n-1)//CHAPTER_LEN+1,(n-1)%CHAPTER_LEN+1
local boss=i%5==0 and(i==CHAPTER_LEN and CH_BOSS[ch]or CH_BOSS[(i//5-1)%math.min(ch,3)+1])
local foes=not boss
return{ch,boss and"boss"or GOAL_CYCLE[(n-1)%4+1],0.3+0.05*(n%3),
foes and math.min(6,2+n//15)or 0,
foes and ch>=2 and math.min(5,1+(n-26)//15)or 0,
foes and ch>=3 and math.min(3,1+(n-51)//25)or 0,
boss,SCROLLS[n%3+1],boss and BOSS_HP[boss]+ch-1}
end
STAGES={}
for n=1,STAGE_COUNT do STAGES[n]=stageDef(n)end
CHAPTERS={{"WROCLAW","WROCŁAW"},{"MOUNT SLEZA","ŚLĘŻA"},{"KRAKOW","KRAKÓW"},{"THE DEVIL'S CELLARS","PIEKIELNE LOCHY"}}
function chapterName(n)return L(CHAPTERS[n][1],CHAPTERS[n][2])end
local GOALS={exit={"FIND THE EXIT","ZNAJDŹ WYJŚCIE"},enemies={"DEFEAT ALL MONSTERS","POKONAJ POTWORY"},
keys={"FIND 3 KEYS","ZNAJDŹ 3 KLUCZE"},survive={"SURVIVE THE WALLS","PRZETRWAJ MURY"},boss={"DEFEAT THE BOSS","POKONAJ BOSSA"}}
local SKELETON_COL=13
SAVE_SLOT=0
SURVIVE_STEPS=5
mode="pvp"
camX,camY=0,0
monsters={}
boss=nil
hidden={}
camp={}
local function stageSize(scroll)
if scroll=="h"then return 62,18 elseif scroll=="v"then return 32,34 end
return 32,18
end
local function heroAt(c,r)
for _,p in ipairs(players)do
if p.alive and p.team==1 and p.c==c and p.r==r then return p end
end
return nil
end
local function dratewka()return players[1]end
local function farCells(ok,minDist)
local out={}
for r=1,H-2 do for c=1,W-2 do
if ok(c,r)and math.abs(c-STARTS[1][1])+math.abs(r-STARTS[1][2])>=minDist then out[#out+1]={c,r}end
end end
for i=#out,2,-1 do local j=math.random(i)out[i],out[j]=out[j],out[i]end
return out
end
local function hideItems(kind,n)
local crates=farCells(function(c,r)return mget(c,r)==T_BLOCK end,(W+H)//4)
local floor=farCells(function(c,r)return mget(c,r)==T_EMPTY end,(W+H)//4)
for i=1,n do
local cell=table.remove(crates)
if cell then hidden[cell[1]*100+cell[2]]=kind
else cell=table.remove(floor)powerups[#powerups+1]={c=cell[1],r=cell[2],kind=kind}end
end
end
local function spawnMonster(kind,c,r)
monsters[#monsters+1]={kind=kind,c=c,r=r,x=gpx(c),y=gpy(r),d={0,0}}
end
function startStage(n)
local st=STAGES[n]
camp.stage,camp.keys,camp.done=n,0,false
math.randomseed(n*7919+camp.tries)
setArena(stageSize(st[8]))
blockDensity=st[3]
bombs,blasts,powerups,monsters,hidden,boss={},{},{},{},{},nil
initMap()
players={}
local function hero(id,c,r)
local p=newPlayer(id,c,r)
p.team,p.human=1,id==1 or camp.coop
p.stats={bombs=camp.stats[id].bombs,len=camp.stats[id].len}
players[#players+1]=p
end
hero(1,STARTS[1][1],STARTS[1][2])
if st[1]>=2 then hero(2,STARTS[1][1],STARTS[1][2]+1)end
local far={STARTS[4],STARTS[st[8]=="v"and 3 or 2]}
for i=1,st[6]do
local p=newPlayer(2+i,far[i][1],far[i][2])
p.team,p.human,p.color=2,false,SKELETON_COL
players[#players+1]=p
end
local free=farCells(function(c,r)return mget(c,r)==T_EMPTY end,8)
for _=1,st[4]do local cell=table.remove(free)if cell then spawnMonster("g",cell[1],cell[2])end end
for _=1,st[5]do local cell=table.remove(free)if cell then spawnMonster("b",cell[1],cell[2])end end
if st[2]=="exit"then hideItems("X",1)elseif st[2]=="keys"then hideItems("K",3)end
if st[7]then
local c,r=W//2-1,H//2-1
for dc=0,1 do for dr=0,1 do mset(c+dc,r+dr,T_EMPTY)end end
boss={kind=st[7],c=c,r=r,x=gpx(c),y=gpy(r),hp=st[9],max=st[9],t=0,inv=0}
if st[7]=="dragon"then hideItems("E",1)end
end
resetShrink()
if st[2]=="survive"then shrinkAt,zoneCycle=600,SHRINK_WARN else shrinkAt=math.huge end
frame,state,restartTimer=0,"game",0
end
local function chapterStart(n)
return n==1 or STAGES[n][1]~=STAGES[n-1][1]
end
function startCampaign(coop)
mode="camp"
local saved=pmem(SAVE_SLOT)
camp={coop=coop,lives=3,tries=0,friend=false,stage=(saved>=1 and saved<=#STAGES)and saved or 1,
stats={{bombs=MAX_BOMBS,len=BLAST_LEN},{bombs=MAX_BOMBS,len=BLAST_LEN}}}
beginChapterOrMap(camp.stage)
end
function beginChapterOrMap(n)
camp.stage=n
pmem(SAVE_SLOT,n)
if chapterStart(n)then
camp.stats={{bombs=MAX_BOMBS,len=BLAST_LEN},{bombs=MAX_BOMBS,len=BLAST_LEN}}
playScene(SCENE_OF_CHAPTER[STAGES[n][1]],function()showMap(n)end)
else
showMap(n)
end
end
local MONSTER_PERIOD={g=3,b=2}
local function updateMonsters()
for i=#monsters,1,-1 do
local m=monsters[i]
if isBlast(m.c,m.r)then
table.remove(monsters,i)
elseif frame%MONSTER_PERIOD[m.kind]==0 then
if m.x==gpx(m.c)and m.y==gpy(m.r)then
if m.kind=="b"then
local path=botPath(m.c,m.r,botPassable,heroAt)
m.d=path and{path[1].c-m.c,path[1].r-m.r}or{0,0}
elseif math.random()<0.15 or not botPassable(m.c+m.d[1],m.r+m.d[2])then
m.d=BOT_DIRS[math.random(4)]
end
if not botPassable(m.c+m.d[1],m.r+m.d[2])then m.d={0,0}end
end
m.x,m.y=m.x+m.d[1],m.y+m.d[2]
m.c,m.r=gcol(m.x+TILE//2),grow(m.y+TILE//2)
end
end
end
local function bossCovers(b,c,r)
return c>=b.c and c<=b.c+1 and r>=b.r and r<=b.r+1
end
local function bossFree(c,r)
for dc=0,1 do for dr=0,1 do
if not botPassable(c+dc,r+dr)or heroAt(c+dc,r+dr)then return false end
end end
return true
end
local function bossTeleport(b)
local spots=farCells(function(c,r)return bossFree(c,r)end,0)
local a=dratewka()
for _,s in ipairs(spots)do
if math.abs(s[1]-a.c)+math.abs(s[2]-a.r)>=6 then
b.c,b.r,b.x,b.y=s[1],s[2],gpx(s[1]),gpy(s[2])
return
end
end
end
local function bossFire(b)
if not b.warn then
local a=dratewka()
b.warn={row=math.random()<0.5,c=a.c,r=a.r,t=60}
else
b.warn.t=b.warn.t-1
if b.warn.t<=0 then
for k=1,(b.warn.row and W or H)-2 do
local c,r=b.warn.row and k or b.warn.c,b.warn.row and b.warn.r or k
if mget(c,r)==T_EMPTY and not bossCovers(b,c,r)then addBlast(c,r,BOSS_FIRE)end
end
b.warn=nil
end
end
end
local function updateBoss()
local b=boss
if not b or b.hp<=0 then return end
b.t=b.t+1
if b.inv>0 then b.inv=b.inv-1 end
for dc=0,1 do for dr=0,1 do
for _,bl in ipairs(blasts)do
if b.inv==0 and bl.owner~=BOSS_FIRE and bl.c==b.c+dc and bl.r==b.r+dr then
b.hp,b.inv=b.hp-1,60
sndShield()
end
end
end end
local kind=b.kind
if kind=="devil"then kind=b.hp>4 and"jaga"or b.hp>2 and"summon"or"dragon"end
if kind=="utopek"and b.t%3==0 then
local a=dratewka()
if b.x==gpx(b.c)and b.y==gpy(b.r)then
b.d={0,0}
for _,d in ipairs(BOT_DIRS)do
local nc,nr=b.c+d[1],b.r+d[2]
if bossFree(nc,nr)and math.abs(nc-a.c)+math.abs(nr-a.r)<math.abs(b.c-a.c)+math.abs(b.r-a.r)then b.d=d end
end
end
b.x,b.y=b.x+b.d[1],b.y+b.d[2]
b.c,b.r=gcol(b.x+TILE//2),grow(b.y+TILE//2)
elseif(kind=="jaga"or kind=="summon")and b.t%150==0 then
if kind=="summon"then spawnMonster("g",b.c,b.r)end
bossTeleport(b)
if kind=="jaga"then bombs[#bombs+1]={c=b.c,r=b.r,t=BOMB_TIMER,len=3,owner=BOSS_FIRE}end
elseif kind=="dragon"and(b.warn or b.t%120==0)then
bossFire(b)
end
end
local function stageGoalMet()
local goal=STAGES[camp.stage][2]
if goal=="exit"then return camp.done
elseif goal=="keys"then return camp.keys>=3
elseif goal=="survive"then return zoneSteps>=SURVIVE_STEPS
elseif goal=="boss"then return boss.hp<=0 or camp.friend end
for _,p in ipairs(players)do if p.alive and p.team==2 then return false end end
return#monsters==0
end
local function updateCamera()
local x,y,n=0,0,0
for _,p in ipairs(players)do
if p.team==1 and p.alive then x,y,n=x+p.x,y+p.y,n+1 end
end
if n==0 then return end
camX=math.max(0,math.min((W-2)*TILE-240,x//n-116))
camY=math.max(0,math.min((H-2)*TILE-128,y//n-60))
end
function updateCampaign()
updateMonsters()
updateBoss()
local heroes=0
for _,p in ipairs(players)do
if p.alive and p.team==1 then
collectPowerup(p)
for _,m in ipairs(monsters)do if m.c==p.c and m.r==p.r then blastHit(p)end end
if boss and boss.hp>0 and not camp.friend and bossCovers(boss,p.c,p.r)then blastHit(p)end
if p.alive then heroes=heroes+1 end
end
end
updateCamera()
if heroes==0 then
camp.lives=camp.lives-1
state,restartTimer=camp.lives>0 and"lost"or"gameover",150
elseif stageGoalMet()then
for _,p in ipairs(players)do
if p.team==1 then camp.stats[p.id]={bombs=p.stats.bombs,len=p.stats.len}end
end
state,restartTimer="clear",120
end
end
function campaignNext()
if state=="clear"then
camp.tries=0
if camp.stage==#STAGES then
pmem(SAVE_SLOT,0)
playScene("ending",function()mode="pvp"state="title"titleTimer=2 end)
else
beginChapterOrMap(camp.stage+1)
end
elseif state=="lost"then
camp.tries=camp.tries+1
startStage(camp.stage)
else
mode,state,titleTimer="pvp","title",2
end
end
local ART_COL={g=5,k=0,w=12,d=15,r=2,y=4,s=10,t=7,p=9,o=3,c=13}
local ART={
g={"...rr...","..rrrr..",".rrrrrr.","..skks..","..ssss..",".wwwwww.",".pwwwwp.","..d..d.."},
b={"d......d","dd.dd.dd","ddddddd.",".drddrd.","..dddd..","...dd...","........","........"},
utopek={"..tttt..",".tttttt.","tggggggt","gwkggwkg","gggggggg","g.kkkk.g",".gggggg.","t.g..g.t"},
jaga={"..rrrr..",".rrrrrr.","rrssssrr",".skssks.",".sssoss.",".csssc..",".dddddd.","dddddddd"},
dragon={"r......r","rr.rr.rr","rrrrrrrr","rwkrrwkr","rrrrrrrr","ryyyyyyr",".rr..rr.","rr....rr"},
heart={"........",".rr.rr..","rrrrrrr.","rrrrrrr.",".rrrrr..","..rrr...","...r....","........"},
devil={"k......k",".krrrrk.","rrrrrrrr","ryrrrryr","rrrrrrrr","kkkrrkkk",".rrrrrr.","r.dddd.r"},
}
function drawArt(name,x,y,scale,flash)
local rows=ART[name]
for j=1,8 do
local row=rows[j]
for i=1,8 do
local col=ART_COL[row:sub(i,i)]
if col then rect(x+(i-1)*scale,y+(j-1)*scale,scale,scale,flash and 12 or col)end
end
end
end
local function drawMonsters()
for _,m in ipairs(monsters)do drawArt(m.kind,m.x-camX,m.y-camY,1)end
end
local function drawBoss()
local b=boss
if not b or b.hp<=0 or camp.friend then return end
if b.warn and frame%8<4 then
for k=1,(b.warn.row and W or H)-2 do
local c,r=b.warn.row and k or b.warn.c,b.warn.row and b.warn.r or k
rectb(gpx(c)-camX,gpy(r)-camY,TILE,TILE,BOMB_COL)
end
end
drawArt(b.kind,b.x-camX,b.y-camY,2,b.inv>0 and frame%6<3)
end
local function drawCampaignHUD()
rect(0,0,240,7,0)
for k=1,camp.lives do drawArt("heart",2+(k-1)*7,0,1)end
print(STAGES[camp.stage][1].."-"..((camp.stage-1)%CHAPTER_LEN+1),24,1,12,false,1,true)
local x=44
for _,p in ipairs(players)do
if p.team==1 then
drawPlayerStats(p,x,7)
x=x+40
end
end
local goal,txt=STAGES[camp.stage][2],nil
if goal=="keys"then txt=L("KEYS ","KLUCZE ")..camp.keys.."/3"
elseif goal=="enemies"then
local n=#monsters
for _,p in ipairs(players)do if p.alive and p.team==2 then n=n+1 end end
txt=L("LEFT ","ZOSTAŁO ")..n
elseif goal=="survive"then txt=L("HOLD ON ","WYTRWAJ ")..math.max(0,SURVIVE_STEPS-zoneSteps)
elseif goal=="exit"then txt=L("FIND EXIT","SZUKAJ WYJŚCIA")end
if txt then print(txt,238-#txt*4,1,12,false,1,true)end
if goal=="boss"and boss then
rect(160,2,74,3,15)
rect(160,2,74*math.max(0,boss.hp)//boss.max,3,BOMB_COL)
end
end
function drawCampaign()
if frame%50<6 then
for k in pairs(hidden)do
local c,r=k//100,k%100
if mget(c,r)==T_BLOCK then
local x,y=gpx(c)-camX+5,gpy(r)-camY+2
line(x-1,y,x+1,y,12)line(x,y-1,x,y+1,12)
end
end
end
drawMonsters()
drawBoss()
drawCampaignHUD()
local msg=state=="clear"and L("STAGE CLEAR!","ETAP ZALICZONY!")or state=="lost"and L("OUCH!","AUĆ!")
or state=="gameover"and L("GAME OVER","KONIEC GRY")
if msg then
if state=="clear"then
for k=1,40 do
pix((k*53+frame*(k%3+1))%240,(k*29+frame*(k%4+1))%136,k%15+1)
end
end
print(msg,120-textW(msg,2)//2,52+(state=="clear"and math.floor(math.sin(frame/6)*3)or 0),12,false,2,true)
if state=="lost"then print(L("LIVES LEFT: ","ŻYCIA: ")..camp.lives,90,72,13,false,1,true)end
restartTimer=restartTimer-1
if restartTimer<=0 or(restartTimer<90 and btnp(4))then campaignNext()end
end
end
BAR=20
do
local sin,cos=math.sin,math.cos
function dragonFire(x,y,s,t)
local mx,my=x+34*s,y-35*s
for k=0,2 do
local l=(24+k*6+t%4*2)*s
tri(mx,my,mx+l,my-(10-k*3)*s,mx+l,my+(10-k*3)*s,({2,3,4})[k+1])
end
end
function rising(t,n,x,y,w,h,c1,c2)
for k=0,n do
local p=(t+k*23)%h
pix(x+(k*41)%w+sin(t/15+k)*3,y-p,p<h//2 and c1 or c2)
end
end
function birds(t,n,y,c)
for k=0,n-1 do
local x,by=(t*0.6+k*97)%300-30,y+k*7+sin(t/12+k)*3
local up=(t//6+k)%2
pix(x,by,c)pix(x-1,by-1+up*2,c)pix(x+1,by-1+up*2,c)pix(x-2,by-up,c)pix(x+2,by-up,c)
end
end
function puff(t)
if t<0 or t>=70 then return end
for k=0,9 do
local a,r=k*0.628,t*0.9
circ(120+cos(a)*r,72+sin(a)*r*0.5-t/4,math.max(0,8-t//9),t<35 and 13 or 14)
end
end
function fireworks(t)
for k=0,4 do
local p=(t+k*29)%80
local n=(t+k*29)//80
local x,y=(k*67+n*41)%180+30,36+(k*31+n*17)%36
if p<10 then pix(x,y+40-p*4,13)
elseif p<50 then
for j=0,11 do
local a,r=j*0.5236,(p-10)*0.7
circ(x+cos(a)*r,y+sin(a)*r+(p-10)^2/120,1,(p<44)and(k%4)+2 or 14)
end
end
end
end
function fuse(x,y,t)
for k=0,4 do pix(x+sin(t*2+k*2)*2,y-(t+k*3)%6,({4,3,12,4,2})[k+1])end
end
function magic(m,cx,t)
if t>=(m[5]or math.huge)then return end
local x0,y0,x,y=m[1]-cx,m[2],m[3]-cx,m[4]
if t//20%3>0 then
local px,py=x0,y0
for k=1,6 do
local nx,ny=x0+(x-x0)*k/6,y0+(y-y0)*k/6+(k<6 and sin(t*3+k*7)*5 or 0)
line(px,py,nx,ny,k%2==0 and 12 or 6)
px,py=nx,ny
end
end
circb(x,y,7+t//3%4,6)
for k=0,15 do
local p=(t*2+k*17)%48
pix(x+sin(t/9+k)*(8+p/5),y+16-p,k%3==0 and 12 or k%3==1 and 6 or 5)
end
end
function glow(x,y,r,c,step)
for j=-r,r do for i=-r,r do
if(i+j)%step==0 and i*i+j*j<r*r then pix(x+i,y+j,c)end
end end
end
function boom(x,y,t)
if t<0 or t>60 then return end
if t<3 then rect(0,BAR,240,136-2*BAR,12)end
if t<18 then
circ(x,y,t*2.2,2)circ(x,y,t*1.6,3)circ(x,y,t,4)
else
for k=0,7 do
local a=k*0.785+t/40
circ(x+cos(a)*(t-10),y+sin(a)*(t-10)*0.5-(t-18)/2,math.max(0,9-(t-18)//5),t<36 and 13 or 14)
end
end
for k=0,11 do pix(x+cos(k*0.52)*t*1.8,y+sin(k*0.52)*t*1.2+t*t/60,k%2==0 and 4 or 0)end
end
end
-- [tic80_unload] chunk "story" (was loaded from address 69988)

local sin,cos=math.sin,math.cos
local ART_RAM,BACKDROP_RAM,BACKDROP_BYTES=0x08000,0x11164,11520
SUB_Y=127
local palBase,palShot,sky,fadeK
local function fadePal(k)
fadeK=k
for i=0,47 do poke(0x03FC0+i,palShot[i]*k//1)end
end
local function word(p)return peek(p)|peek(p+1)<<8 end
local function addr(p)return word(p)|peek(p+2)<<16 end
local function nameAt(p)
local s={}
for i=1,peek(p)do s[i]=string.char(peek(p+i))end
return table.concat(s),p+peek(p)+1
end
local backdrops,castRuns
local mapBank,syncFrame=0,nil
CAST=nil
local function loadCast()
if mapBank~=0 then sync(4,0)mapBank,syncFrame=0,frame end
backdrops,CAST={},{}
local p=ART_RAM+2
for _=1,peek(ART_RAM)do
local name
name,p=nameAt(p)
local e={peek(p),addr(p+1)}
for i=1,18 do e[2+i]=peek(p+3+i)end
backdrops[name]=e
p=p+22
end
local src={}
for k=0,peek(p)-1 do
local at=addr(p+1+k*5)
for i=0,word(p+4+k*5)-1 do src[#src+1]=peek(at+i)end
end
local a,o,n=1,{},0
while a<=#src do
local c=src[a]
if c<128 then
for i=1,c+1 do n=n+1 o[n]=string.char(src[a+i])end
a=a+c+2
else
local d=src[a+1]|src[a+2]<<8
for _=1,c-125 do n=n+1 o[n]=o[n-d]end
a=a+3
end
end
castRuns=table.concat(o)
local i,byte=1,string.byte
for _=1,peek(ART_RAM+1)do
local len=byte(castRuns,i)
local name=castRuns:sub(i+1,i+len)
local w,h,ox,oy=byte(castRuns,i+len+1,i+len+4)
i=i+len+5
CAST[name]={i,w,h,ox,oy}
for _=1,h do
local x=0
while x<w do x=x+(byte(castRuns,i)&15)+1 i=i+1 end
end
end
end
local function sprite(name,x,y,left,bw)
local sp=CAST[name]
if not sp then return end
local a,w,h,ox,oy=table.unpack(sp)
if left then ox=(bw or w)-ox-w end
local byte=string.byte
for j=0,h-1 do
local i=0
while i<w do
local b=byte(castRuns,a)
local c,n=b>>4,(b&15)+1
if c~=11 then rect(x+(left and ox+w-i-n or ox+i),y+oy+j,n,1,c)end
a,i=a+1,i+n
end
end
end
local function loadBackdrop(name)
palShot,sky={},nil
for i=0,47 do palShot[i]=palBase[i]end
local e=backdrops[name]
if not e then return false end
for i,c in ipairs{1,5,7}do
for j=0,2 do palShot[c*3+j]=e[i*3+j]end
end
sky={{e[12],e[13],e[14]},{e[15],e[16],e[17]},{e[18],e[19],e[20]}}
if e[1]~=mapBank then
if syncFrame==frame then return"wait"end
sync(4,e[1])mapBank,syncFrame=e[1],frame
end
local src,dst=e[2],BACKDROP_RAM
while dst<BACKDROP_RAM+BACKDROP_BYTES do
local c=peek(src)
if c<128 then memcpy(dst,src+1,c+1)src,dst=src+c+2,dst+c+1
else
local d,n=word(src+1),c-125
if d>=n then memcpy(dst,dst-d,n)else for i=0,n-1 do poke(dst+i,peek(dst+i-d))end end
src,dst=src+3,dst+n
end
end
return true
end
function BDR(row)
local y=row-4-BAR
if not sky or y<0 or y>95 then return end
local k=y/95*2
local i=math.min(1,k//1)
local a,b,f=sky[i+1],sky[i+2],k-i
for c=1,3 do poke(0x03FC0+32+c,(a[c]+(b[c]-a[c])*f)*fadeK//1)end
end
SPEAKER_WHO={DRATEWKA="dratewka",WANDA="wanda",KRAK="krak",TWARDOWSKI="twardowski",
DEVIL="devil",["BABA JAGA"]="jaga"}
STRIDE={man=0.732,dwarf=0.497}
local function drawCast(who,x,y,s,t,left,walk,talking,roar,anim)
if s>=4 then
local b=CAST["bust_"..who]
if not b then return end
local bx,by=x-b[2]//2,136-BAR-b[3]+math.max(0,14-t)*3+t//40%2
sprite("bust_"..who,bx,by,left)
if talking and t//5%2==0 then sprite("talk_"..who,bx,by,left,b[2])end
if t%170<6 then sprite("blink_"..who,bx,by,left,b[2])end
return
end
local name,lift=who..(s==1 and"_far"or""),0
if who=="dragon"then
name=name..(roar and"_roar"or({"_a","","_b",""})[t//(walk and 5 or 9)%4+1])
elseif walk and CAST[name.."_w0"]then
name=name.."_w"..math.floor(walk*8/(CAST[name][3]*(STRIDE[who]or STRIDE.man)))%8
elseif(walk or anim)and CAST[name.."_a"]then
local b=(anim and t//7 or walk//(CAST[name][3]//5))%2==1
name,lift=name..(b and"_b"or"_a"),b and walk and not anim and 1 or 0
end
local sp=CAST[name]
if not sp then return end
sprite(name,x-sp[2]//2,y-sp[3]-lift,left)
end
local OVERLAYS={
rynek=function(t)birds(t,3,34,0)end,
odra=function(t)
birds(t,5,30,0)
for k=0,20 do pix((k*37+t//5)%240,88+k%8*3,(t//9+k)%4==0 and 12 or 13)end
end,
forest=function(t)
for k,e in ipairs{{70,44},{196,58}}do
if(t//30+k)%6~=0 then pix(e[1],e[2],4)pix(e[1]+3,e[2],4)end
end
rising(t,6,0,100,240,60,5,6)
end,
sleza_far=function(t)for k=0,6 do line((k*50+t//3)%300-40,80+k%3*2,(k*50+t//3)%300-20,80+k%3*2,13)end end,
krakow=function(t)
birds(t,4,36,0)
if t>40 then
pix(171,52,t//6%2==0 and 4 or 12)
for k=0,3 do pix(174+k*3+sin(t/8+k)*2,50-(t+k*9)%24,12)end
end
end,
sleza=function(t)rising(t,10,106,74,12,40,4,2)rising(t,5,0,100,240,50,4,6)end,
cellars=function(t)
rising(t,24,0,116,240,90,4,2)
rising(t,5,34,78,24,10,5,12)
end,
workshop=function(t)rect(89,70+t//5%2,2,4,t//3%2==0 and 4 or 3)end,
wawel=function(t)
for k=0,14 do pix((k*53+t//4)%240,106+k%4*3,t//8%2==k%2 and 12 or 4)end
birds(t,4,40,0)
end,
night=function(t)
for k=0,6 do pix((k*67)%240,24+(k*29)%40,(t//20+k)%3==0 and 12 or 13)end
local p=t%240
if p<24 then line(200-p*6,26+p*2,206-p*6,24+p*2,12)end
end,
}
local ROMAN={"I","II","III","IV"}
local EMBLEM={"dwarf","jaga","dragon","devil"}
local function chapterCard(n,t)
rectb(28,26,184,84,4)rectb(31,29,178,78,3)
for _,c in ipairs{{28,26},{211,26},{28,109},{211,109}}do
circ(c[1],c[2],3,4)circ(c[1],c[2],1,2)
end
local top,title=L("CHAPTER ","ROZDZIAŁ ")..(ROMAN[n]or""),CHAPTERS[n]and chapterName(n)
if not title then top,title=L("THE","TO"),L("END","KONIEC")end
print(top,120-textW(top,1)//2,36,3,false,1,true)
print(title:sub(1,t//3),120-textW(title,2)//2+1,47,2,false,2,true)
print(title:sub(1,t//3),120-textW(title,2)//2,46,4,false,2,true)
local name=(EMBLEM[n]or"dratewka").."_far"
local e=CAST and CAST[name]
if e and t>40 then sprite(name,120-e[2]//2,104-e[3],false)end
end
local IRIS=36
local function iris(k)
local r=k*150
for y=BAR,135-BAR do
local d=y-68
if math.abs(d)>=r then rect(0,y,240,1,0)
else
local h=math.sqrt(r*r-d*d)//1
rect(0,y,120-h,1,0)rect(120+h,y,120-h+1,1,0)
end
end
end
local function every(fx,step,off,f)for x=(off-fx)%step-step,240,step do f(x)end end
local function lamp(x)
rect(x,40,3,96,0)rect(x-3,32,9,9,0)rect(x-2,34,5,5,4)
end
local function blades(fx,t,c)
every(fx,9,0,function(x)
local h=10+(x*7)%9
tri(x,116,x+3,116,x+1+sin(t/20+x)*2,116-h,c)
end)
end
local FOREGROUNDS={
krakow=function(fx)every(fx,190,60,lamp)end,
sleza=function(fx,t)blades(fx,t,0)every(fx,160,40,function(x)circ(x,116,12,0)circ(x+14,118,8,0)end)end,
road=function(fx,t)blades(fx,t,0)every(fx,300,200,function(x)rect(x,70,3,46,0)rect(x-8,72,22,6,0)end)end,
wawel=function(fx,t)every(fx,7,0,function(x)
local h=14+(x*5)%11
line(x,116,x+sin(t/25+x)*2,116-h,0)rect(x-1+sin(t/25+x)*2,114-h,3,5,0)end)end,
night=function(fx)every(fx,420,0,function(x)
rect(x,20,7,96,0)circ(x+3,28,16,0)circ(x-10,44,11,0)circ(x+16,48,12,0)circ(x+4,60,9,0)end)end,
}
local function closeUp(who,x,left)return{{who,x,126,x,126,0,0,4,left}}end
local SPEAKER_PL={DEVIL="DIABEŁ",DRAGON="SMOK",DWARF="KRASNAL"}
GRAVITY=0.109
local WITCH_A,WITCH_B={112,84,124,-0.84},{112,84,124,-3.1416}
SCENES={
wroclaw={
{bd="odra",len=230,pan=60,cap={"WROCLAW","WROCŁAW"}},
{bd="rynek",len=200,pan=50,act={{"dwarf",-10,108,96,108,0,190},{"dwarf",250,108,170,108,30,160,2,true}}},
{bd="wawel",len=170,cap={"MEANWHILE, IN KRAKOW","TYMCZASEM W KRAKOWIE"},
act={{"sheep",150,104,150,104,0,0,2,hide=95},{"dragon",-80,64,300,24,10,160,1},
{"sheep",150,104,300,40,95,160,2,show=95}}},
{bd="rynek",len=170,act={{"dwarf",-10,108,52,108,0,100},{"poster",-10,64,52,64,0,100,1,hide=102},
{"poster",64,98,64,98,0,0,1,show=102}},shake=102},
{bd="rynek",len=120,act={{"poster",120,112,120,112,0,0,2}},label={142,92,"1/2"}},
{bd="rynek",len=170,act={{"poster",64,98,64,98,0,0,1},{"dratewka",250,108,96,108,0,150,2,true}}},
{bd="rynek",fx="idea",len=90,act=closeUp("dratewka",110)},
{bd="workshop",len=140,act={{"dratewka",70,108,70,108,0,0},{"sack",100,108,100,108,0,0},
{"sheep",130,100,130,100,0,0,2,spark=40,hide=96}},booms={{132,90,96}}},
{bd="workshop",fx="soot",act=closeUp("dratewka",110),
say={{"DRATEWKA","...less sulphur next time.","...następnym razem mniej siarki."}}},
{bd="night",len=210,pan=30,act={{"rider",-60,64,300,36,0,200,1,anim=true}}},
{bd="odra",len=190,act={{"dratewka",-10,76,110,76,0,190,1},{"sheep",-26,76,94,76,0,190,1}}},
{bd="black",len=120,title=1},
},
sleza={
{bd="road",len=170,pan=50,cap={"THE ROAD SOUTH","DROGA NA POŁUDNIE"},
act={{"dratewka",-10,108,100,108,0,170,1},{"sheep",-26,108,84,108,0,170,1}}},
{bd="sleza_far",len=220,pan=50,cap={"MOUNT SLEZA","ŚLĘŻA"}},
{bd="forest",len=210,act={{"fox",-30,106,280,106,0,70,2,anim=true},
{"dratewka",-10,108,130,108,80,200},{"sheep",-28,108,112,108,80,200}}},
{bd="sleza",len=200,cap={"KUPALA NIGHT","NOC KUPAŁY"},magic={96,80,150,88},
act={{"witch",56,104,56,104,0,0,2,anim=true,orbit=WITCH_A},{"witch",196,104,196,104,0,0,2,anim=true,orbit=WITCH_B},
{"jaga",84,108,84,108,0,0,2,false,anim=true},{"wanda",150,108,150,108,0,0,2,true}}},
{bd="sleza",len=80,act={{"sheep",120,104,120,104,0,0,2,spark=0}}},
{bd="sleza",len=160,magic={96,80,150,88,80},act={{"wanda",150,108,150,108,0,0,2,true},
{"witch",56,104,56,104,0,0,2,anim=true,hide=62,orbit=WITCH_A},{"witch",196,104,196,104,0,0,2,anim=true,hide=62,orbit=WITCH_B},
{"jaga",84,108,84,108,0,0,2,false,anim=true,hide=82},{"dratewka",-20,108,24,108,0,40},
{"sheep",36,94,112,100,44,80,2,arc=true,spark=0,hide=80},
{"witch_fly",56,90,-60,10,82,130,2,true,show=82},{"witch_fly",196,90,320,0,82,130,2,false,show=82},
{"jaga_fly",84,90,280,-20,82,140,2,false,show=82}},booms={{112,96,80}}},
{bd="sleza",act=closeUp("wanda",120,true),say={{"WANDA","I had them.","Dałabym sobie radę."}}},
{bd="sleza",fx="flash",act=closeUp("jaga",130,true),
say={{"BABA JAGA","Twardowski sends his regards!","Pozdrowienia od Twardowskiego!"}}},
{bd="black",len=120,title=2},
},
krakow={
{bd="wawel",len=210,pan=50,cap={"KRAKOW","KRAKÓW"}},
{bd="krakow",len=220,pan=40,shake=130,act={{"dragon",-80,50,320,30,120,210,1}}},
{bd="wawel",len=140,act={{"dragon",64,110,64,110,0,0,2},{"wanda",204,108,204,108,0,0,2,true},
{"dratewka",174,108,174,108,0,0,2,true},{"sheep",160,94,104,56,40,80,2,arc=true,spark=0,hide=80}}},
{bd="wawel",fx="fire",act={{"dragon",90,124,90,124,0,0,2}},
say={{"DRAGON","*burp* Spicy! Who sent you?","*bek* Ostre! Kto was przysłał?"}}},
{bd="night",len=210,cap={"LAST NIGHT","ZESZŁEJ NOCY"},
act={{"devil",-20,108,220,108,0,200},{"egg",-6,94,234,94,0,200,1}}},
{bd="night",fx="flash",act=closeUp("twardowski",120,true),
say={{"TWARDOWSKI","The devil holds my pact. Burn it!","Diabeł ma mój cyrograf. Spalcie go!"}}},
{bd="black",len=120,title=3},
},
cellars={
{bd="black",fx="stairs",len=270,cap={"DOWN TO HELL","ZEJŚCIE DO PIEKŁA"},
act={{"dratewka",-10,39,250,120,0,250},{"sheep",-28,34,232,115,10,260},{"wanda",-40,30,220,111,30,260}}},
{bd="cellars",len=220,cap={"THE DEVIL'S CELLARS","PIEKIELNE LOCHY"},
act={{"devil",214,108,214,108,0,0,2,false,hide=135},{"devil",214,108,214,108,0,0,2,true,show=135,hop=3},
{"wanda",-30,108,96,108,20,130},{"dratewka",-10,108,128,108,10,130},{"sheep",-26,108,112,108,10,130}}},
{bd="cellars",len=130,shake=30,booms={{146,106,30},{126,100,52}},
act={{"devil",214,108,214,108,0,0,2,true,hop=2},{"wanda",96,108,96,108,0,0,2,false},
{"dratewka",128,108,100,108,30,60,2,false,arc=true},{"sheep",112,108,84,108,30,60}}},
{bd="cellars",fx="flash",act=closeUp("devil",120,true),
say={{"DEVIL","A shoemaker? Against me?","Szewczyk? Przeciwko mnie?"}}},
{bd="cellars",act={closeUp("dratewka",100)[1],{"sheep",170,112,170,112,0,0,2,true,spark=0}},
say={{"DRATEWKA","I brought sheep.","Przyniosłem owce."}}},
{bd="black",len=120,title=4},
},
ending={
{bd="cellars",len=170,act={{"wanda",-30,108,36,108,0,60},{"dratewka",-10,108,66,108,0,60},
{"twardowski",-50,108,10,108,0,60},{"devil",214,108,214,108,0,0,2,true,hide=104},
{"sheep",76,94,191,62,64,104,2,arc=true,spark=0,hide=104},
{"devil",214,108,320,90,106,150,2,arc=true,show=106}},
booms={{191,62,104}}},
{bd="cellars",fx="shake",act={{"devil",200,108,200,108,0,0,2,true,hop=6}},
say={{"DEVIL","My pact! Noooo!","Mój cyrograf! Nieee!"}}},
{bd="night",act={{"rider",40,104,224,56,20,200,1,anim=true}},
say={{"TWARDOWSKI","It's quieter up there.","Tam będzie spokojniej."}}},
{bd="hall",act={{"krak",120,108,120,108,0,0},{"wanda",-30,108,68,108,0,90},
{"dratewka",250,108,174,108,0,80,2,true},{"cheese",128,82,166,92,175,215,1,arc=true,show=175}},
say={{"KRAK","Your reward!","Twoja nagroda!"},{"WANDA","Half the kingdom, father.","Pół królestwa, ojcze."},
{"KRAK","Half the cheese?","Pół sera?"}}},
{bd="night",fx="fireworks",len=240},
{bd="odra",len=180,act={{"wanda",-40,76,60,76,0,170,1},{"dratewka",-10,76,90,76,0,170,1},
{"sheep",-26,76,74,76,0,170,1}}},
{bd="rynek",len=200,act={{"dwarf",40,108,40,108,0,0,2,hop=4},{"dwarf",206,108,206,108,0,0,2,true,hop=5},
{"wanda",-40,108,96,108,0,130},{"dratewka",-10,108,126,108,0,130},{"sheep",-26,108,110,108,0,130}}},
{bd="black",len=200,title="end"},
},
}
SCENE_OF_CHAPTER={"wroclaw","sleza","krakow","cellars"}
local SCENE_MOOD={sleza="calm",krakow="tension",cellars="tension",ending="joy"}
local scene,backdrop,shown
local READ_FRAMES,FADE=100,12
local SPEAKER_COL={DRATEWKA=3,WANDA=4,KRAK=4,TWARDOWSKI=13,DEVIL=2,["BABA JAGA"]=6,DRAGON=2,DWARF=12}
local function nextShot()
local s=scene
s.n=s.n+1
local sh=s.shots[s.n]
if not sh then
palShot,sky=palBase,nil
fadePal(1)
musicMood(nil)
scene=nil
s.after()
return
end
backdrop,shown=loadBackdrop(sh.bd),nil
local stop=0
for _,a in ipairs(sh.act or{})do stop=math.max(stop,a[7])end
s.sh,s.t,s.line,s.lineT,s.start,s.leave=sh,0,1,0,stop+10,nil
end
function showBackdrop(name)
if not palBase then
initPalette()
palBase={}
for i=0,47 do palBase[i]=peek(0x03FC0+i)end
end
if not CAST then loadCast()end
if shown~=name then
backdrop=loadBackdrop(name)
shown=backdrop~="wait"and name or nil
fadePal(1)
end
if backdrop==true then memcpy(BAR*120,BACKDROP_RAM,BACKDROP_BYTES)end
return backdrop
end
function castSprite(name,x,y,left)
local sp=CAST and CAST[name]
if not sp then return false end
sprite(name,x-sp[2]//2,y-sp[3],left)
return true
end
function hideBackdrop()
if not palBase then return end
palShot,sky,shown=palBase,nil,nil
fadePal(1)
end
function playScene(name,after)
initPalette()
initFont()
if not palBase then
palBase={}
for i=0,47 do palBase[i]=peek(0x03FC0+i)end
end
if not CAST then loadCast()end
initAudio()
scene={shots=SCENES[name],n=0,after=after}
musicMood(SCENE_MOOD[name])
nextShot()
state="scene"
end
function actorAt(a,t)
local who,x0,y0,x1,y1,t0,t1,sc,left=table.unpack(a)
if t<(a.show or 0)or t>=(a.hide or math.huge)then return end
local o=a.orbit
if o then
local p=t/o[3]*6.283+o[4]
return who,o[1]+cos(p)*o[2],y0+sin(p)*6,sc or 2,sin(p)>0,false,a
end
sc=sc or 2
local g=GRAVITY*sc/2
local k=t1>t0 and math.max(0,math.min(1,(t-t0)/(t1-t0)))or 1
if left==nil then left=x1<x0 end
local x,y=x0+(x1-x0)*k,y0+(y1-y0)*k
if a.arc then y=y-g*(t1-t0)^2*k*(1-k)/2 end
if a.hop then
local T=2*math.sqrt(2*a.hop/g)
local p=t%T/T
y=y-4*a.hop*p*(1-p)
end
return who,x,y,sc,left,k>0 and k<1 and math.abs(x-x0),a
end
local function stairs(t)
for y=BAR,116,8 do
line(0,y,239,y,15)
for x=(y//8%2)*12,239,24 do line(x,y,x,y+7,15)end
end
glow(236,118,56,2,4)
glow(236,118,30,2,2)
for k=0,2 do
local x,y=56+k*72,30+k*22
glow(x,y-3,11+t//5%2,2,2)
rect(x,y,2,7,14)
circ(x,y-2,2,3)pix(x,y-4-t//4%2,4)pix(x+1,y-2,12)
end
for k=0,15 do
local x,y=k*16-16,40+k*5
rect(x,y,16,120-y,15)
line(x,y,x+15,y,13)
end
rising(t,24,120,116,120,70,3,2)
end
function drawScene()
local s=scene
local sh=s.sh
s.t=s.t+1
local t=s.t
local len=sh.len or s.start+60
local cx=(sh.pan or 0)*math.min(1,t/len)//1
local shake=sh.shake or sh.fx=="shake"and 0
local dy=shake and t>=shake and t<shake+60 and sin(t*7)*2//1 or 0
cls(0)
if backdrop=="wait"then backdrop=loadBackdrop(sh.bd)end
if sh.fx=="flash"and t<8 then cls(12)
elseif backdrop==true then memcpy((BAR+dy)*120,BACKDROP_RAM,BACKDROP_BYTES)end
if OVERLAYS[sh.bd]then OVERLAYS[sh.bd](t)end
if sh.fx=="fireworks"then fireworks(t)elseif sh.fx=="stairs"then stairs(t)end
local l=t>=s.start and sh.say and sh.say[s.line]
local text=l and L(l[2],l[3])
local talker=l and s.lineT//2<#text and SPEAKER_WHO[l[1]]
for _,b in ipairs(sh.booms or{})do
if t==b[3]then sndExplosion()end
if t>=b[3]and t<b[3]+16 then dy=dy+sin(t*9)*2//1 end
end
if sh.fx=="flash"then puff(t-8)end
local close=false
for pass=1,2 do for _,a in ipairs(sh.act or{})do
local who,x,y,sc,left,moving,act=actorAt(a,t)
close=close or sc==4
if who and(pass==2)==(a.orbit~=nil and y>a[3])then
drawCast(who,x-cx,y+dy,sc,t,left,moving,who==talker,sh.fx=="fire",act.anim)
if act.spark and t>=act.spark then fuse(x-cx+(left and 3 or-3),y+dy-(sc==1 and 13 or 26),t)end
if who=="dragon"and sh.fx=="fire"then dragonFire(x-cx,y+dy,sc==1 and 1 or 2,t)end
end
end end
for _,b in ipairs(sh.booms or{})do boom(b[1]-cx,b[2]+dy,t-b[3])end
if FOREGROUNDS[sh.bd]and not close then FOREGROUNDS[sh.bd](cx*16//10,t)end
if sh.magic then magic(sh.magic,cx,t)end
if sh.label and t>20 then print(sh.label[3],sh.label[1],sh.label[2],2,false,2,true)end
if sh.fx=="soot"then
for k=0,34 do rect(92+(k*37)%40,48+(k*23)%30,2,2,k%3==0 and 0 or 15)end
elseif sh.fx=="idea"and t>30 then
local r=4+t//4%2*2
for k=0,7 do line(176,44,176+cos(k*0.785)*r*2,44+sin(k*0.785)*r*2,4)end
circ(176,44,r,12)
end
if sh.title then chapterCard(sh.title,t)end
if s.leave and s.iris then iris(s.leave/IRIS)end
rect(0,0,240,BAR,0)rect(0,136-BAR,240,BAR,0)
if sh.cap then
local cap=L(sh.cap[1],sh.cap[2])
print(cap:sub(1,t//3),120-textW(cap,1)//2,8,13,false,1,true)
end
if s.leave then
s.leave=s.leave-1
if not s.iris then fadePal(s.leave/FADE)end
if s.leave<=0 then nextShot()end
return
end
fadePal(math.min(1,t/FADE))
local done
if sh.say then
if t>=s.start then
s.lineT=s.lineT+1
print(L(l[1],SPEAKER_PL[l[1]]),8,119,SPEAKER_COL[l[1]]or 4,false,1,true)
print(text:sub(1,s.lineT//2),8,SUB_Y,12,false,1,true)
if s.lineT%4==1 and s.lineT//2<#text then sfx(8,"C-6",4,2,5)end
if s.lineT>#text*2+READ_FRAMES or(s.lineT>20 and btnp(4))then
s.line,s.lineT=s.line+1,0
done=s.line>#sh.say
end
elseif btnp(4)then
s.t=s.start
end
else
done=t>=len or(t>20 and btnp(4))
end
if done then
local nxt=s.shots[s.n+1]
s.iris=nxt and nxt.title
s.leave=s.iris and IRIS or FADE
end
end


local sin,cos=math.sin,math.cos
introT=0
local INTRO_BOOM,INTRO_END=110,330
local function drawIntro()
introT=introT+1
local t=introT
if t==1 then initPalette()initFont()startMusic()end
if t==INTRO_BOOM then sndExplosion()end
cls(0)
if t<INTRO_BOOM then
local sx=t*126//INTRO_BOOM
for x=sx,126 do pix(x,58+sin(x/10)*4,13)end
circ(132,74,14,15)circ(127,69,4,14)rect(129,57,6,4,14)
local sy=58+sin(sx/10)*4
for k=0,5 do pix(sx+sin(t*3+k)*3,sy+cos(t*5+k*2)*3,k%2==0 and 4 or 3)end
circ(sx,sy,1,12)
elseif t<INTRO_BOOM+6 then
cls(12)
else
local b=t-INTRO_BOOM
if not showBackdrop("night")then nightSky(t)end
if b<60 then
for k=0,2 do circ(120,70,math.max(0,b*4-k*14),({2,3,4})[k+1])end
circ(120,70,math.max(0,b*4-48),0)
for k=0,20 do pix(120+cos(k)*b*3,70+sin(k)*b*2+b*b/40,k%3+2)end
end
drawLogo(function(i)
local d=b-10-i*6
if d<0 then return-60 elseif d<10 then return d*3-30 end
return d<20 and-math.abs(sin((d-10)/3))*4//1 or 0
end)
if b>90 then
local sub=L("THE SULPHUR LEGEND","LEGENDA O SIARCE")
print(sub:sub(1,(b-90)//3),120-textW(sub,1)//2,48,13,false,1,true)
end
end
if t>=INTRO_END or(t>10 and btnp(4))then
state,titleTimer="title",2
end
end
local mapAnim
local REGION_COL={6,7,13,15}
local MAP_BACKDROP={"rynek","sleza","wawel","cellars"}
local function nodePos(n)
local i=(n-1)%CHAPTER_LEN
local row,col=i//5,i%5
if row%2==1 then col=4-col end
return 40+col*40,54+row*15
end
function showMap(n)
mapAnim={n=n,t=0}
state="map"
end
function drawWorldMap()
local m=mapAnim
m.t=m.t+1
local st=STAGES[m.n]
local first=(st[1]-1)*CHAPTER_LEN+1
cls(0)
if showBackdrop(MAP_BACKDROP[st[1]])then
for y=20,115,2 do line(0,y,239,y,0)end
else
cls(REGION_COL[st[1]])
end
for i=first,first+CHAPTER_LEN-2 do
local x0,y0=nodePos(i)local x1,y1=nodePos(i+1)
for d=0,9 do
local x,y=x0+(x1-x0)*d//10,y0+(y1-y0)*d//10
rect(x,y+1,2,1,0)rect(x,y,2,1,i<m.n and 4 or 13)
end
end
for i=first,first+CHAPTER_LEN-1 do
local x,y=nodePos(i)
local r=STAGES[i][7]and 4 or 2
circ(x,y+1,r+1,0)
circ(x,y,r+1,STAGES[i][7]and 2 or 0)
circ(x,y,r,i<m.n and 4 or(i==m.n and frame%20<10)and 12 or 14)
end
local fx,fy=nodePos(math.max(first,m.n-1))
local tx,ty=nodePos(m.n)
local k=math.min(1,m.t/60)
local walking=k<1
local walked=math.sqrt((tx-fx)^2+(ty-fy)^2)*k
local far=CAST and CAST.dratewka_far
if not castSprite("dratewka_far"..(walking and far and"_w"..math.floor(walked*8/(far[3]*STRIDE.man))%8 or""),
fx+(tx-fx)*k,fy+(ty-fy)*k+2,tx<fx)then
drawSp(5+(walking and(m.t//8)%2 or 0),fx+(tx-fx)*k-4,fy+(ty-fy)*k-11,12,tx<fx)
end
local title=chapterName(st[1])
print(title,120-(print(title,0,-20)or 0)//2,4,12,false,1,false)
local sub=L("STAGE ","ETAP ")..st[1].."-"..((m.n-1)%CHAPTER_LEN+1)..": "..L(table.unpack(GOALS[st[2]]))
print(sub,120-textW(sub,1)//2,16,4,false,1,true)
if m.t>60 and m.t%40<28 then print(L("PRESS Z","NACIŚNIJ Z"),104,128,12,false,1,true)end
if m.t>200 or(m.t>30 and btnp(4))then mapAnim=nil hideBackdrop()startStage(m.n)end
end
function TIC()
frame=frame+1
updateMusic()
updateDeaths()
if state=="intro"then
drawIntro()
return
elseif state=="title"then
drawTitle()
return
elseif state=="scene"then
drawScene()
return
elseif state=="map"then
drawWorldMap()
return
end
cls(FLOOR_COL)
if state=="game"then
updateBombs()
updateBlasts()
updateInvul()
updateShrink()
for _,p in ipairs(players)do
if p.human then updatePlayer(p)else updateBot(p)end
end
if mode=="camp"then
updateCampaign()
else
local alive,last=countAlive()
if alive<=1 then
state="over"
winner=last
score=addRoundWin(score,winner and winner.id)
restartTimer=210
end
end
drawMap()
drawBlasts()
drawBombs()
drawPowerups()
drawPlayers()
if mode=="camp"then drawCampaign()else drawHUD()end
elseif mode=="camp"then
drawMap()
drawBombs()
drawPowerups()
drawPlayers()
drawCampaign()
elseif state=="over"then
updateBombs()
updateBlasts()
drawMap()
drawBlasts()
drawBombs()
drawPlayers()
drawPowerups()
drawHUD()
local msg=winner and("P"..winner.id..L(" WINS!"," WYGRYWA!"))or L("DRAW!","REMIS!")
local col=winner and winner.color or 7
local mx=120-#msg*3
print(msg,mx,50,col,false,2,true)
if winner then
local sub=winner.id<=2 and L("YOU WIN!","WYGRAŁEŚ!")or L("BOT WINS","WYGRAŁ BOT")
local sc=winner.id<=2 and 12 or 9
print(sub,120-#sub*2,72,sc,false,1,true)
end
local pct=math.ceil(restartTimer/210*100)
print(L("restarting ","restart ")..pct.."%",88,90,13,false,1,true)
restartTimer=restartTimer-1
if restartTimer<=0 then
if matchWinner(score)then
state="match"
restartTimer=MATCH_TIME
else
init()
end
end
elseif state=="match"then
drawMap()
drawHUD()
local w=matchWinner(score)
local msg="P"..w..L(" WINS THE MATCH!"," WYGRYWA MECZ!")
print(msg,120-#msg*3,50,players[w].color,false,1,true)
print(L("new match in ","nowy mecz za ")..math.ceil(restartTimer/60).."s",88,90,13,false,1,true)
restartTimer=restartTimer-1
if restartTimer<=0 then
score={0,0,0,0}
init()
end
end
end
titleTimer=0

-- <TILES>
-- 000:80120000f04a70a99047c0a12048d0009070210060a05143107a510840ae7100
-- 001:81000000029eb81efa12212439bceba037332157623325524442443019ffbdbc
-- 002:bba88880012553434333233434231109acbdbcbbcaababbbcbdbccabba988021
-- 003:2289adba265554453332118889bcdbcabcbcaba9990012353442432333211010
-- 004:010133342210aedddbcbbbbb9a999abdccbca9012564434222011009adbdbcbc
-- 005:bbaa800213334423343434221080980036443432109beccabbaaa9a9aabcbcbc
-- 006:aa888365543333222228acddbdbbcbaa980112333533353432321889aaa91464
-- 007:43422108bcccbbbbbabbbbbcbcbcaaa998166453342132110abecbdbcbab9980
-- 008:01123343443443232108999a9126434332188cbebbbcabaaabbbccbcbbbaba82
-- 009:65634332332318acdccbdbbbb9a8000122335444343332100999a80354352221
-- 010:89bdbdbabbbbcabbcbccbabbaba0275534333233208bcdccccabbaa980011232
-- 011:4435344232210899aa9013543432209bcccbbcababbbccbccabbbbaa02764334
-- 012:23332209acdcbdcbabaa98001122344345334322108aaa9a013453423188bcbd
-- 013:bbcabbbbdbcbcbbcabaa90275442334222188abdccccbabaa880012233354434
-- 014:423211099aaa9813453423189abdcbbcabbacbbdbcbbcabaa904645333433221
-- 015:89accdcbdbaba9900012323443535233211099aba9913543432109bccbcbbcaa
-- 016:bbccbccabbabbb92564434334321088accccccabaaa880112233443534422220
-- 017:099aa9a00336343110aaccbccaaababccbcbbbcabba92564353334321009accd
-- 018:cbccaaa9800022222434443343211099aba9803453422089bbebbcbababccbcb
-- 019:cbabcab982554353433321089bcdcccbcaaa9900112323444343433220099bab
-- 020:980254343118aacdbbbcababccbcbbcabbcaa02554344343220088acdccbcbbb
-- 021:a990022324335353433331109abbaa803544321189bdcbcabbabbdbcbcbabcbb
-- 022:b913644443523211089acdccbcbbaaa80022333435434343231189aaba990345
-- 023:3421089acccbbabbcbbdbbcbacbbca803544443523210089bbfbdbcbbba98011
-- 024:32343354343432220899bab990345333118acccbcbbabbccbcbabcbbdaa81345
-- 025:4435342210089bccdcbcbbaa980122333443534342321009aabaa80253432218
-- 026:accccabbabbccbbcabbccbaa81354544343312008abddcbdbbbba98012333443
-- 027:4353423322089aabba80253522118accbcbcaaabcbcabbbccbca901344544433
-- 028:321188abeccccbbbba981123334434353343321089aabba80253432208acdbcb
-- 029:bbbbccbbcabbccbba982355454342311188abddcbdbbbaa98012342343435334
-- 030:322208a9bbb990253423108adbdbbbbbcbcbcabbbdcab9901345544432312088
-- 031:accdcbdbbaba900132423434434333331089bbcaa80143433108adcbcbbacacb
-- 032:bbbbdbcbca9881345454432221009abecdbcbbbba98122343344343532332108
-- 033:aabbba90253423119bcdbcabbbcbcbabbdbcbbb9901364553523211009accdcb
-- 034:ccaba9900123334424343433221099abbba90244333209cccbcabbcbcbabbcbd
-- 035:bbbb9801265544334211089abecdbbdaba988112242334434342322108aabbba
-- 036:90243523109bdbcbbbcbccaaabbccbcaa9801246543532220088bcdcccbcbab9
-- 037:88113334343443343331108abbbc990134342109bccbbcbcbbcabacbbdbbba98
-- 038:81365544423211889acdcccbcbaa990113334343435333331108abcbaa901344
-- 039:23189bccbbccbbcbabbbdbcca9a9800264544342210089acdcccbcaba9881224
-- 040:23343435333322188abcbaa90134342189bcbcbccbbcababbdbcbbaa98813746
-- 041:3533332008accdcccbbcaa990123334343443342322009aacaaa9012433228ab
-- 042:dbbdbcbcababbccbcbaa9a881374635333211099ccdcccbbcaa9801223433353
-- 043:43433231188acabaa98134341189abcbdbcbcaaabbccbcaaa999813745533422
-- 044:2009abddccbdabba980132433353344333331189bbcbba9013442200aaaccbdb
-- 045:cabaabbdcabbaaaa88145653533322009acdcdbdbbbbb9802243433353434233
-- 046:21189bbbcaa9813433200aabccdbcbbbabbdbdabaaaa9981465453423210899c
-- 047:cdccbdabaa980223343434343343221089abbcaa981335211899abdcbdabaaac
-- 048:bcbbbcaa9998137644343311189acdccdbbcbba88013343433443343322208aa
-- 049:cabbb901343320099bcdccacaaaaacbbcabaaa918146545342221099acccdcbc
-- 050:bbba903133434335242422120089aabbbaa00243211089acdbdbc9aaabcbcaba
-- 051:aaa888146554334221899abecdbdbbbba811134334343433432221099acaca99
-- 052:00132221088accdbcaaaabcbbcbbaba98a0156544433220889acddcbdbbca900
-- 053:0123343343434323221099bbdaba891233221008acdccbaaabcbcbbbbbb99b98
-- 054:257454343210089adcccdbbcba888112433343434333332109abccbaaa012323
-- 055:12119adcdbbaabcbbdbabbba9aaa8256553532210089acddcbdbbba898123434
-- 056:334343423231188abbdbaa901222222118bbfe99a9abacbbbbc99aaa98155643
-- 057:52311100aadcdccbcba9a90113434334334342222009aacbbc98811222121189
-- 058:ddaaabbbbdbcbbbbaabab99266454341211089bcddcbdbaab990123353433352
-- 059:342221088aacbbba801132233210cf9aababbdbbcbbc9aa9aaa8147453432311
-- 060:089bedccbdbabaa88123533433434233321189acbdba990810100009abcababb
-- 061:abaaba008fff85088080088008088008800808808080808088080277738bccba
-- 062:bb999888102132344434343332212222180bacbb95802d190582211328780286
-- 063:20308801438bd019afbb9110bfe9988899a9bdcbbc8808b8b8006b1ae0a0be9b
-- 064:cc8a90989910644242223335234342008923339a1261bdcb024299da98991900
-- 065:b3ffaa99089998b349090981dfd9bb89bd99892124732322245222202420a002
-- 066:300c084589dc8831009ac9b9ab0182affc9a908aa0a8509a12a02cfdaa999cba
-- 067:9a82826541312237121122318002229a995628ae99821088aaaacd008219fcac
-- 068:998bc8888009b12859cebac9bacc8aaba01454313253342143231012330b9845
-- 069:349abbb8200210dbcfb000308fb9b9cbca9a098ac021319dbeabfbaaaacada91
-- 070:123434442324334322333319c8124429abc9a0993419adfa801109bcbcadcba9
-- 071:a09baa11448a80aecebba9adbcc8800224354123244321333331ab82263209ab
-- 072:abab94528afca901108acacaddba9b89ca901138b830ddeda89abccb98881245
-- 073:342234433333523218b81243219aca9aab2431cecba011099cbcadfaa8aa8aba
-- 074:01040a831cddea989bcbd98880235432234434322432328a912352189ababbd0
-- 075:231afcbb81108accbabfea89a0aaa81121aa12bfddb99abdbda8808235433235
-- 076:3352233422109a0124210aabbbbd02429ddbb912189bdbacfca99a89c9800229
-- 077:a139dedc999accca8808224442223435222343220a98215210aaabaac82338de
-- 078:ca911108abcbbffa98a88b9901129a838ddeca89abcda9808134443233533423
-- 079:3432319b82153108bbabac92528beda901088acbbafdaa9a98ca900228b038ce
-- 080:eca89abccba0801354432243353233432318b92144208abab9ca2421bfcb9001
-- 081:09acbc9edaa9a99bb981130b941cdfca98abccba808134543314334423243222
-- 082:8aa12352089bababb1531afcbb01008acbd9cfaa99a8baa81031b932ceeda999
-- 083:bccba8881337352123344322432220aa1135218aaababc04319ecca810089bcb
-- 084:bcfca99a8ac9800219a22aedeaa89bcbda88802354422234352223422209a012
-- 085:4310aabbbad83418cebb910199bdbbbff999989b9910129a129ddfb999acbdb8
-- 086:0801354342233534223422209a01243109abbbad93338deca901089abdabfcb9
-- 087:9b8abb900249a038ecfba99bcbea90801244432243353224323219a81152208a
-- 088:babaca3340bfda9001899cac9ecb99b99bba01148b030ddeca99abdbc9880034
-- 089:5342233444213333329a91144218ababbbb2531bfdb981008acbbbfdba9a99bc
-- 090:900030a931ceddb98abcdb98800245342233443334333328b911442189bbbabc
-- 091:13419fcba81008acbcadeba9aa8bc920021a812bedea929abcca808023636302
-- 092:222422234221b9901141109aaaafd001089bbb8002db9baacfba9aa8bb080031
-- 093:9a23beedc009abbda90882347511021232233422908a01133209ac9fd8801009
-- 094:bbb9819e899baafbbaab9a9a900228a139fcf9999bbcda988822761111112332
-- 095:33438118980133210baff89801009abba09c889bbbcedaa9aa0aa9801389038c
-- 096:fabd9abcbea998004722121323432335112009800232109fd898900109acba9d
-- 097:0889a9bbfcaaab89ba9801319021baafaa9abcbd998807313232334432333333
-- 098:329a10232119f89099001099bbaba000999a9bbbbba99a9a00011091191aab9a
-- 099:9babba99952021322221311210110009909090904400800719b09cda13202329
-- 100:ebfb9835421147723225523633462019fdccbdab998088102543533342323343
-- 101:332189bcccbccabbaabbbbdbbdcbbca999001121899cc9155545453322200899
-- 102:adbdbacacabbaa988013354335333422211100001113333220afddcccabbaaa9
-- 103:999aaccdbab9813664433332120109ccccbccbbbb99011233433433533432220
-- 104:0889004544433220abfbdabbaa9a9a9abbdbbcb9980274634232212110abeccb
-- 105:cbcab9980112233443243343220089aba8045534332209dcacabbbabababbbac
-- 106:cbaba9a8275544232222210acccdbbcbbb9988111234513343433321009baa80
-- 107:3553433211beabcbbcaaabaababdbcbbabb99265552321211188abdbbcaba990
-- 108:0223333455100403533334222210089bbdcccbbdbbcbbcbbbbcaaa9a88812253
-- 109:5433534334334323422222111089acbdcbccbcbbdabcabbbcabbaaba99980224
-- 110:4435353343442334333343233323211188abdccbdbcbccbbcbcacabbbbcbbbab
-- 111:bbbaa998013445344353344242423334333432342223212110889bbebdbccbcb
-- 112:cbcbbccabcabbcbabcababbbabab9a9801235444344343443335333434333433
-- 113:3343333333332311009acccbebbdbccbbcbcbcbbcbcabcbacabbbbcabbbbbbab
-- 114:ba9a880134453534353353343433442342342334233423333334223221210099
-- 115:abebcccbccbcbcbbdbbbdbbbcbcbbbcbcabbcabbbcababbabbab9a9981124444
-- 116:434434352424234334334343334334333433334323422232222110089abcdbdb
-- 117:dbcbcbccacbbbdbbbccabcbbbcbbbcbcabbcabbbbbcbabababaa9a8802244443
-- 118:5344343434343344242334334334334242323423333423333233322211089bbe
-- 119:cbdbccbdbbcbccacacabcacabbcbbcbbbcbcbbbbcbbcbabcaabbbabbbaba9a98
-- 120:0123544435343533434424242334343334423343334334324233333432333342
-- 121:2121110899bccccbcccbbdbbccbbcbcbcbbcbbccabbcbbbcbcabcabbbbcbbbbc
-- 122:babbbbbbbbaaa988123544443443434433434343424242334242334333433424
-- 123:223334233333423223222110089acccbdcbcbccbcbbdbbcbcbcacbacbbbcbcbb
-- 124:cacabbbbcbbcbbbbcabbbcababaaab9a98801235444344344343353343353335
-- 125:234333434334234324233342334233333342232222110089acccbdbdbcbcbccb
-- 126:bcbcbcbcbbbdacabbcbbbcbcbbbcacabbbbcbbbbcbabbbbbcaaa9a8980123444
-- 127:4434434344243343433434334343334423342342342333334334233233333332
-- 128:311108abcdcbdbdbcbcbccbbcbcbcbcacacabbcacabbcbbbcbcabbcabbcabbbc
-- 129:abbabbbbbbbaaa99811354354353434344334343434334334343334423343334
-- 130:2423333433334233333333323120089bcdbdcbccbdacbbccacbbbdbbbdacabbc
-- 131:bbcacabbcbbbcbbbcbbbbcbbbcabbbabbbbaaa99881244435434434343442433
-- 132:35333443334343343334423334333432423333342323332231211889bcdbdbdb
-- 133:cbccbcbbdbbcbcbcbbcbbcbcbbcbbcbbbcbcbacabbbcabbcabbbacaaabaaaa99
-- 134:9801135353535334434343434334343343433433433433343343342334233333
-- 135:4323323323211108aaccdbccbdbcbcbcbcbcbcbbdabcbbbcbcbbcbbcbbcbbbcb
-- 136:bcabcabbacababbbbbbbabba9990023635353443434344334343344234334334
-- 137:334334333434233432342333333423323222211009abebcccbdbbdbcbbdbbcbc
-- 138:bcbbcbcbbbdabcbbbcbbbcbcbacabbbbcbbbbcabbabbbbabaa99001344444353
-- 139:4344335334343344242334334342342342334333343334333334323332332212
-- 140:0099bcdcbdbccbcbccacbbcbcbcbbcbcbbcbbcbbcbbcbbcbbcabbcbbbbcabbca
-- 141:babbabbabaa99901135443543353434344242343343433433434234333433343
-- 142:34333343334233333333233211009bcccccbdbcbccbbdbbcbcbbccbbbccabcbb
-- 143:bcbcabcbacabbbcbbbbcbbbcabbbabbbbbbaaa88013453577334233433334334
-- 144:232333323222100df08509184c209209984d000b1b2b29b8b5b3199978960884
-- 145:b0400a083c01d1909a2f2989a202f184a1914a32f380092b15c8081a99199a03
-- 146:cb84994c688838849209311f01801ac995d81c5b8190188912b54b3a04b68900
-- 147:0098009c0d390af29818098896192084948c1500e12a09910c11f188880a40a9
-- 148:2b7889302188a1179900b2b4f03c0992988c300b400b312a791935d4b84a81a3
-- 149:c18b02d94991b03a294c31b26903a86b923c22f0a4991c11c11c282c85b28018
-- 150:914b4a859092b915e010b92088e04b11990103a2a20230d5c384bc4a3e821aa8
-- 151:811a0d5a181e30088838019c780908808b201bbc228f15d0904a11c380b5000b
-- 152:21985e2808b100a08e22b902898c52c598080311e18923b1d8941ac82809c925
-- 153:9d301f22aa408884a2d2000b01c381c808a93c590ac51a10c5902a0868c28199
-- 154:4b9032f8088188b300a96b6b3c130b0282e03a82900a2cb5aa131f8859b04a20
-- 155:c842b2983991818e52f820b119a82994c20a4a8a688082094f3a20b2098a87a9
-- 156:2a3e1a23d8182aa3869a2a6c281b33f10a1189b40b29881c1101ab878c690082
-- 157:b949390c841d008092b108c1191959f2018b4939811d15ba3a481d080911c883
-- 158:b17c0811b3b8410ab71b2901c5a94c4a91b41c01a3a928b13a3b37d849931b8a
-- 159:34ba7a92a029d388c41d2888195ba580b48810c1811b6b00919914f289095ab4
-- 160:81a02b391a7a82d319b5a8181b00a48c083c21b987a86c281c31c2902b979a11
-- 161:a18b6a01a29c69910808883d309008b68b59808900a7b09014b0a941c3c10008
-- 162:922f49191c3a38d3a83b18881aca701b8830d3906b29a39112f4c0181aa58909
-- 163:8886a882b49d48829a149a2929d79a111b0013f901804d0095a93b20b31c30a0
-- 164:a26d2891918882f48a91298a87a940c118894b200c13e21a19a2d580b8488c10
-- 165:005c2a9295a8002a939b5a38c193a08b3b788e05b2a119d5882d049908189280
-- 166:b3b879a1911b4d380d21988b7888001b0598996b21a8e40908a2810a1f202b18
-- 167:905e398108894b02a18e6a081a11b195aa848009a488c6a12c8208882a0a29b5
-- 168:0a008800098028919108e0c18509c6b2c4c22e06c08192a85e491c21b20c38b6
-- 169:b292d30c2809100d3098192c3b20d5a2a081985c03d12c03a8820c13b8290a04
-- 170:2f2b4a1a85a0a2180b2a388a5c20b3892c29292e2804f100982b1298b7a85d3a
-- 171:0009002d29812c01985b095b02b2911e4c3994a94b10910b30a0094b3d3a11c2
-- 172:1d4a0093d21a939a6a00b5a2a1902d3983e11a03d3b3a3c1800900802b83b28c
-- 173:489083c1800900fc73850e6c20b12b4c29848f6c292aa7b01994c5e492c03989
-- 174:84e48c59b30d30b39094d281c3a2993d49b5900a3c20b4982c12a800a68b1a69
-- 175:94d12b029a5b4d38901910c20a3c3892d22d2a3a886c3a81a5a80018c394f39a
-- 176:31e20a2a3c4b2a4b298082d4a189291c7b83a1a5a93a1a398b7b38a28a4a0a7a
-- 177:82b3a01a110f49911c21c3b4a921a3f391aa7b399010b3a2c4901e21b28930f4
-- 178:99188000c5c30d21a00a5a81802e101c389095ab69910881994a0915e290081a
-- 179:2a83a94a19820b97b04aa5b05b01a3b807d289298191b5a84d399290092c48d4
-- 180:901c2881a2b6c1192d3a2a1911c110b282d290108d396d03b191092c294c028a
-- 181:02a19b7a18a7a94b2892a11d398012f11b2009a3a12d7d3b13b800803c93985f
-- 182:39929949a20a28b7b12b84c29191881b41f12c3b3c209094b28b5a095c39b6a0
-- 183:1b380a86c2a21b0828c308a04b839b7c3b293b6e289291b491d31c1882b5b109
-- 184:008080d6993c3b3b11a39b38a31ac7d4994c02a85b108a281b30f5b28a4a0092
-- 185:b3b490c5a2b2880b7b290191c5a00928b48c5a1901a1088b7b110a84c292c39a
-- 186:22b02f5b28a39092b48b2985b38e31f3981b5b12c12aa5b12b01a281c12a19a7
-- 187:c4b11a2b4a083d194a0091894d4a093c38a4b915b83c020c4a0093a93ba70c3c
-- 188:49a4b2893ab7b1180a110c3a097d209829b6a2b21b10b5981a12b02e14c2c5a0
-- 189:09821c3d4b280a39903c3b011c4b979995b20a10a3c38b5c5b119a391c30b119
-- 190:2b4d11a5d21d39091895c290883b811a14f11b49a219b238e4a18996a8108881
-- 191:a2901a193d3b398190809000c4002341100080808080808099efffb088080808
-- 192:08080808080081427771000808080808088008808088abeffca8080808080808
-- 193:0808080001777310008008088080088008808099ceffd9908080808088080088
-- 194:008080000237775210008080080880088008808098bbffffa880808088080800
-- 195:880800880080014377751000808080808080808080808080899eafff99989888
-- 196:8080880808080088008080800137766323351108008800808808008808088888
-- 197:9acffffbaa989080889808808080808080808008002376376436341180080800
-- 198:8080880088008800880808889beefffda9980888880808808080800880080808
-- 199:01012474454427323224210008000808080800880808080808809abfeca808cf
-- 200:fffb988908888088088080880088080800800000220066423776122108343331
-- 201:010100808080080808080808808808899adfecdbffdaababaab9898888888088
-- 202:0808808008808080001001227633744416523643332332233310000080080808
-- 203:080088080809098909afdbbdeacddbdcdcbfca9a998989888080880808080880
-- 204:8080080880081011235428240277623424646234432121010080800080080800
-- 205:8080808808888098899cacaadbadeedc99cfcccccbba99880890988888088088
-- 206:0880880080800800888001224536533764344511435343313532333211800001
-- 207:008000800080000808808888088088abdbbcbdffcdcfbbacaacedcabbcba9988
-- 208:8988898888880880880880800800000808800002013256753422282775533346
-- 209:324421232224311111110000808008080080080000018889a912129a0bddbda0
-- 210:9bcefdbcdedcaacbcbedc9999899a99889888008089888888890888808080080
-- 211:0801898133443543446462555323633533344442111312422211001111010010
-- 212:01088800089908101220109a98019dfcdba989bfcdcbdcbcafcbccbcabcbbbca
-- 213:caaa9bbabca99999988899988889888080088099998801243522327725311244
-- 214:5433534543324265243133421244323331221111121201001080800880080819
-- 215:801208acbcda908bccacacfdbacdccb99b9cba9cffebbcabbcabbaba9a9a9989
-- 216:899abdbba89a99888a9988999888900888081136336345332455222152234474
-- 217:3333652335435332534421233222121200101010011001001101001898001088
-- 218:9012180140bfebbbdddbc9bfcbcc88abbfabbdbdb9cdcabbcbbbccbabcbbbaaa
-- 219:99889998980898998988880811208808800240ae890122750346544434224420
-- 220:3633353363452322523342120101335321012122222111122110008000a91213
-- 221:10191432adab9afdba9addceba9abebbebcabdbbbdebaabdcbbbcdbbbbbbbabd
-- 222:cbbbaaaa998a99a889989a9aa988aca990011211dc9a90990224645344335343
-- 223:2442244363453523223323454443435221111111112423412111012011122111
-- 224:111111088089acdbbdbcbcaa01a8130030affbbacdcccebbebccabbbbcaa899c
-- 225:accdcab9aaa99aabbbabbaca9aaa99abccaa9a99a9b998098089014453322133
-- 226:4555334330145344344634343333634311112237434242332224333233232210
-- 227:1024232222000122222533099990020a89cff9900888a9afdbcabdccbbdbcbbc
-- 228:bbdcaababfbbdbdbbcaabcaaabaaaabac999babbcbaa9bb9aaba889aadbaaba9
-- 229:028aba9020342433734346113624454422424442522213532232232354342035
-- 230:535212321223333333232212122010898182321535342008888acd9bddbcaa98
-- 231:abaecbdbbacb89adbcdccaaaaddacbbccbbcbaabcbacbbdbbababab9bbaa8aca
-- 232:abcaaaaaab99aaa8109db9a999a8081337618080825354533444432452334225
-- 233:434334534222333523433433423224311221112213641232323110110889a813
-- 234:4891812074220108bebdb99ac98abdecdcbbbbcbeabbbbaddcbcbbcbbaacbbbd
-- 235:baabcbb9a9aa9bccccbbabbaa9999008089999a98bbdcbdabaaba88822474332
-- 236:2463435442233412343423244345211234344423423335334221331134222343
-- 237:3533233322212099ba822242189ba9351cfb8199bcbddabacaadcabccccabaab
-- 238:cbbccbebbccccbbbbaa9999aaacdbabcdaaabbbbca9aaabcabbcba9abbbaca90
-- 239:8080202008983608a90476242101224443634243434211113644222335323542
-- 240:232342434233433334233332322321222228342214233210ac9242442489bbdc
-- 241:bbcbbbcca9bebcbccabaccbdbcdcbbcb9aaaaacbcacdcbaababcacbbacabbaac
-- 242:aaa98abbdabbbcaabbba98ac9ab8ab0110133838efb902424434434532233634
-- 243:3433343424454323334233343335212363332343322233114444332322222321
-- 244:80099890441432220810bfabcabdcaacaaddaaaaabbbac9ccfbbbdbdbdaabcbb
-- 245:bcacaabbdbcaaaaabcbacabaaa9aaaaacdbcb99899aaaaca999a99abacc9a026
-- 246:32143118a9018377343422254333333336364353433442322222421344433334
-- 247:22232333335323543332111088bab8901037321232809caa9bf99bbbbedccab9
-- 248:cbaacccbccbcbabbcbacbaaaeacbbccbbca9bccbcbbabbbcbbaaaa9bcdbbca9a
-- 249:998109adbda9a880111111002543321209063412533432364233634232214735
-- 250:2324234223352242332221223634222443332122223242234311812222889a83
-- 251:19865431188aca8cdbabccb809edcbcabdaaa9cbcbccbcbcbcbbccbbabcabbca
-- 252:bcbbbaba9a9ada999aeaca9aba9acbbcaa89bbaba81201a99a2126298d9800ba
-- 253:2445644235343633433534343212353334342333442323521333433542233324
-- 254:23233343332210002544310089a9112899aab8e990bffc9ba9999bdbbbabddcc
-- 255:cbcbbccbcaabbbaabbccbcdabcabbbbcbbbbbcacbab989abbdbbdbbbbaaabcbb
-- </TILES>

-- <SPRITES>
-- 000:abcbbb9082090428b01274243421826553433122354335433333321225533353
-- 001:424422244232334322343222222333633331135433333221110020ac9abcccaa
-- 002:bb0bfe989889adbcbdcbcbaccab9aaacbccbbbdcaabdbcbcabaaabdbcbabaaba
-- 003:a8abcadcbba9aaaaabdbaabacaa9999a9881015430a911254313373237341125
-- 004:3235363352332243354212112453322343533332433433321122254322321201
-- 005:3622323543221133082128cb8801359bebaabdecdbcbbcbbbcabbbdaab9aabdb
-- 006:ddbbccbbabbbbbbccabcbcccbababacaa9aaaaaab9cebca998bb899ada900080
-- 007:89bbac9bc9311375533345221898135442434443343333434342222443343122
-- 008:333434342122422344334312334233344322222211008bbabcbfcbabbbddca9a
-- 009:a99a908089febcbaa9abbcdcbccca9abbcbccbbabcbaacbcbcbbcabbbbaab9a9
-- 010:cbbc9bbccacaaabcbaba91111234300bcca9d934534423322243624353533422
-- 011:2234233534222334423323343442433434213322342344433422222242232243
-- 012:3330888bbdcaa013419adcaa990acbebccaccccbbbbbbcbbbddbababccabbbcb
-- 013:bccbcbcbbcaaaacbcababbbccaa999aabbbdbdcbca8188809881001200bfa900
-- 014:2122337435434333432101473424333344223322325224433424334222324342
-- 015:34433242242332334223211233123300185310af811080a9881efecbaaaa9a9b
-- 016:ccccbcabbcbbbdbccbacbbbcbbbadbdaa9bcabbcbba9bbcaacbbcaabdbbbcbaa
-- 017:baaaaabcdbaabbaca81801811519cb1245445343431233623333424353353343
-- 018:4232122344442233334333433353333523433323234432421123353333351108
-- 019:abb911bfcbbbaacbcaaccdadabaa9acbbbcccbbbbdabacaabcaccacbdbbbcbcb
-- 020:babbaaa9a9ccccccbaaa9999aabcaabbc9bbbbbb82453354321110aaabca8145
-- 021:5435233423202236335343342322432335435234332342223522323353442322
-- 022:2422110011243542342221100008888889a09fbaabbedca9cbcbeabbca9bcbbf
-- 023:b9a9abbcbbcccabbcabcbcaaa9abbccbbcbbaabbcdbcbabbbcabbaa900809acb
-- 024:afcaa9aab9a99002432345234434424532311135432254433233523323434344
-- 025:4323223332234442233543343233421235322223223211110131bc111ac8328a
-- 026:fccbabbdbcdcbcbbbbbcaccbccccbaba9abccbcabcacabbcbbabbcdbbacbcaaa
-- 027:99abbdbbccabbcabbcaacbabaa9a9aa9a01053009a9915733027234331362235
-- 028:4323322222642334344333343435333234342322224333342432201222253533
-- 029:4322110018999adcaa80189bfdbbbbaba9bdcbcbbbccccbbcbbacbccbbcbbbbb
-- 030:cbacaabbbdbaaaabadabbbcbbabaaadbbaba9ab9908331123733443354374333
-- 031:2423323423333333332332211000000000000000000000000000000000000000
-- 032:8f304851000892db0018084100188d1208046318439908b1c00020081fd00851
-- 033:0060430023100b0b1008c82a38810008f07408a721009308d703001018880028
-- 034:bda208426d08f2402002b32b085f430881e118410008309b10030908afb13022
-- 035:63202b1832d300020848d308775320030d600877331023080871a808fc710012
-- 036:08885818bfb3281fa510300208b5ed089310102b4b0842d30821c308c8000857
-- 037:98400f291d3013182fb9202b9028188cd308b960401918103f0908cb2a501328
-- 038:002b12340873d308943370101f18501f0a102308471008890010137408a00a00
-- 039:04087f6310080208e79118fcd910002b08710010735418d3000040088c530895
-- 040:73303b10223318f098086515400900140273086120307042585308416308d000
-- 041:e0006b4012989304091083006b9068a308bf53086483006b08129c10c30908d7
-- 042:7308e943086b50203320a318510908b413084d50306322732908083328dd9670
-- 043:7b009322330f3902089310280c6010631c08d0500810fb0039080200001b283e
-- 044:2020430c64081a1a08932008abe80824831023a418d92918ce1e08d679000c08
-- 045:d000001408e6c5081ae0003208408120dbbb0018af0e087a661022e408eb6608
-- 046:720320640324185c4310000308234100040860000846e118326a08b1f3001038
-- 047:866a08040018d64338c000002318d2781868530879f208b323188100086d3700
-- 048:b068e82008b433ff0920ff0920ff0920ff0920ff092018092000268a092028b0
-- 049:0038f82018d01258c82008d1c358982008e2836858200816e2c8182008d8c1a8
-- 050:c720088f9748872028762400fb983720001b18131500eb68d620081f50081200
-- 051:68962028f000085ab3684620084420280100880620183100082a14b8c5200010
-- 052:184100b89520104b2008ef06b87520105b30086f61782520106b3008d49898d4
-- 053:20107b1008723008642078f420108b2008de2998d42018532120330063580520
-- 054:309b10330248152018bab9583520008b085fc37835202043000888452008e000
-- 055:a8652020430038a88520003308375110131218670688b5200013085100002308
-- 056:eb1688f52008c7202023022808512068562018f82020022338087a3048b62008
-- 057:fd8010023308e400206400db0838800808002002280228d000003008b8001028
-- 058:0208bf0700eb18cf2110021308754010180408c3a30892070804611002230861
-- 059:3108119a084820007b082cd10886c308df1208791118b720008b185840101314
-- 060:08e4002805d920fb2bdb0875001868310803000890200859192003043028f000
-- 061:18ac3400a038776518292020e0900008966581033b40032c0430033c443c9474
-- 062:0344240394940324440374d41823c118cb4228c45000c4086585008b08675308
-- 063:9652084753702c0e000e1c10cb8b08ae31184acb280350100e2d083000000c08
-- 064:d70708c110188c2208f110388100080a42100e2d081e0a0817a328ac7a08472c
-- 065:187b5318410030db7b003208fde808820008595308f09b087d25007b0839b300
-- 066:5818751728ae4218e033006208506308f8d3700e300e30db1b5072084af12852
-- 067:3320031052087459400b20b20003080300183442008208681018c9a800a22821
-- 068:0018bb9a4062083203200811331022000841002886000879303072205370085f
-- 069:2008787208671218e842400482145243288d1010520028410008b17b08c22200
-- 070:b218c9a7087153008208f5b1083060081700009208ae8d001b0823630072080f
-- 071:0a18ca326008038208e2031b08d50030620003380852000831d6085aea500882
-- 072:0862781b08c2630052386100089b2230141228420882cd207010e20846001003
-- 073:3808a414600334123822083308ceca182000089f7120d2104208ad6118821708
-- 074:28b9002208c8ad00c2080b50201220c208789e001808be5018bc22500b100852
-- 075:48c208f140084240203230a2081c39084f6128481018851060081204420810d8
-- 076:08d16408ee630082084a42180be408302018c1db001008f1e0101bd008ae8320
-- 077:92207218781008f02018be300850000816d000fb08610120b2304208ce201003
-- 078:180821001863990008186d92087100a008e220322013341043120408740208e5
-- 079:a00868223012106330186300705b4be0724008224308fe0008d00008fa6a5062
-- 080:d01208122318b100188f510038084a22003218248d000408cc8a006b08783260
-- 081:4338a20832082218abbd006b0890705060023852182208b64218d912006b18fa
-- 082:12085d00087f0008310008200010024808da10007b08176010ab101811000874
-- 083:0028710010320818f40c08ef0208b0700871ed0850f7085b1448200028125020
-- 084:8b320308f41218b100005208474058b100084ef1c022080213300813a2132208
-- 085:22043836000867208062335208720302c31218f4d960bb1208a228a2e4185622
-- 086:10bb1208e9e0303820a2f318eadb10cb0208670008dab7089e1018cb0200db18
-- 087:e9c3000808c03000c21835f300cb08a910008b489100080e022092b308085b62
-- 088:186a7c1082b4183ee82839a708493b00b368d000307260044068d000089c0118
-- 089:243058f000005218ae37f8d0000801f308dd7c085130087229082d49081c9e18
-- 090:8d4930abfb000c0832e0083db918d1e008a00020fbbba0783b30181b30089560
-- 091:08d03b48da3038d000585a3008e00018931b48b93008e000085e6c38393038a1
-- 092:0038d83038c000389830081000001b38583008c64718733028083008762528cc
-- 093:6218c730003b083860080240185270389730002b08cbd108f82818eebe285730
-- 094:088a2008db400804a30821305857301810c3103048087300009b685730088660
-- 095:20032058088300185e301847300896991003100808ed18ce52384730102b0008
-- 096:e2fa0068181df7782730002b08e5720010187300188d20480730202b00a20841
-- 097:00181273c8f63008f682086573000208572088e63020f2031008d282003bb8c6
-- 098:305040e203103803084850e88630086360003008640008390e18c890a8963050
-- 099:0b006230920308563008b100a8a63008f30008a973300310042818310078b630
-- 100:0899c300400832112004100368d63008eb2118e630088bf348073018ab321873
-- 101:f1583730180462108230684730202bf0f088073008c0a010f24018b330581730
-- 102:08c302107250b8273008310010024008ae72b82730205b10f8d8d63008147dff
-- 103:d630ffd630b8d63098027000268df63008a00008822028e63038b00028d63008
-- 104:b00068863028c0002826302844a258b5301863845845301874a238d43028a000
-- 105:487430182b5268043038d000489330283433c8433018d3a278e230081200005b
-- 106:b8a23008db00180100186230c8a230384fb24840008872302881001801003822
-- 107:3078723000dbd8610078a23018eb0068310088f23018810028310000430898ed
-- 108:381330180d0008f00018082058433018310008d6f1485c2038933018ae0008b3
-- 109:002821000020b83b6008710018c030101230089c20589b600849c118de2008e8
-- 110:b7081d1eb8fb60085100080f900010e81c6010121008f804182000389530c84c
-- 111:60001008ba4e088240382430c8953010022008510b08ebd028e90098c5300022
-- 112:08c300004208a10018954e983630003208810000521868341000735886300092
-- 113:1831000801803002140094680730300810136208781a08028000c368673008c4
-- 114:800082084100086b3418184428a730201003920821000899610881fd18e73000
-- 115:0b08f09008f500382200009b088f800052086880008328783000ab0892000062
-- 116:08e000008428843008e4d008e000004208c10018e000184c3408c200003048e8
-- 117:3008a992085500002818f16018f00000db089acc002808b18438183008bc1d48
-- 118:a000081800003878d83008429099f83018e0f158f83018f6f2ff1070be107000
-- 119:0208587120120c1808f9120018f8a07000f0c890702003e00be820701002d008
-- 120:38d2d820702012d01b491070201822b0082a6049207008e100009008b6e02950
-- 121:70088e8c102250183ca0099070105b10082c0008882b08b0e0e82170108b2008
-- 122:4fa1002bc8617000bb1840f2088c71a8b170084fb728eda188e1700814b0ff02
-- 123:70ff02709e027000000000000000000000000000000000000000000000000000
-- </SPRITES>

-- <MAP>
-- 000:c077502797e656b6100008000ca8a40c07a7a4a8a7a10205a6a4a70ea9a640f6462716108c1900a10203a2a4a3a3a8a6a2a3a60ca7a80f0c088077f627b63786f60710e52b00a806040ca9a6a40382a00103a1a2a5a2a3074027f6164610b4eb00a5a4a7a4a6a3a7a6a9a2a1a40ca6050f0a059037c656a716f566162710fc9c00a1a2a2a2a403a4a5a701a104a6a4a60d08a66066f62756374710f79e00a2a3a2a10203a3a4065080a101a1a3a1a2a45037c656a716103e4d00a1a1a2a2a3a4a5a7a95080a10102a4a2a5a760b62716b6f67710d3fd000ca9a5a2a5a4a4a8a7a2a3a7a9a7a90f0b085077167756c620
-- 001:000800a3a2a4a2a4a3a4a9a7a4a2a60ba5a60f0b07408616c6c610a93f00a3a4a2a4a6a3000000020306a3a50aa80b0e703656c6c616273710282a00a2a001a5a1410000000000000380800c030150e696768647209c8800000000a1a204a4a6a85050a101a104a2a30620a6180061e700460076b0000000000061d026573747f5462716475677b61685850000fbfb001d2c08600010fb0b08a000002d28a00008c00020000d4c08a00000eb18a000101d3c38a000001b38a00030dbfbfb2b38230028a00028230030cbfbfb3b38230000bb18a00028820008a000004b38a00030abfbfb5b38230028a000202d2c7008
-- 002:930018e10040180d4c08020820003012c0fb5b280100101d3c18f00030f200fb4b18740020381d2c18e000301200fb3b18a60020581d0c18f000002248f000006818b20038010008d400001b680100304200fb1b187b005801000052480100007828e000107200288e0038d000008218d00000eb48d00000a2186e0068630040a200ebfbdb68e00000b208e00000cb68e00020d230ab08e00038630050f222207bfbbb58d0007062303bfbcb10f82838720010002b08340020f8680c28d10010827008b1004000f8580a0c282000404c301850bb18c20010382a48110020001b10089a0060cb000800f8184a58410008
-- 003:901000bb18210010087a38210008f41008210060100800e89a0c3018e000003b280200400800c89a7008161008e00008c10020b8ea1018c200080100002b48e1001098fa487700001c18410010ab2008210010ea6018110028f000703008006813fa2c09286300083100a01bfbab406833da3c090009285300282100a05048330a03da2c19000c2a383200406018030243183100202a0c2a581100301243fa8a28c00070800322530a03fa5a18161030bb70033208c30008f000004a38f0003013120302281100201a43da18922050701322030213181100200a73da08a61020bb70230811002801008083ea00dbfbcb
-- 004:60332248f10060fa00cbfbcb708328d0002063da1008c10010709328d0001033ea1819201060a328d00008200010ca1008b60020db60b358010000aa18ae0000eb780100009a38010000c3580100007a2865207801000062280100200b50d348110008832018662068010020033a102878201040e3581100101a00185c20003b7811002000fb6b085d205801006000fb7bfbfb6b3028e0007000fb8bfbfb8b001a08d0006000fb9bfbfb7b0018040010d300180230107b00182200202a931018143028910028db0008c63038a10000ba48c000889100006b68d000086a30106b0028b210080e0028d0007aa100089500
-- 005:f8810048270008c000005b68e300081000203b000b688200081000402b000d000888f100301b002d0838f1000020180a0008f00048d30008392008b240300b002d1c08a320008a08fb20084e0008014008b220007a58d000003c08d000105a5c18b01040eb002d4c6328d010006c18621040db002d0c0d381100100a8c18241020db003d481100009c18f00000cb18f000400c0d5c53cc08b61040d04716c6b6687e4021a070b3532a301a000a6c000b9090030042100b08a7102032001b285a0060102be026c696e678f20040705093523a089f2008683030606a6aa0282350307716e64648f25008100008bc109e60
-- 006:00309b80ab2018d420307b100c04182000702c200b202b002c20182820206b0024385100704c002220043c0604289a20904b108419343204164c1608010018ff40c0100b00242c3439041642263c26283100c0001200244c0406492632362c36182100e0db10320604064c26393612560f060f28620070cb001632264c3619181100282000102f06386540186300685100009f38884040060f161266584100300f067f6438710018c4008861000004187c4008b100186400003f283100108f4438d940105c3028da0040cb009fa41a581050002b18920050db00040ff404183910385150005b08210040030403d46a88
-- 007:72500842004003d48a0c4328225028f10020a4aa7328315000cb28d00000da38c2004821004013040384fa683150182100602304035403fa30182f4028525050cb00335423da78515018210050433443ca2c294841502811007014030a53ca2c103a28120070bb00044304130273188e4028e000107312185050003a285650085800007328415008f0000812502000a3223830500033083050000b28f100108332485e4000ca18a270083a0010833238405018415018120010a31248120018515018120038b5402053da10380200000348110008200008e050185500201304f3481100087c3018f560009b18af008851
-- 008:00080b30003b08510018c30000f3083930182000081c5018310008b30038c63020031a3208ee00004b486200302304f3235811503872001023244821002003321048720010333458310008a160005b386200004458310008d400006b28620030236400f3381d0018c1501852002013641028210018fc3028f6000084088640102ae3080100009b38ab00007448874010c31008024068220028960010731008b540a8520010038a08691000db088650183f00101354489200283350008b28cc0020334410280800082f0000eb28720020335410586110181100280f000044088300086200281150284200181100b86200
-- 009:003318c5009842000023181100b8420008de006808001821000043180100c8d600008468e70018e16018ac00680a00181100182200000d684300583200001d1897000010583400301403541d088610009a083c2000db185260286e00001c28a620006a28d750007b48e01018185008965048410038ae00003c284100003a08f43000bb28820010334418e550001a08e75000ab2842004033540d3c73083200481100188e0018185008e750009b28020010236408085000fc08cb50008b08f00010436418e85000fc08d40018e00048d100300c0dbc22080200107ba028f950284550019060b3530a101c100a00005c10
-- 010:8010322008995018f95008200020101bb0389950289200b0604093624a0c5a2a001a5a9028395030b62716b609295008010008b25010eb0008b57008c72060eb00db002300eb4851406000bb004400cb00087640003b08f000201300ab08f00020bb001438f0008023008b0064009b002438f0008033006b0084007b003438f0007043004b000394005b082300480100303b0003b408500000543801002053001b18741000b40870000074384b400063082e10200403c4086000008448110000040801001821000094380100007318e00000f468d1001858101003f448d30019c100204422f488d100204442e4a8e100
-- 011:10245248010028e100003458e00048e100003458e20028e100205422f428b65078770008a60018f000387700080a00b9c10020cb000ca8d10030cb00fc6c28715000ac18e00010bb00088f10482c50105c30085830085f90000008c020002c682c50086d50387200001c983c5010ab00182320008a682100003b08210008110048ada028e10020ccba70081e5018f45018d42000ac483c5028aea0209b001d182100488700284c50009b183380308cfa0a40482100180050103d7c18f150003c0861b068eea0309b004d5c08533030da3c0810680fa0209b005d18f03020da2c18581fa0082100101c0d283fa010fa3a
-- 012:382fa0082100000c082100084100386fa0309b007d1308e0001053fa08d4a018e750006d489ea010fa6a580100087da0000d281c301831002821002032033d38f000183c50307d13326d18c00000db08c110306d23226d184e0008d46000cb18f00010537d18e000101cfa084fa008e000006328e000003c08b99008c710105d6328a20008cf80006a186fa000cb58d20000ac0839a0183f10105d5348020008a190189c10005d38f10000dc18e00030eb005d4348e100103c6328321030fb004d4338e5000083288f0008fa90104d33581600002308e710083100001b78310000bc281100302b003d33285300283600
-- 013:0802a0103d23a80200304b102d13880200406b100a0d03a81200083240001a981200288e40a82200285aa00a320058310028b820580da028830058520028d540c96200005b382100b872004840b079720008b05008d79098720008930028210038a47028310008dba0088b9048520058a300007c4851008882000831000870f0001b08d230281e6048920008d750086100300b00082028040038b20008510008c7c0100048086c20003a28110008565028110008e72058930008ab10006b08fe100048182c20584100089330006b08112010482238cf70486100087f10007b08642010483208fa807861003851001038
-- 014:5228510028560018bd5030bb00584208f8d0180100000218220040ab005802083821000899f0106b90289e5018aa50188e50a02c202c0c006c202c20800c0848b0401c42000ca0381e501812001070406867b0300a506af0283e50904777162746f67737b696589e50202b004c08f130081000001b0890000879c0889000000b08900028606048900010f0f0188000081ef000701830f00854f0003828db2010eb8038d00008c10008d00058c10020184c0888d10010280d081240a8f100201d1c18980200102d0c38f000580200007888d1000098a85700008828e000ffa10038a10000a8185e0158910008720020fb
-- 015:db9068810000db28320048810010cba068810000cb283200f8810020bbf0305869010040183e5010f02078490110f01058090100f098d80100e0b8880100e088580100c0082801000888280100b008180108b60078180100a028080168f850083601b8f7010080ffe70148e701300003ca3008e32158d60120f020db68a70120f040bb68670110f04008fef038c000203062a008700188e60100a0081201a8d601104b70085d80a8e601109b50c8f60110cb40089140880701100b00081200ff27014d2701000f38c1b0581701003f38d100480701003f38c100002948f601102f1918f6010039382601102f2918f601
-- 016:58d000003918f60120290819381701102f49381701102918081100183701202f090f383100200a3928083100185701003f483100000d48210000cb18210070090f5953090d4938082100107bf0284f4078bb4008af405063006c008080189701288701000b28da0020101b0138ef4078b20019a7014046566796c628ff4030ab30eb30184da030ab40db4008ae1068800000bb28800008c6302050cb5018a5516880002060bb6008e010082c201880000891805880001070ab08285110fbdb187000088a2048700020809b8008d31030db908b9008531000eb18e00008700018e000082b2010f0d018f11040b00f004f
-- 017:a018232060900f000f005fb018f6b008565018f6b020f0f010181760487000000b18800008d82020f0f02008700030ebf0f0401832b020f0f06018f88038700020cbf08008b2901013a018f90010f06018549008939000501861a010f060081a3048f00018654010503238f00000434863a020f0306258110018401020f0308268f0000852a040f02092702338a0003000b2703328b54010f0f23822000881000841a010f0f2480600001328f00030e003f24048e000082c9050c008030803d218974028420028410010b02808410000c208d1a028630028310040a0480308d208c84010032238320008225008210020
-- 018:f23203084f6008f00028945010480318d66118e000001808e000005838a76120ab7018081a51003808e16108164128f00008c8510018180261202258d21831a010701808e851281100200278d21851a02080183038f0001088e21881a02070282028e561200278f21881a010709818a10000d21851a01070a82881001038e2186a501060b828d00030000208c208b84010cb7038f00010f030081e101060c818c00020f040cb08b00000d838b00018494018b0002040629008ed101050e8388e610082185840000b58e00050020832103b70082f10001b7821003012007b6028794000f8582100300200ab4028794058
-- 019:21002000db3028694038010058594020100200181100286940507b000822e810185940106b0018801000c828a930006b18501020426820181c30288100200208a208c61028c740280110009248034038b10048d00018c00000b2f89100005b38d00038a100005b3804004aa10018618168a10008470028d00088a100002b080fd048240018884038ca1038b100100b4008aa1000b2282940100b40083f1010a22f28f84020400f4808a400003f186e0020eb402f08c000300208524f28e00010303f08c390086f00202f081f18f84020db305f28010020223f18080100509bfbcb504f88084710203f280f28e0000040
-- 020:08e830080100104f2808d100008b3815f028b24000a008f64050105c10202c3008692010422008050010100b38c8106805f028820018079018b530504203020250623835f020a61676ae5e4100bb3841a120ab00080899400800b0408b10780250285e10001028d69110526018d540205b000d28e00008123018c52008420008d000087e2008d00008a76138b79128e000001b58e00008a520187840084ed02048020c08ab20300c420c8208faa008c8403885001851a118110138e200006208b1001830414822a1001d38cd31389200008248e00048c100001008b20018fee028d10010324d681de0001b8862002022
-- 021:3d5a68da91005b68c200001d488de0280a4158a200200d9a7008a09018010028520020220dba08bae0483a412822001012eaa85a4138620010ca5038629078620020ca2c28887a4148620008f49088ba41389200000308610038249078920008b190001a184490886200182ce0687e00101233381ce048e10000020856c028fbe058f10028c670103a4328019048140028310008540008f290485600485a80286990088fa178b400481e801013da78d200001228f99028d200002a28610038d200480a4118fa0078c2000002485a4118a080004a18ea9038d200187a21282000208a200a08e15158d20038bb90082000
-- 022:006a18d460683d00385c90081e90886610000258b4a10053881b1068f3a1288d4158a2006853a128bd4148b20058cb901851d030db20781e380100282f40500b10581a0ef3286d4150fb2b100a284a388890080521300a03086a388890003b289090208a0c3328044028b10008f00008ff7008ebc1002b78504128a0d138b74138c0005aa10058b49049b10018d00028d7e068184108c330182e2178d10020db000f1838e0185400180210004f38b100082a00189320004f388300003e08d10018df11104f0e28ae10107a4e18a54030ab004f1e186790005e18d000309b004f3e08d000104a6e185750309b003f4e08
-- 023:0d10103a7e384a51005f18d000101a9e383a41205f0e0f18f00000ae18e000006b18e000500e0f5e431e0d08010000bb080100408f0e0ffe8e186410705b00af0e0fae0dce18d510404b006f0e2f18920000fe081500009b38b8e0182e4008199010431a08f0a130005c000b1869903807412012101b48e8e018420008e641005218a9d1082e3020505a8058a1a110437428c150087210084000006b18b700105b0008c43000ab08c000087000009b187000004008912008d760100c0808b080004b08f100102832188000404b00285210082630405b0048002828448008a100301a000c2028410010080308b60028f2
-- 024:0020100213080281003b0890000814100002284100006b18b00018f620007b082a41080620107b0008d7201870001827c1006b08f100001a08b700006b185250100c03188240005b08d600002d28b74008f7f1102c0028064008210028a000003b2839f108288028a000202d2c30488000f92100103d1c794200103d1c382100080831686200104d0c484100004c08df8038030008e100182ba1084100301c1d0c000804f0002b18610028020008501020300f0d1836f0002b081d00201f0d1a385100406b200f0d1a3851002040030a38900010200f089f0038e100005048800020200f2038c10010502838c2000038
-- 025:187000107b4028e000107b3038e000088300080870180100102f0e38f10048f00008a87088e000087000003b28d200086570089000380100006b18520018700010180308c770189000002808291008800018360008da1018170008700018f70018e00008700008bc10188c9028c710187100087000185200004b08a19000481893e1203b406808a230103b101894b06820002010ebb058962020f57703a8c620584000007b88d620007b18700018d571100d40089500087490000c08b6201832000028283212306b002842183f91506b00380a0018085412000b18b390002a1847201851002008020328a620306b1003
-- 026:02280ba1306b10231a08a920081400101023289720208b000a0851b0005b18958128cde1089600287f40006b28a62008c70038b0000013282620081e12284c51087820003c38a62008210028a000181e20200d4c30288000005c18f120781100204b000d482100204b006cb8110008f422102c0d08a62018a000006c0842b0383100105c10289e10103b0008c1002020080d18ee41386100081520186250287100000e08d00000eb488100001e08c00000db589100000018e00000cb48a10020101e1328c00038a100200b000e0820c000bb18c100300a0c101f087600001b08b8301000ab081100002a08f520000808
-- 027:8e7108e0c018f00008af00405018004b1018c200002a38362018510010601808a120001b08b000301350281e18c610304b80180f0896200890002070281f08900030fb4b603808a72008990010802808a820088000407008202f1e18e90020800b2008a10008900050201f103b202f18a000006008c000183100302b704b10181100401b804b201f18800020705b1008c20060cbfb0b608b100808e82010cbfb08f900109b0008092011cbeb60ab102800cbdb60bb202800bbcb70cb18610030bbbb70db08610030bbab70eb08523030bb9b70fb18e000308b70fb0b08520000ab088000701b101803505b8b80182332
-- 028:01304b8b501f20eb00280f505b9ba0db906b8809200013a80920988820085020a8f820000808bf30280920000d184050289820003238472000182840d038192038b9200018289f4018420078092000232813d118682028f820008b08a89128e820386820008b18ff4028d820884820289f4008b25028484228582008d640000868782018a00038672008d90038b00038605089c920a9da20488820083100004c38c920287550884100283a2138510018f45108602028710008d4a018b000187100002d183120285100000e08ac00080120483400100e1318c00030102c1f200817e0001328612010031a181920000b08
-- 029:2820000a080f10302b30031a08cb100877c0084f1008c7d0401a3018002b08c790301b50030a08810008380018a00008510008a000100bb0281100400b700b3018084820101bfb089000002818900000eb0847200038182b2050eb201f201b300808c0300beb603b28b150300bdb705b08582008800020606b10088f40100bcb08b62018010010cb50080a7008800020bb609b28010020bb50ab28010000ab08282000ab282100209b60bb18472028900008762030fb0b8b60082361188000005018582040fb0b7b60db280100207b50eb280100404b000b60eb282100103b8018992028800018dc50200b3b7008eb61
-- 030:08a250087000706830bb4b200f30eb78d2501010ab8899200023699920eb125008c4a1ba325068d920991250102d1cf81250185570b879207a210018b870f86820103d1c684100188e7158f670483a70288100097870183380488870085100201c1d1c48d970001f08715038d67020102f0d687770080be128f430083b70001018101038c8703890000010086350180fa0690a70c8e00028c72018a510082b90384870581100289b70685870005b18700018657008510018657028e000003b08d0f0081b70405bfb2b5018281910101b60188820205bfb0b08d6501870000070085600305bdb000b08bf6118110020cb
-- 031:800b18e620006b08800018e72018800038010020300f5018010040db500f1048186590106058182610002b08f50058200010fb1b88c7200033e85a70480820b82150000d5821502861a01852000018d8215008a810e8215038b0a0285720489410002308c5101831105821503891a08831502868201857201851a0b8f720202d1c0308410028a000002c18a0001818200861a018b00018c420381e90a8862068c220205b004d08bb90484100002c481b90481d90189220400e1d1c0d1c8814200846e0b81420189920001d28be2028a8a01887a148f15008830028b00008e4a018610048e150000818c000489d2008b0
-- 032:0068d1500891a010ebfb08e94008c15018b72000db0882b0003f28b15018e00000cb08a100101f1008e11118f00018e00050102f2018101b08b150005b088b1008a100002008f50028510018c22058510010101f183500186100085f9008a000185e10302028300f28d500201f103808bf1008b40018610000c0183500001f08a000202b60cb082a50004f38800050203f002b50db280100101b6008800000000881000050182c50202f003b088000003b083450102b6018f880003f080100184a802008031f28a000102b0008185048900010003b189a5108c1c0080100000b0839702028004b189000100b1028a100
-- 033:089000083200004b084b5128800020a0cbfb088100404b600f30bb08fcb120103bc00870005068300ba0cbeb082c00687a20007b887a200043ffc4a0bac4a0180cc028800028600218d92058925018c6c0d8982038d920c8782008d082002c1827d0287100487820403b000e3d4c185100080ae1086a2048310058b9201851000851503855a00861000010283bc2186100002008a000183c10185100001808c0001825a008610000081806d01844a028810010101d1879014891000804d2089e001842a0200e0300183a20001b1812501804a0001308fc402805a0084a20180100086c701829203815a018c2004835a0
-- 034:000218820028414008c000187100084b2018e130287100181e1008d00008df20002808f15018a230203f1038280c200804a020202840288720201008501833a0003b283300100b50182d200817c0001e085720088a20003b088a201863500836a010005f08e62008048010006f488000204f105b286f20000b084200008b086e5030cbfb0018085b20009b08513000cb08ea70400f00ab50cb0853e1000008068130cb0058000853500876a008900020db50bb08ffd14000eb50bb9b18e3502050bb8b08e00008aaa000ab288000001b08c550205b8b20089100100bb01886a0200810eb182100d886a00053ff86a08a
-- 035:86a0002d6866a0102d2c5866a0081e405866a09e555018b00058555048a45008f35018065019555018d241b87550204b005f187550001a283320005f084620586550202b006f08592018cf1128d000005f5807a020005f034807a008a0004807a010005f3831d008900000000847a02841d028b000185b61101beb0836200887a008391070eb001f1e1f001b900877a01898200060180d2000db089200005b08ee4000db082100006b08800008642110008b0870500816b108dec10807a0080100388000003f0828200887a028692018a000009b18592000bb08782058b000084100008b081a200870b1088000003808
-- 036:99200837a00801003880000038082a2028b7a008210018a00008395008a00000fb28a0000068488000080b20007008c43008c08000b018d7a010280059e7a00063ffe7a0ffe7a0cde7a008b7100b08a0001f0802f0c808a0084100a847a0084aa0c80100181dc02847a0002e186a11307b002f0e388021084150284b10005f187000005b187000185531004f181840304b00083f188000403b00281f301838a008497028c8a0080d7018392008e7a0200058502870001048602858a0200048700838a0286720100b500857a0086720a8800020300f38088f810848a0001808e00030fb600f8008c900002b0832300918
-- 037:a00073ff18a06a18a01849f05838a00893705848a008b4505848a08e59f038b0007949f02844219839f0205b002c0891a01850e1000a18b1a018c150084f405859f00801000859f0000e28010048f00018ef4028d7a0086a20002038eb70105b1018610008f12150fb5b60281f1e18650010701828512108010008c620189500105038381e11205bc02f18600010602b0814a00876a010702b08ef40288000280121204b701b08810008800010602b083b2008aa0020503b000862c1088f7008130008c650089000082100086d20183f7010203b187f20083420382100002b08a1002870d00862d028a1000827a01050
-- 038:4b2868f008da7048c10008b00018410000201820e1704b006820cbfb604b080b201847a000701827a000b0e807a00050286ab210233428092008b172094000007b180230105b100825b2187330000218610338c161300f240a032859b2204b001418c4f21890000004489a70203b003328ff40403b00430a0228c3510886b2000038205008f49038b720003b085cb238f79118e100000d38d72008510058a050286100101c0228e72008710028c0502841002816a008210058900018720028323018410058a000285100284a2008c29130141d1c1268c000100d2c68c000100408589100003b18b67038b000184e6348
-- 039:6100e8b000387e0010180208890038b000002848a00008a440085100080200185f00000818535008710018c0002028122c48a00000180815b1181772386100083a805881000032183260286100182200485100083ed14851000867021815a0186f301880003a0100202b0028280100202b0018082373aa01000823f1000b18010028a6737a010000b8187000103bd038eb2068e171008028262008b171a95620584000008b185722306b101402383133305b000216480720405b00340c0a48510020142a0028bd40005b48072018a0000033283a13204b0053283810087fd220140a1318972008492008cd52082e4018
-- 040:eb2008482028ce40082b203822a0385100100c1348b00010142c18e620185300000308b933489000087992281500789000001c08518018a00010140c088b83383100100c0828410008772048510018a0000018484100300c030c0828510008afe1202c1822284f9008b000201c1832288b9218d31008af4110420c28117138910008a4a018dc40389100001018d000185fb028a100087f6128317128c100005218f00010130a086bc018f00008b89318464108010000ab180100200a0c7228f00028e00020031a720804d1281171001b080de008e000003b08fbc028b000289c10000b08a99058a00010280318e01220
-- 041:0028c21860000018184e22100028089d2208566100e21860004018f200ebdb086000501200dbdb0028089bf100db087b61084d9310cbcb085100303200cbbb087000004218700000280870000866c0001808bbf10866c00018080432087000002808700000ab08ef6108d5320870005018f292009b8b08700000a2187000002818e00008e690a0f2b2305b7b00f8e8100f100877c0500ff0b05b9b800832a010906b58f4200013e9f420107b50280170301409021638222010162f08430318900010241a2890a108e320003a58842038e320005b082a40281cb1384d1008d00048402008c42019142038a00008df1018
-- 042:bb4028042068532018abb228a150f8e320f8742058900008a40068c320091520200d031c585100200d2c32485940101c42489000000d08230048e4c0202c320e681c61201c321e18c000286100485520080a40000d088cb2083c6128262030180d5c02386b6118c000100a0c08f620380270001b08dd40401a42000b10185791001b080fa0001a18e62028c27008d22008ba40005228c27008f22018a1001853c0180c4018a00008922008c5320870000018082420001b08b22008342008700008442018a1c00854201870000864201881c00018189f121881c01843c30880001805201831c00028280100181220084f
-- 043:0018122008601018122008e00018122008e00008e8b018412208ef8018995208fe3218fa52083ad108700000eb08995008a2c320eb3b1018062040eb3b00f8c8086000082e622869610860f17881c05825200023a92520489940088423386940000908307338c000200f240c18707038894048c9b009794008607038794008689018912000132b594058752088642018507038a000002c2865d318740018407039410018052038410008787008702048f100100d0829cf60101d0c58b0000028185c60d8bf6008b00048bf60001268fe60a8bf60002208f420388f4010283238ceb0083620005248900010284228ee00
-- 044:283760006218d430001b185620007208473018e9e018e86018800018e96078010008c620280100080820086760f80100100018188720089820080c4008700098e000b84920592a2088e00010cb1028e000080b2028e000100018087b2008700000f81856e200db08c292089b0078c4900818215894200033e9b940686e6048a940100226281bc0083e60100a0c893e60002308359018c420283590584e6038422028259028d22028259038794028259028510038259038852038259028c94078e420585420001418cff338a320082120484100087220585570000458c000188420081390489e1008c000387120185200
-- 045:0004383190188100001d08e220582b31101812588f01002828a00018ac0010183218a000188a40002828a0001831000042084b40283c31003828a00028fa40201d4c02080f013861e1087e8008bf0128da4000821814e018907008d12048046128fc80186940d80a8008a42008602018800018e02018f00018ef7248e00008742018e00008642018fb9208e00000c228700058e00000d208f600186b40086000085b4088c0000002082700089640182631187b40087000001808707008bd5118db4008700028e00018a270003218700018cb4000ab08d504005808179220ebf06008020088f32068ad600043ff92900a
-- 046:494078642098594078e320888420486220189420001d584220100304087640f8d320285390589d51200d031808754038c240100e1d08d64028188108c000000d08142028d23118c0001018422822312871000032185a81183d6018710018153118702028810008bd51186f5108e0000028184c6018c420182390200e082d282390087b1128429018c32018401018c00008452018565228f29008b42038d29038442008a12008f220289290187320ff82907982900053ff82903a8290787c6078a000280053a9e84048152069e84018bc7178f84008712048094008864078f8400022580da149f84038848118f8400856
-- 047:1128239008094038575108722010621028223028f2900878400010182940089220009258294008d22000a258829008a84039f860ff32901a32900063ff3290ff3290185120ff3290ff3290e93290007008405108ab005878f18822900073ff22904a2290d8500178fcd009dbd038a00029dbd008d57068cbd0003c38bbd0081e60cacbd028619038bbd0001d487cd0105c0228eff018819000080894200052187f41388cd0101a52184dd028d190787bd008910008bdd0387bd0189100280d2338510028b000ff5290c9529000401857a310639428e32008d20348400000ab38837108175008400018f5b20890001014
-- 048:1008822018cc6108c62028800020130402085204a821000044283f10206b002c085db2383100000c385db228407110020d08e4202883c1000318f68018b271003d58bb91002d28030008900018726008a10010100a3821000896500003186c1118bdb2086510002d284d0308b00010220d08aa5018472008b62310120d2866c208d14028f83428410028ab84192100203812032828a1b94100005b083eb338800020280203180621283100089f4338e74008c0000032182e0018a00008330018b62018b000004818120048ae2010285248a6c2084f230022685100201218125871000042685100302208120c3813a030
-- 049:1832081a887100001a48c20008bb4138b3a3188470000318610028a250005258a000086d40388d9018ca4158a000101882085500283100007268210018c500e831002898d228410048a000a85100000c0887f1b861001810c038b2001831c038be7018410058a000b8410018957038510028a4003804c078710028a40028510000a228f50049510018933038510018c330100d0c08df103841000012088d03100b0008163418f080388bd3d820002000cba078c58328a2a108903418da2428d01048700008cc14185100106b70189991103028288c20005b187af118f000284bc2105b2008f0d118a752085100187000
-- 050:283e2018dae2297be2100002189991286be200401841a0086be208adc40896f1c88be230000f1a0938ed20400f09030a0808c000185d20102f19081b91189000101f293873d218210048b27108310048c070784100102f19684100002908096348410008d990d85100103f0978510020090d0909c200103f195851003013040f19286044404b00231f0948a0002013142928924408f950401f090f1902081b0028590020191f0918f3a318e820102f69388000401f290f090d58410020190f1a48b00008710058b000102f1908d9c168710008835108e400388100001838b000005b086a001806a318a000201f191808
-- 051:aca33841000018089ba31863b008410048a0002941000898002821000079188000106b2038e3610800c108f34028a00000101880002880c1186c7328a00020130804182720181cb02002132438412010003328df00182100287054581100080ea148210008057058310018800018cdb1000208266408a210283e9138410008331028f200184791085774285c801033641910f200d0780b20e830f2189b0000eb18b720186b24287000482c20107b60287000106b20085cc1185a00186b20087000184c2018e00008700018d100084c201870000826f1287100089cb1e84b421010021851d118f5f1181de328f5f12859
-- 052:f4786b42000f486b42283b2058b0000013288ef208e6100029489000100f3938452018310018f920289ba00039183b2018a0000049d831000800b1484100204b005958e82008310038ee90300f290f19385100203b006918741218eb40000f08820048b00020290f29088012386b42300f19640928d6e2087100300354090008c00018dd7008ec2030280209102825e2181300080500002918e00018fa4208860010292038b0f238910000204890f2000f083fc3003918d0002850f230291802393847c24850f2202928390870222860f208c100004928470040030a0f292838b000001308301018a000502b001f4928
-- 053:5928bec0302f391869289000101f494890000821000079284680082100189000301b001f59489000102ff928cfc0201ff90928c680105860089be1188100006808787408631018b00010481008a3330024383461001308e123086a100024180280103308085c7410131418e1800043082e7418510018fa7430bb0013240871f2089a7400cb0833d41842f0005308c18408e1000802f00053082284082300088b420864c3284100008b08410018850000240852f218b00008ccf010140c180c42081200200b006428a2f2400310eb0024583c42a8ab2088d2f2986b20287050d8da2018275059ea2058e0005839f1785b
-- 054:20002318e450189c300013385b2008eb42384b2008aa20484b204849f1200f030a28c550485b2008c00018988008532048ca2008cc4099ea20d92c2048b30038ea20782100681c20f83d20082f40203918032858330841002019540928a9e20842400853501044094853131000030894000019484f62001f081b50102819081fb2181300188100185d0028ad20302f29281908458118b000201f090c18fb20184aa12835200009085550102829280bf1182420002f08f00018f10048fba00826200019180200280ca0088620002908621018f10008a800000b080a0008e000080e20288911202f5918089c20000b08c2
-- 055:040069489000101f79289000084c420089489000002f382100080304080b20087940101ff908bb5000cb087000182804200048a01867120848f0003808992008a8500878f020080a2808c00028710008892008b44000ab0883c038a9f008fb20285b2018e8f0186b2008835048a00028510008b3c4081c20185100181b62281c20185d42004308b000185100007b08510008cfa4185100182e42004308d00018710018b58248bd2018d000006308b000080f2018b00008cd200000183950002008a2f0088d20182bf00803b498ee42a8ad2048e6f2ecc85009de42d9e850682e20087d20682e200013381e2088d85008
-- 056:3570e8fd20380480b8fd2049410078c300586280987480581d20002988648048410008548058138010230408bd2048c00010131408038048c20020031f59580400000f08a22038098008de2058510010080f189d0038710010080f28b732187100001848adf128f280389ef028d19048a000185b0038af4269548048a000c9410008d900282100286d80106b10187cb3385080184d832822c048cd8308e7504888c020230a04182aa0289e7018448018f052005328c2d0001b08082028d2d0000b08372018782018a000004318c022283152104310082cc408c00008da1508920008f7d008d0000821521844d4083200
-- 057:48a00038510020300f3318730018125200130822210822520054f85af2a85b20887af2799b20080f72f8e85048eb2049e850f802520013183c2408f15248c85008ec41d8d850481252100f09186c62b8048028cfa0389000000d08a000182610380ca0186810480ca02899106851001898a0586100204f090d58ca2020090f29285793188d1008aaa0583420100f1948b893280aa068a520781720003928b0001844203023340f194842522013540f08342018a00010231408578008d12028f95008ae7008760028395018172008d500000d282352088820087ea028b00018810008a45018c691288100004938dd4138
-- 058:91000049383d4138910008227438610018a280283100189000084d50383380188e502881802821003890000821000089286b8008210038900078210000f9281c80102fe908700008e97220424038083cc2204b0042085871102308281600089c200865d2088e4018de01003218cc0208635008c00010240208810008905008b000003438220028f1d318c000186100002b286100289444080d20004448220018a9d008a920004b18320018136028f20028520018e000003418910018745228a000006308945218120008852128c45208b750280cf20064f80cf2a82c20c82cf2ffb0b0c9b0b078bc20002938de40a81c
-- 059:2038a6d0481c20281200481c2038f0b010101f18ba204811b008d57438b15008610048aa2008cde208e6701801b0003f489c2018475208eb2028be4018610020081f192811b0301013541f188c2018fca0002328b00018a1f2001318e0b018d00028d1f20003082f4010022918f00008c320001018fb2010001f38acf218be50102910183b3008f42018a100003908b8732800b008472028f0b0484cf208688058d0b018a1003820b00851003890005831004cb0b0205270282871002062004b087da218a0002042105b0819921870b0001408d750008b185920086620103402082680001208adb00856200825801851
-- 060:0000db28fe251012231870b000540864800854720870b0005408b38008e1000870b0005408e2800823000870b0088550284100008b18fd25000b1833000870b008b0002821421870b0081200200b00632870b000040870b000232970b088ccf2ff70b0b970b078ae70482101b89650386f706ed75028b00058d75008b000282750188a200825004831b0d8f750089b856821b008b51158f350083da048e5a108d72000292813d228e0b028a1004875a108362008c10058a0b008fab05870b000697c40b0004218a8a30830b0003208592018a6a220bb0002081205009b28f7a208285508cfa008ea851884400820b008
-- 061:ab20280b20188fa0181b2018855038a000285100008b284c55185100008b08455028cb20188fa0004408b000185100182b5500eb3851001820b0004408d000187100003b086f55486d2018d0000818a518be2018b000087d2008f7800820b0085580083d201820b000248920b0482ff2ff20b0ff20b0ff20b0be20b00042283c30206b0052481e30188000383f91001248da4120240c02188a241800b0004408b0512800b000441837201810b00044189820187fa0005428682018a000004418a4f22810b00044088f1018510018e9851836a518d000087fa01872a508320048a00038510020300f341873001810b000
-- 062:14085dd018320300432820b0884203a83b20886203ff00b07900b028b80158cb207805016c980110190d08aa21c8410018b80148c751b8b80110540928db4308c000102904082150381773284a010863011804a338b8010039080b01483ba0003928abf338610038620308d000089a202009284938580118f000185801004938380138f00048dfa0001f28080148ffa00861006c00b02010483008abd418e6000048088ea0081ea018c9a30028182aa0085e40087d80003818b92208235008130008d1b0188fa0184b800033381200185b8008b1b0386100002b286100287ad028ecd038220018efa0087920004b2876
-- 063:01082d2028f20028520018e000003318910028efa018a000006418efa0081200004b082e2028efa0004338efa00063f8efa00050284ac4a8f9b1006b184b94009b08e881100b20085d2308a263085000007008e59408c26308500000701845810080187200009018ad701030121810c508e000086043001218a51108b000002018a3d2181574002828295308ad1300121819640822630040081020108b00089d7008260018110008ece0007b081200000818465108c50010100f18875118c674002f080a20083b8110301f18942008f8b110202f18282018a291001f18492018c291e8210020301f0e18e20018a00000
-- 064:2f18c380c8310038e2640040282500181100080b84483100000f58520008d10008080018d50008a05348b00030500f0e08485100004f1803e41899910821e42890000870d348c2f3006f380100002f388d4308870010001238c20008310038a000085a7110202f08e66348a8134002103f081228c000003b08e110003f1842001835b03012104f08282274402b0012307f189000001b080426000b18060048b000002028610008b2a010001b38610028b000586100080f5068710018c00010208f38180218710008320018b000087100000b38710008472008b50028710018f60058b200080a9428180008322418eb10
-- 065:08910318685308ca74086110189000287100185000382020785000186120105b90585000104bb018aa5000f018fc3028b3006847200080283720087781e851e1184000007b18c120008b08542008e720484720007b18e9e408835008987018d3b1285000107b9008b310107b30089520184a0028c72028a46310102828dbf1085720081ee408d6200803c30882b11843c51002182813b1009b185720189116183220006b081200002228c363088e0008682028b25008586328e150206b203f38800010104f285c40086963387d40691100205b105f488550006f388000480100185ae308872048bf10006f185e201896
-- 066:d018e30028d58108a47010002f08754338a050088100001f18e6c318805028810018d745085100002f08f6c328210010083f2890f3405f083f2018381e40185100004f18d0001898401003af083d4208c00000ab089100083620008f08b160001828d000200802bf08212018caf01012bf38f50008c02000af18a0000816f018d10038a00000200890001811201010cf281840201210df3880001020df286302201220ef28800010024038010030080220ff28c1d130080230ef2882d038110008a6202010ff1f28945400ff186ec3101bf0086b00200b708b283ff3003008d47418cfc360eb70ab60cbdb7018bdc308
-- 067:157470db50cbcb60eb50cb08f35508d10000bb08b155000b08ddc308392238600000b00801d0000f0873a370c04b9ba0ebb05bab08737220dba06b58f4200013e8f420f9b42038cc2010400208d0a318a034003208bc4018ae20089c5028c4200018082af1183da408028318b4201028021896d118a42038a6d1584420483520108b0008342028298308d420001838c420884420684520b84420e81100885520383300081100488b70489920005b28b20018210028b20088110008330038774008900028744008ac40100e1f58a52028f10038a52028810010082f182d3018710010082f180c73086100203f083f0869
-- 068:6308862030200f037f185420089620302008126f2820f0103b3008a00018c52018ef6010200f18d000001b085570302b202f1238544010301f389000101b3008b32008adc0003008a320087000004028e0001040ef1897001030ff185cc0182120087000004088d00020db30ff082b0020db20ff08245010cb4018c00030bb6022e0085bc0009008ee82101bab08b65000bb189840201bab600867c3201b9b600847c3201b9b5008a6c3101b8b08832020fb1b7b08932058600018fe640806c3201b3b9028600018742008700008c894083000089b004040fbb0cb4b082820083d9468694000bb5874200023a87420ff
-- 069:e840080a54b8e84028ac60989320991100482300a8240019407018a010196070002f48cf60080a30001f58707008342018b364186100005f48b87018a364285670086400383100003f18c790484100388e6018047018410038b07048ca00189070105f1228d1721880700822003831700002181d60003b28796028b57038607008f60048b000002028610038607028610008094010002b58610028607048710028607048440068710048607028710038607028710008f60000a0084b0008920000b02825c0200b101f08a4c308d19408c220087000080740084a10102bb0085000101bc0085000500bd0fb6bebf00802
-- 070:c00080080620307bdb701b78600060300fa0fb7bebe008f220000b08770308dd0008141098737158e62000330b5b403827200040080420184b400022084832984b40100800385b40082b24086de028472000603827200028381720b84b400010286880983b40107b10c8732048029098952018f190e8310008ed8028b00018239038072018410048369008f32048299018d2f1b8632018152048632028a000181490102f0828b000182c4008f800183300080c40082900089400289bc118ba40001f18140008b00008d200080670288866281c4008052008aeb310308f08ae00186c6400af088000081fb310309f18bf
-- 071:0018e270200210af08721018e0c0200220af08ed32187790184f60087720003008f0701870201020cf08b300584f6008800008ac40183e60001208fb4018004118232000df08deb0185ec1483100086d9500ef284e1110080308ff60289000000208b100183be208017008164018750000f00899b008e520007038f864100b5018f864081940002028f86418422028f8640814c318d864087000186ed0102b500851000845501851000870000050080a641804c3104bb00867000050189930000f081e0708c2c310cbfb08c2c310dbfb88051110fb8b5876200043ffb690b9dd40189ab0b8ed40783620004028c100c8
-- 072:4620001f389b9178f42008362068f42008407018aba438c10008564008572548a00010303f180912183790004008262038752008510068752008710008e2702820f1086100182a2008c07008b200003f38e0e3003008f520002008f520086420085100004f08d33028379008b52008102008c00028669008d5b008df10001218d00008f42028179018359008d50018e52028369018f620ffc6907bc6900053ffc69089c6902a9b4010401f8b9b4048a00058b620699b4028b000f89b40381400489b40000f18a682389b40002228a790188a4028979010308f081620288790380620287790182520184790284590102b
-- 073:30080420ff07909b07900063ff0790ff0790ff0790ff0790bc07900878b4f8e6900073ffe69069e6906f12e0186f0668f1e008152078f1e0003f389cf4204f084f385ef6084a40004f0831e0187cf400af083584188000082620008f08b00018e7542008128f28a1e0083620086f00008f08303638a000009f482690001208eb4728a6200008ff46909c46900040187cc5f910a318751030db1008301825f5102c0808d21608ea0008726308be811880002028020a08c42028210010122a483100202a0308187fe1083100100203584100001308ec7118fca70008087d6638a000082f6108911028e100185f7138c000
-- 074:00ab08166020030a0e28320030ab002f3e285100309b002f4e489000201f0e0f384100308b001f6e48900008014538410008e894004e089d74189000301f2e0f1e085d10284100201e0f1e286100206b002f586100306b001f3e486100088381304e0f0e0d287100081d91087100000d28e700088100303e000f2e084220188721101f4e08b700389100085b21003e08d9c4289100084471205e1f1e287100086571006e1842000008189590188100102f1e084020386100101e08380871005e08f181001a48610008bd06486100006e08de4048c000101f7e08886318b00008e8d1008e08710048c000202f7e120846
-- 075:00386100088a7758510018ea9048610068b000f96100009e28b610286100008e68b0004a6100082c02186100001008b18218baa3401fae10230428a000002f884100000008acd2009b18410020ae2324289000101fbe69210000cf087757008b18cde348267008e457108b6018892000f5ffa920ffa920ffa920ffa920ffa920d8a920002649a9200010185567100a0c088f4610102a08d92020ab000e084dc1080a2030206b001e183520486a2008dda1103e0018dd4708e4e3085c70003e08500828da20081bb708c00008eca0180b20003008b000087e363000285a4e08e0e3381b20201a030a081320089045386b
-- 076:20303e0f005b083d87188b20003e08d490006b18c00050030a3e0f107b181200089b20102e0f1824c2489b20201e10ab08319718122008c5c22855360000081100087b20007e285200085b20007e181100084b20005e28220008e920305e00cb10181b20004e080ad0382100002e08817508410018fa200804c018510018fa2018b000086db60892001889e018d30018ea2028c000287100003e08f190081a0018910028fa20000b084a7018c60028fa20001b08e30008ed7638482008749048d00008c920001b18530018c90028b100001b08781038d00008b100102b1008e8a108f8b138b100002b080ed238d00008
-- 077:b100180355000a08597728c10008a20018451138e000081e0028d45518e000283820186e7038d000085820005b28340028810000fb5841003890002a2100009e085422282100008e48900008210008bf1038210038900039210010001338a920389000002f8821001848c728a92008a310002328a920182a0349310000cf08251008831208550008ca206811b4009b0875120080284b203066c69784386b2038c596fd500000cb28eb66085f10183dd408a720003c289dc1082720086ee338900038d1c2182100000228bd2238510008bd220868021851000003286e22184100003328b41818410028611208e400002a
-- 078:086820188000481376009b081d420805c00877000806f008ee20001d1806d028675008a00008c930082b20000e08c000082a30182b20404e2f4e0d5008d90008c920006e081566300d0e1d30085500085b20202e603f085466201a0c1008e60008e920501e103b307f0e08780008680008e420600e107b404f1e0f08417228010008965000ab08dab010231a18e20008dc10002e08e34508707228d000087b1620fb1b4008be30003b18bd42088330087700005b0874f1006018750008e00000eb08a776005408bee508c13018c0001023b4088c1008a130208bb09b08910040c4c03f4e801876e65008034803008b18
-- 079:f100500803a82f6e38285637082000d06008008b1b0023c4d02f6ef0209b08387610d4a008370008e27600bb08610010447008750008892000ab08d7820811c028c00008650018ba0708a00008c210387b2008b210389c2008900008cc00089000080510085e0008900028a6581890001889d618a82018d71008c21008900028aa67085a2018900008451008900028d51008e72008b8700829a20828a00046087522306602c200089c2008b4b228500008924008e001082bd328592408b5b2184924085101086d400878b3083220381924204200ab0877040052186000800872009bab002c2a2008d824100d1c083676
-- 080:185100000c08b197004a188100700d030d2c3a008bab08a495089125609bbb001d5c009b0881e208b7f318700008f044084100000f28f00000ab18432218110008bf40000d080b4838110020090d2c28b0000827a2100c19284100004908e87318530020190d3918800008574218e00018a200002918a000302f3900ab0801000059186000080c7208997300ab089b6218597330abcb101808ff9200cb08cce508c67000cb082f1508c00008b5e520abcb3008f33610db4008ca1308651738300040bb70bbbb8018840058f930008028d2100815e11803100883401000db285000080ac308bbc308b310084210080310
-- 081:084210080310088bc308c000084210080310084210080310005218ab0010186218600010088218f010204c1a2018e110101c4a08511018d0b7084092000a18a000001d289310081200001d08931008a9a6007b0895b7000308fe55108bcb18a310308bdb000a08b21008d000000f18b310008b082e0018b31008f200101f1908c8c338231020191d0c282310086c52001c3864102823100811000069180210007928f21038b000000e183400100f69080c3308860010791318600050030a6913006b085300201a691028f000081ab130109bbb40088210209bbb50086000108bbb08fd25308bbb100f081530b08babb0
-- 082:8b8b700b408b7b602b08500030503b705b08500000800894a2203b605b58231000133c2310203c1a1038c210001c48b21008d845005a28a210083310005a38921008b297081d00103d1c080024208bcb1018e00048131008fa00281310088d0010190308a02418e01099231008f892486620289210986000101f4908be60181620086310181810100c49084110109b10084f320049081410084d4008e7431049020831002030132808a310209b100f18e520009b081578183a56086343108b500865705000ab7b501b40385000706b502b40ab5b503b28500010608b085000485720007b58341000234c3410085634b8
-- 083:241010020d383410080be3003a483410202c031c181620087c7508d31028531008e62038541018e6b24864100029485410082b303864100039584410189830988720086300002938a93088aa3008593028e930002928ca300019388000101f1908065228ea3028309208fa3008408200ab083a3008ad00001018ff6658ab30088e4208fb3008cd0180bbbb60cbab70cb9b802830002090bbab4820b100ab58931000334cea30000a78c720481b3020134a1019c72008da303ae72068931008eeb209b3103857c398d310387310289f4018347328410018620028310010391f081d10081100003918c473189a10005908
-- 084:d0d0087900101f59081172007b08da63004008290008f5e5001008c80040080318408b08758628e00061200f18309bbb3008409bbb909bab90ab9bc08b9bd07b9b187980006008ad913864100043ff4f40294f40194410683c30482410189e30000f9892600891b328431008d31008900018c21000490807d2000d28e21000490869a2088000200f791a283050008908205008c62008ef5018a7b818e9f5009b08b076084620086300103850187d10001818d00000ab08ffb8f970500053ff7050dc982038dfe2d8982028551048a82008815028a82008715000992872500048086720009b08d1c02003284008038000
-- 085:3808f31008c80308c51020609b8b0846d6ea91500063ff91508f9150101810589150085a701891502000080f180a5228bd8000bb080d80b8d15028fa6168b1500073ffb150cc997038641038c000100c5928791020030a590864e028900000691880500013085050208bcb5018746018cf4008dd30208bbb7008946018d00000501830500960500060082ad54076f6e6898648b4770875b0501e6c0e101e3c185a88281000085301004d18f2c5001e08322618df372875d060001e2d1e101e6d08e5c008fbc0181000008b083be6286200005d084100486200084100100d0e086511101e4d08410008a247181000209b
-- 086:002e18620018210048060008f901184200003d08210028f21818420068210028f218682100002d1819c558c500000e0864f0101e0d182100082fb0385900000e283d0138501148110008fc0018c27158bc0008220010200e38c947181000003b0889f0202b203238bb4718100008b1d0087e010082085613088131088200285fd708200100c2082100088d3608117118b8c030130410f2186cb7087f8108b171285404300400f23208aee208df810856200874c21848e1401314d2086218ffe2107b3008921128e400088af35004e21863022308cd81006b086ac60048084f810810001861007050227370ab6b806b18
-- 087:38f5180be0801304f250a273702b7b08a30130405b0078084c822882b860f2020834f22223081543301b7b0022083fc5007818030008f44328910040521022001b088ff24013203b0098289800087d4430f222181008218708d4a1606b0072500b00b818c80008cf000020589100083484506b00820350c828f800081bd008c51008c100089129088100209250d8082600187a88001b18130038510030c20330d808290018c10108f93040f23218f2c218710010d23018c20018db000814c1082f2908ddf4007808e98830f21310d818d80008ee04102418085100300218e2e8187100201210f808b80008f1a8086100
-- 088:7028f21862e8700b5b08941010033028980008ae347024083248a20822f80802502000f24228d50008d61080443204588218c3e05b08510030720330b808980008fae0a04442786218721c22031c3308200010004b08d100208230b8082300900b008342883218821c32082000002208df46704b4b10f2a21310b8183900a0008352981218f28218105b084f0030e210d830086a00504b30189298020861006008007b1b10f2f208049100a80829000821640815204018c2a8f2720865300881000032080600007b180fe318710020e2f8f808bd147090f2e20330780308083b100855c018912018cec590149220f8d8
-- 089:009b90f2f218c100085b1098c100086600011bf0d0ab10086270f2921310481304181208583108f100182010089f201018f208aea110fbab0877a4305270f2b218120010383008f52088020008f1000847f0a008d270f24203301324380208500008161008500008530028e30008f1004018c270f252089100004818d100084b0800440850f428b100102b0008d8490070186e002004005808578328d1003818f410fbcb082e7470f23270f212301458186100203b008338630000cb0819a350f2b29092138038610030083214a2488100080b158090b210034283201b70080e001884b400db087d1200f208560008f9
-- 090:002012b330183200185bf1086100001808641050705230729310188c0008b37108610008e23430f2f2b270080900105293084a00001248510008b20040a27012308208180018d30000eb088f1600f2087d492070825348420008210008420040f21270a23368210040f0f0f0e0b208580018ea2500fb68e00000b218d10018975750f2f2904228e208e8b42811000892413028f2d29008c82010023828ef0010fb0b08ba2208410010b0b2083100009828b3d7300b02031008310020d2b0920815050098189533084100081a53088307301290f24208040008aee7285100081a1208d3072090f858083e00188a5608a5
-- 091:30004208a8342020f8e808a0100050284200101b5208930000b0084b0000b208341018084008952000db08b537187c0028e600107b621875e40899c230b223f2f21813f718210008180008210010f202083100287d00107b52089ca7001008a3d13003f2423308521048410010321328a40000820831002801e7407b4208621308a16740f2c22372d418e8690831000871301033e20878c7302312f47418bc3508210008b4c75048f21213f4c4285300008b08d01010426808752010f4d4088ab4180100081d8060e26830f252f4e408abd1084d3008961008a0d410a268083b2008510010f40408e43138610008e1c6
-- 092:004208aa37084a30086100182b1010fbab08a1101802052068208b38610028461010bb18081461004808425018310008b75308210008f53008704200fb882100087541085e3078010008da10a8d00008d1d708050018e00008856018554508e00018dc4008c8601830304032f484189328990028c9c610f212080100280e002801002048f202880100081b5420e2f49488f0005038b33210f47468110008efa450e2001b40d440682100080d2030d2007bd008700088210008b91008e480881100081d10085680ad110008543000d80849701020b828af50085b50001c08c91000a818e966008b08b00000b818747618
-- 093:57e808810020100ba008d000309b001cd048410020fb101c08b44028400008ef6010102b38b00008b07128a40008521068f10018267068a000080779703786565607028100083d40083541081093203e20db08500008c765619b000c1e4c00bb6b201c0e6c208b4b10fc106b3b00fc3c18384108e7f8004b086000303c501b1b08b1c4007008c198100dec08600020fc3c8008c1f730fc2c401c082800201dfc0c288000202dfc8008759510fc0c083667500d4c0dac606b1805a6007c08ede1080d60502d2c2d6c006b08e181611d1c3d1c1f007b7b202d0c102d0c207b7b601b607b7b30082000285000906007f637
-- 094:47562782430008d65020f0301b0825a330f4f4241008104370f4f4440004f3f343084fe830f302f33318bfe810e4021841004003d422f4348870002032f4241872f8004238700030529402642880002084225408800050b4725422100218630050b4724432101218230030b482249218c20030a49204a21801002084f2621812002074f2621823002074f2521814003064f252740870003054f252840870003044f242a42870001032b4087000089e7000d4183a4308fa2028e000081e2008c10000c22818001054620828f808f30020028410086030087c00000438800030c403441018e20020b42334288000704403
-- 095:54233413103408182908d00070133443241310241328d000602314631433102328c00010330478c00040c30453101318d500a8a000107310d89000109310188c0098900010a304081f24d8a000102410280a00081a0038800048671028700010e452184a0008600048091038700008e0520036085520303756c1210889a0105b3018aa573040131c04082cd610132c0800b13030131c940851e630131cd400081100087f00703cf46400f4a400f4088d0018400010541308440028500010f43408e960285000509413e400f3a318620080f0a00b3056767641a108c50008bb32182000608b306b6b103c10084380117c
-- 096:003b4b009c002b3b00bc001b2b00dc000b08a03010169c687000083a2008af20984000108c16186518100d7c087000083b2000bc18a200102dac186000103d16084a20503b002d166c00081e52004d08f10008a4d6502c003b6b103d089b8590306b5077964736864354087800082249286f550804810003080465289000086045988000001f28810010ab0028f00008d2c01840b5183c5208ef6918a77238f000105b7008620018adb7100a0c188865184c42282345189b2228b8e3189000001328bd81304b30130a28b091104b30183a6608f64310500a083300288000185871104b5008e000087000004018610018
-- 097:800008960008d100387000103b5008987908c3a3197000084b71005638a252101f6648c394102f56486a33101f66480d7230001f562f08a540085c71004618f486186b86101f56180586182b86102f460897820894d10841000046081052100f0a0855a1187100003608c9b0188e3608b57318a100104b10087891008b086500103f46081460085ca018c00008c700107b101825f7101f6638580068d800007648c80008810028b800d901000086386593002f088100188000b90100082b8100963829a2101fa6388000e9010008800018f00000b6287000a9e00000b638369300c618700010f0301806f198c0f23863
-- 098:0110ab7028e42010f516ff0520ff0520ff0520ff05204c0520002638052018f01018732038fab2b8700000ab18215318442028e0000833d238f09700402882721841c238a42038459218493538a00088593518855838410068d42818f4202881b3104b40089847987420284d82397420104b4048932008ec2028fd2008a0001885c928900008220008800020101f2628310028bc1010161f387e2008e710003628b000281b10003628c0302875f320260f2618f95418f120100f2618e5a018d420201f160428ba7708162008b00008cf1228b4200860f10026385132004608a00208476448362028d3d308362028a320
-- 099:004b18774548362008f9d0c92620580100a82520089b1008a22018800018a2202b010008a320282620282720da0100087bd1280100086bd108652028010028282008010008f52018800049010000f0187c82085c1078662010db9038462008510200a4186620384ca01e500010ab301891c0084a3708c000080aa218ddb820400a30188ea0107b3018478818110000201849201890002010132a18492018d10010201308b43228d100184e4018f90900602899090050282909004008472008e000006b08c9203872c82040161408ab22282c9710304608f8c0089ce118b000302f460430183821083d104030163f4614
-- 100:087dc838c00040203f66143008030018d0002006405f08f8e908423000002811f108fa504026002b407f08ac0418b5a808b92040005b504f0a18052028010008d720208b600f08335200103804f10016086619002208dec12886f108bf2008500238b6f118223010008b08e6e00898f1088100086ff108ef65082a0208c00008f100102324087ab2285200183511307440db1028910018cdf160009b203f46f050088ef12023c4a0185102301f66f8481810022013d468582102302f66f03028120020f02f56089411300b0023d40808f1189b2000bb08bf2100640842f718c00008ac0100030801f328192008e20028
-- 101:9f09084e20281dc018da2008161038015028b01018772028c5b818f20028900018192018d9d828900008451008200208900008d10208350008d20028900018d920087f31108bc028a9b20803f8083aa2602796465627060658be415d100000db08bd30083c0018e13118fee008442138d00008e86708400028d00018845218e0002002006b18a5c80819d0088802088ae0001218b9912851f008f20000320845c32032005b08d4643820f078110018d4f0008b083f3208efd0005b18829408f000006b08e038306872004b08507110001218aa40304b100c100869e518084048310020db600c08ac872023048808c601
-- 102:0852971829420817f808410020106324080a81003b08847418610008a20020ab40280871001000a318f321004b089d4008e8f0001218dc06609b304810db00c30812210851000006586100008b087bc430db00e304187dd0086100081b4108b921089430004808080000f308120008240008b500689100084c471891002013004b08e448001608c2100012082272184b958010bb00a31063003b1b887100103b40080780289100605304102b2b200208840008b100086ad00839c210024a08a10010f3230863c0203b2012283300188100002b08de98081f180881000836002020080228130008edd00874110023080a
-- 103:6308a5e220f3835b0839b3085955587100100a4008a41420f3332008088510121008b6d218745508ce260050181e007012f3202b7b2028120888e028f200200b102a0866f018e3103032d3004b08dc000012085bc02012530418987408981208290070121332630833005b084ae2301048122018c10010cb1008d344200a08400830102023524318d100008b08d100305812001208b6d908728110491d080341401233621318085145006b18bca710680228c100209b104f08c10008cdd250635203180210187b7140106822730408f741801f193f490d50128342086320007b08bd2820107812088100087908101918
-- 104:18910010b328087100002018b40000881894000893e700290834e7b0090f691d307358006b120460184582008818e900082bc408b04480205f090f392a0c10530849e1606b325460092098181f00003b18930020507f09086cc1003318a903000808b4004042235450a818d610002b18a30008ad70504f0e1f230043183582906b1b10426364b8122350086e3430101b801f08294008fb65503b2032b35478081795003318704420102b90286e2908c045506b1032f36418088420001318e0d4100004088b612012133008b92008e40010db8b08d100304334001408a7c70832840034088710301253205308910040ab
-- 105:1032e310086f2118f700500900442012e308ed32a1103243105288436409006412f300eb7b9052d893441900034412e308d444609052f838e3240908c1051012f318f00070f888f3131409003308b20030fbe0f8280800014009001312f3187e8080e0d8f35309031032d3089730a09bd088f3730902032022b308e00020ebd03808e00018793910102208f42118ed60803380f37319321300320849d8180100a0833002f363194203001332083c0028674440e312f33339184925203332235831004042f3034932081010186c5318532430f352d35908b531104320289939080100500362a30f691218eaf9089b7138
-- 106:310030130c725308be74185100080c5018fc2450f31c34620318089874202f5902181255007b18b500100cc408764000141841844821003012b30cd4283100085232283100502b0022830cf4081af0081100081a8108f5a22000426308f4010866a128f000403b0062230c080100000208110008b7a4009b0811000082181ff908f6b50030089a10282bc80082080100083aa20034080c0018ae80007238f10018d55418d3c238b93118f0d808793128a000008b18a000184e91409b1052f4d418bd9140bb1042f4b418bd40080d5a1003e408442a288991002008dcf520b40344081c2128d2ba40131032841318ac31
-- 107:286319201304d008f70018126028007118b68208f00028f92118d5b2e8f000182064083360187791001328c69518781308110018312a2828711812151808c9103310080d6508180038c10018ec8218a400008b089950001308da4008c2a620fb9b7028f36010f516ff1460081000ff1460ff1460ff1460ff1460ff1460ff1460ff1460ff1460ff1460ff1460ff14602a14600026ff146008100088146048f00058046018f000089ba148c260e8e00068736008c00078436008d00098036018460a98c26018eb0ab88260080110d8426008c500b8f1601835f0a8a16018620a6851602841f008d71068e060089ee008dc
-- 108:4108a3216890602880f0187fb998406008f27518830098ef5018b021188200889f5008f6e0186200002b783f500866e048210068ee50084b42283100a8be50485100001bb87e5010201f08dbf408cf50e83e5018c08508af50e8ed5028640000dbf8ad5018840000cbe85d5018b01000bbe82d5008b20000bba8fc5000bb08c919080430b8ac5000cb185c8408cc31d83c5010cb300804000825f8d8eb50084cf908f900d87b501861f408e0a3a85b50180be320db3053c82b501860103000ab2083090b5008de19000f08286000b3d8fa50081af3205b10d318840058da50085710080ea80868da58ea50081d10401b
-- 109:007300c3781b5008cf70108310882b50082a20100f83082300585b50085740109300887b50084940109310789b50084b4010a30088bb5008010008f100c8db5000a308210098db500093081db3d8eb5020a31018f80c50009308d1f1c82c5020931038c84c5020831058e85c503083106800d86c505073106810236208b127b89c5050731058104338087a16a8cc5000431861000002387100880d50002308fb8200530871000044984d50284100104843084100689d5040321038100238510088ed500022086100301243025808d670984e500012083962000448810078ce5008f9b2002208d11000580807f5682f50
-- 110:005b081f721823102058024308cd5018fac850082042330204081090003338110010505248f00000c4185060b03b70422302141048041233a418c060403b402b10222821002014122308bfba186f301883302024103808110038b160102b30089c90089faa08da002024122318ee1508d31000301865a0082d10300210383408f5a0289260001b080a02087e1040130430383018c775089f00000b08cb49283100088c9208dc20389ba028151020ab002208ce5048610018d20018e78a18b20028510018d72538c2001817b90022288460000b2875b800132866b0286100187460585100182400182bb9001208f46018
-- 111:f63008ee2528f9b028310018334208410008b9310014285db0186100000208e560105b300831000020288034403066f6870308d8f1180b2008653028e041788000002008f231088d100003088050289000088400089017187520089d00107b700865e50090085c2008f709101254085162d020533420b3003c348310b3344310080135403cf3f3331008d543403cf3e3025328800020f3123308f31070001012f3f3222332282b303032f3533208361be01b00d2234043403332402b0062403208b000102340084a50000208ef42002208d00008f470003b08aba040124002236008b7671060320812e3103bf0084000
-- 112:088bf1586000204b600b5860000050087d0010f516ff9d003d9d000026ff9d00389d00300300c320489d00400230b32013389d00303b70b330083361408b70427350083829107213086ad8705bbb701b904b603b08495a202b602b08fa79105b6008645940fb8b609b4008ffd0700b40371636b6c102086d0010bbdb08acb208c64010ab7b0812300014084b50005b089777109014081a72b010149c14103b3b102cb42c1008c6f1201cf414080722501b000cf4540c08f4910801a0202b00f4081a2b302b20f41408e442402b2028b43818700000f8084eb8386000301b20f838086e04087000081a88586000104884
-- 113:08e988401b205864788870002068448888700020782498887000208804a8687000100b20185817086000084400b8500018b5d908a2b210f51628c2b2102b30087f3018563200cb8803b218510008cb19180890a843b2002b08b22b08cb55182c5028c10078c3b20809e01890a3003818a188185cf0a854b2001b082600207b005848150098b4b208a100001018478200685835008855b2600b0052204b008838630088b5b2088100084300202b0098386b008836b2200b007208b370009838c40000bb98b6b2000008d6c71010a838d900188ab27827b23000a220c81894001888b24857b240eb00b210d838540088a7
-- 114:b240eb00d210d818a200005b78d7b210db0008869218410008e7b25808b2509b40f20210b838f300184d274868b2103b50083da200b838280018710048b8b2102b40087ba200031828000806b058e8b228510010020318eda208dba35829b2087a82001208ea622817001869b04849b2083b60186100284400180ba25869b208abc000101837005871002879b24851001003a8280a00187fb038c9b2086dc02030f23228d200184e4b88b9b248a1001003a808d80008c8e678c9b2303b00c21048330008bb5778a9b288810018411088a9b2303b00e23008a2b2188b10a8a9b258810028490028c11058f9b218320010
-- 115:30f218230028e110680ab2d88100682ab2089100506210d210038818c40008eac0785ab248a1002002037818481038b10048aab208b100508230b2307820189210789ab2085a7210923008ef9210007818d40008c21068eab2001b1806b228130008d210d8eab208e4b200102863001876b2d80bb2086fa23030923058181500006b881bb2287100084300005818c900001ba86bb230101832500888001072500891a8a86bb20862b258a100187710b8dbb20890b200820842b2101072087f840038086742d80cb208c4200072390200484cb208c00010e25008c2b2005208120008a394e83cb208c8d08802000008d8
-- 116:3cb2189fa208e90000100893200028f82cb2180fa2002228e10020020318d84cb218bfa26072709230123038c81cb20829e238a10008a2100028a82cb208469230f2e25072d81cb2082c2360f2d25072500302981cb21827b708d6b210323088fbb200ab08a49200f208310010034298fbb240abf0c0f29088abb2280100686bb250bb6078c2f0b0784bb2086350306892f0b0783bb218fad54068f2f21810687bb2085f10505378f292280228310038cbb2189020300068f25288dbb2080495300b3068f2a8dbb218e430202278a2a8ebb208b20020726852b8ebb208213020b26802b8dbb208fe2000f2b8cbb20850
-- 117:5000f20802b298ebb208f1e1b8fbb20888c0ffebb2ffebb2ffebb258f000ffebb25a11001febb2587d800026ff3043ff304318100098304368110058204328100018a34158104368110058004328100018e34148868068110068268088210028d58038010068458078f00078e48028310008e16678748048210088148028210000bbb8b38028410008d92478538068210068d280282100189c6078828088310068328028410038aa3348b18088210048218068210068d080282100083e60684080681100c8ff70288100083d50c89f70587100683f70281100b8be7048f410985e70081100005b088b44a8cd70084100
-- 118:18773318cf00d87d7018290018c200b8c100483d70383063287100184e90c81d7069e10008d10008042008887048410028bc70b80d70e8f100980d70288663987300983d70088e10286300284100088200985d7028ed106823000060c8cd7028e100287300086100a81a33281f1068d4000042886e7038a10008510008703010f23298ae7028de10081430208320f2081c33580f70386100303b90f2c2584f7038210008d37010f202788f7018602008531008167078bf70284100006b08c6b0005098df70008308790010f27228310088df70084d20204270c298ef70086200082100b8df7008d690201850b2a8df70
-- 119:0850b020080250082180a8ff7010e230082c21089170c8108000300877a71881000092a8608010b230081a090881002010f292a8b08000c208ad9028710000a2b811806082300362103230481f7058618020a230729851003891802072509208cb30285400c8f18000a208a10008a50378810038328030923018b2088100003258810048828020b230d218e2002014109488d28010a23008534b501052103410e47803800831c018210010f41468338030323008e208ac00305410f434887380202830f208510018f5030044a8c38008904b08cbd0086b00302410f484a804800058181ac03891000094a83480404830
-- 120:03f22208a100002218a10088748000500830d0386100085d3158a4800040083f402092104268510008942008913110f242a8510000fb08210000120824c020420314683100188d630843a01010520831002831411814c41008d2082100307210f4b43806800829b000c238110000245836800868b00092084fc028310048b97008b7b00082c831000875b00052083100009288310008ca000042c83100180c2508310010b210780780087580082100208228f078178020ab205808cc000896ba78210010506808cc280068082615683100086d704030681058300878b428b67828510008ee8130281018309864800858
-- 121:1178840018943508bd41180202582100207b106208ad70886780084e1500000872bbc887802008008839a78008b8ea4cc78018f1a918c7803027f61627fff780fff780181000ff28c3ff28c32e28c300222866800038085cd9003809b8c3a0221c12181c08201c301c603939c320f0b03bf839c3300302f0a01887c3c859c3100203387100a8f8c30022084100e888c3185100e878c33022f0905b1968c3188100e858c3407852f0705b6958c3306852f05008e1005968c340404852f0200898659998c3106b10085200006b99c8c3509b203852d06b99f8c3085e641052b00822003929c300eb08e10010906b8959c3
-- 122:08044010280208db10002008ae040891e1290ac31846400028184200082b0039aac3202b100b08bc00088e40080200f82bc3308b20383208d5a0197bc3087354087c60008b19cbc300db18571419fbc3082a21009be82cc3202b00abff4cc3ff4cc3ff6011ff6011ff6011ff60115809800f601100c0689a2a40661627a132182f4310bb2018bef4101200181d74003208ed740828a810007b18dd74002a181d54188ce9083b54187597386000080205089d5418bd9c08a26408e20008d17a08600008e000087020d8e000101d0ca8c100100c0d18f000002d08734a18a264100d0a08166410100f08fe6528700008d0
-- 123:00083332108bab08a4e158a00008155308b56408459208460668500008064000ab082a75009b28a000009b08e200109b8b084c1208500008194000f098ed00086ef4481e00082474085c5a183f6408c897083f64002218600008300c08a22308e00008f9f908180008bb4308b664100a1018cf6408ac47181e0008e484181d00587e00981e0018d18a18700018c000186d98000808b92200000803da084c23481100188ed8105b8b08c210002008f6aa18900018014300080802b1304b9b000a082d22005b087000085d2a08a61018692a207b9b40084a66106b9b0834fa18e436180c55083032087200001f08a33208
-- 124:5ac1087000083f070010087c0a40005b5b404b187000104b40080c6008f400103b4008c5e540202b3b506b08f427201b4b4008965010302bc8901000131890103870101855a7000888c0100032e84010087dd148401008f20018fe15182c1008aa3a68df0029b010c8d0000869db08211018a200100e0d18411008f100081852208b200a085010182db108a00010300b08fce300301830a508d6b4085f10081e000040181110106b40186965107b5b287f00107b5b0870c0080210104b4018e552107b4b082a40088d52103b30083660082b44005008301020007b0b08bf0008e00008aad10819c6287000089e80c820
-- 125:10002378201018df00483020283010001818d30008310018ae20085010188b63199020580f20b84d2099e000180fb80010180100083d30189ec408e40018ae200875a328700008b2d1d82f20183c751860000807000845b408ed2008a0000825b408b000006b0838600804b408e9f6005b08d84500ab18102608090518e067009bc8ae00003398ce1010bb30d8ae10184a2ad8be1028ce3558ae1008b290687c30189b00788c00289b3018ff30285d00186e2038d02008900008ce10186f0038003008d300000a08e9d2083e0008feeb089e2030101f406b08141508ba10085d200890002000182038010008b00008e1
-- 126:00100f6008c030002f083200081e10100b3058700008356008b2b00040088000083d5a08bd0418450b08700018e00000600885f10028088002004b08427a086bf5005bc8101000438c6f30c8201058f00008bea4382010187f30182010001c188f00282010001c18de30000e08301008751018a000002f08e630000a085f300010085d5b185f3008010018fe3018601018d30008319a28d0100060187ec2086dd0189f00002f08bbb3088f79302f002b3008ae0018358b080f2018cd20204b305b081970000018df1008d3b008ce2000500899d108ce200060187f300050d85f300053ac5f307bc020085a31084d0008
-- 127:ee10281110002f287f3020002f02288f3008810018af30083485000f187e20007b08b782085f10007b08498208df0008700008891b003008b9a0089b1b1870000849fa0030087ee1082880003008ea8408901010307b18fbf02018006b1890003038005b40480100105b50d800400063ff0040a8004008ad0019004018fb5608d100002f181700002f2836f408299608303010309b0832771020ab08ad4000300850000867f4084020400830ab6b40086d10c8ae0000737c0040794f60998e50080f1000ab080410287e50209b100a0875f2081e20087e501833d508de60187e60085de408e000205b9b60088d60009b
-- 128:0832b708810018b2b228700008ec1008b03028c327106b8b280100207b7b4038700008e0002028205b08026008bf300050089f300090382769087f00108112083f3008210110ab2008db00100c06089610208b00140882d90870002004020a085da308cb05089ca308f0001860f35860000004084a20187000002c28820018ed1918800018026908f20018010028900000084811000018380200000808fb4c188000001808302918e10010020d08832018f1000886002811000012480100002228e00008671098c00018d43118003008c79508600099c000308b607bc0680e0008cc80583e00485e0000040863b20828
-- 129:100014082772081810000418d4e318800008a6d308600008ed0018600028701008ab69287000003c18380008ba6a08dd9018800028290058f000087000283e00100c22186c10280100084c4018fa300822fa080c80004b089ee70008086f5408da0108d900300a42204b28700010006b08f940007208b98018c405082a4008dbf908600008497c004b08e4e000a218600008cea008aa40088fa0082ac23008c2003b08cee000e21820527018d2200b3bf0101b982e000013582e0000bb18c73008fae908ac00000f088064288d00284c10084cf008682518e000187530480e00000d184219288e00002c287b100804c9
-- 130:88ad000004389e00001c086b1018800008da3958800038ae00200d0c22088000182b2b080e99081b2008a00020020a22186be508e56008bc100022080720180315006b08ed000062186000080f00006b08ed00008228d6f000922835f008c00028880a18acf00803e208010100c218600018c3e2088b2008c00008ec9010d05b98be000023a8be00000918868568ac1048ae00000428973558bc1008d930283e00b8be0018b74918ce00488000580100001d489b20681b2018e950181a20080100681a20089e000854ad1815700813bc18e000004228d000083a20080f0008c00008ef00005258c00008cf0008c00008
-- 131:cf000062b8c000088010007218600008a110307b5b808b982e00003309dc1008d604f9dc1038da20481e000008481e0008d46028bb0008f60a389000000d189670285730181760084d00186d6918c2800841ca186d10002c08693018fb2010183208741008da2008130a18bd10983630082b2008c000005258eb20189f61184f10084c2018af1008c00038ac20080f00109200082031080d20303b5bc04b984e000043db39300894d098ed0078900018ab10286e00d8fd000012181670088d0008b440081e000879300018080272000a1869300018385930082e009c493000533c4930798c100018797c10485930088c
-- 132:1028e920189c101859202d19300063ff1930cd193000732c19306ad55038783028d55028f8303850f0084360089550086d00100a324c093000902849d4183e002001c000087931002e081020f0101e0c104b1b101c0e3c102b0b00ac000830d4309c3000ac08e380208c200c083611500d8c301b107c0894e2100f0d0859da200f0c0008e293a00d100d103b2b301b203ba03804d41835001893b4000018c6c450f313048402940830009074228474224402247432087b18e10214644204520454b21444b22444a2343492542492643462844402340084740827793074340314086c0e08b42010343408bfe208b04030
-- 133:1334349308dd18d034a3003434b3002434c3001434c3087810082cb42084227418d6000070082bb418d70010a0d00886e4004b08f93008e64308b3e4004c083bb2083b2d000b08ed8008b00008a00050008c0b003c0618332108987508318e10063c085e1108b46b100b2b08bc00001b48584678a19010db20081b48102c00185e4b08ee31004b0871b1100a1008600008ee60081a96003b08f000000318f000100f0a1884530853b230030e104b08187508ea86587000082b11089b9c18f10008dba0001e18800008ebc0002e388000083cab28a1000812a5002e08938028a00008779608423718310008d276482100
-- 134:1879c82821000013481100086fd638110008e0c028110038800038010008c948005e18020018217638800078010008d510085f40100f5e185d71880100004e088338087c91386754182bf10090380df618de21104200087941000b080c47084ba508300030509b9b6008bca538a0c01008301890c000301812b00851d228f92108a8b00818f008de172800b50834b039d00008c91798b100085cc018e000187cb0184ed0082b2108e00008fcf718c10018700008b0c808142718fbf4089000004f28700008191718dd30002078e00068c1000012085328907b8b708bab508bab409b183b0010509b0887e20821000090
-- 135:3800a5188f2010610008238108dd7118501d28ce500860002805f8182f50386000003218ced4000c08959a08d000082eb0000c18143008d760486000088c63387000101f0d089a9518f00000190811c5180100002928e000002918730008e5d5000918ace208a88108600018972108a1c308500030404b4b501830000090384f73081900100303696f7318034828bd4618686108ed1308c573087ba5085020082a7318d186187c730012183000089f2208f00010eb30083340080d0a0810f010000208b1c3088e11007818f9104801000843d0000c08b9c310431428f400087bb418101b0890c3086733004b08b1fd18
-- </MAP>

-- <MAP1>
-- 000:00bb7b100000cb082000981000207777774ba400ba1000c8870000b70887002e970010cb2ba8870018770010777b5bd4008a100010cb8b2f870030bccc2ccc88f0002876100e961000bc188700881f008e8700008c7a870000be685000db1000d80f00b90e108c870030b22222220f870040ccc882888c989520a9fd1010eeeb585000cb100040bcccc22222a8961030777077073e870000283f87001088884a870010bddd8c870008752010282898952079870020dddddb4a870010bccca8323009100018fd10181e1068110000dd28852000dd09b20050bdddddddeeee08fc20185000b9100030baaaaaaba9120028
-- 001:76100028081d2068f90069870000cc281000f8870010111bf8c20039870000ef08100000ff28500010fffc580f0010cfff48100018f00020282888f8630008ee00181f00d8870020b111114a870000bf5836000810002887000028081d2008870020f0fff00810001877001022887a8700101111f81f0038b110d8610048ce0028500010fcf218761020828888680f0008f000108f887a8700282600d8442000aa281000c8510098fe0000ff287610080d20108ccc080f00281f0008010000ff08d80019870010dfff08870030ebbbeeee881d2008fe00f81f0039870058ce000840000876100032281d10781e104022
-- 002:222fffff390e10f8870010b8887a870098fe0090fccccd882d888d888d8c08870008de0008400008761010fff8090f0008643018870000ddf9870008db30381000a8f71008fe00781f0020fcccd228100020d8dcdc980f0000f8580f0000b868080018db30288700084b40b8870010fff1c8870008dc20381000a83d2098fe00b0fffcfd222d222d282d228d82280f00081f00188700680e1078870018270038870000db098700403b3b3b3888085000103b3b59870000bf98ec2060efcccdd83dd88d18200000dc089520380d200082888610b8870038100000de088700581d20488700181f0078b200298700b8fe00
-- 003:80cccdd22dd22dd82dd208870000fc381f00480f0000fbb887001876105810000987000011680f00103b3b58ed10b83c3088dd1078fd1010d2d8081e1000fc580e10280b40588700002808cc3010888bd8870000ec48532010b828488700001b783a0058ee00a83d2010beff08d15038100018625030cdc8dd880820005028dd82ddccfc08dd1020e0f0f008444018c60000ff488700008208010008870088770018961008d15028c42010b822280d20181f000038483a00003ba8870058e80098dd10e0efefecf232d232d222d222d828d828180f0008c80008fe00002f080f0000f0281f0000b808a0001810005987
-- 004:000028080f0038100008260018100010808bb80f0048870030befffeee48fe0018900020ccd32338670080d282d288dcc0f0feee680b4010ff0f380f005088dddd8880805987000088380c30180f00103228381000103b3c980e1048870030efeffeee48ce00a0eeeeefcfccd838d882d8882820000028082d2018c800108888080b40208888f0281f0008ae1010dffd08d400008b081d1068100028fd10381e100022680f000013683a0009870020befefe08f600380f00288700a80f0040ccf0eeeee0580c3010ef0f181f0008a31010dffd08d400c8870000e1485a4008c600588700001b08e90010d44d181e1000
-- 005:33881000489920387e00381f0028870008ed10680e10080f00185900480b40082620081f0008d40008870008d40018c330781000688700780e10301328228228870010833ab80e1018992000fe180f00381e1018900040cff8d888d208261048a61000fc18410020f0882828834030ee0f0f0b0885001022822887001088eda88430588700089c60585010003b680f00b88700189920508fffefeee444381f0008900010eccc18ee00680f0020d8ccce08d100580f0008262000f01863000028085b10d8870068eb1008f10058c00018fc20088700608080803addddda383000280f00608dddd8fefffefe18b500280f
-- 006:0040e444cccc33980e1020d8cccc588700080e10080f00100f0b28b13008d130108080a8870058c51000b2480200181000003208382010dddd08980060883ad484dad9ff1830000887004022282dffdf387e0000ee28fb3028870048ec2048c61038870028e780380f0008462048d1304088edd9ffdd383000988700202ccccc58c000783a00a887002088888d08de00081f00d90f0058069010eeff081f000008780f0019870000bb88870028e900281000503ad383dadfff18300010aaaa086f10002d587e00084b20188d2030e444cee3b80e101088fc388610280a5000ee28626068c33000ed08407038300010dd
-- 007:dd78253008b20020d1dddd1830000018083620283550b8870020b82882280f00980d2040eccc3888d318261058c6102088ccce180d20381a5010ee0f181f00298700583e00701111255555d1d9ff183000001808bf004810009887000038080f00a8977028d8600033c80f00284690480f00385e9000f218e000181000d98700001188870020ccccca38300010aaaa08ff00008e18ec20082e1088d7700032b80e102088ccc008c600480e1008ee00181f0058974030edcccccd383000a8870008261010dfff1830000011581a005022223a00000a38300010aaaa08c40010efef98cd503a100020f0f0f35887002000
-- 008:000d38300020dddd8c68bd00002508ae0048870008bf004810008872500032281f10fa87003023ddddd3383000986250c9870088834000a8287d5078b010381000080900181000381d102870300082389100485b3070282823d484d3d9ff18300098834078d2405025dfffc1cccc18300018371000d5383000980c3028870048214069500008100048500028113008500088870010d484680c300081780e1040dfff010000183000001108bf0000d538300098870040000000eeeed80f004810003024444444b82100780f0010d38308a30010d3df89870068bf0078870088843040044440dddd183500002d38a50048
-- 009:700058770038970048d600002d1820402082828d08400008870008a30028870010d383688430008138b2400830002025cccc48a00018380000d5383000e8870018a31010dfd828351010dfd8682610604444999994444878171008c10058320049870010d484183b3008600020250000187000180c30898700184d0010dfd2285e0048700028fe00409900000994181f00480f0010dfd8280f0010dfd2080f0010cccc08a30030c3ccccc339870008530009870088834018870000d418061010fdfd287610387000181000304449000408970010444258110008c10028e6101870002023000008a30030030000039883
-- 010:402081d38318b33008600018834038d000001108371000c538300098834008e12010ddd408441008e400184410008d085500388510508444900094990840000044583d2028320008fb6018700008780008a30018e80098834088870008ae005887002000000538300098069040ed00ffddd318061010fdff1826104870001876100049085610109999081f00580f0008c10000d82875900870001883400000e88340298700789a209807806987000876100099088700009018961048fd1008c10018fd10187000180c300000e88340008138b24008300039834038db30280c3028870008441020fffdff082610008d18
-- 011:700048ec2010900908ec20081f0010944838ec20983200288340488700888f70008138b24008300098834010d484580c30a887000841200843200099289e00487000280f0008870008fb3020490094480f0028c10008eb30287000088430188700188430888700a8825068b0007887003854302884302871207987000049080f00481d2018c100080e1038700088870088087039834010d38358843088870000ee08725020ee8828186c0010d88838dc0038624078870008a340180340a8320049870038be7008300048834008300049870010ed00080300590f00380e10290f000823401000cc288340298700080300
-- 012:09870088834018852000d9298700080d20081000780d20b80e10082340383000a88340383770083000488340083000498340288700086a20186c00008238700038fb20180c30088700080c3048944038c10048700018a900287340b88340788700380c3028870069834000df190f000024080b4008fe00080b40480a50b80f00398340198700798340188700086930188700387000589610081000780a5018c100180e10287000002308ab30088520086c308b834000df086a20086300089c20002d08700000d8681a5038096058478048320018700010d88888870008ab3008bf7008300059834038db30086c301983
-- 013:40f80f00002238087078f860a80f0008243008870008e43098870039834078870009834020f3f3f3188700387000582e10a8078028c100080e10287000888700082430083870083000b9078008e430e88340089c20203f3d3f089c20387000580680189700780e90a83200498700385f70290780c88700588340090f00781000090f00a88340f88700085300098700098340086c0018870038700029100018c100180e1028700079834038e330e90780288700089c20086c00089c2018dc00380e90f824b0283200080d202832001898003983404887001a0780180c30da0f0008b3000000281400d88340e887007824
-- 014:00988511588700da0e10688700698340888100191000188520689c20187000488070e85000383200487d2058a3008910006883407889d0a80f00388340089200180f00387000390f0018c100080f00287000390f00a88340000008ff01000008801180255500005555500005088700400000aaaaa01875201883400809a0402d222000020a6000000808cac0186000080e10087300303330000308870008a0b010ddd01875200802d0400000111110185e0000cc18be0008420008b2d0005008352008c7003000553aa018bc2008a00008870000ee087000300e288d8208700008e391086000008228600020888d2818
-- 015:6000002d18c000002848210088e1002088233018870018400010edd018bc201878b0088700001058e600085c2010000008e00018380018b00008c70010000508843010000008c700388430280f00002008600000020a60000008386000180c3010000018c700000328140008c70028843068e600186db01a870018600000001a6000008d286000180780a987003a0f00008838e400986000986600f86000e90f0008d600500303130303030887000008081000005308b00010053a18a00000a80840002887000880000b0f000884001000330850001003ed18500000d308400018870018c00028e60008d60080303010
-- 016:303030311125085d3110805008b00010353a18a00000a0084000008a1887000880008a87003860001028230884000000084000203033ed18600000d0084000003d08870018c00028e60008d6000a0f0000827a261038600000889c0f0000020a600000083860004c0f001a87003827000002280f0000021a0e1080f3ffff4ffff3ee4ee308800090f3eeee4eeee3fff3ff3f0830003820002000fbff08700000bf08c4f180bffbeee0ff0eebfffb08c00008110000be081051083100000f08020010bff0085100183200d00ffbeeeebfff0ffffbeeebffff0018b20018e10008b20000bf08a00018500008d00000bf28
-- 017:610010fbff2819100f1000080e0008fe00186000004e28600008c00010ee3f186000003f189e00081c0008bb00085a00483000080100086af118900000ff087c0008b10008800038b10018900008210008e30038e10038010018d00028820018c00048d10038c200fbab003b100008862000dd08ae0010eee30880001865c000e318a180003e380100087000285a0000eb08c000189dc100db18ec6008900018800058010028410008dc0028520018b5e118111000ee18e100482e0018400068020048710008700008f41000ff18060008361008152038400018110048f5102841104843102834001844004813101867
-- 018:1038410098920028630018e200189200c8d3004855009f8610383bd0182f0038500018061038d31068e31038a00048b0002894e158171048920028a00018320068310028e00028130038030058d10078e100689510282c20488610185d2038010028a31028b310a8b000588c1028661078a00028900068c200686710d8a00018f300fb23103b100038bda0186d205852f028c00048d000288010287c00487610282310484310a8d000782710b8c00028c30048030098600038b30078361018e24078d00038493238870028b000282610381c2058a71098681038660038b20088c30048030098600000bb99100030b777
-- 019:5555a91200082200007558320088b000db1000ff87007922001d87000077088700005ba92200ff8700be8700007718d60038320088b000db10004f870000b7188700b9b310ff8700ae870008220008d60028320088b000db1000ff87008922000d87000077288700993b10ff87009b870010efff182000781000f9870008220018d60018320088b000ca100000bf88370010fff00820006e8700b81f0000f738870099b31048d600005f08630068b000a8100030f0f0f0fbd9870000feb82300aa870028591068870018d210382000000f081000c97700d8fe000a870008c42028d6003055efffe758b000e80f0000f0
-- 020:c98700d8fe0070f0ff322322222288893300688700385a00788700681f00180f00000bb9870048fe00881f00503332322228282a870000efb88700a80f00b91f0010beffe81f00403888828888990f0010bddd38100030dffffffd78b000d80e10b91f00f8fe00f90f0000bf08220018320018830058b000090f00992d2009fe00f90e1070ff3233222228228818130088b000c80e10a92d2000bf58fe00881f00187610002889870010bfef28a81010288818630038a000488700b80f00991f0008fe00e81f00380f0079e91010fffe085e00002d780f0058b000d80e10891e1019fe00480e1069f820084300082200
-- 021:10dfd2680e1028b000190f00792d2019fe0000ff38a31069ea0070bffeff88838dfffd38d51010828808b0000082390e10693400003b78fe00e80c3069e910285e00403dfffd282818630048b000390f00591f0008bb00690e1059f820184300103233080b3000d2480e1068b000e80e10493400003b39fe0030ff88883808834059f82018c200087610083340008818830008761028b000390f00594310085f3020323223081000082e0038100020282828380f0069943018a240003d08c50010d28818830048b00058c300081000008228100008ab00493400003b081000003318100028d70018100048b700380e10
-- 022:691b4018330018d60010d82818430048b000688b0058e70028100059340000b318351028fb2078500008100028a000690f0018230018d51000d808820020838888288700008818230008600010888d18c30018f000008d490f0018ee00bc0f00102dfd08500040dfd222282d080e202028dfd869340020b3b3b308930000d2180e1000d318070000d218500008f2004b0e1058f60020828dfd080e1000df18ef00f8d30038fe00303b88388d080040785000002828a000b91a5068d51028f810003838371008a00000df08f70028444000df08010028854058340020555151889f9008fe00080f00103dfd080f002832
-- 023:104850006b0f0008f60010282d0844400082081800008288870070b555551511515151980f000033086f3000d308265010ffd228500018d30000d24b0e10002d087c3008f30010ffd21890000028089000082b1048770008fe00781b9018fe0008c920186a00d85000089410088d2059870008e10048d51028820038b0003088882d9f08700000d9087e00108d9f080010189000283400087700080f000015085000005118970058ec2008ea0000fd18b210385000385b00480f00003b48860018a3001a0f0008f600002208f60018900010d8280890003833103055556565085610281f00184e1018fe00303b3b323d
-- 024:08e200002328330058500008f400a80e103843008801c0280e10083590580e1028b00028870038f600180f000082580f0000b128170020151511180f0008fb0048fe0018511008d720b8500038761010883b281f00288300a89700681f20081000003818d20018ec5008a0304887007817100088080f0008a3000065080e10380f0018540020b3b44408b700480f00109444780f0010d444780f0020b444b15843002015b444780f00103444285590280f0008c00008b000380f00102444780f0010f44408340008f300680f0018f520080f00103444289a10009f080d20003d088700282800388700580e10003b0887
-- 025:00284700006518530000546887003033333444283200280e1008c00008b000380e1018870058171010f444080e1048d21048db003051515bb3380f00008218e11040838d9444d828a00018500000d4088a00282140280f0008982008330000510820000014588700405838888444783d5008c000283d501804000084480f00188610280f003847003051551111082c30087f00001b0847000003180f002035515f080f00109f0f780f0010d202680f00303bbb015138de0018f300000b489d2000550873000002780f00103202480f0008bb3010220f38413000d8080c3030fd082828285430189700280f0018700008
-- 026:ec20000b08a520003208a4400052080d20000f880d200008880d200005188910a0115511151111150515151508a21050bb5152323203780e10103302480e1018f6000887000028081d3000d2084b4040fd088888b118921008dd1008e300281000101115084700180f00008118880008bf30000f18b55028065020ffd208480b20080f0010b101487a0000110820000001386b0050bb5155838808283200603565656588380838171008b30010d88208870018440000d808084018870048fe00286610386f0008ca40000b0894300035080f002055552d088700388210185b00880f0000b5280f00281b002011110108
-- 027:fa0018c300101555280f00002118b10020555552990f0028b60028e300181310880f00284320083900180e10488700980e100051480f0018a300380f00183f00105153180e104839300055890e10002558dc2008e210183000280e10003b080f00003108f400085c0008cc0010188818f20010515d180f003801e0180f00284d1038ee00101111280e1018180050151188088881284660081000105802388d2028f510588610380f00108151181210380e103844000015087be00007084000581000adc000380a00184e10086e00a071370b733711711755711708600000011860000057083000011575170175272272
-- 028:278878b7bb7b57017518e10038300008420008e10070117557517157037118600000150881005075170272272218810050f7ff78270f7f18210008b100305f7ff70818030020575575182d2058531040155175570318870008f300182700000108900008150028450040057157887808870020373b7b18c00038570008720018420028c900305575570518150048c300300878278128810030ff78870f28420008b100005518870038c000381c3028770008700008c6000073181500184b00580f0028fc00080f000017590f0018900028c90008480008d50028f0002017057248120030517827052824000051286000
-- 029:38c00010557188fe00280e106e1000780f00101155fbe4007a100018bb30480f000011fbe4007a100038ea40183b30584f3079100020ddeeeee942001a520018320058ce0038100028671000d128100020d5d1d128010018072008c2003051513888080300903b3b7b3b71517111711108320000d758100008210020517155288100005108520018f100482000007758320048550008243028320048b95028f50008480068662078e62038bf1008f00010222208030030b3bb7bbb2815000017d893102071157528b600788700f8320000110867002055751508320058bc2028500000ee28100000de68100038010078
-- 030:100008030020eeee7e182000082841084c0068920038750028a100185200583200184100583200386f0000de583200aa1000688700182500c8c100187600007e888700c93200a810003879f000df681000c80bf000ff08030020ffff7f186e510077a8820038b20018694108e100085200683200d8620010d7d7583200a8850018d3b03868e010333418100010334338700028100008b10008030020bbbb7b081051007b983bb078100008d600107bbb0852000a3200a8510050b2b22b2b2bd228100000d318100028e8e058f60108b100086a0020bbbb5b0802902883b000dba81000182100087f20105bbb08520068
-- 031:3200f87200583200a887000000c9100008030040f00005000508d300005009f100187100000518520000f5f9320000f0986100e80a00c85210c88a00f81f00095200196200d83200d88420d8100028e020005f18200000f5288740688b8138784028a1001852000a3200a810004000001010d0981000589010600110101008888e080300302bb5bbb518b61018231000d5a8100020d01510188100000e085200281200283200b8620070d0d5d1050115101e1832003810000010285000c87510e81000d802105b5200d83200b8ca50e81000188a00c932002a5200183200289e0058e410d98460080300d932002a5200
-- 032:183200184d10001008e7003010001011c9f11018ab81d83e201b5200e83200181701891000005d08030000d5d9cc000a5200283200105101081000488610900050150052050050050108dd30483000401501510500283000808858850050b5bb5b1518f0007812002830002051151008c3000050087bb008600018d20010015848b10020105085382400001028600038c00020115011787700100001b9f1107d10004050250b5225084a00001188fe00582f00008559fe0028e10018fe0010025018600018b21050510508588588388210005008630028fe0018e1003803000861100010880f000001089e3000508878
-- 033:10adc00028fd10089700084000100105fb23103b100040102b2b2202083f6020101111183000901000e8282e0000e8888e08500000080885e0308880808008f07010100008df3028d73028f73010101008d00008110010122208540108900028100010280818e200008828b300308800000e18900070e080e0000e00808128120028eb3028300070101001b2b2bb0b2b08e3f0000108dc30001128330058500020e000281888e0284b6010b10118970078f91018eb5040100111282808d7e0008018b1008011111822088880880028870010e08008870010800e18cb00188700381340001128e3002896100001388070
-- 034:0f100020b2b20b08a610002808ee003018828ef0189e0048500098ee0000bb28ee0010001148da00000108ee00301bbb101838ee0010880018eb81002899ee0000b008791038d21028e30008f210086e8018ed106022211010e2282e08370028500028d70088ed1000bb0848101815d0282020100bb108a00008c80008d5b018ed1008320018ab81002289ed10008018230028ed10185120289000002bcbf2106b100030b2b2b233288c8190ef000e2282ef333e828208a00010888808500008810008a61030080802b208414108201148beb010013348916100b228bf8118320000021892a108c00018e20028b30020
-- 035:883330086f0008900060080ef00033380828421028d30010010138700008f30010b33308b41028061030828ef333782e1010e333782e1020b333b038521008430010b333484b00089810102333782e1008c000382e1008d120108333182e1018ea1030ef00033308340008f300381700381930d980707d100008961008d52048fe00a81d200080881d20081000381b00001b78a30018cd21002e0837c000e838fe0038b00038fe00008008361058fe00181d2020bbbbb048761008fe0008840010bbbb0836100863400022084a40000e189a4038500018c820100e88580d20487600487c20787700387300180a00180d
-- 036:2038b00028770028ad1078080010808008e200180ee058aa1008cb009f0d2018100008fa0008fc20308e000e82185000186830200e888238fc2059cae118fc201022e008911048fc2028b00008fc2008800000e828031018900008561008510028340028761058ba1008323028c61090228282e0e2882828e0e8083d1048500010080218c38110800079970008f60018e600008008f3400867d138b000284b000008089a4010e800089000008008a340088100383400189c20089430c98332bd10000000a9100000e0b9f1004bb30020015150c9d30000edc902003bb30020011110c9d3001d0f00505022515151029a
-- 037:b4003c1000401022111111c987001d0f0050512151115152b9d3001d0e10101121080f000012b9d3002d0f00005108870000519ab4003c1000086700081000b94200ed0f0020022222194200095a10100220591500c8b300291500081000c80f0018a0000002d8c200c85b0018ef20000118c64059450058820008c90000e028150009d100780f000022183c00184440c98440102221085000100515189e402833007982000847002859400011098200680f00088c30187200088c00e88350c80f00180200005108ba00100555694700281000000108420000e118870019985008ea40001118540018470058f900180f
-- 038:00982a00c80e101802000015280f00080500892f0018150000ed28d200091410780e1018f90028b400187800100112881500880f00083d106842001005550890000052399700002248420000e158d200d89820080f00181a50187e00280f00001128400008500029c44000025841100015084c001883001025154982002815000010187d0008c02018d110c84150380f00002118681008b90008b400080d00180f00983d30680f001002212841102842004050005555550811000051096d20087100287e000050080f0018d200089020100555b88200380f0098f900480f00884200680e10102515783c006050225555
-- 039:51525519cb1008100058411040ed1115000518033008aa00a8a610380f0018f600480f00183c000050285710681000780e1018cd1048411018870010555218c200191000584200080f00200221550890200055c8df20480f0010110208026050102215151112085800185d00081b00f833201005151883700015087d1010155108f4002051515518cb10f81000184310084110001508820010151208033018ea00b82200580f00187e00084170105151083c0028720018ca20484200780f00183c0038420020555525080f0018b700e8094008f000484020105121080f000052086200180f00b89110580f0010121158
-- 040:f900084000480f000011481f00480e1008e000784200085c0028670028ca20b891100025188110284110201525ed480f0008ea00b8de30082400089310387e00280f0018100048720058cb10480f002055000578411028de0028a70008d110c8bc002840202815000051080f0028b20008d110085200888200580f0008d90088100018ca00d84c300002183720581200185300185700086000086120b8820008f210488310381000080f0018ea00889b10280f00587400981000185d0078bf20380f0020255502086b0038020058ee0018100018d11098961008cb30484020b80f0008f210005578820038840038c700
-- 041:e80f0048a960380e1038b400081c20483c0068100008d200985c30083d30088130481000080e10685d00389550588700580f0038da1078cc00289c30389110280f00000208ea30583200a80f0018cc00881410000248f210381000580f00181000088700788200389400f8a61020515112182720780500187130680f00e8d200888200082200088700388200a8c110187a10780f00181f000011a80c0048100078c840280f0038fa30190f00181000789b10002548f100680f0078150098820018220028520068b2005810000052184e10281000580e10780f00781f0048341088100008cb30489200085230080e1078
-- 042:150018c700780f00290c0048cd00880f00182a0078c900c8a200981c3058e10028ac0000e188a200188700582a000005d8a60078820018f500005078db60a80e10686b1009870019ff1078d200688700582100102525482c10a88c00288700280f00482a00c8161028100008b30058f4800005288e5078b10000e5d82500390f00a8100018e50018c3a0280e1018b040281000b87a2058c20078870008ec3088ed3000ed78730038e20078870028c560381000f8c700084e50380f0018e67068e800b80f0018a300580910000528c540781000580f006861000a0f0028030058820078b040290f00588a200005187950
-- 043:883d10686a00582c60b88700f80f0058c000480f00000598c100b80f0038b300498c00680e10ca0f00288200080e100005980e30284d200011881140082230580500c88e00180e10387b60086010f88700480f00785d0068c000580f00a8d8008a0f00004478c00028b0009a0f00688200e8ea10f88200d88d1000c478930028b000d90e10980500e80f00b810008a0f0078820029d600881000580e1038e000b8cc00d88200b8870028120000ed190500b90f00788b10c90f0028a200590f0000dc78c00000dc988200691610481000b80500c8fe00885f00590320988700f8820019e700b88a20c9f810c88c0078d4
-- 044:0008d60000cc2810001025258b0f0058ff30489e00886e10890f003887005b0f00a9e900090f0048e2001887000022081000cb0f00881000b86d2058820018cb40483e70688700281000205252dc988d4038820059ee00380a00086aa0380a0039b900a80d20780f0038f20000dc08370018fe00081e103c0f00c84c30788c0048100048810020dcdddd380f0000dd180f000052b88200e80f00784b00a80f00390a00e88020981f0008870048100000222b0f00782c00481000c83b40e80f0048f2007887002025dc22086100e80f00f83c00198c0009a90019820010222268e200780f002851000b0f00b81f00880f
-- 045:00e88b10005208a70058e200780f00081000c80f0008820048c700486000690f00f82a00298200480f0028e2005025ffffefefee184c30186100b88200c8cb10881000b8091098100098fe00788c00184c10288b1078e2004000fffffeee480900390f00f88e00581000e88930c8fe00b88c0038bd00585500890f00c85e0008ffb0100666381000790f00781000bb0f0098ce0010066608ae3000c688a700b88930a88890a90f001810005a0f000050387700a89700480a00491f00185d00888c0038ad0068f200880f000025990f0020000066a887000060f80f00489a00a85300488c00488d00881000280f005860
-- 046:102862000010980f00689640180f00888610380f00280c001a0f00387d00881000380f00587f10588200285300d80f00686520680e100015c80f00e81000a80f00b8b100580f00282f00e80f00781a002000fef0a80d2018f000480f00081f00a86f0078d000680f00185d0048d200580500580f0018fd00990f0008f90000ee48020040000eeeefef0805a00015c84c00f90f00786f00f80f00980d2078f5202000fefe08a20018d70018600010effe280f00a84c0098f110e80d20480f00088f00e90f00389920383630083900183700781000280f000005e86b10982d00980f00088100a8e400880f0028d500f80f
-- 047:00683400290f00d86b1038ca00090f00a80200187300790d20383bf0680f00000fc80f000882000015e87a2058ec00f80f00980200181000a90f00881a0010500ec80f0058820098ad100055186400887670790f000025290f00388300a81a00102000b80f0008fd100010e80f0068eb10387b008b0f006823002052000ea80f00688200081e10680f00480150790f00783a00580f00a80fa038830078d900381f00980f0010e000b8e100ea1000880960d8100018ad81184b01585d91000f880f00088861689100a8100018030018a1000010f89100481300388000280f0029e300689e214890000050881f0000e048
-- 048:3c4108c100587200a86f61289cd138210028700048d10008700068750058710008240068c60038700018ab0028c90028aa11086761302222233208100000331857101890a198e10068ce00a87010381291b8a01098a20088e20078e40048080018500008ee105050202222323328100040323222202018610048bb00088000c8ee0019100048e2006880100850a0a8c21068640018090000552848001801002050022008fe002877005033222022005508ca21282b00081000086200286f0048868148cb31482110389c00682c4138ee00188500681b9148e3001839000860000015b86741380f000043181000280f00
-- 049:083100d81d003828f048a000d8020069e00078ecd058600058fb002895310050088d0270223334334334333208a0000000286100487d00686610587841484400484e00005128ed0018e00048211038ae2128da91284800001518c000587610986651084000080f00086610404344444343081e10080e1019776168b00028529048d000380400183681b88801184100689300683400280200283a00181e81101555d80f0018e40008ad1028891018c00038e30018e220682800683c00388100981a91784510287300880e00a8100008f000f80e10899bd04850d0788c0010ccc569b200886000581000589210180b00e8
-- 050:0d2038a10058e420d81000784510181000205ccccc880910689720a8030058cf00384800280260181000d80c30685a0048720038c20018f20008200058f00058650020c0cc0c281f0018e10038b10048a30038130078a200183100c8cb00c80b4058d100105dd508fce0b8cb00488b0078f10000510897b000c1196110286a6168460078b400581170181a000000181f00082f0008a70008fe0058c27010255d58f3f068ab0058fb0078f10018632100c5584100482200285200586170385e0038c200005538551068100010300218cf6010232308500020200200c8d1009c100028f0d00000381f1138c00008100000
-- 051:0c88010078910019510010ccc0187100100ccc48330010c00038620029140058840048c20010c4c478750008c00000c008e300000c089300186100186000604cc4c44c4cc4c018d20000c448100020cc000418530028c00028870058b100185b0028800068210008310048010058c60010c4c008f50010ccc408b500284400083300784800200cc40c18250008450058b600a88700086d0018530038150028eb0028710010000418870008390098870000c0e8870008b60008570090004c4444444c4c440c4008230008c000304c4004cc087000100c4c08a00008940008d100281000004008790018a20058d000000c
-- 052:08a20028c000004c08850008f3002810000004083300000028510008100038e100185400280100004408620048510010400c08900018bb0008c00008790000c008aa0038a00008700028ba0018bb0078b600000058c000204440c0286d0000c428460028a00018b1002813003887000811000004083100004018410018870058921028240010004018330018820008615008021010440418900008940008700038510008230018700028100008870068c000185800280800000418c00018a00008800018d200000008f00018120038b100084300084100000328e40038100008e6604861000040486300188700000028
-- 053:4300004328f50028d00048ed0008a30018480028b400283800688700100003281b00182400282100100003087510288700187000185710386800004428f200285c000044488700600004343433333408f300103430880b3020343403185000181000003018a000003018f53018a200081000000018d00028a1002000343318510008b0000033082100004408ff3008700028f30010000428d00018250008d10008280028b40028e0002884000040000008100000702810000077c8100010171708b100108017d91000c8630038c400e810007876008811000007281000f8e70018c1000870000071091000d85a006827
-- 054:00007738d400d8100078760088110009fe0028bc000080081000e90f00d83f00ca0f0019d61018c10019de00494f00482500ba0f00f8ee007a0f00b82f00aa0f0019c610d90f00f83f00791f00290f001910001080808a3000fc10000008891000fbe500d81000189d10aa1000fb3700a81000084d00b93000ac1000eaee005b2f00e8cc2048ea20488c10000759e3300011197d2038d40019cb20e84100886300a8850048ea201081112910000000084000185200296c30e8ca3058fd00d81d3009fe00007718de0010180818c160b82700486900185000107171282e300853001078884910000087587510890f00a8
-- 055:64100011188b10001008a30019ee00903838003838311188880008a50018f20000185987000080990f0009ee00101717181b2008d25029961038bc000017287000008118f2008b0f00b8ee00180f0008ce00188500290f00081000303111282828f700280f0000bb68100010b88b78c000008868be20090f00e8fe002848000008088610101110185000f90f00107178598700180f00390a50f8fe0038c50050808808801118086000f877000018380f00101828181f005a0f0000ff181000980f00e8fe0038e700188520490f00486420487000a90f00188700380f00288700e80f00e8fe0028c410286000108151b8
-- 056:1000580f000038180f00082f00290f0020bddddd68870038fd00380f0020eeeee0480f00d8fe00483800001118534050111108808801e80f00101383980f00087c30f80f0030dddddddb190f0020eeeee7980f00f8fe00480f000058086000c80f0020515158980f00002818a440d80f0008fe00281f00880f0010707018ed10190f0088fe0018852008943038bc10090f00081000780f00081f00d80f00187700181f0018870068078028ed1018fe00090f0078d50008fc2018ae00189610c90f0008c350d80f0098870068f94028ec2018fe00b80f0088cc2018870008734018ae0048a340001528100048390018fe
-- 057:00282f00480f001017112b0f00085100201717100861501852c008642008b000480e1018cd00091e1038fe00003838fe00180f0008f8100b0f0008cf304077777fffff08fe0028704020132323280f0008834008250008961038de00581000680f00008248385009852088870048fd00090f0028b300201fefef0803101867503011123232880f00089d00b90f000021090f00980d200a0f0008275020871711380f003884301015150870000085b81f000015580f000082282f00190f00880c300a0f00189660580f00189c20000828dd0020083031390d20481f00190f00880b4078f670190f000071180f00407717
-- 058:88838708f930680f0018dd00186a30c80f00101833580f00181f000081b98160aa0f00085d00082500289d1018dd000055681000381f00003328fe000051790d20888700990f00085b00080f0020ffff17187c000081080f0008a61018834028ed0008900098b160183100103838182f000011381f0018379079870058fd00f80f0028fb700027080f0010efef28948050311232333333080f00489c200831000035781f00283f00080200088200380f0018fd103a0f00281000a90f000032180f00488d100051183100a875201055151890703083811112181f0018ec40898d90880f00281000b80f000028a80f0008
-- 059:fc0020335130089c20185600105550089000980f00082f000053181f0020315158880f0059870088f3a0690f0000fe480f0008fe00580f0008a7000053084100c894300055180a00089b40180f00187700480e1010bfffa90e10b80f0038e990f81000282b2028fd00d81e100810002821100051281e10080880580e1020fffffbe88700790f00498700188340001128ed003080830385b8843040515118383518aa50001228fd1048870018222008970088870020bf88872b0f0038c6003058383333c80f00081800485c400021680f0000bf28ac80288700187f00281010f80f0028100048087068a770786f702889
-- 060:50387d10105553a8a340483f000055880970388700287700081f0020b88bbf28071018a800f80f00281000280f00d8a68048a410086c2048e6003053303303e80f006827101816a018870038fe00081f0010b88f287f00289710f90f0028be8088fe00080f00287c2018360009a340c81f0010188858770010ffff288700189700083100f90f00d8fe0028567048860008db20d81d20c81f0010188868770010fff8288700089700085000f90f00d8fe000015086c20008038fe00105558084440f83700981f0009870000fb182010bb0f0018f9400a0f000044a88700281000a90f00f8fc20287860187a40483600e8
-- 061:a34028f600d80f00198700d90f00683700680f0008fc2068d5103003303305891f008b0f00a8fc20685490582600b8cf70584700881e10090e10ca0f00584c0028bf50586600391e10881f006987001a0f00a8fd10001108fc20780f00684440a83700ed0f00d92c307b0f00e8fc20187680680f0009b070581e10ec0f00180780686600405303303445dd0f0028fc20180f000088682600081d20003cb88700b81d206c0f0028b510884c20103333888700083270b81f008a0690780f00e8fa40286c00005108fc20885950103808888610188700b81d200013189f8019100000374a0f0068fd10e80f0010dccc790f
-- 062:0000516987000030ea0f00a80e10081e10d887006d0f00100830880f000050880f00382500a80f0048e30058cb8008d861184d0058a8618b0f000055080f00582c30382320a80f0048470028487138e21118c50058b7718b0e100055080f00b88700c90f0018b6002b0f001807808887002050dccc5874402a0f0038c6006a0f00590c30305553dccc58f000f80f0098c7006a0f001a0b40081d2010dccc587260680f00a835a0580f0098fd1048e2c1890f00004338100000441b1000190f0038fc20f90f00203333341810001bc7000043ff0f00780f0038fd101a0f00281f00cb0f00d8fc20f90f0018a0005b1000
-- 063:090f0048fd10f90f00389312981d20a80780181000a8478028c63020158080686f8128f600680f0048fd10f90f0008a300483c81584930a80780282c30d871e0084e21008008bcc078fe00e80f0088fd00490f00081c30780f00e803c0382c30889e9028a9000844d0786e9158fc20380f0048a60048a1d1890f003811c1980f00a805a0280f0048586088c700c80f0049fc20c901e0c80f000008081a504801e04810000854b048eac038b450080f000008e80f00a8fc202c0f00d854b0084200083300290f00b8fc20c90ff0880f00c80ff0481000681e1058fe0000150832e10afc20c90e015839b1580f00e8c9c0
-- 064:0854b0881e10184200380f00e8fe009a0f000071a80f00a80d11681000382c30489270284020a80f00e8fc20a90f00cf100028391218a4020883a118b3a100081854f1108380085c30a0038383008388303838300828d00008410010800348120018b20028f70200881b2d1248581208370008d400485700088600185cf110300808400008b000487000c8210008b20018c700186300381400fadc1248573218830038970028e400082e00183f00584000000048400008b100183200287200283300008018fe004b0f00581f00183c00086f00386d0018ed0018bd0018ae0038110088510048a20038ee00481800eacb
-- 065:22281f0028140038cc00180500189000289e00188d1068900068b100384700287b003b3a4268e910681700185000288e00285000281e0018ae0038500018cf00003828b20068d700682f003b0f00482d2068b700485000189e000080283f00089c2038be0058500028f60000884b1a42789542682500281f00382f00389e0028b00028ae00280100280f0048790028f9102bec20181000283920381f0038062038650028d32088d800b8110038e6006b2862680b00884500186000480e10f8600088420068e7002864000b1000482e10885b4048a320585600e8310048c2002bdb3028100078f82018370098a600282e
-- 066:00287d10483e1018fd10b8b80088dd103bc672186b00484c3048bd0038480038d71058700038170028ca4058dc200873002b1700983b40480a508896000080287e00487c20003848761078420068d0304bfd10081000582e10382f0048a500485f00e8f000687200fadc2000bbff1000ff1000ff1000ff1000ff1000ff1000ff1000ff1000ff1000ff1000ff1000ff1000ff1000ff1000ef10000077fb34002b1000ff8700be10006f8700007bfb4400fa100020b777770f9700085700181000da9700003bb81000cae30038de00281000eaa300ab1000687700aa9700c8de000b3f001077712b970008100000b38810
-- 067:00baa30008100088fe007a970029ee00aa2f0020b17171880f008a2f0098de000b3f00a8ee004a5d2068ed000033681000da2f0008fe000b970038de00b8e610aa3f00b8dd104a9700e8de00b83f001a870008dd10d80f001a2f0018bd0098d70048c0006a1f0019fe00081000a9430049ee009a2f0018cc20191f00c95d2058ee00f857004a2f0039ee00b99700f8ee000043f82f00b97700386610291f00992f0048ac203976100a1f0049dd1038100059c520a8ee000043981000a82f00998700298e00e9970018fe00497520285700083e1099570008552099670069970088fe00a8ee00782f00480f0000b14977
-- 068:0020b71711390f00287010184000399700a8fe000034681000e81f00598700b9661028100009630078fe00e8ee00682f00381f0049870010b717990f00385900007109830028fe00a8ee0020434344b82f00381f0010111b29770098de707a2f00e8fe000044481000f81f00398700498a40d81000f83e1028cb3068ee00782610184f00585700790f00a9bb30899700680f00b8ee00882f00390f0020b5b55b0810001055b5586a4008500020757557081000105575b80700686100c8970008bc002035355308100010553538ee00785700082f0028b100205b553508620020b11111a8870018970000b59856002075
-- 069:7577082600086000c88700089700005518610098970028fe00003518e50020554545a8ee0038d7002045454518290000350872000031a88700005b1887003055b5715158dd10107177083700289d000057a88700886100c80f00103b5b28870020353454a89610281f00005438b100103b53081e1098770000bb08470008c700a8560018be00284000b8870018470018c70008c000c80f00089500103353089d00005448270020c4c4c458c70008701010435308c700005b180e1098761008461008870020715155480f0008fd100846101071570856000055a8761008610008870048610098fe0030bb355b53088700
-- 070:08fe000055c8961008761010545418b100203b5b55088200a887000857002015555518250068260008d0002055551598310068610068920098fe0018a5000844002043544548de0038100018d00008de00004508630018b700080f0088496000550896101810002051755138060050717755775105082100205057759896100827002055505068610068c52008fd10087500284400105345589610681f009055445405005505055b35081e10b8752010551508ca00189c00689c100075189d00a8310028610038510058610038970038fd10003508f11018b100004408870068fe00281f002054455018910020505533
-- 071:081e10980f0008870010555118910000714856003071715175087d003050055005198700005078e800680f00105b3548d5000043280f00004c2810004875201045002873000005181d20880f0010b5bb08ed1028ca0068ec10107577182600083510783100386100287200986100083f00180f00103533080f00281000081e10289e0010cccc481f0010454418ed1028481020353b1b180f0048496010b5bb08fe00005128660038f40050717175715500082000080f00982b40107577380400b86100007b28fc20003b28040018400018952008ce0020cccccc381f0010454308a40028b10010503538fa4068c25000
-- 072:15081000388b1068100008620038740088761008952018920018b200a8610028d950005008d200381e10280f00087700381f0008a70048fe00405550331111080f0068c25008fd1018a910086900387b10085a500075087400000018b4004831003810000070580f000050b8f4404073bb3b350008100028ca00080e1038fe00681f0008a400287300105051088700101bbb0850003897001887000015184300001568f400589b2088310078610008f800b887003077773330085a0038e500005458fe00581f0048fd1008d01018870038100028a610007028cb20084630880f002834000000087e20a80f0018c50008
-- 073:4000d80f0018b100200000050820000863000004180f0038870000cc280f000040688610680f0028770000b758cb20980f00181f10182b10101517b80f00284d00b8e71038b100180f0018d100f80f001887001824200015280f0068870000b7187c0008f440185810980f00185100c82600089200000518f5000000790f000050f80f0048fb30d80f0020888880185600289c0010188848100000852831001841006831000810000080483d002050505888610068b10038a430f8b10058b220b8b10008018008de00100005181e100054588fa0003008de00182a20005078310018610008520018fc20200505048861
-- 074:00281000103500087100288310f8b10008b41008921020005000a8b10008b97068533078199038f410a83100386100389010682100008058900008fc00387220a8130028ae8028b010a8630018100008b70018ad0018cd00005578e80038310010000588310038610018c110100005682100008058900038090008c100d8fe0010344328b310180510a87100286a00185f3048156048402008880008200078110068610018c20018172038100058db10482040e8230028630038f41048b0306803002015115128bd00005008ea30280f20281000481f000051081000a86100287f10781100008068a00018eb00084900
-- 075:78b1006810000011380f00b8b100087500381f00180900186600481000384a0018d100987100388a10000158e00040000080000048e00038bd0088240068100048f500c8510008a7000051281f0018cd00881900283910188900b81f00180e10280b00085100001028870008520028100008e500005519fe00083400180f00c8b100001168ab10b8ad0028cd00487c00f8610008710038f0000080f8b100e81000383e10d8510048dd300000d8fe30193100f861000080e9130059b10038d6a0104000e8873010400058b7b0b86100a8f000680c30f8b100896300481000084cc00030f88730003038c200e86100a8f0
-- 076:00680c30f8b100896300181000382d00ce0f000875006919008d0f0078f801be0f00188500588430f8fd40194f40d8610078825059130059b100803333303838380000380870003030083838083000181100300838300058a00098b10008610008700068b100008018b10020033333083000d8b100896300087000a033383833038383800083831870002083838308a00028b00008310048210088700020038000a821000080187000389400108300784400d87000108000d821002088033318690018dd0018090028d80048ca00b8f00048e100103000a8f000008028e1000804b018cc00184000a8e10078f0000801
-- 077:00b8b400303338083308080048dd0048f80028400008310068c000484000081d0018911018b2004840000080188000008808f4000038885d00f8400038621098b300000828ba0068dc1028400018740048ad00186a0028db0068d100485d00289100080f00188000103300081f00003008b100c82400784000180f0068d100281200180e1028181018d800185900682900a8ad00287b00189000188200588c00280f002080838828b400284310f8540048720018b0107854000840001038584f100000854f10000832102810000088589000a81000081b60285000181000a8820048910068d000a84200483100e89400
-- 078:b801006e100018ce1008ef20381000490900987b00b8a200b80b00c8cb00590e00f804004893a0ee100038f70008001078c80008e8307889002083333378da0008a100783d10284310a8d000987200680e0038e40078a1008820108c1000680c10d9100038b80069d720782d0038a20058b100381100982300288020881100981500b8030028c200fbaa103b100028b90029da20e8210058ca00090f0059013078e4009893008851405c10006a0e1000bbff10001b10000000fb34002b1000ff8700be1000ff87007b100000bd0b430010000b0b5300fb100010b0003f96101000004a1f001bc41079100008fe003f1f
-- 079:004f7700ff8700ce1000ff8700be10003f8700103f1f181000001bfb9400ba100040f3f1f1f11108400000fb1bd300002b78100019f10089864050bf3f1f111111184000ae2f0030b31f11f12886100810000b2f00880f00594f0029100030b131111f18ce002810001a4e1000dbf932000a100000b3187e0000ff580f0010f1f1eab610c80f005a3f00003158be005810003e4e10001358ae0018de00287f00da6d20f80f00882f0059514018ee0058dd10084700386000ba2f0000b2881000d8c10000b0388700e8212028dd1008dc2018e60018dd1038600000ffaa9700190f00582f0020b0000f19330008bc2088
-- 080:0f00684d20ba4e10980f00d83f00100000195b1028ee0018100028e51038af0048100088970088521029c740986e00000bb82f0039fe0038ee00c8ae00fa6d2088ce0010b00fb82f0020b000f009130018bc2058e600881d2048c0006a9700202b2b22281000083e002020f00fa81f0010f00f09c2a0e8ee00c810005a970088a600300000f002982f0019fe00001388e150580f0098ce1008a0003a870038ee0028100030200f00f088ae1000b009fe00f8dd100910002a8700988520000008970038ae10189b301000f0e8870000b3584e0098760048e000788f002ac610880f0010222208970000fb189e1008fb80
-- 081:187710e8d2001aee001810000a9700980f00081700100f0008fe001860c0100bb0f828c00013581e00d84340781f0018800018d000e98700a80f00002218970028fe00181000d8a96018dd100071c8d6004801000071d88100e93f00784700484d20000f486700e8534018dd1058bd00390f009a9700b80f00083e1000f058970008ae10a8a20089dd100071b8801048d00068a300193800a85700283e10489700000fc80e1008dd10882d0048ab20b9100018730000b1189000099700d80f0008dd1000f0288700086000981f0058cd1018ac1088dd0018b00028ee0078410058d000007158b200084000f89700c877
-- 082:00202b2bff389700085f0098720088dd101b1000f86c40d80f00002208870068fe00680f0010b131483c10084c0098bc10084d0018110018700028b00028410048be0028c200481200081000c98700180f0008ce00184e1088620048ab306b100018a020b887000032781000780f0038a5204878700810000031488b0048cd00085400486c00783e00287e10786e004890201810001070014842002a8610980f0010b3173b6e00381000001038870008100098e520880f00382f00788700580f0008dd1038db10786c1088800058fd1048df00e8720020700000189700281100007baa0f00cbdd10780f00982f00a80f
-- 083:00181f00288700281e1048778068dd10781000a8d000b88100387e1088620020117001882200682f0020222223281000880f00181b4018970038978088ee0000173a8e10c87c4010100098c300582f00b80f00082f0000ff08df7038b340280f0028dd1078d920b9100008850008400008870048e000286000080e10a8320038870038ee00882f0000ff385610089700180f00988a400017780f00a89f0028d00088210010fff1b8fe000000181f0088d300490f00680a5018569008ee0098da10f82e0009410010fff198e00018c400981f00081000b80f00482f0068807000f0081d20e8bc20187b00084000f80f00
-- 084:781000201fffff88210018fe00181f00784300089000090f00003248fe00184e90100b2138cc2058bd001a3e104071717fffff38f20068fe00e81f00087d20187e0008e600781f0078078020000007c8ad00287b0038fe00487000980f0058b10000ff689100001748fe00382e1088040060171b32323333d308100058fe00003048fe0038970000d1581000482f0018100068410059100000ff18e20018c20008c00058c4000001d8520028ee00181000480f0068fe002000001008c00018ec10487d1098fa00980f00387000484100184000080f0078cd0068fe0068940038a30048fe0010d33368fe000002085690
-- 085:5000d2d2dbd1d1083620188a00989910e9de00280f00881000300000444488831010d1d748800018a8000012781f00202f00f0085f001843400023089100189700783e0078ea0068bb00286b10681110487100180f00386f20280f0018870048e10088040030d5d5dfdf08400070d5d515d5d5d5555508a600005538b11008f00010d5d008f00010d51508100020fff55508100038c20079100028d10020dfd5ff58b00000f5084000388700f88200905555fffff15fffff515118a500305f00f00548870018f0000055085530300151515108020028f00018c20008f00028100038110028100058310018d1002055ff
-- 086:f518c200189a00005f18900088d40058100028e400284c0000df588c0018fe0008810008920048b9001000f5180f0008b040a80f0008310019fe0000ff08ae0008550008600028b00010ffff181f00082f00d88200186400087200881000080e002870002860004c100039d40028dc2058100040d00f000333081000086000785100001308100018510030333fdfdf08f00008ea00303313131f28c000a81000084e0058100078b000088100100000b88200001338043078100010313108fe00003148870058310028100038d00008740000f338600010313108600000f188b300680200c86d00080300203300009836
-- 087:0078f400781000301313000028bd0068870028510048fe00888700101313286000d88700004f188700004f28170018600000f4f8870018d40038730088d7004031313ff001880f00286300103331689d00788700288d00680f00103fff385000290f0010fff388870088fe00b8820000f018400000f018078000f018b0002c1000398520c8953078616018100018e240084200285340889a30083100287c3068630000ff38500068f000484200588700a8eb3009100018be00281000280f0028100028740078d90018cb4018ec3010ffff28a00038630018a90028500078f0003842005a8700a8ce0058d07098870038
-- 088:fe0028b800784b4009870000f13842004a8700584e00b81000790f00486c4098870058a000490f0068c400980e1019ee00382f00680e10481f0028b50028700028685018d400380e10186000780e1028380098870028b20018d40088e01068cd10392f008b1000390d200088081000008108100059ee00181000000818520088100028930000f828600010f18f387400183400008138c00048520028210018900010000028f00010888848b20000f82890002842002018181079fe0008100079870000f8489c100018181000a88700085500101818788700108818f88700c9fe00381f0038db00990f00489500880f00
-- 089:289000480f0058f100a80f00a9ee0008100000f828fb00890f00180200b88700681300480f00098610108180b9fe00081000280c00890f00881c10586200b80f001987000088d9fe00181f0058fa1058140038600010181848c40068190048b000281f00b88700380b00182700389000c8595039100048b2000b100039c30000770810000070f90f0000f01882003b100010000019610078c3d0b9100048a5d038130008800018b00048f30038810088050028f000485000007118870088420048a20000710abe002d100048fc00000f8881d0681000000f296100791000780300e8a300c80100085ee04f100079db00
-- 090:79ea00f91000000f39c21018410008910018a100fbab003b10003afb00d90f00288c00a8f000698400488200fbab003b100088a80029aa00782910e8020079fe2058d400d84220881100fbab003b100088e800e83a0068c100f80f0058479139100019d310c8a500fbab003b1000395a10482951d91000c85840086b30c8010079100000bbfb100000eb681000fbc4009b100000bcfb3400a9100000bd488000f80f0000cb78d100007b581000fa0600a9100058060079100000b70810000a9400fa1000890e1068ee000d2f00a9100018ce000837000d3f0000bc890f00186e000077281000ce1f0010b7b738970008
-- 091:60001b1f00080a2089100099fe0038ee00582f00a974008c100008fe006877002b1f0099100099fd1018270040d7ccccc7d7381f001bf5000b100038fe00307cccccccf91f0000db5a5500681000c9fd1030d7cccddd281f00781e10694600fad70029100008bb3018fe0020dddddc081f00085c30fb2500081000e8e950e8220048fe00288700481f003b3600da820010b7bb089700488700087700ac1d2089b770580f00080e10680f00000bea16000b1000480f00181000580f005c870000cb89a680580f00288700380f0010b000487300786200484c201870005a0d10d91000480d20181000480d20588700db10
-- 092:0089ed10780c3078fe00180f00385d00adc090f80b401000002c1e1069ee00385b10f80a504c8700d91000e809600c8700083d0099dd10181000880870000748fd1000004c9520c91000680780000b28fe003c870049fe0088c93068069010700028e860788700b92c80fb10004805a010b00028d950087700a81e102bde10d9ed1018100058b3b01070f028d860a88700081220addd201803c048f600c80f003beb40f9fe0018b940380f0038f60018fd10381e10000b28be005c63507910009c870020ebebdb990f00982850488c20688700081700188700edeb4048870028770018c6000887003801001b87000afc
-- 093:20581000ac87008a100048f600688700085000088700686440bae7007afe0048870028fd1000f018c60018870038010028f1006d6f0088870028c600b88700ca7d20280f003a8380c8870008900000f00801005864406d7c3048043048770010000b8801000b8700bafc20898700697d20db5b60398700686440daf4306a0f00286c2049100028f1004d1d2069570028870000b028b5308a10008a0f00791000887c301c10009824f05804304c87005afe0000bdcc8700294600c801000055181000005099870078f4305a1000d9fe00007558100010f0f079fc202000005579870000b5186b00005ba83100c9201128
-- 094:8e00581000a9fe001000751850000005685a00291000980a0119fd1000b5296300b98700386810305d5d5d57181000088000981000784100082c1000bd28100048b60038d000181000689200c87300b9fd1048100000d5081000285a0018900078100078310010757518661020dbdb2b581710381000f8920068f00000701a8700585a0010575da83f00580f0038c10008be1000bd48870088be00c8911068f0002a0f000005483b00d84f0048f00068b10010bb2268fe00f89110b81f0048d950086000689000f81000000d584d00095e1088a10020575222186f0000bbe83200092e101afe00b80f0009db00581000
-- 095:107232e83110887200a8d0002a8700081e10886d00b87f0098410010523239311038720098e0002afd10181d20d80f0078fb00883100207333253a0f0000d598fc20898b40f8fe00290f0020233327590f000882000a0f0068762018c00008a0002005d545087c00184000a90f00403333357575083f00e8de00004508720008400078100078a60078ee00098f00000d3a0f00403333325752083f00e90f0089fd10a8e70000050a0e10002508fd103043337572190f0028720078c00000d0797700c810000a0f002022575308870020572222f90f006a77000000484d0030ffefefe548b00020ee3e35a80f00907222
-- 096:7533344433322222590f006871007afe00380f006050fffffffeffee28c000305feeeee3a80f002052222748870029fe00980f00797600c8d35010000028072108770040efefeeeee718c00040eeee3e3337788fa140777772222318870020332222986100191000c8b860a9878018bf70107ff0180f0008970008c000507eefeee3ee339876201887002044444308870038c3407910002a3070483f000007088a00187700180f0000ee088e00087000103e33a81f00002218870000c4188700002718f000407888888f8f18400058100008d30008100008659000ffb80e00082100281000889f00000fa80f00107f0f
-- 097:08970000fe180f0030e37575fe08600000ee186240681000202222332887003032222888281000a08f88f88f8ff8f888fff8f8384700285700000f885500094e0028280058b80048100028fe00180f00203e8f8f1860002033333f382600403888383838088700203444c4189520002808e000389100290f00c80d1068f50018a000a8a100082a00000f1810000000180f0000ff180f0020efffff086000203e333f08a410381000108382188700104ccc281d2098370000f868ee00286700288400c91f0008ad10f80f00189e00103e3f480f00487d00080e0010383218fd10088700181e10880f0028e70010ffff58
-- 098:2f0058bc10190f0028a10098590028de00290f0018a320680f0078870078270000f8085e10d90f00983100c8ad10f80f00281000585700180e1098870008010058b700883e10781e10a8fe00a8c600480f0028980058fe00a80f00087b1000f808fa2068b700008828752010cccc389520584610383200782f00280d20f80f00788f00c90f0018e400985700080f00a88700781e10780d20380f00689d0029260008a01058be0048c80028b000680f0028fe00008808e22038a410281e10108383489000a8352008de00882d20380f00782f0028900028960048f00019ee00383000281000a8ed10380f00a8d00008f0
-- 099:00682e1038ce00a80c3048bd00095f00586710781f00182f00388200280400580e10b8f70078ce0058370088fe00089300480f00681e00a84f00387620291000580310684b10582e00486e0028ae00a8100068fe00b8fd1018bd00484000c80f0088f800182a00482d20185b00781000b82d20d8170028500010f88f88d95028fb3028a410595b4039fe00690f00181f00183000289a50480010980f00081f00d8fd10291000a81810386f00381c3088c700284e10e82e10881f0018e90020f8ff8888dc2018e30028ee00e88e00583f10d8880068fe00387700780f00b86d2028bb40889610387e3058cc20982f0039
-- 100:3510290900000018e440184870a82f00186c3018260098ad1028f60028ac2010f8ff78e95048cb00a9096019d800281f00587700384a2048360029761048be00581e10389700192e10982870684e00a8e260200f0fff284e10a82f00082c1078f50028ee00384a4018be00b8d77008be0008c30048c310b87b30c90f00c83f00986d20886f00988e00488110589610d92d20986d1078aa50382360289740882e10186d2000ff18d490289f0000f8088600380f0028ce0098eb30b8c950e81000580d2078500098ee00884700886d2048300078c61078de00a80f0089ae0038600088f71068f770480f00385270a81f00
-- 101:386f00488d1068100088702048a680a9d59058124059100068c400280d00a86f00f810008897001a100098654018355078a72018ee00c84d20287f0028af0038ef0068e00048270018200048dd10c87b90d85510b85da0d8fe00888a50986e1019de00587950d81f00591510b83270a85a0028c70018b7804a100018de0018530008bf3098a770381320d8624000bbfc100000b4fb34002b1000ff8700b81000004baa6400fa10005f870010745b398100ff87003d1000ff8700b81000007bba7400da100020b77455399100ff87002d100020b744453981000077ca9400ca100020774445291e10ff87003d10004f87
-- 102:0020b74444391e10dd8700004cff8700b89100ff86101d1000407777755555199520107777ad9340ff8700b8100020b777777d961000b718f500088700007508a000d8b100d8870010bddb3c4000c98700087700b89610ff87001c870008e500188700005bf9870010bb1b4c400018d500007b2887002057775be8db20f88520398400303b3b1b3b4840003d870010b1113c4000f98700b83100f84400203b3b31f840003a870018100018870000551b87008b0f006b870000fb19ce00484000bc87002011111b884000001fc801007a400038c500288700287000c88700d8843030aa11111a4840001011a149400049
-- 103:1000101313884000c9870038b100881100880600101a1a7840001ac600101131784000788700207ddddd1a870000aa58100000a159100089480088100038e40090333332323222222828ffc81000287700207770f018100000fb280f0030a1a1addd184000201a1a1d68400010111149400030131ddd13684000303ddd3131784000288700303232232208770010228878270000f0282000388700107f0f181000000b480f0020d0d0da08400010d1a1494000001179400010d313784000283a50708883888838888288888700f80f0000f0480f0020ddddd108400010da1a78400010d1114940003013ddddd3884000
-- 104:10d131784000288700090f00381f0000f728870028fe00100f0f480f0008c60008400018c700294000594800084000984800288700690e1038870038fe00580f008c0e1008261010288d085000e80e1028870038fd10381e10fc0d2010dfd2290f0010077058fd10281d2068f500001a8810003ab60000318810000033388700080e10202dfdf2290e10088700580f00181e1000cc4c100028593000bb08ec2040dffdfd8828e80d20a80f00181e10fb270038100000ff18770070bf32322dfffdffd8f80c30e80f0000334c100000ff181f0070ff33333d9ffdffd2e80e10103337188520107828681e1010bf284c10
-- 105:00180f0040ffff88388d08870000d8a8834018fe001088872887000088681d2000ff89fc2069e52019100008870020bfffef080f00088610090f00487d30680f0000ffe8fc20aae600a88700080600590e10103233088c4020282282681e10580f00dbfe0008870008fe0030ff38888d188700e80a50385b50102888681d20080f00a0acccccc1aa1a1cccccca1a18600020c111110b600020c3ffbf180600090f00281f00d80f00000b080f0030ac44c4c108e70010ffcf18600038c00008600008e40008210008600038c000e9600008de000820004a0e1010f0fb180f001044c418ae0010ffcf18600098e4009a87
-- 106:0010c3ff18c95008e4104886100028388510285000081000003808127000d828f00028100008c0206c0f0048a040303ddddddd080f00080e00283e00481000080f00103dfd080f00481000088700a80f00b8e400ca0f0038b60048087068270018f000087800303323dfdf080e10081000ec0f0038e41058ab20386710781710208dffdf08f710386710c80f00d8e4004a8700101313690f00002d28600000d8180f0060dfffdffd2282d2180f00008d280f00584e00880f000b8610680e10489b2038580008b87008d70000fd180e1000d9088700102828083000302828dfd8180f00ebab30080f00180c3000bb5885
-- 107:10008d68d510208dfdf808a000089d1008f000188700208888df08a000086100288610cb9a40680b40580f0028078038fe0000fd08be00102dff081100580f0000df084710086100088700cb795068d780680e1038078028ed101834400022189d10680e1010dffd281e3020dbbb3bfb2f7038100010bbbb48ec2008fc0048b2402831700082189e00086710188700008808ce0028610008c7a0fb270038100018c590181000480a50280f001830800022281610980f00288700003b09dd10381e10ba60000805a0480b4038078018380028b000288700080e1028f610080f00002818e800080f00001a08a77010101a
-- 108:18c3000010282400ba6000401313101313086000103031084d9028b24038d51038b240188700489c200038288700085810488610280f0010000168600020110001184500ca600020130003680f003809602a0f002bc6002011000318ae00286000203100010b0e1020a000005860003011100000084500ca6000001308600010bbbb28ec20008318723000d238c950383170289c20103888087a6000dd086d2010fd28388430180f0010000008361000110b60002003a1132860000031086000000b090f00980c30380780780c30289e0008be00386000089b005b6000090e10688700180870287b50180e10580f008b
-- 109:c600486000003028870098d510008818dd2028bf000028389c20085810186a50180d20580f001853000000fb6000000be80780a90f0000115c8700f80870c90e105c8700e8f680880d20589100688610080f000083181000fb6000ea0f000038181000fb6000f80780c90e105c0f00289410487610282c90288610008228861048b710a80d207d0f0018bd200022189a40680f0030dddd282d080100bd0e10b804b0280e106804b08c0f0088ec2028f68088d3b0b80810188700ff0f00eb0f000904b09802d02871006802d08c0f00c8e410e801e0483d20ff0f004c0f00aa0e10203ffbff182000203ff3ff18400060
-- 110:3ffff3fff3eee308600060f4ff4ff4eeee4f08800070f4ffff4fff4eeee308d000004f08120008200018c20018430070ff3eebffbeeeebee28600008860120fbffbe18700018200010fbff08500020beebee18910018c00000fb18a00018920008120028c000283d500f1000403fffff3eee08dc0010eeee18ce0000ff089d0008fe00084f0010eee408310008d00008700008010008ae0008300008610010ee3e18c200082100085c0038300008ce00088c0038700010eeee08d511380100483f0018120008410018b20028710008600008f000083000fbab003b100010dddd18645000d348400000dd18cf00087000
-- 111:004d884000182010089e0018710018b20008400058a20000eb18800008fd00689000081f0010eebd18f75018010058900018120048400018020018c20008b10038410018b41018311008c22028e61008550008251028961008081000ff08262028c70048710018f30018f210282300187b2158900048651018e41038850018a20018110058870048c2008f861038911058a310383d0028452038500038f00068e10018d61078a91048561058dd0038500018f40038961028e10038510028981028971018e00018420038b50018101028d51018651038b61028eb20084b3058f00078a00018d81038b51078a000285241
-- 112:28360028a00038e100785100280600682910184100fb23103b1000285e0000ee18a31048b31098600018cc2058d51038c00038a20048841038c000389510580410c8c00028ee0038b81058310038600028c01088d01048b41028561058fd1028210028451058600038f100e8c30038110068c410683200280e20a8030000ee01ff7b555b5555000000ffebb55555bbbbb008a00020ffebff08110000f0084000a000007fb5757555bbbffff508d10008600040ffffff7bbf08500010ffff08c2001810000870001801002055555b18b300407f7f7fbb5518740028940018100008a10020ff7f7b188100187200384300
-- 113:00bb08d20010fffb4887001000fb588700200f00fb188700381000000f086100b8870000fb08140020f7fff7a8870000f7488700000f08b500b88700000f08870010fffb082200287200888700690f00381000080f00c88700990f0010007fd8870000009a0f00000b9f0f00680e108a0f00007fe80f0008a100007f1b0e100000dd0f0010000b58870008bf00ff0f007f0e10d88700a90f00e88700580f0000ffad0f00084b000984305a0f00388430ca0f00007b590f0000750e0f007c0e10f88430dc0f00788430ff0f00da0e10183d00290f00088100ff0e103a09603a0f000075280f0009843000758a0f00ff09
-- 114:60ca0f00090e109a0f00af09600070380b003a0f000075590f00007f280f00188100ff0d20b90e10ff0f00be0960ff0f001f0e103a0960086d006b0f00ff0960fa0d209b0f00ff0e10980960ba0f005909604a0f00af09608a0e10007fb90e1000ff0b0e10ff0960be0f00ff0e10790f0008eed0cf0f00be0960c90f00083300ff0e105a0e101a0960bb0f006f0960089c01107b7b380f00007f780e10086100c80f0008d0b0180f00007b28100008700008fe00180f00007b08130018f100080300207bbbbb189400f80f00384300083700007bff0e10380f00285b00280f003810006a0f00005b282e00480f000810
-- 115:0048f120100075088700280f00187300c90f00be0960c80f006a0e10380d20288700580e10780f00007f9a0f00be0960580f000000083d00ef0f00ae0e100b0f00388700090f00188700ed0f002b0960680f0010000bfa0b40083c00c90f00ff0b40590f00080901680f000807405a0f00380a50188700190f00287c60190f00bf0960780f00380d11280e1008ca00c90f00088700a80f00780d11a80f0000bb18330000bbff0e10a80f00180721688700d90f00088770880f00488430880f00288430780f00281000ff0960190f00980e10007f090690190f00480e10888700090e10ff0960c80960fa0f00180591a8
-- 116:0f00680c30680f00280b407a0f00ff0e10286000ff0f00fc0960007f380960ab0e1000bbff0e103b0e10280960d90f002802c1c90f00ff09600901e0490d20b80870580f00186b20f80f005802d0b80f0030fedededd580f001887004e0e1060efee6eed6ddedf690e10287a00b809608900f0f80e105802d008c5005802d018870080ef6eee6ed66edd6ddfc90d20dc096080fefeef66e66deddedd690d2018f200b80e10f80f00e8087018e000d80e10a80960406fefe66666081f0010dd6b390f0008781000e0fc096070f0ff6ffe666feeee081f0000d6090f0010ef7508c100206eded0185632080f0000f0080f
-- 117:0008300010ffe5aa0f0000ef280f0048870008110000f008040008f10040e6666eeeee083d2000d6580f00880e01b0feb66fffeeeeedee00fff0fe080f00000f4886100817007a0f00b88f70000f18101070f5550ff06fff6efe183d2020ed6edba80f000050280f00a0666fefeeeed66ed07f7e7f18aa00480a1000ee6a0f0028e200680f0008e000280f0000ee18861090ffefefee666edede6ddba80f001887004000f66ffffe081f00106dde080820286e103887000835004a0f0028e200680f0048fd10080400200f0ff008350000f608b61010ed6d680f000088681000008028690020eededd78210078d10019
-- 118:1000287f0008100000f8b972002088666008520010ef660887002066ded868c50028d50040808000800f08ea0008681020eeedd028410008500010088018100028600018010018500038430018300008972058100048f10038630018f20010880028a300089000408000888060381f00006e182e1000e018b3001842002088881828b400208188f008d10010ef1e083d2020d8888138490028a100b8d00068100010808f58fe00081000888100001828580068430018c8001081f0281f00001f18e23028e40008320010180018d100089000100180082c2020ff6f1e08590020e8080118aa0020808010086010208080
-- 119:8138ab00001818ff00183300183c00108008088720189a0008ee00084500082f003080080808084000084300088200100081089300000008430028b3002081006f181f00101efe08f25018e4008108080080101088118868888180811806f06f1f6f116e6e6ed108d000008618da002011806018a100001018d000008018d00058a91008d40018f600681000007f38861008aa0008e400006008ee0008430010808018430008b50008d0005066f0ff1fff11084b4010e18808b50008a10020881108181500084a0020011086181f0060116f666e00080118d10040808011086818a10010180608eb00000808d00008fc
-- 120:0008dc00183000000f083b10000f18ce0028fe0008100018fe00181000000008b600087000189b001008000843000060087000088700182e100011085b4008df0010180618a1108011818811866180601008d1007010f6f1ff1166616e38d000008698a10028d0000066081a0048b61028f420982f0018a610087c00108180084300008858430030801122211814002018661818d00018e400001858a10008b7003006681668086d003066616600088700a0661660082228660166080868a10008d000700011866006680000086c00400808ff0fff182f0018ee00085030383e1010000818cb1008720078430030081c
-- 121:222208d000088700008128e400006058a1001188081180181016861116818181686111601028d000308c22226068d00008a10058d000106666386c10281e00380f0038470028a6100844100011080320984300302222c22198140088e400e010081010666611080101066661180028d00008f200602666611000181888a10018d000080c10081f0028570008fe00180f0000f018e000187a40181f003000011808684300702221180822222226b8b50068d0003081811116087b102010111108dc0048d00018f20008d0000001f8a100181000389b3088ed1048b000183e1078e400206c222208d00000ccd8140068d0
-- 122:003000111110083b102001111108cc0018d00008fb102001cc1118c5502011111808fd0018a100188a20287200184200488c2058161000f008be1008ff5010fff0281d5018720010000008430008431030201111cc08230028140048a10048e4002008111118e14008100010000138bd4028d0001080cc18210058d00028834010000038d00010800f98ae00388e00283800007f2803507843000843102020801018940008834088b500386840008018e90008991078100028c00000ccb8f00098e000188d00689a40280f0038be1008810018a280781000284400589400289210a8940008ac0018f800188000288d00
-- 123:18bd00008028f20038e00018a10018410028100038bc2079100058430018700008440068c00068b5004880002841009a100048c330381e1038100048010038253088b20078431029100000889910000008a9e100d91000b9e3000000281000fe8000286900008039800000084981003a800008a000a90200108448598000388700790200b980000004c902003f0f005f0e109910009d0d203da300f9e3005f8610ff8430ff8430ff84306d800000449910000004a9e100d910007be3008d87003022223333694000000289c100f9400000036bc300ff8700ec870000f098100000ffc81000000fd8110000ff791b10e8
-- 124:b200e8e300a8b600000f9810000000a8b10010f0f02801001b870078e30059b60000dd681000b83600204ffff46850008810000022691000a8870029e30008160078e600781000b80f002040f0f44850003987000028a9870078e3000040a80f0088f60040bbbbbbbeeb085000180f00003378100020c3333c6850000033390f00102442398700d8e300581000180f0068e60078a00008f8008a8700080f00da8700180f00098700180f00405151515565085000605155c5555c5151085000301155c551490f0020c44cc239870018e300906c5151c1555c5555c565380500105555990f005151551555555115155511
-- 125:c5511c1555c1511c1115c115390f0000cc08100088970098870018370008500020515c15082800081000401111115155990f00006518990000551850007812300041390f00187700989700888700006588e300004518d4000051087700a90f0020551511180f0008400088a3000055198700002c38870000cc198700986b00004528ce000011088500990f00005528a810285f0010556528bf00181100d88700185e00988700285f00988700005118eb0008930018ad1028c00018f400a90f000011280e1038630018730010151108de10d88700584700581000e80f000051184e0018640008e300180f001015150805
-- 126:00b90e10480f00083000080f00280b000051f80e10b87700384e10a88700287400083400580f00286310990f0008aa0038ce0008ea0018d000001108a9100011e88700b81f00f80e10088420086e0028f210184400080e1020111551b90f0008e900389a0028ed10087300190f00a81f00483d20888700106565381400287e00482b10088520a90e1038212008e91018f200280f000055f80f00a81f00190d20184400084d10083000083e1008bb00186e10b90d20384300386c3018f910188800098430e8fe00b8870028c120388c20582a20a90f00086e0008d900085820182e10183610180f00298340990c300830
-- 127:3028d21008913028ac20083320186130990a50584b3008655018464018ea000065298340990b4018f300581e10482e10c90d20189a00081d10280f0018c730080b00182d50098700990a5028fe0018031018b40018ae10080f00b90b4048e86058dc2058a460190f00182f0049096008fe0068cf30689b40a90f00288e0048c73018573028e640490f00c8100098870018ee0028c300288b4008532018a000990f0028eb30482550380b00083800590f00798700006558d30048ca401874000011a90f00284c202848201847300015280d20090c30f90f00188e4028d03028e130090f0000ee481000304d404040080e
-- 128:10282e10286a0038fd10c80e101a8ca0286040185e0068bb302860000033081600104d4e48e600788700380d2018bc2008330028e910185000082000a80f003a870038ed50386520182e5028d520280f0068e60068af00380f00480a5048ad10481f00a8861088b240681000184100002f980f00182c3028940028bd1038cc70280f00004b490c3008881028d200880f000015980f0000f228460000f2280e1008600008100018600010cccc78220028069018c600188a40189b30180d20680f00f88520280f0058c95058d91038892088870000ffc8c770581000098700387b8028ec20288000990f0018a63028a640
-- 129:08673018243018783000159805a010fff20a8700189c20181000388c20182e10181230e90f0068b370481380a80f0020ffccccf84520e80f0028d12058dd1038ef000011a90f0008095018ef9018f77048665008ef00da8700289a4038ef3028ed1008a00008d700a90f00684d10386910188820c80f0008b4300088c8fc20c858e0003328a030183250487f00386500a90f00183820588550483530c80f001a8700481000286220180b9018d61000151a0f0028d43028d00018b6502b0f0038677058fe00087400990f00482210186c30183a50281030b80d202a870048c86018c210680f00a90c3048a95028d34058
-- 130:8910a80b402a870028e120384310480050d90e1028aa00185a0028dc2018efa0188d20fa0e1038277058a310087b80186220990f0038b910180f00688be0a808703a0f00885160689c700a0f00285b40380f00286000da8700280f40185a4028f6c018231018db40a90f00488a001864a0486560d80b400a8700488950785000280140a9096038695038c4d0586f000b8700182301488250181960186c70a90d20491000ca8700491000890f00ad8700790f00004f981000a8c4009a8700981000981500790f00d825412810001b8700198400280b3168e600108080084681c910000038a81000198700b822000038d9
-- 131:15000857003008080800087000981000c95300198700f98600a8100018570028ed810a6000003858600019870078e100686000b9e400480f00383f00486000181a00287e9139600019870099030018fe00a80600080f000000185700a96600286000083b1010303858600019870078e100286000c9ab00780e10ff0f00ff0f00ff0f00d80f00f810003e0f00f81000ff0f00ff0f00ff0f00190f00386b40e86000896e40198700d96150e86000000808b700086800b91000d80960f810003e0960f81000f98600a81000580960891000004088c0003937f0781000598300db10001965c1981000fb260098100078ab00
-- 132:7a87009cee00d96610d8a610db10000870a028fb00d9ee00682f005813004c10006a87003ae4002887a0285300b8a00000fd18900000df29a0000044a818d12022444d69540028a00029540059d20079a000c8670048a700695a0049a000588000293600c8130018510009670058a70029840019970018f100d80100e8f200a85100180e22391000002458e610784600291c00685100d83100d8270088b00079670058a70009b400d8e700888c0049c200c8b000b9670078a700d8360039b00079c600b8b200f9670058a700e8e40029970099c6007804003a670048a7008844003a480009220028c0000044495c2039
-- 133:10000044388e1088150098860058a800f87700d8c000ba670068a700e8eb00b897000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP1>

-- <MAP2>
-- 000:00bb0b1000307777777b38a00010b44b0951006d100008360048a000ff870000b70851005861005d1000df870030b33b44445897000e870068360020333344789700fd0e1018770018460030b333333408970000cc6861004e870000330810004044444ccccb586100cb8500c91000287610185600298700108222b92000008b3d870020b22822c920005c870010cccc381e10388700d9fe009b1f00480e10087520189520488700385e20f9fe008b1f00298700385100f9fe008b1f0048761048870008100068510000720afe007b1f003077707707d88700485f100afe007b1f0048870010bbdd4810001841005887
-- 001:009d1f008987001afe006b1f001987009a0e105b1f004885201987002afe005b1f0079870000cd28100000dc28100058e10028100000de28100000ed28100010eeee2b6700088a4010323228b210b8870018d71008cc3008100038e700481000f8e70010dede4b870040888828888859870000cd08400000dc28300000cd08400000dd68700000ce08700000ed08e00020ecccccab0f00a8fc00084c0038870090fffccccfffcdcc444ccd18700090fffccdc444cddcfffcdd08e00060dc444cdecfffce08e0005b0f00503222222888cc682c10389b1058870008170000cc08360000dc18a60008170068870000ce08
-- 002:510000ed08510020ecfffc5b0f00408838888288e80f001810001f0f004887008d0f00290e10285100bd0f00187610c80f0010dded18410000882e0d2000fd280f0000fd28c70000fd480f00ad0c30380e1010dfdf18b400086000089400086000285100bd0b401835103028cdffdf181f00086000087500086000008318e4400e0f0010cd9f28270008600010dede1860003850106b0e10003b781000698700380e1008c60008fc0068e700680d20082c2038f430587d2078f430280d20087d20793d0099100000b2187610e80f00285b5038a33000cc083600280c3010444c281430288700181430280c3010444cd8
-- 003:0f0088ce00994f000022380f00c80e10ed0f0010b222380e10682700080f00086000380e100b0f0009ee00292f0020222288081a50288700980f00285b507b0f0000b368100049fe0008fc20890f00ea0d2049ee00192f000033890e103b0c3078de00993f0028ab20e80f00285b50da0b4089ee00e82f000872c0280f0008e40098fc007b0f00d8ee00492f0000b2380e10d808701b0a5098cd00185fc0181000691f0000b828ab20e80780285b500b0f00480e0088d600492f007c0f00f8de00e83f00980f008083388800000338883318cca0a8100020b8883208b1003008228882f8a8c000b808e82008c1000028
-- 004:08700088610038cd00d805200033192f0000b808dc2008140008600009870069b10009c10049ee00b82f00680400288100080f001870000032091000300000022229100020282828180f0038100098fe00a8e700982f00a88b0028d60008d50018700010332378100058f500b887004876001810002022828208c1000082281000183f0079ee00a82f0058870008ec2008b580485000084c20195000002829500008100068500078fe00380800f83700d81f0098d510190f00e8d510880f00681000088700b9fe00781f0020ff5ffb780e10481000190e10081000e9380010282828c40068fe00294700381f0030b0f0
-- 005:ffff28870098351028cc90785000b9d5101806b068500000ff580f0098f60020434343e81f0000ff081000185a00005f3c0f0018c40058fe00d8ee0058570018020010b0f0181000087f0000ff3c0e1020fffb5f081000005b78470008ce00581000583100205ffffb28fe00181f0010ffff88ec208b3d2010fffb38250000ff798430403ffff00fb328fe0030f0fbb0ff4c0f0000f0088700081f00184000c8ee00682f00289e0010fff008852028d2009859007b0e1018b400681000291f0008fe00081000600fff0f00f00f0f08d700a8d510d9ec20a8d51078ec20180d20280f0048100000f3c80f00181f002829
-- 006:003876100867005c0f0018a220981000089e4148100058c500186100000f081000400000000fff08a7005c0b40380700083e1038800030ff43434c083380781f0008a10018ae0000f008870040ff5ff0ff5f1cec20180a50b80f0008100000fc28ca80682f00085610080f00000028870020ffff006c0c30e8870008100008870000c308de0040411111111f38dd100860000876101848003c0e1028650028050048900038642010ffff08370008470028370018dd1038b7000850000000a835106b1a5068c60079100028e6002865202810008c0f0008632078923088210048710028cc201810002841004c0b40290f
-- 007:00b85100183520281000282f00a8ec20008f684110186000a8ec20002fb83500a8ec20187300080d0058ee0068100008894088e000587700482f0019100038202028011038e40069a200586200084c00f83f00682100688700487000a8fd0098130018c40088b100496320384700580300087750d8e80088eb00289a40281000681f0008c00048020058be20088000189e0028de00281100489200383400483500083200181000580f0068ba00689a0078cb00489a40486600581f00582300a8fb0038963038e300781200688a30886d0048f00058eb00284a00180c00187900282860586e00389000381f0018496048
-- 008:7b0058120028340068420048610048510038700048410048100048410098a80088c00058900098e42098c00078d20098dc00d8f10019c100384100a8b800e81000383e0088e000597200887000286000488f0008700008e000b80f0038100019da00981000a8d33079a430ea100008e900c84d00286000580e00b82e0038d200887d00587100681000e85300b8720078f000e97900b80f006c1f00a8ca00381d00486a00786100f89d0078b000c80f00481110687100485e00a8220028100000ee4f1000392d40fd1000b840107e1000fbab003b1000a854018e1000fb2310ff10009a1000fb23103b1000fbab00ff10
-- 009:009a1000fb23103b1000fbab00ff10009a1000fb23103b1000fbab004e1000202000026850000008b8b10008f0002841000080385000a8100028f000785000ff86103a1000a85d61882ed098ded0391000000888100008940000bbec100000db4a41006d100000bc19510000cbda64008a1300eac5007e100000bdfb3400ff1000a8100010bdbd084d00285000be100000db0810002850001880003b1000094b00c97c00088e0030b7b7b7bb18500008b0006e5f00184e00007b0810002850001880002e0c3038de0018be0020b7bbbb187f005e1000387e0000bb28500010bbbb084000187000cc1000d8241008bc10
-- 010:38de00281000081100db0f0039c12000fb195100485d1048ad10007becdd1030bdbdbfff28fa20c84900780f0018b10010b7bdb9ef20ca790028f93010dfff393a30488c20282f00bc1f0020bdbddd086b2020fffff7388d00f8b940883e10a81000296a60781000184a0079320008be00282c1020fffffb285d0000bc082b20f889409bf24068c40098dd60582a3030bfffffff788b20186f00bd100000db08be00185c10007f088700485c10381010691300286000684f10a8c100c99710981000383e0018fd10481e1008201019cc10ec1000388a2018fe00081f0008e00008dd10e88c00f833009810005aa600b8
-- 011:1000380f0018fd10281e1048eb200a63002a8200c9100008ec2018100000fb18db10782c00884e10888620c8ee00fa0f00986020388700081e101a930038ae00082700eb3f0038761010ffff580100897430384e000077481000680f00a8003038275048f740993930d88700a91000084e007856100077781f0028160038a65048275028f74099129048770000ff184960780a0019aa00a8ee00382f00782b10486e0000dd88d46008129098df00d8f7004afe0018730038bd10787610981e1038483018574048f01018d37048e720294f005a7610a8fe0008480018c70088f100883280582f0048a9300850001941a0
-- 012:7afd1028fe0048770008e00088843048583038110068102058cf00381a40d8e58009870069088038de0000dc381600082f00a8590058a530681f0028ef0000c7180f0018b00010bffe098700a84100d8220068a50038fe00007c585d6088834038357038cea0680f00088d1018e0a0280f00198700104444b8870020ffffebf8670068fe0010d7cc48a6a000bb980f00383570480a0058c00048ac20388100d86500e8870018001009970008f30038fe0000dd681100b8825058e000484d1028b000789c2008824058560000bf28a000d88700289440f8a61068fe0010cddd58741000b7580f0098ea2058feb018c000
-- 013:98863048870008b20018160008b000d8870038862000ebe8273018fd1018fe0000cd78a100988520d91000786410380600d88700488350981f00288420480f0020d7dcdd5803d0aa870078641038160000fec8870058fa50f8a61048fd1010ccdd290f00d96ea0198700986600587700d8b52058fc2000d7088700688230f80f0069f70078450058f500c8ed0059fe00c90f00c9100088eb10ba8700880f00580d20007b680d20a810002957706b8700780f0000cd780c307a0f0009db10da0f0000cd681e1000d76a870019ea20da0f00781e10a88160a910008b8700680c3008970048fd107a0f005877009896107a
-- 014:0f00380b4000cc08100018010000bc4888700a100068fe00e896006a0f00081e10181000407b7b7cc7d72e870078096028970010cccc888e80490ba078e600fa100068080088087028100018fe00c90f002c870088078068fe00c98ac00c870008a410681f000077083d2000cc18ee00a80f00185a013d0f008805a028100028b070cd0f00081000284b3078670028a7001e87000810009903c029870010444f784000181000980100b94100888700e81f00f986102c87000810005901e0bd870048f6007875206e0f00a90ff0e86b40f8e2207a1000a88700784610481000f84e002d87002810008857d099100008ef
-- 015:008c87008f0f007a10003824007ac4209840002992d01ade00ec87007a1000bb87007b8671db0f000000681000000b694600a8806100b038e200f8e2207a100000fe78570008100000f009d7004856000910007c8700d89f0098f8002850004d870058c500f846001910007c8700ba1000ff8700ff87002b87003a7d10fc8700ff1000ff1000ff10008e100069fa503d100010bdbb48c511fbab00591000cab3306c100019870020ddd00d48a000bb73107b10009a2c00ca1000091f00000d882f006d1000a91e10fb2310aa100020bdddbb88e151281000a8f0005a4d0089100009fe005ae90038e200103330b84000
-- 016:3a4100000fa8eb0028ed8028de0000bdaec582ca1000db1f00c8100000db09fd1029100038a6a0100333b840004a4100e84bb100b55810000aa700bc100008fd100a2f0000eb89a5b00a1000b80f0068de000a3f008c770008100070bddb5ddd5bdddb5dff1d205910001b7c20584100c8fc2008b51010bdb508de0030ddb5ddd5f995205c9700005b281000005548100018c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP2>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <PATTERNS>
-- 000:1d82f1b3826657e6364796f6e68292a0c6f63616c6023796e6c236f637d3d6164786e218d000289000082100480200f0142545f52514d4c2241434b44425f405b8d000422495455435d303870383030303c203871313136343c21313532303a0355524f595d313237348a400700716c624163756c2088000d03586f647c237b697c266164656b448020058b9000002185100600516c682b692a028020051d3b6a066f6270296d303c243730246f60207f6b656820857005033643403b2965815
-- 001:00c0b596d5a2b6f2f2139256e646a0184000c875001177f627468207922756475727e602075656b608e00000c738800060b21392c3c383020963003016464627786300484400586300002308630010136319730050e616d656144708b20058761020d3b7d7486c001013c248c70008ac000037085b00a0d337472796e676e236861608a600389500109692286c0048670040471626c65608491090e6361647823792c207b248240010b213889e0001261636b64627f60737c2361637472557e6
-- 002:583c10d0d616072416e6b6c23797e636642708990008941080e696c6a034143545d3189000c8cb0040c6f616463408340008422010966658e30080e7d30302478656e602186400408243c20392197500006618800028011078e80028760020b7d7c208101048902000d348552010b22328311000f558311048710008911048a20018641000a018500020c207d3d825102056d3b748601000c2384a10084c107836101013831892203056b523b20816104855100033087510a8b90000b5184500
-- 003:50d5d356a007d308cc10002388c41020372736581b1000b6087d0048960010d213085500482200201647d358770030b2b6a25308ba20483a2038322010b24328610028230018e40010b53208500010b21348c80010164748b8007827004016c2f6c2e6089b00089210a003a0778696c6560216c3d31863007847001036d318a4001016d51879104036c3132383282910684f0008060018e60020e6d3e608900020f6b5e6b8a52028b30008e0102887004016d316b23608f7103056c6375648d5
-- 004:00004638d500084a0000c73890001023d5083130681a104036d2132353c8f50008500020d246d5580500003328ec0018400058082000d3a89b2000f658ab105096c22697475608450048f90018e000299020082d1068cf0030c656e6d3189200008258d50010c296580500186c1000d3587100a0a33757268296b213c296b20833005832008077c286c2f687c2f697d8440018520058d20010b243081f2000d338b000005328e13048122020b796c268140038512018aa0000867899101087d3
-- 005:584b102087c3771852104087d387b282d8fa0020621353082b3008ba1008f900284230984000c84830303707279608e30028cf20a087c297c2c6566647c2267768f4401007d3780a0018f02020e6f647085100382a3048634098c5207800103839102057e60708503010823708e43008d30018d50038b30060f687d382267702082e00607792d2f687d277886400285b10d83b1000a6082f20008698813008303048b010009628b01058d300c89710001658ac000036086f206026e3e343c282
-- 006:2638021028dd2030e7d3131358dc002036478208d410284a002016e646083a0040b277d296d208ca00002718c000b09692c297b2f697b2a6c2e6c2086a2038ed2010c296080920186d1000e6994610188e40002448c04028a6101092a088c960183b4018d150c8b76068c66000d3480d6008b00078c5001056d3c8d54058c9100056a8b91010661608873028b51028e50021c2360296e602960716962737b713c253c273d708931058f51000239887004036a233b2a6083b4010b59628900058
-- 007:ad00280b0060b756b51323d5c208600000332860001043d5085750088000005328e00000632860000073484100008328e0000093186000402303d5d7d7188a0008110010d5e7089080287d5038b54008610078fd5000d338ed50889c005022771696472228180038616018340009916018710038c160b8465030c246374708d100085b0098f58048042008c10000c398710000b2b8678098715028534008050028ec2078a1507002d656d63607978208a40000c228f750183250009258870018
-- 008:210008405018c00008800008a47088c050085920288c50286300009238df4018c5002046e3d308f870c8b50008400000d20823000092181400000258f22000e638bf5028ba80182600087a80185a0028b00010d24628fd7028102098e800003328c800784b2058ff7010275738831068ab20502444258227f668e0401097d308d00050d243d224142568c04010b6971812302097c30328700020e3935349c14070b6d397f29353a22368fb302800a050d696e68213c228e4906844403026c266
-- 009:d308750000b508eb4000d5181230089000089b1020b6d29628aa2000360821500033e8d990903323b236c28216b536d508f05008600000d218b0002092a26608300018ad9098ea904235055414b45425f57584f4d3b7442514455475b414d322462716475677b61622c27514e444081100007708504008e00092b42514b4d322b62716b622c24575142544f47535b494d3224777162746f67737b69622c2a044546594c4084400b2566796c622c2b5222414241402a414741422d5d322a61676
-- 010:1622d7a0354525944454d3b7d616e6d303e27333081120083400006608c00020439373583b8068a71008f800007728c190207786f62899502037c24738d950507716c6b6c24708500008025090c227f61627c216e696d62829203037e3d34338053058d05028db50802226573747f522e2e208c4006892400026498a1010268708637030d387d22608e23060f2f223c2133363180f100801002033d5b2384b109016878203c21343d2479208c1407047f2f243035223a048946098c60000c228
-- 011:c400286b0028f900485b0028e55008730030535223d368de9048e300183200f8e30000c218d800281c101864005052137303c363b883003026c696e6a99300388e00886140282f6040c6966647d308330060e2e28237d3d31318a900a022f566162722f62722229208129008070008f10000d328f1203076f6e62228d51028808018500008730018181038730018a0000883003082b722f5087320002208300010f52618800020d792b508de000082187b1028af000053189230309392524308
-- 012:fd20009228d04018560058e10068e67070e2e222f5770322d5d82700086100087e002898102066c6f608070018b30030a283f282788a7008aa1010a28238f62000b5183f1008070038e00008730050e6929292528348770038590008f100282420e8f700001648e70058d420008218720058eb10007328db7008040008cd00a8b700089d1008360008bd1000133825b028461048e210002638b210002618061008f5001092c228110078ef0018992068560008df9020270203989c504ad880a8
-- 013:4d8020d2370748ac20009718b0002033d5d218190048592078c50001f4655425c4149535d3b7a02797e656b6d3681ce0c0479226962746378247c233c2331809c008530020c2a0f608112098420000a05852002053c233081ae0387ab0183db010230328da407096878282b6a23373180330005308f110c04303c28383b2b65283a233c2820841002093b2b608312018013028bf00002318cf00101333585b4000c218f400005608eb5098270028260000c2080090683d7010b77308f3800043
-- 014:08977060139363c25383d718ed70086e1008f500103303180600006368d5d018090028d27028517010439258010008b16048210068c160009608daf00076089d001063c2085f3008d7f018bb00106303088e00006328041060c2a037c656a71618633098e90058ff00006318ef0008d930005618ff0010530318ff0060339252330303d2182010086900405233a223c2d8c100002388c100386010189d1010c2a018785010f6772987102043c233082a0038864010e343387e0000a0187d0010
-- 015:137308ae801023c208d500006338174018161000432806100023787a1038356028f2001825d01033b2086f00089310083a100092084800405303d28247087100087b300023087701002368e11078101098590068431000131833102063c27318430000c2081f002043c22378d1000053881510005318c100006338b520603656c6c6162737a86e0068530008f700086300101363286300009338250078e10008d7203043c2738318620008b700005318aa00383a0008568040b63786f607a86a
-- 016:00182fa0308393c27328a71008e85000c2084a001882100033c8821028181008440030167756c6f8282008d310101343884e200053384160384e2008ef00087c100043085e20084100008318850020b65223883e20388620784c10083300084c1028f60030e6967686091f2058452048e600106373389600202343b208e000002318855000032815300023282f20003329253058f101004718b3001823202007c32338937038ba2000230838201007a20846102063b20708ef102023036338f0
-- 017:00004328f00078ff1010c2a0588b708025f4d414e4d3b72294082f5000943850002860000065089f703822005054d424c454d4083200286f7008c10028718000c258956008900028d380e890800845f040074756273408e6802082e6c218b020087b1020268223085e10006308e7011043c2083000004328cc108026823313c22393c213081020083000003338131000f5a85fb000b728830008224010231308c2002890000083085a10009348210018a0001853405036962736823618024000
-- 018:3618e0400033082600c8310008e30098f3504147f607c2479647c656d3c482223484140545542502085d00b025f4a544a594145c18022292080060287210082df038f5704882000035081100183a1048ae0000e4087b5000820815f0480e5028650038c910a85600204584540806001045f408840008e0002054e44408e00060b4f4e49454342228f91008406020e6478218330080132303d2475687477538e000009218c06008c240003308514108607008ac00188fa00839d0381300180600
-- 019:28cdf008810018094098f30018c100088f00081400083eb010437308033038340008e540fa340020c24363081f20b81400888601008238132038d21068d9a0085410381a806880e0182170b8a38028b170086d11188a7058a050a88ef018f800186e5028fd9010034308c000088cd0289800c8c2216094259435d33363d8392000960807401853513871006027d3b6a213530328d6201097d308b2a0082b5000531833a07893d05046d397d26383385e31088b8080162637824692e3d32788a7
-- 020:f00003083ea02813402800407822d00086481361a01727478227a227d246a24608d310001328603028530018dc00008628730028310008f00010b286587100086a1038050079c9f0705667562797826687084221705607c2f66666c26628cb60080a0108d00040d26687925218a10000d228f100181a001890001808402066828768c5d0d80ff02016d60708e100384a000087184d401033c2081970482a001087d20884802023c293082000682100081920004308fa500053088630195a0010
-- 021:26c6085cc00037186a00004708a70100a0684b0008240000c2681250081700583310501303b28287a208a1501093a0087411083800181360008708cd70388000001348dd6008b210008718ed6008610008341018950010e6469808009064f425547425f455e444187190d8c77008b110689800001308a860084180189f0038c260c8317018ab000092986c0008649068c300089300083210888c0028b640385b00087370000348010010b213181f712083c2833838903886000857b000463a76
-- 022:00087580089c50a88600480a10085390081e40880a1008f350085f500023182f8078a600c8ef6028b60068d5000073599810086960008708f95130521313a028a56058b8104818100053981810680800680a1068f100004308f1000033181380780900c8f17098e810004308f390b8090048ae00088100007338a8204835101033c218ff5078110000d20863800043187610886710086a40084200888810089a8008b78098c800f85b6050c6f63756550748dbe028c6b0380ab010b7b7383100
-- 023:001308db6038600018ba00004328320010d7d778b720585af01005c4084af038d5f08044941424545c1822c2084bf08074f4e4d32235d4f4b408e0000849f02064d322087af03035e414c408047060742514659445950885f008ec6048f400707594453484f514c23880003024d3b713081d00089370001308929030d203e2832843b08831005033e213431363084bf0203454e40887a180b7a07727f636c6167708a00040b72646d32218efb00022085b0020e6d32308eeb00007082df00831
-- 024:102036160708fd70607525f434c4147508e86018a000105c1808b00020d7d7c238730028a5c048830008b820188300089f902016364708453158818018381020130383187a1018700008d00010930308e90058f10000230813001881000840f028800008f70018143038146000d768a60028ea2038a60018a20038b900d0d45414e4758494c454c20294e402189d0100f4188a00a04595d434a5143554d402754851002094542208940048890060378656560722c2083e5018d260688000188b
-- 025:108023c286964656d39353281a00489c8010d28308c04008e8b028ada02820b0080a000013189900d8b400183200186ca0088aa0283c00081aa0007718d400190310186c0039921008cdb048921000032892101007f6083a50002738020008880008f10008600038a6b008c471180b002013032328f80058a200080200109383486000187d0008138118a80018720000d708b0001016b6683300d8590008153048590058c40018310018a42058800028721008740020c6162608f34020b71343
-- 026:08af505023c22213f223297120887e0069e90048d61048ea21581120780320081100d8f020482600306687d32208101048bb20084b5018b60058ca30884500301313039268a42048a3c0480a00080b1058781068f20048b820487000084a00182a000037080a6108a40018671018fa2048800028d10088a02018fb2018b1004880003855205037071627b6d308a60038e5200063087c003026f6f6d608bdc110b71318a370083320084100f81a0018fd004037f6f64722998d0008c960001618
-- 027:4c61002258bf3108203001e2e2e2c6563737023757c60786572702e608ca900897a0083b0138d10000e6089831114c9907e697d6022716a756d602d6e69656a6083de1088a001096e2089c1058c800285950481e3008f720181e3008ad00481310002708ec0018892008ce20480230182be02859600013284c3100d3b85b1078564018f570e86710180e200073085f1038700028824038c12048c51000d208d55008910000930811e078f10068d500086270180a10586c203875b0186a300830
-- 028:0038db7048be4018267078c920483b403805400838b0089fc07014440235f455458408b210085371b0741402e4140205f45c18554408d8b0888440b8ab00b8512028ec40c8cb0018a10018095088120068eb0068370148c610082c00a8a90000d4085b8050450235c454a518fd10705ca9c44c895cbb1478273038e411789a10483a002066f68708c70028c82008eed0088c4018800008f510185920781a10180c2009dc00287300083b00282d10a8cc0018ae00084000186140781200b8cc00
-- 029:785160381c0040b4550514c408b4103094748445082c0030e4f43402183100205c189508251030d61676960873e1082f30183a00085f0010838378761070779647368622c25318141008ef40387000388530683c0060c2f627269647d348617018ca00486300188321285e504880009983000024289010386ce0488a1068fa1018630038adc0887310086600383571380060082110488000380300b8df20886110085e00c8b86018c550186a0048800098634039951018066009631008a00000
-- 030:d758c500f9c90018fe002ae510287b401063236b6610190400cae6103844000083085b60a8ca2028131048f12118a3000043a8e85008f84008e240388a202880a018ba2010c216083a0228350048161048b50038a300282d0030f566c69728411008364018ed400821300083188b3158a31038f47038d80088130018ff00082300003328eaa0681300389c00682300485f00382300082f0008130018993028224108330018af11c8330088d26008ac0028fe10e84120a8026058af1018705018
-- 031:68f000c24812602880a1185c112002861608b4f0208656d618f0605044165c28162608a0604037f626965608016020464c9998306048260018c8603066c6163708fe10a8d600382c1018be0038c60058e8607823a108199068b5a11002370831b04037028696370862f000760861001037120802002005f6a708afd190779656e6961602f64602780300305676f61288c800295e5018551008300048fcd0486e508803a0589b6068d4506892a0189000103c39880da0384400b848501832f038
-- 032:339078af6098b1a0087500182f1018e25008700018d600888d50987ba0a8a68028f300282f5228d37018700038a590786540002318253018dd20488000c8ab3088608018f8512834b0f89200784640184ec0180200286e3028ca6199c030d82c0028ff102096275638ef10884c0018687008f73048700058e1a088498008bdc008b610f0a226572707a20235079636971202758608cd327056e6470297f657f328e1004056b6a202f408421250561202b447f60814916037020727a7973708c9
-- 033:20205c28f3792980382d1000c418432158c56080a55435a55c1854a40208566018e560680b7038dcc168434048800068fd602056767618dc80186210002308eb0108700048cc80e8d70059c0309834d178e73058c01078d6d11831300086088af1181900300286f6c608213010d69708aa02403647e20224185f911096471871301044960846b0105c28084621e002d63c3ba602369727f676271666e20874102016c63608da300ae130003338e13058487148f13048b2002816a00047189451
-- 034:48251068b5d0089a0080e40245f4028454c4c4284510d0a45ca93494540244f402059454b40870e069a090103393384cb028705008a000c8b38008b5100023085fa008be82188550102363280200483f2018449118535028c6c00871f1380200681e00485c00780a30787b902845f03072350234080b0020142535185540087a00909454c4e45402c4f4348409902000231808111890204880009887603875d000333880e099f20078f06008e20000c2181981181710781d0048549048dcc018
-- 035:8d00003338efe0f80790587590684200c8c3a0580790481200396110185a4038fa4008900068836008d02118af90287500184a0118f0700053288a301a311038087008bd0098e940482d00686ad068c310d8d940687d00680ef028c1f0480e70480840989a405875a038380028030009de0059483048ac00f8f73028222008812010140208fa101056d60832109027f30214761696e637470859221878402135a7567736a797b6f3020527a756369677b6f628a1d098084068180028a3101949
-- 036:d020030392186581781d0018beb0185d00488000989320583e90195cd05094022627f657081740081b0008940018ca700879003097e696f6086150084bd020f67736080dd0c9ff3008902118ff300867700815b158ef30b82320782af0c85b2008f39038cd10384a30f83b200063981200086f1098005000d25887a0586650485400f99620382d01189b00683410387fd030139313c20864a018f270086c6059db6058b300c8a600184a70185a6008703038150178e30038c1111869f000a068
-- 037:233038b60018c40039b72028463078d07048c600484e20588000c8f330282600c8e82000d4388f50301202e4f6081000186f5000d498be500881003096565656986e50484860b848f028a9c108411008387008ed70188880d858f03978608094477237021757965608a91110025728a7020027285201804516d602264c9946a7086660003708a94210f6a618220198f620208616c6083f0048780038f442380cc018bc40a8a311c87520006338114018f810c8c24078c041586120285a805812
-- 038:40003608d020003708571018354018c2b008f72008b72120137353085e1008d460d82d100073089731686f0018be90087d001095f608e011102756188a2018c610404577f6a61608f9a1407627f646160856100856005852b0208416c60897f1086a70182e323046f6d6c208c78218e110287830103c3b08797030b6273c3b086611085f2050c202f6a636a718d830180d0048b600681400387b001806403883003037562716092d8058269028ff11483e6038fcc0c8c31178f3e08863700822
-- 039:3008755038911158c701e8b51108003098220078063048b511087710880200596e51b86b4128a720008358700048545108de20182861684e5118573028813098e26068813008667088237048a40078ff31791370c83200e8037068e81198f27088725018ec0038725018b89218eb1018300038527130f5f464f5480dd108368048f271084c1048f0d068b2c068714058438138e30050d4f4f444d3b7389721002208710020d622c2481ac040224756e6370845811022c2584990782100487a50
-- 040:3022a6f69768050050373656e656c258e1b228cd20582c425025541444f564082e92405435c2641408c8722856705829825837811034f4184781588182003348f08200433890820043984082201333c238c9810023c83f720063584a81002348f981101323e8329118464118a6b278123300d328bb0040a037e2e6d30840000892a2488100008608f000087c00204737b5087100788f420086483e2288a4c258af2328f4c248dd2308959270d657379636d4f6f60814023096c692a028760028
-- 041:09133037e2166608ac4008380088f172b8b31000d3a8dbc2503786e226469228060048d9000835f10898d2389602001678960218a200089f2008471210b7d728082318820068e38218e00030c216b57338b97218ed0020c237e2083c0000e21842b1487000004508800008c6b00027287100205616670831e20832b1180dd10838d100f608e01338c523a8faa2182b00c896d248e21048a11048d6c220e6964708b1101056470811f128b8d218b1007883338838d24887d2388fb26890436862
-- 042:f148d5002838f138e322682d2348f10028441000e728ff6238c70058e510b8851038ca0038171058220000e718d4e0086fc228817218040008d900c89d1048560068450028fc50a873c20878f100a218f56089655398104358a400b8751018d4f20035098203c85203096802091a727839e2b97a7248260069b9c218db80680410298e1098318298c06338761088c230d80330a886004007c6169735182330389a0028133008f600a8342018e0001064f608bf123907208d2620089700401457
-- 043:4696f608a700387d3000b728a24000d3389bc13898100846e2086860188b0000d328600000d788114078e75038c2001092a088894008f73008a81300222895000022b8611008cd3010f627086253001618294248bf23189dd10829125003c28713c29708bf2208d26008a4b10036289c10b8f023085913187a7220c38216189d402870231003920850001047e30846a200e218ad1018310028f24040865776569239aac230f6d316e228325118d40000f6988fc208ad5210f2f61860b29063e2
-- 044:238333b2f6b543d5589420186a0000f6189e8208a78308a65310a2f618dc421097032827f108f0000063081b0018c70008f46128110000e30884f138a7d038ff0308a15338020048a6001076d348f6e130a23736f258510050b6d34713e3473887628823d2881fe2908247d2470392f2824713188000009218cf0028092328b21018b95048de1018f000408713c38703887f0008e73010d387181e126013d2870392a2b618eb0040829713d29718d0001854001016e208ad9038140000970897
-- 045:321076a2487600b0e523a2b6a28213d2b692f22328050028c20008258098b3103045d323a27827321023a228120010f276585e101843723045f245a0189500004338d10010a207185500081e33888440685be238ef1020c2b6e338e01010b6c32846d27870420087184c0048d510d8a943289611588f7248a54208e80218177338d41228434208f31108ee32488173086b3200972886820092086f4028c100088d725818a218190008400010b27318f2005816305076c6f677822318bbd008b5
-- 046:2218c0c0183832a8510028696188a2a218723388b8100053081e8200a20803221826b200a208cd7328c300089100086e32101313789592186a92385812084b000868120013087600488e22009708ff320804002848b218e0000895f20804920863003879b208381228320048cc927857921862738898000868521063d218ea12189800005378e6002864321003d238521078901000b20840c0084100086282288b108806a238bbe128630038c13258970098c903383150d8cb80a82b80089d70
-- 047:08f62310e24768ac8028e00048c0001805a008428008700018f43048be7020b2630358b63308ac1008f10008156138d14038492038d3301047f218177318506258f600180c1108e20028900028f40008c1f20087085bf23867e018172058850010469708920018620038e17298d00000c328c00008380028f00028283208345210a2230896003898e23036c637823816c2781770383a7028c63039ad7038239068e08038890038981138670048244318d500282e10380103893d70184d7020b2
-- 048:4697182e20f98d7008b40058ade200b528b800282df2d84100085630d82a0068a5d028030068f00018a200382a00684610380151385682583b3078fc3010c6d318661038fd10389510088a1010169788b000086da018692000d558522008086000d308704308020020c482c618e95000c608ac50589620180223088c603802004892a008538010c33218730028510088fd3310b5c6089e5000d548d9a00026b8d9a028ab0158f9a028e86010d3d3183e23388c0040e64654870708ca21281ce3
-- 049:48b110088c00181200386b1028e0330829d328f200085520104697384b520822e2382320881c70b86f1038f7f21057660879f210d28388921028b13100d328d660282b00300716373708be43285973d9f5b098287088675020d6f6671842431818e0a80b7038b60028600028e2303036d3d34348ae23183410008228b70030d32392d318e870282670082ca008496018bf002097e31618f810282360b84a4310d23618d550004628f70048ba4348180028243338ab1008d79078162028f01100
-- 050:e268eb4318d00028b92158d93078110038582010573708cb40087600885a930033081c0000d20826b218970010d28218ac0038166000131891003002236392186a72387810a88c3348f72078b800389c1028d100006408010028860058fc0068550038a18038250048400068d593b92620000218e00008a9631013d518850018694318b5000047286553581a0088f69248893058313338ba10283a00f852002082368708af50084720080790887c3028fee148934018b00018390028900000c2
-- 051:08180098920028a94248371008da23380a20289cc258d10018e8b068c00018497358c00008d930c830d2c83f2028e83268c3e328861328097028d960109323183bf20033087aa218a1130083280cf228002318f27000c208df1358cbf228b583584b70b8e74028ec4238cb000033484f135869c2004328780310522308378358d7002857b02830700013089b11189e821073632890a010b6a208297340835392a22708f69210434328cc30b8410028d700281b7048b300002768197038f80088
-- 052:8ae2983bf258a10088371038fce0482c4018c4d23863002865d248d10000f218a7d24899d0288ec23862231830904862a2186a1128997388910048a800086e9198a010185f9100c418880008900048eb1018a000088173480be208e00049eae208a1004803f2180e22c803f2c8fc0028270068baf038800000d2285da02850e0889e0058a6d058ce0018b811c8d11000c3588a4378e8c078e5a038d880485400a8818028a40058b2601046f60819803821101817605876c388f860583b001854
-- 053:60183b0018800008da8038611018d76008e2107898a238e460009218b01010139368810008e22138910018dc23392503083c00480610781b60187400288b4418a5b2b8630038601018820018016338a740e8ae60387a608066878283c22234d26308854108333038223078040000e328c20020a223b2889f2108b43018971028f10008ee3018d500602647e607824392384d50b848114861100828a01003a018051048010010e332385510385050482b8038640048540018be90285610683200
-- 054:38040008e710383f90008228d64098f700581520188200980c2000e608018088103108639308060018e42000d308a10038638310874738563088082028f62018d10018a43018044018c120989003009208dba000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </PATTERNS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

