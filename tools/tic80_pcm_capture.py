#!/usr/bin/env python3
"""tic80_pcm_capture.py -- give v32lua the music a cart synthesizes itself.

Some TIC-80 carts mix their music in Lua, every frame, into a PCM buffer in RAM
(BlasTIC: updateMusic() writes 128 signed samples a frame at 7680 Hz to 0x14E24).
The SPU plays only sounds that are in the cartridge, so there is nothing to stream
that buffer to -- and the synth takes ~8 frames of CPU for each frame of sound.
This tool renders the music OFFLINE, one standalone sound per "event", and writes
hooks that play those sounds when the cart starts the music. The cart is not edited.

  tic80_pcm_capture.py blastic.lua -o pcm/ \\
        --mixer updateMusic --pcm 0x14E24,128 --rate 7680 \\
        --music-fn startSong --sfx-fn sndExplosion --setup 'loadSamples()' \\
        --event 'startSong(1,false)'  --event 'startSong(2,true)' ... \\
        --event 'startSong(1~,true,MOODS.calm)' --event 'sndExplosion()'

Output (in the -o directory): <stem>_pcm.lua (the hooks and the --#sound lines),
<stem>_pcm_NN.vsnd (one sound per event) and <stem>_pcm_main.lua, a two-line file that
includes the cart and the hooks. Compile the _main file (v32lua --api tic80 ...).

--event CALL   a call of the music function (or the sfx function) with literal
               arguments (nil, true, false, numbers, strings, or global expressions
               such as MOODS.calm). An argument written N~ (1~) is a wildcard: captured
               with N, matches any value at run time. One sound is rendered per event.
--mixer NAME   the cart's per-frame synth function (called once per 128 samples; the
               compiler replaces it with the hook that plays the sounds).
--pcm ADDR,N   where the mixer leaves its N samples (unsigned bytes, 128 = silence).
--music-fn     a function that starts a song. A song calls it again (the next song, or
               the same one to loop): the tool records those nested calls and when they
               happen, and the run-time plays the follow-up at the same point of the
               sound, overlapping, as the synth did. A game call (not a follow-up)
               fades the music that is playing out over --fade seconds.
--sfx-fn       a one-shot function: its sound just plays over the music.
--setup CODE   statements run before every event (loadSamples() ...).
--upsample K   store K times the cart's rate, linear interpolation (default 2).
--fade SEC     fade-out of music a game call interrupts (default 1.0).
Needs v32lua, assemble and v32orun in PATH; numpy.
"""
import argparse, os, re, struct, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
import numpy as np

MARK = 0.0  # unused


def split_args(text):
    """'f(a, b(c), "x,y")' -> ('f', ['a', 'b(c)', '"x,y"'])"""
    m = re.match(r'\s*([A-Za-z_][\w.]*)\s*\((.*)\)\s*$', text, re.S)
    if not m:
        sys.exit("tic80_pcm_capture: cannot read event %r (want name(args))" % text)
    name, body = m.group(1), m.group(2)
    args, depth, cur, q = [], 0, "", None
    for ch in body:
        if q:
            cur += ch
            if ch == q:
                q = None
        elif ch in "\"'":
            q = ch; cur += ch
        elif ch in "([{":
            depth += 1; cur += ch
        elif ch in ")]}":
            depth -= 1; cur += ch
        elif ch == "," and depth == 0:
            args.append(cur.strip()); cur = ""
        else:
            cur += ch
    if cur.strip() or args:
        args.append(cur.strip())
    return name, args


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def lua_match(fn, events):
    """Lua source of __pcm_match_<fn>(a1..aP) -> event number or 0."""
    P = max(len(a) for (_, f, a) in events if f == fn)
    params = ",".join("a%d" % (i + 1) for i in range(P))
    out = ["function __pcm_match_%s(%s)" % (fn, params)]
    for (n, f, args) in events:
        if f != fn:
            continue
        conds = []
        for i, a in enumerate(args):
            if re.fullmatch(r'-?\d+~', a):
                continue
            conds.append("a%d==%s" % (i + 1, a))
        # missing trailing arguments mean nil
        for i in range(len(args), P):
            conds.append("a%d==nil" % (i + 1))
        out.append("  if %s then return %d end" % (" and ".join(conds) or "true", n))
    out.append("  return 0\nend")
    return "\n".join(out), P


def capture(a, cart_text, ev, work):
    n, fn, args = ev
    call_text = "%s(%s)" % (fn, ",".join(re.sub(r'~$', '', x) for x in args))
    ptxt, _ = a.matchsrc[fn]
    addr, cnt = a.pcm
    code = re.sub(r'^function\s+TIC\s*\(', 'function __cart_TIC(', cart_text, count=1, flags=re.M)
    code += """

--#hook-fn %(fn)s=__pcm_rec
%(match)s
__pcm_first = true
function __pcm_rec(%(params)s)
  if __pcm_first then __pcm_first = false return false end
  ioports.spu.volume = __pcm_match_%(fn)s(%(params)s)   -- a nested call: note when, skip it
  return true
end
local __c_n, __c_seen, __c_sil = 0, false, 0
function TIC()
  if __c_n == 0 then
    %(setup)s
    %(call)s
  end
  %(mixer)s()
  local quiet = true
  for i = 0, %(cnt)d - 1 do
    local v = peek(%(addr)d + i)
    ioports.spu.channel = v
    if v ~= 128 then quiet = false end
  end
  if quiet then __c_sil = __c_sil + 1 else __c_sil = 0 __c_seen = true end
  __c_n = __c_n + 1
  if (__c_seen and __c_sil >= %(sil)d) or (not __c_seen and __c_n > %(sil)d) or __c_n >= %(maxn)d then exit() end
end
""" % dict(fn=fn, match=ptxt, params=",".join("a%d" % (i + 1) for i in range(a.matchsrc[fn][1])),
           setup=a.setup, call=call_text, mixer=a.mixer, cnt=cnt, addr=addr, sil=a.silence_frames,
           maxn=int(a.max_seconds * a.rate / cnt))
    # the parameters of the music function must match the hook's
    base = os.path.join(work, "ev%02d" % n)
    src = base + ".lua"
    open(src, "w").write(code)
    r = run([a.v32lua, "--api", "tic80", "--no-build-scripts", src, "-o", base + ".asm"])
    if r.returncode != 0:
        sys.exit("tic80_pcm_capture: compile of event %d failed:\n%s%s" % (n, r.stdout[-2000:], r.stderr[-2000:]))
    r = run(["assemble", base + ".asm", "-o", base + ".vbin", "-g", "program"])
    if r.returncode != 0:
        sys.exit("tic80_pcm_capture: assemble failed:\n%s%s" % (r.stdout[-1500:], r.stderr[-1500:]))
    r = run(["v32orun", base + ".vbin", "-f", str(int(a.max_seconds * 60 * 14)), "-s", "-q"])
    samples, marks = [], []
    for line in r.stdout.splitlines():
        m = re.match(r'F\d+ SPU SelectedChannel = (-?\d+)', line)
        if m:
            samples.append(int(m.group(1)))
            continue
        m = re.match(r'F\d+ SPU GlobalVolume = ([\d.e+-]+)', line)
        if m and float(m.group(1)) > 0:
            marks.append((len(samples), int(float(m.group(1)))))
    # a skipped call returns nil, so `a and f(x) or f(y)` calls both: keep the first
    # call of each instant (the one the cart's own run would have made)
    uniq = []
    for m in marks:
        if not uniq or uniq[-1][0] != m[0]:
            uniq.append(m)
    marks = uniq
    if not samples:
        sys.exit("tic80_pcm_capture: event %d (%s) produced no samples:\n%s" % (n, call_text, r.stdout[-800:]))
    x = np.array(samples, dtype=np.int16) - 128
    nz = np.nonzero(x)[0]
    end = int(nz[-1]) + 1 if len(nz) else 1
    x = x[:end]
    print("event %2d %-34s %7d samples (%.1f s), %d follow-up(s)%s" % (
        n, call_text, len(x), len(x) / a.rate, len(marks), "".join(" @%d->%d" % m for m in marks)), flush=True)
    return x, marks


def write_vsnd(path, x, rate, up):
    y = x.astype(np.float64)
    if up > 1:
        t = np.arange(len(y) * up) / up
        y = np.interp(t, np.arange(len(y)), y)
    v = np.clip(np.rint(y * 256.0), -32768, 32767).astype("<i2")
    st = np.empty(len(v) * 2, dtype="<i2")
    st[0::2] = v; st[1::2] = v
    with open(path, "wb") as f:
        f.write(b"V32-VSND"); f.write(struct.pack("<I", len(v))); f.write(st.tobytes())
    return len(v)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cart")
    ap.add_argument("-o", "--outdir", required=True)
    ap.add_argument("--mixer", required=True)
    ap.add_argument("--pcm", required=True)
    ap.add_argument("--rate", type=int, required=True)
    ap.add_argument("--music-fn", action="append", default=[])
    ap.add_argument("--sfx-fn", action="append", default=[])
    ap.add_argument("--event", action="append", default=[])
    ap.add_argument("--setup", default="")
    ap.add_argument("--upsample", type=int, default=2)
    ap.add_argument("--fade", type=float, default=1.0)
    ap.add_argument("--max-seconds", type=float, default=130.0)
    ap.add_argument("--silence-frames", type=int, default=60)
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    ap.add_argument("--v32lua", default="v32lua")
    a = ap.parse_args()
    ad, cn = a.pcm.split(",")
    a.pcm = (int(ad, 0), int(cn, 0))
    cart_text = open(a.cart).read()
    events = []
    for i, e in enumerate(a.event):
        fn, args = split_args(e)
        if fn not in a.music_fn + a.sfx_fn:
            sys.exit("tic80_pcm_capture: %s is neither --music-fn nor --sfx-fn" % fn)
        events.append((i + 1, fn, args))
    if not events:
        sys.exit("tic80_pcm_capture: no --event")
    a.matchsrc = {}
    for fn in sorted(set(f for (_, f, _) in events)):
        a.matchsrc[fn] = lua_match(fn, events)
    os.makedirs(a.outdir, exist_ok=True)
    stem = os.path.splitext(os.path.basename(a.cart))[0]
    work = tempfile.mkdtemp(prefix="pcmcap")
    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        results = list(ex.map(lambda ev: capture(a, cart_text, ev, work), events))

    # ---- sounds ------------------------------------------------------------
    names, lengths = [], []
    for (n, fn, args), (x, marks) in zip(events, results):
        fname = "%s_pcm_%02d.vsnd" % (stem, n)
        lengths.append(write_vsnd(os.path.join(a.outdir, fname), x, a.rate, a.upsample))
        names.append(fname)
    speed = a.rate * a.upsample / 44100.0

    # ---- hooks -------------------------------------------------------------
    L = ["-- generated by tools/tic80_pcm_capture.py: plays the music the cart synthesizes",
         "-- itself from sounds rendered offline. Do not edit; regenerate."]
    for i, f in enumerate(names):
        L.append('--#sound PCM_%d "%s"' % (i + 1, f))
    L.append("--#hook-fn %s=__pcm_tick" % a.mixer)
    for fn in a.matchsrc:
        L.append("--#hook-fn %s=__pcm_hook_%s" % (fn, fn))
    L.append("__pcm_ids = {%s}" % ", ".join("PCM_%d" % (i + 1) for i in range(len(names))))
    fu = []
    for (x, marks) in results:
        fu.append("{%s}" % ", ".join("{%d, %d}" % (off * a.upsample, e) for off, e in marks))
    L.append("__pcm_fu = {%s}" % ", ".join(fu))
    L.append("__pcm_music = {%s}" % ", ".join("true" if f in a.music_fn else "false" for (_, f, _) in events))
    L.append("__pcm_live = {}")
    L.append("__pcm_nmus = 0")
    L.append("__pcm_nsfx = 0")
    L.append("__pcm_internal = false")
    for fn, (txt, P) in a.matchsrc.items():
        L.append(txt)
    # event -> call with its own arguments (used for follow-ups that start another event)
    L.append("function __pcm_call(e)")
    for (n, fn, args) in events:
        if fn in a.music_fn:
            L.append("  if e == %d then %s(%s) return end" % (n, fn, ",".join(re.sub(r'~$', '', x) for x in args)))
    L.append("end")
    P = max([p for (_, p) in a.matchsrc.values()] + [1])
    L.append("""function __pcm_start(e, a1, a2, a3)
  local music = __pcm_music[e]
  if music and not __pcm_internal then
    for _, r in ipairs(__pcm_live) do
      if r.music and not r.fading then r.fading = true r.fleft = %(fade)d end
    end
  end
  local ch
  if music then ch = 8 + __pcm_nmus %% 4 __pcm_nmus = __pcm_nmus + 1
  else ch = 12 + __pcm_nsfx %% 4 __pcm_nsfx = __pcm_nsfx + 1 end
  for i = #__pcm_live, 1, -1 do
    if __pcm_live[i].ch == ch then table.remove(__pcm_live, i) end
  end
  ioports.spu.channel = ch
  ioports.spu.cmd("stop")
  ioports.spu.chansound = __pcm_ids[e]
  ioports.spu.chanvolume = 1.0
  ioports.spu.chanspeed = %(speed).8f
  ioports.spu.cmd("play")
  ioports.spu.chanloop = false
  __pcm_live[#__pcm_live + 1] = {ch = ch, e = e, music = music, fi = 1, fading = false, fleft = 0, a1 = a1, a2 = a2, a3 = a3}
end""" % dict(fade=max(1, int(a.fade * 60)), speed=speed))
    for fn in a.matchsrc:
        params = ",".join("a%d" % (i + 1) for i in range(a.matchsrc[fn][1]))
        L.append("""function __pcm_hook_%(fn)s(%(p)s)
  local e = __pcm_match_%(fn)s(%(p)s)
  if e > 0 then __pcm_start(e, %(x)s) end
  return false
end""" % dict(fn=fn, p=params, x=", ".join(["a%d" % (j + 1) if j < a.matchsrc[fn][1] else "nil" for j in range(3)])))
    L.append("""function __pcm_tick()
  local i = 1
  while i <= #__pcm_live do
    local r = __pcm_live[i]
    ioports.spu.channel = r.ch
    if ioports.spu.state ~= 0x42 then
      table.remove(__pcm_live, i)
    else
      local pos = ioports.spu.chanpos
      if r.fading then
        r.fleft = r.fleft - 1
        if r.fleft <= 0 then
          ioports.spu.cmd("stop")
          table.remove(__pcm_live, i)
          i = i - 1
        else
          ioports.spu.chanvolume = r.fleft / %(fade)d
        end
      end
      local fu = __pcm_fu[r.e]
      while not r.fading and r.fi <= #fu and pos >= fu[r.fi][1] do
        local ev = fu[r.fi]
        r.fi = r.fi + 1
        __pcm_internal = true
        if ev[2] == r.e then
          %(self)s
        else
          __pcm_call(ev[2])
        end
        __pcm_internal = false
        ioports.spu.channel = r.ch
      end
      i = i + 1
    end
  end
  return true
end""" % dict(fade=max(1, int(a.fade * 60)),
              self="\n          ".join("if r.e == %d then %s(%s) end" % (n, fn, ",".join("r.a%d" % (j + 1) for j in range(len(args))))
                                       for (n, fn, args) in events if fn in a.music_fn)))
    hooks = os.path.join(a.outdir, "%s_pcm.lua" % stem)
    open(hooks, "w").write("\n".join(L) + "\n")
    main_lua = os.path.join(a.outdir, "%s_pcm_main.lua" % stem)
    rel = os.path.relpath(os.path.abspath(a.cart), os.path.abspath(a.outdir))
    open(main_lua, "w").write('--#include "%s"\n--#include "%s_pcm.lua"\n' % (rel, stem))
    tot = sum(lengths) * 4
    print("wrote %s, %s and %d sounds (%.1f MB)" % (hooks, main_lua, len(names), tot / 1e6))


if __name__ == "__main__":
    main()
