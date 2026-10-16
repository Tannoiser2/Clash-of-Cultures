#!/usr/bin/env python3
"""Sintetizza la musica di Clash of Cultures: lira pizzicata (Karplus-Strong) in modo dorico,
bordone, tamburo a cornice e una melodia di aulos. Niente campioni esterni.
Gli effetti sonori sono quelli sintetizzati per Manila (assets/audio/*.wav).
Uso: python3 tools/sintetizza_audio.py  (serve ffmpeg con libvorbis)."""
import os, subprocess, wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
rng = np.random.default_rng(753)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

def lyre(f, dur, vel=1.0):
    n = int(dur * SR); p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p); out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = 0.5 * (buf[i % p] + buf[(i + 1) % p]) * 0.996
    return out * vel

def drum(dur, f0=90, vel=1.0):
    n = int(dur * SR); t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * (f0 * t + 30 * (1 - np.exp(-t * 30)) / 30)) * np.exp(-t / 0.18)
    skin = rng.standard_normal(n) * np.exp(-t / 0.03) * 0.3
    return (tone + skin) * vel

def aulos(f, dur, vel=1.0):
    n = int(dur * SR); t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t)
    ph = 2 * np.pi * f * np.cumsum(vib) / SR
    s = np.sin(ph) + 0.45 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph) + 0.12 * np.sin(5 * ph)
    env = np.minimum(1, t / 0.08) * np.minimum(1, (dur - t) / 0.15)
    breath = rng.standard_normal(n) * 0.04
    return (s + breath) * np.clip(env, 0, 1) * vel

BPM = 84; beat = 60 / BPM; bars = 32; L = int(bars * 4 * beat * SR) + SR
mix = np.zeros(L)
def put(sig, t, g=1.0):
    i = int(t * SR); j = min(L, i + len(sig)); mix[i:j] += sig[:j - i] * g

D = 50  # re
scale = [0, 2, 3, 5, 7, 9, 10, 12]
chords = [[0, 7, 12], [-2, 5, 10], [3, 7, 10], [0, 7, 12], [5, 9, 12], [3, 7, 10], [-2, 5, 10], [0, 7, 12]]
for bar in range(bars):
    t0 = bar * 4 * beat
    ch = chords[bar % 8]
    # bordone
    put(aulos(hz(D - 12), 4 * beat, 0.08), t0)
    # arpeggio di lira
    pat = [0, 1, 2, 1, 0, 2, 1, 2]
    for k in range(8):
        note = D + ch[pat[k]] + (12 if k in (2, 5) else 0)
        put(lyre(hz(note), 1.6, 0.32 if k % 2 == 0 else 0.22), t0 + k * beat / 2)
    # tamburo a cornice
    for k, v in ((0, 1.0), (1.5, 0.5), (2, 0.8), (3, 0.45), (3.5, 0.4)):
        put(drum(0.5, 85 if v > 0.7 else 120, v), t0 + k * beat, 0.35)
    # melodia nelle battute centrali
    if 8 <= bar < 24:
        mel = rng.choice(scale, 4)
        for k in range(4):
            if rng.random() < 0.75:
                put(aulos(hz(D + 12 + int(mel[k])), beat * 0.95, 0.12), t0 + k * beat)
mix = mix / np.max(np.abs(mix)) * 0.8
# dissolvenza per il loop
fade = int(0.8 * SR); mix[:fade] *= np.linspace(0, 1, fade); mix[-fade:] *= np.linspace(1, 0, fade)
os.makedirs(OUT, exist_ok=True)
tmp = os.path.join(OUT, '_m.wav')
with wave.open(tmp, 'w') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix * 32767).astype(np.int16).tobytes())
subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '3', os.path.join(OUT, 'musica.ogg')], check=True)
os.remove(tmp)
print('musica.ogg pronta')
