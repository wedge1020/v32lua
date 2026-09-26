#!/usr/bin/env python3
# spu_render.py prog.run prog.xml out.wav [first_frame [last_frame]]
#
# Rebuilds the audio a cart produced from a v32run -s log: every SPU port
# write of a frame is applied, then that frame's 735 samples are mixed the
# way the Vircon32 SPU does it (nearest sample, per-channel speed and
# volume, per-sound loop points, global volume, clamp). Sounds are read
# from the .vsnd files listed in the cartridge XML (in order: sound id 0
# first). The result is a 44.1 kHz stereo WAV -- for listening to, or for
# checking that sounds start and join where they should.
import re, struct, sys, wave
import numpy as np

run, xml, out = sys.argv[1], sys.argv[2], sys.argv[3]
first = int(sys.argv[4]) if len(sys.argv) > 4 else 0
last = int(sys.argv[5]) if len(sys.argv) > 5 else None

import os
base = os.path.dirname(os.path.abspath(xml))
paths = re.findall(r'<sound path="([^"]+)"', open(xml).read())
sounds = []
for p in paths:
    d = open(os.path.join(base, p), 'rb').read()
    assert d[:8] == b'V32-VSND', p
    n = struct.unpack('<I', d[8:12])[0]
    s = np.frombuffer(d[12:12 + n * 4], dtype='<i2').reshape(-1, 2).astype(np.float64)
    sounds.append({'s': s, 'loop': False, 'ls': 0, 'le': len(s) - 1})

chans = [{'sound': -1, 'state': 'stop', 'pos': 0.0, 'speed': 1.0, 'vol': 1.0, 'loop': False} for _ in range(16)]
gvol = 1.0
sel_s, sel_c = -1, 0
events = {}
pat = re.compile(r'F(\d+) SPU (\w+) = (\S+)')
for line in open(run):
    m = pat.match(line)
    if m:
        events.setdefault(int(m.group(1)), []).append((m.group(2), m.group(3)))
end = max(events) + 1 if events else 0
if last is not None: end = last + 1

outbuf = []
for f in range(0, end):
    for name, val in events.get(f, []):
        fv = float(val); iv = int(fv) if name not in ('GlobalVolume', 'ChannelVolume', 'ChannelSpeed') else 0
        c = chans[sel_c]
        if name == 'GlobalVolume': gvol = min(max(fv, 0), 2)
        elif name == 'SelectedSound': sel_s = iv
        elif name == 'SelectedChannel': sel_c = iv
        elif name == 'SoundPlayWithLoop' and 0 <= sel_s < len(sounds): sounds[sel_s]['loop'] = iv != 0
        elif name == 'SoundLoopStart' and 0 <= sel_s < len(sounds):
            snd = sounds[sel_s]; snd['ls'] = min(max(iv, 0), len(snd['s']) - 1); snd['ls'] = min(snd['ls'], snd['le'])
        elif name == 'SoundLoopEnd' and 0 <= sel_s < len(sounds):
            snd = sounds[sel_s]; snd['le'] = min(max(iv, 0), len(snd['s']) - 1); snd['le'] = max(snd['le'], snd['ls'])
        elif name == 'ChannelAssignedSound': c['sound'] = iv
        elif name == 'ChannelVolume': c['vol'] = min(max(fv, 0), 8)
        elif name == 'ChannelSpeed': c['speed'] = min(max(fv, 0), 128)
        elif name == 'ChannelLoopEnabled': c['loop'] = iv != 0
        elif name == 'ChannelPosition' and 0 <= c['sound'] < len(sounds):
            c['pos'] = float(min(max(iv, 0), len(sounds[c['sound']]['s']) - 1))
        elif name == 'Command':
            if iv == 0x30:            # play (retrigger if playing)
                if c['state'] != 'pause' and 0 <= c['sound'] < len(sounds):
                    c['loop'] = sounds[c['sound']]['loop']; c['pos'] = 0.0
                c['state'] = 'play'
            elif iv == 0x31 and c['state'] == 'play': c['state'] = 'pause'
            elif iv == 0x32: c['state'] = 'stop'; c['pos'] = 0.0
            elif iv == 0x33:
                for x in chans:
                    if x['state'] == 'play': x['state'] = 'pause'
            elif iv == 0x34:
                for x in chans:
                    if x['state'] == 'pause': x['state'] = 'play'
            elif iv == 0x35:
                for x in chans: x['state'] = 'stop'; x['pos'] = 0.0
    buf = np.zeros((735, 2))
    for c in chans:
        if c['state'] != 'play' or not (0 <= c['sound'] < len(sounds)): continue
        snd = sounds[c['sound']]; s = snd['s']
        for i in range(735):
            buf[i] += s[int(c['pos'])] * c['vol']
            prev = c['pos']; c['pos'] += c['speed']
            if c['loop'] and snd['le'] > snd['ls'] and prev <= snd['le'] < c['pos']:
                c['pos'] = snd['ls'] + ((c['pos'] - snd['ls']) % (snd['le'] - snd['ls']))
            if c['pos'] > len(s) - 1:
                c['state'] = 'stop'; c['pos'] = 0.0; break
    if f >= first:
        outbuf.append(np.clip(buf * gvol, -32768, 32767))

a = np.concatenate(outbuf) if outbuf else np.zeros((0, 2))
w = wave.open(out, 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(44100)
w.writeframes(a.astype('<i2').tobytes()); w.close()
print(f"{out}: {len(a) / 44100:.2f} s, peak {int(np.abs(a).max()) if len(a) else 0}")
