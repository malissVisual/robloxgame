#!/usr/bin/env python3
"""
Zombie Delivery's own sounds and music, synthesized from scratch (numpy + ffmpeg): minimal and soft, nothing
borrowed. Writes four files for Roblox (one upload each, the game plays regions of them):
  sfx.ogg    every sound effect one after another (src/shared/SoundSheet.luau has the regions)
  music.ogg  four seamless music loops one after another
  sfx2.ogg   5.7: the world's sounds (knocks, doors, steps, the zip line, the bikes, the bus, the phone, coins, the
             city's ambience and wind), a sheet of its own so the two uploaded above stay exactly as they are
  sfx3.ogg   6.12: car doors, a van's back doors (swing / roll-up), a horn per vehicle class, footsteps by surface
             (concrete, grass, wood, metal, water) and a splash, ambience loops (the day, the night, a rooftop's wind,
             the park's fountain) and UI stings (task_done, purchase, event_start, event_end)
and regions.json + src/shared/SoundSheet.luau (the regions, the asset ids stay to be filled in).
Run: python3 art/audio/make_audio.py   (from zombie-delivery/)
6.12: a sheet whose .ogg already exists is NOT encoded again (its asset id is uploaded: a new encode is new bytes and
a new upload). Only missing sheets are written, plus the ones named: --sheets sfx3 (or --sheets all). If the sounds of
a kept sheet moved (its regions changed), the script stops: rewrite that sheet with --sheets and upload it again.
regions.json keeps a hash of every sheet's samples, so a changed sound in a kept sheet is reported.
"""
import argparse, hashlib, json, math, os, subprocess, sys, wave
import numpy as np

ARGS = argparse.ArgumentParser(description="Synthesizes the game's sound sheets.")
ARGS.add_argument("--sheets", default="", help="comma-separated sheets to encode again although their .ogg exists (sfx, music, sfx2, sfx3) or 'all'")
REWRITE = {s.strip() for s in ARGS.parse_args().sheets.split(",") if s.strip()}

SR = 44100
rng = np.random.default_rng(7331)
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

def t(sec): return np.arange(int(sec * SR)) / SR
def env(n, attack=0.004, decay=0.2, hold=0.0):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    d = np.where(x < attack + hold, 1.0, np.exp(-(x - attack - hold) / max(decay, 1e-4)))
    return a * d
def lowpass(sig, cutoff, q=0.0, circular=False):
    n = len(sig)
    pad = 0 if circular else min(n, SR // 2)
    x = np.concatenate([sig, np.zeros(pad)])
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    resp = 1 / np.sqrt(1 + (f / cutoff) ** 4)
    if q:
        resp *= 1 + q * np.exp(-((f - cutoff) / (cutoff * 0.25)) ** 2)
    y = np.fft.irfft(spec * resp, len(x))
    if circular:
        return y
    return y[:n]
def bandpass(sig, lo, hi):
    spec = np.fft.rfft(sig); f = np.fft.rfftfreq(len(sig), 1 / SR)
    resp = 1 / np.sqrt(1 + (lo / np.maximum(f, 1)) ** 4) / np.sqrt(1 + (f / hi) ** 4)
    return np.fft.irfft(spec * resp, len(sig))
def noise(sec): return rng.standard_normal(int(sec * SR))
def norm(sig, peak=0.9):
    m = np.max(np.abs(sig)) or 1
    return sig / m * peak
def note(freq): return 440.0 * 2 ** ((freq - 69) / 12)  # midi -> Hz
def bell(freq, sec, decay=0.35, harm=((1, 1), (2.01, 0.25), (3.0, 0.08))):
    x = t(sec); s = np.zeros_like(x)
    for mul, amp in harm:
        s += amp * np.sin(2 * np.pi * freq * mul * x) * np.exp(-x / (decay / mul ** 0.5))
    return s * env(len(x), 0.002, 10)
def pluck(freq, sec, decay=0.5):  # marimba-like: soft, round
    x = t(sec)
    s = np.sin(2 * np.pi * freq * x) + 0.18 * np.sin(2 * np.pi * freq * 4 * x) * np.exp(-x / 0.05)
    return s * env(len(x), 0.003, decay)
def thump(f0, f1, sec, decay=0.12):
    x = t(sec); f = f1 + (f0 - f1) * np.exp(-x / 0.03)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(x), 0.002, decay)
def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out.append(p); out.append(np.zeros(int(gap * SR)))
    return np.concatenate(out)
def mix(*sigs):
    n = max(len(s) for s in sigs); out = np.zeros(n)
    for s in sigs: out[:len(s)] += s
    return out
def at(sig, sec, total):
    out = np.zeros(int(total * SR)); i = int(sec * SR); out[i:i + len(sig)] += sig[:len(out) - i]; return out

# ── Sound effects ─────────────────────────────────────────────────────────────
def gunshot(dark, body, length, crack=0.5):
    n = noise(length) * env(int(length * SR), 0.001, length * 0.18)
    n = lowpass(n, dark)
    return norm(crack * n + body * thump(180, 55, length, length * 0.25), 0.85)

SFX = {}
SFX["gun_light"] = gunshot(2600, 0.6, 0.35)            # pistol, smg, carbine
SFX["gun_crack"] = gunshot(3000, 0.55, 0.55, 0.6)       # rifle, revolver
SFX["gun_heavy"] = gunshot(1500, 1.0, 0.6)             # shotgun
SFX["gun_rapid"] = gunshot(3000, 0.4, 0.14)            # minigun (short, it repeats)
SFX["gun_launch"] = norm(thump(140, 45, 0.5, 0.18) + 0.25 * lowpass(noise(0.5), 600) * env(int(0.5 * SR), 0.002, 0.08), 0.85)
SFX["explosion"] = norm(lowpass(noise(1.6), 420) * env(int(1.6 * SR), 0.005, 0.45) + 0.8 * thump(90, 30, 1.6, 0.5), 0.9)
SFX["hit"] = norm(np.sin(2 * np.pi * 1700 * t(0.05)) * env(int(0.05 * SR), 0.001, 0.012), 0.5)
SFX["headshot"] = norm(bell(note(88), 0.45, 0.18) + 0.6 * bell(note(95), 0.45, 0.14), 0.7)
SFX["kill"] = norm(thump(160, 70, 0.25, 0.06) + 0.3 * bell(note(76), 0.25, 0.08), 0.6)
SFX["pickup"] = norm(np.sin(2 * np.pi * np.cumsum(np.linspace(320, 620, int(0.16 * SR))) / SR) * env(int(0.16 * SR), 0.01, 0.06), 0.55)
SFX["putdown"] = norm(thump(130, 60, 0.2, 0.05) + 0.2 * lowpass(noise(0.2), 900) * env(int(0.2 * SR), 0.001, 0.03), 0.6)
SFX["load"] = norm(seq(thump(110, 50, 0.16, 0.05), np.sin(2 * np.pi * 2400 * t(0.03)) * env(int(0.03 * SR), 0.001, 0.008) * 0.4, gap=0.02), 0.65)
SFX["cash"] = norm(seq(bell(note(88), 0.12, 0.2), bell(note(95), 0.5, 0.3)), 0.6)
SFX["job_done"] = norm(mix(*[at(pluck(note(m), 0.9, 0.35), i * 0.11, 1.4) for i, m in enumerate((72, 76, 79, 84))]), 0.65)
SFX["job_fail"] = norm(mix(at(pluck(note(67), 0.8, 0.4), 0, 1.2), at(pluck(note(62), 0.9, 0.5), 0.22, 1.2)), 0.55)
SFX["level_up"] = norm(mix(*[at(bell(note(m), 1.2, 0.5), i * 0.09, 1.9) for i, m in enumerate((72, 76, 79, 84, 88))]), 0.7)
def pulse(freq, sec):
    x = t(sec); s = np.sign(np.sin(2 * np.pi * freq * x)) * 0.5 + np.sin(2 * np.pi * freq * x) * 0.5
    return lowpass(s, freq * 3) * env(len(x), 0.01, sec * 0.5)
SFX["wave"] = norm(mix(*[at(pulse(note(57) if i % 2 == 0 else note(64), 0.22), i * 0.26, 1.2) for i in range(4)]), 0.6)
SFX["ui_click"] = norm(np.sin(2 * np.pi * 2100 * t(0.03)) * env(int(0.03 * SR), 0.001, 0.006), 0.35)
SFX["ui_open"] = norm(np.sin(2 * np.pi * np.cumsum(np.linspace(500, 760, int(0.09 * SR))) / SR) * env(int(0.09 * SR), 0.004, 0.035), 0.4)
SFX["notify"] = norm(pluck(note(81), 0.4, 0.15), 0.45)
def horn(sec):
    x = t(sec); s = np.zeros_like(x)
    for f in (note(69), note(73)):
        s += lowpass(2 * ((x * f) % 1) - 1, 1200)
    return s * env(len(x), 0.01, 10) * np.clip((sec - x) / 0.05, 0, 1)
SFX["horn"] = norm(seq(horn(0.16), horn(0.32), gap=0.06), 0.6)
SFX["ding"] = norm(bell(note(79), 1.0, 0.45) + 0.5 * bell(note(83), 1.0, 0.4), 0.55)
def groan(sec, f0, seed):
    r = np.random.default_rng(seed); x = t(sec)
    f = f0 * (1 + 0.06 * np.sin(2 * np.pi * 5.5 * x) + 0.12 * np.sin(2 * np.pi * 0.9 * x))
    voice = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    breath = bandpass(r.standard_normal(len(x)), 250, 900) * 0.6
    return norm((voice * 0.6 + breath) * env(len(x), 0.15, sec * 0.4, sec * 0.3), 0.55)
SFX["zombie_a"] = lowpass(groan(1.3, 82, 1), 1400)
SFX["zombie_b"] = lowpass(groan(1.1, 68, 2), 1200)
# Engine: exactly 1 s, every partial a whole number of cycles: the loop has no seam.
x = t(1.0)
eng = sum(a * np.sin(2 * np.pi * f * x + p) for f, a, p in ((55, 1.0, 0), (110, 0.5, 0.7), (165, 0.25, 1.3), (220, 0.12, 2.1), (27, 0.35, 0.4)))
eng = eng * (1 + 0.12 * np.sin(2 * np.pi * 8 * x)) + 0.12 * lowpass(rng.standard_normal(SR), 220, circular=True)
SFX["engine"] = norm(lowpass(eng, 520, circular=True), 0.5)
LOOPED = {"engine"}

# ── Music: four seamless loops ────────────────────────────────────────────────
def pad(freqs, sec, attack=1.2, release=1.2):
    x = t(sec); s = np.zeros_like(x)
    for f in freqs:
        for det in (-0.12, 0.0, 0.11):
            s += np.sin(2 * np.pi * (f + det) * x) + 0.2 * np.sin(4 * np.pi * (f + det) * x)
    e = np.clip(x / attack, 0, 1) * np.clip((sec - x) / release, 0, 1)
    return lowpass(s * e, 1800)
def render_loop(events, length):
    """events: (start s, signal); everything past the end wraps to the start: a seamless loop."""
    n = int(length * SR); out = np.zeros(n)
    for start, sig in events:
        i = int(start * SR) % n
        idx = (np.arange(len(sig)) + i) % n
        np.add.at(out, idx, sig)
    return out
def chord(root, kind):
    iv = {"maj7": (0, 4, 7, 11), "m7": (0, 3, 7, 10), "maj9": (0, 4, 7, 14), "6": (0, 4, 7, 9), "m": (0, 3, 7, 12), "sus2": (0, 2, 7, 12)}[kind]
    return [note(root + i) for i in iv]
def track(bpm, bars, prog, arp_pattern, arp_oct, pad_vol, arp_vol, bass=False, hats=False, bell_notes=()):
    beat = 60 / bpm; bar = 4 * beat; length = bars * bar; ev = []
    for b in range(bars):
        root, kind = prog[b % len(prog)]
        ch = chord(root, kind)
        ev.append((b * bar, pad_vol * pad([f / 2 for f in ch], bar + 1.5, 0.9, 1.4)))
        for step, idx in enumerate(arp_pattern):
            if idx is None: continue
            f = ch[idx % len(ch)] * (2 ** arp_oct) * (2 if idx >= len(ch) else 1)
            ev.append((b * bar + step * beat / 2, arp_vol * pluck(f, 1.2, 0.45)))
        if bass:
            for s in range(8):
                ev.append((b * bar + s * beat / 2, 0.35 * pluck(note(root - 24), 0.5, 0.18)))
        if hats:
            for s in range(8):
                h = bandpass(noise(0.06), 5000, 11000) * env(int(0.06 * SR), 0.001, 0.015)
                ev.append((b * bar + s * beat / 2, (0.018 if s % 2 else 0.035) * lowpass(h, 7000)))
    for start_bar, m in bell_notes:
        ev.append((start_bar * bar, 0.25 * bell(note(m), 3.0, 1.2)))
    return norm(render_loop(ev, length), 0.8), length
MUSIC = {}
MUSIC["menu"] = track(80, 8, [(60, "maj7"), (57, "m7"), (53, "maj9"), (55, "6")], [0, 2, 1, 3, 2, 4, 1, None], 1, 0.22, 0.55, bell_notes=((0, 84), (4, 79)))
MUSIC["day"] = track(92, 8, [(57, "m"), (53, "maj7"), (48, "maj7"), (55, "sus2")], [0, None, 2, None, 1, 3, None, 2], 1, 0.16, 0.45)
MUSIC["night"] = track(70, 8, [(50, "m7"), (46, "maj7"), (53, "maj9"), (48, "sus2")], [0, None, None, 2, None, None, 1, None], 1, 0.24, 0.35, bell_notes=((2, 74), (6, 69)))
MUSIC["tension"] = track(112, 8, [(57, "m"), (57, "m"), (53, "maj7"), (52, "m")], [0, 2, 0, 3, 0, 2, 1, 2], 0, 0.14, 0.32, bass=True, hats=True)

# ── 5.7: the world's sounds (sfx2.ogg) ──────────────────────────────────────────
# Their own random generator: the two sheets above come out exactly as before (their uploads stay valid).
rng2 = np.random.default_rng(5707)
def noise2(sec): return rng2.standard_normal(int(sec * SR))
def loop_noise(sec, lo, hi):
    """Noise band-passed around the loop (the FFT is circular): no seam when it repeats."""
    return bandpass(noise2(sec), lo, hi)
def knock_hit(pitch):
    body = thump(240 * pitch, 120 * pitch, 0.14, 0.035)
    click = bandpass(noise2(0.14), 900, 3200) * env(int(0.14 * SR), 0.0005, 0.012)
    return body + 0.5 * click
SFX2 = {}
SFX2["knock"] = norm(mix(at(knock_hit(1.0), 0, 0.62), at(knock_hit(1.04), 0.17, 0.62), at(knock_hit(0.97), 0.34, 0.62)), 0.7)
def creak(sec):
    x = t(sec)
    f = 260 + 220 * (x / sec) + 25 * np.sin(2 * np.pi * 3.1 * x)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR)
    grain = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * np.cumsum(38 + 20 * x / sec) / SR))  # stick-slip
    s = bandpass(tone * grain + 0.15 * noise2(sec), 300, 2600)
    return s * env(len(x), 0.05, sec * 0.5, sec * 0.35)
SFX2["door_creak"] = norm(creak(0.9), 0.5)
x1 = t(1.0)  # the loops below: exactly 1 s, every tone and pulse a whole number of cycles (no seam)
zip_tone = sum(a * np.sin(2 * np.pi * f * x1 + p) for f, a, p in ((96, 0.6, 0.0), (192, 0.35, 0.8), (288, 0.2, 1.7), (1440, 0.06, 0.3)))
zip_hiss = loop_noise(1.0, 700, 3400) * (1 + 0.35 * np.sin(2 * np.pi * 16 * x1))
SFX2["zip"] = norm(lowpass(zip_tone * (1 + 0.15 * np.sin(2 * np.pi * 8 * x1)) + 0.5 * zip_hiss, 4000, circular=True), 0.5)
hum = sum(a * np.sin(2 * np.pi * f * x1 + p) for f, a, p in ((180, 0.5, 0.0), (360, 0.3, 0.6), (540, 0.12, 1.1), (1260, 0.08, 0.2)))
SFX2["scooter"] = norm(hum * (1 + 0.08 * np.sin(2 * np.pi * 6 * x1)) + 0.25 * loop_noise(1.0, 250, 1400), 0.45)
ticks = np.zeros(SR)
for i in range(12):
    start = int(i * SR / 12)
    tick = bandpass(noise2(0.012), 2500, 7000) * env(int(0.012 * SR), 0.0003, 0.002)
    ticks[start:start + len(tick)] += tick * (1.0 if i % 2 == 0 else 0.8)
SFX2["freewheel"] = norm(ticks + 0.35 * loop_noise(1.0, 150, 900), 0.45)
def squeal(sec):
    x = t(sec); f = 2350 + 60 * np.sin(2 * np.pi * 7 * x) - 300 * x / sec
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(x), 0.04, sec * 0.4, sec * 0.3)
def hiss(sec, lo=1800, hi=9000, decay=None):
    return bandpass(noise2(sec), lo, hi) * env(int(sec * SR), 0.01, decay or sec * 0.35, sec * 0.2)
SFX2["bus_brake"] = norm(mix(at(0.35 * squeal(0.7), 0, 1.7), at(lowpass(noise2(0.7), 300) * env(int(0.7 * SR), 0.02, 0.3) * 0.6, 0, 1.7), at(hiss(0.9), 0.75, 1.7)), 0.6)
SFX2["bus_door"] = norm(mix(at(hiss(0.5, 1500, 8000, 0.15), 0, 0.75), at(thump(150, 70, 0.2, 0.05) * 0.8, 0.5, 0.75)), 0.55)
def buzz(sec):
    x = t(sec); s = np.tanh(3 * np.sin(2 * np.pi * 165 * x)) + 0.4 * np.sin(2 * np.pi * 330 * x)
    return lowpass(s, 900) * env(len(x), 0.008, 10) * np.clip((sec - x) / 0.02, 0, 1)
SFX2["phone_buzz"] = norm(seq(buzz(0.17), buzz(0.17), gap=0.09), 0.45)
def step(f0, cutoff):
    n = int(0.13 * SR)
    scuff = lowpass(noise2(0.13), cutoff) * env(n, 0.002, 0.03)
    return thump(f0, f0 * 0.5, 0.13, 0.03) * 0.7 + scuff
SFX2["step_a"] = norm(step(110, 1500), 0.45)
SFX2["step_b"] = norm(step(96, 1250), 0.45)
SFX2["coin"] = norm(mix(at(bell(note(96), 0.45, 0.12), 0, 0.6), at(bell(note(103), 0.5, 0.16), 0.07, 0.6)), 0.5)
x8 = t(8.0)  # 8 s loops: every modulation a whole number of cycles in 8 s
rumble = lowpass(noise2(8.0), 180, circular=True)
far = loop_noise(8.0, 500, 2200) * (1 + 0.3 * np.sin(2 * np.pi * 0.25 * x8))
SFX2["ambience"] = norm(rumble + 0.25 * far, 0.4)
gust = 0.55 + 0.3 * np.sin(2 * np.pi * 0.125 * x8) + 0.15 * np.sin(2 * np.pi * 0.375 * x8 + 1.0)
SFX2["wind"] = norm(loop_noise(8.0, 250, 1100) * gust + 0.3 * loop_noise(8.0, 1500, 4000) * gust ** 2, 0.4)
LOOPED |= {"zip", "scooter", "freewheel", "ambience", "wind"}

# ── 6.12: doors, horns, footsteps by surface, ambience, UI stings (sfx3.ogg) ──
# Their own random generator (as 5.7's): the three sheets above come out exactly as before.
rng3 = np.random.default_rng(6120)
def noise3(sec): return rng3.standard_normal(int(sec * SR))
def samples(sec): return int(sec * SR)
def tick3(sec=0.015, lo=1800, hi=7000, decay=0.0025):
    """A short click: band-passed noise, gone in a few ms (a latch, a heel, a slat)."""
    return bandpass(noise3(sec), lo, hi) * env(samples(sec), 0.0003, decay)
def modes(parts, sec):
    """A struck body: decaying sines (freq, amp, decay s), each with its own phase (a panel, a board, a bell)."""
    x = t(sec); s = np.zeros_like(x)
    for f, a, d in parts:
        s += a * np.sin(2 * np.pi * f * x + rng3.uniform(0, 2 * np.pi)) * np.exp(-x / d)
    return s * env(len(x), 0.0005, 10)
def bubble(f0, sec, rise=0.8):
    """A drop or a bubble: a sine gliding up as it fades (the way water rings)."""
    x = t(sec); f = f0 * (1 + rise * x / sec)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-x / (sec * 0.35)) * env(len(x), 0.001, 10)
def narrow(sec, centre, width):
    """Noise in a narrow band (a whistle in the wind), circular: no seam when it loops."""
    spec = np.fft.rfft(noise3(sec)); f = np.fft.rfftfreq(samples(sec), 1 / SR)
    return np.fft.irfft(spec * np.exp(-((f - centre) / width) ** 2), samples(sec))
def hump(n, rise, fall):
    """0 → 1 → 0 over n samples: up in `rise` of it, down in the last `fall` (sine-shaped)."""
    x = np.arange(n) / max(n - 1, 1)
    up = np.sin(np.clip(x / rise, 0, 1) * np.pi / 2) ** 2
    down = np.sin(np.clip((1 - x) / fall, 0, 1) * np.pi / 2) ** 2
    return up * down
SFX3 = {}

# Car doors: the latch and the seal letting go; shut: a solid thunk of the panel and the latch catching.
SFX3["car_door_open"] = norm(mix(
    at(tick3(0.02, 1500, 6000, 0.004) * 0.8 + modes(((2400, 0.25, 0.018), (3650, 0.18, 0.012)), 0.02), 0, 0.5),
    at(thump(260, 150, 0.12, 0.03) * 0.6, 0.012, 0.5),
    at(bandpass(noise3(0.35), 200, 1500) * env(samples(0.35), 0.03, 0.08) * 0.3, 0.03, 0.5)), 0.6)
SFX3["car_door_close"] = norm(mix(
    at(thump(150, 62, 0.5, 0.09), 0, 0.55),
    at(modes(((185, 0.5, 0.07), (310, 0.3, 0.05), (520, 0.15, 0.03)), 0.5), 0, 0.55),
    at(lowpass(noise3(0.5), 900) * env(samples(0.5), 0.001, 0.025) * 0.6, 0, 0.55),
    at(tick3(0.015, 2000, 7000, 0.003) * 0.35, 0.008, 0.55),
    at(tick3(0.015, 1500, 5000, 0.004) * 0.1, 0.06, 0.55)), 0.75)

# A van's two rear doors swinging open: the handle, the second leaf's catch, a hinge's squeak, the two stops.
def hinge_squeak(sec, f0, f1):
    x = t(sec)
    f = f0 + (f1 - f0) * x / sec + 18 * np.sin(2 * np.pi * 4.3 * x)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR)
    grain = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * np.cumsum(55 + 25 * x / sec) / SR))  # stick-slip
    return bandpass(tone * grain + 0.1 * noise3(sec), 400, 3200) * hump(len(x), 0.25, 0.4)
def door_stop(f, amp):
    return thump(f, f * 0.5, 0.3, 0.05) * amp + modes(((f * 1.3, 0.2 * amp, 0.08), (f * 3.4, 0.1 * amp, 0.05)), 0.3)
SFX3["van_back_open"] = norm(mix(
    at(mix(tick3(0.02, 1200, 5000, 0.005), thump(320, 200, 0.08, 0.02) * 0.4), 0, 0.8),
    at(tick3(0.015, 1400, 6000, 0.004) * 0.5, 0.06, 0.8),
    at(hinge_squeak(0.36, 520, 690) * 0.22, 0.08, 0.8),
    at(door_stop(180, 0.5), 0.42, 0.8),
    at(door_stop(200, 0.4), 0.47, 0.8)), 0.6)
# … and shut: the air they push, two slams (the second leaf latches over the first).
def slam(f, amp):
    body = thump(f, f * 0.4, 0.4, 0.1) + modes(((f * 1.05, 0.5, 0.1), (f * 1.9, 0.35, 0.08), (f * 3.1, 0.2, 0.06), (f * 6.4, 0.08, 0.04)), 0.4)
    hit = lowpass(noise3(0.4), 1200) * env(samples(0.4), 0.001, 0.03) * 0.7
    return (body + hit) * amp
SFX3["van_back_close"] = norm(mix(
    at(bandpass(noise3(0.38), 150, 900) * hump(samples(0.38), 0.8, 0.05) * 0.25, 0, 0.9),
    at(slam(140, 1.0), 0.38, 0.9),
    at(mix(slam(165, 0.8), tick3(0.015, 2000, 7000, 0.003) * 0.3), 0.47, 0.9)), 0.8)

# A roll-up door: the slats rattle over the rollers (faster in the middle of the travel), a rumble, a stop at the top;
# down: the rattle speeding up with the weight, a bang on the floor, a last rattle.
def rattle(sec, rate0, rate1, rate2):
    out = np.zeros(samples(sec)); pos = 0.0
    while pos < sec - 0.02:
        share = pos / sec
        rate = rate0 + (rate1 - rate0) * min(1, share * 2) + (rate2 - rate1) * max(0, share * 2 - 1)
        k = samples(pos)
        slat = tick3(0.012, 1000, 4500, 0.0025) * rng3.uniform(0.5, 1) + modes(((rng3.uniform(1100, 1600), 0.15, 0.01),), 0.012)
        out[k:k + len(slat)] += slat[:len(out) - k]
        pos += (1 / rate) * rng3.uniform(0.8, 1.2)
    return out + bandpass(noise3(sec), 80, 400) * hump(samples(sec), 0.3, 0.3) * 0.5
SFX3["van_roll_up"] = norm(mix(
    at(mix(tick3(0.02, 1200, 5000, 0.004), thump(300, 180, 0.08, 0.02) * 0.3), 0, 0.85),
    at(rattle(0.45, 18, 34, 22) * 0.6, 0.03, 0.85),
    at(thump(200, 110, 0.25, 0.05) * 0.6 + modes(((330, 0.3, 0.06), (780, 0.15, 0.04)), 0.25), 0.47, 0.85)), 0.6)
SFX3["van_roll_down"] = norm(mix(
    at(rattle(0.42, 14, 30, 42) * 0.6, 0, 0.9),
    at(thump(130, 55, 0.4, 0.09) + modes(((140, 0.5, 0.09), (380, 0.25, 0.06), (1050, 0.1, 0.03)), 0.4) + lowpass(noise3(0.4), 1500) * env(samples(0.4), 0.001, 0.03) * 0.6, 0.43, 0.9),
    at(rattle(0.12, 30, 20, 12) * 0.2, 0.5, 0.9)), 0.8)

# The horns: two tones a third apart through a buzzy diaphragm (a car's bright, a van's lower and rougher), a truck's
# air horn (a low chord that swells in with a breath of air), a bike's bell (two quick ring-rings: close partials beat
# like a real bell), an electric scooter's beep-beep.
def horn_tone(freqs, sec, drive, cutoff, bend=0.0, attack=0.012):
    x = t(sec); s = np.zeros_like(x)
    for f in freqs:
        s += 2 * ((np.cumsum(f * (1 - bend * np.exp(-x / 0.06))) / SR) % 1) - 1
    s = np.tanh(drive * s / len(freqs))
    s = lowpass(s, cutoff) + 0.4 * bandpass(s, 700, 1800)
    return s * env(len(x), attack, 10) * np.clip((sec - x) / 0.04, 0, 1)
SFX3["horn_car"] = norm(horn_tone((415, 523), 0.42, 2.2, 3000), 0.6)
SFX3["horn_van"] = norm(horn_tone((349, 440), 0.55, 2.8, 2400), 0.6)
SFX3["horn_truck"] = norm(horn_tone((196, 247, 294), 0.95, 1.6, 1800, 0.06, 0.04)
                          + bandpass(noise3(0.95), 500, 3000) * env(samples(0.95), 0.03, 0.3) * 0.08, 0.65)
def bell_strike(f0, sec):
    parts = ((1.0, 1.0, 0.45), (1.0045, 0.8, 0.45), (2.32, 0.45, 0.25), (2.33, 0.35, 0.25), (4.25, 0.25, 0.12), (6.8, 0.12, 0.07))
    return mix(modes(tuple((f0 * m, a, d) for m, a, d in parts), sec), tick3(0.01, 3000, 9000, 0.0015) * 0.15)
def ring_ring(f0):
    return mix(*[at(bell_strike(f0, 0.5) * amp, start, 0.95) for start, amp in ((0, 1), (0.045, 0.7), (0.09, 0.5), (0.3, 0.9), (0.345, 0.65), (0.39, 0.45))])
SFX3["bike_bell"] = norm(ring_ring(1900), 0.5)
def beep(f, sec):
    x = t(sec)
    return lowpass(np.tanh(3 * np.sin(2 * np.pi * f * x)), 5000) * env(len(x), 0.003, 10) * np.clip((sec - x) / 0.01, 0, 1)
SFX3["scooter_beep"] = norm(seq(beep(2093, 0.07), beep(2093, 0.07), gap=0.05), 0.4)

# Footsteps by surface, two of each (a, b in turn): concrete / asphalt a heel's click and a scuff; grass a crackle
# and a rustle; wood a hollow board; metal a clang of a plate or a rung; water a wade (a splash and a few bubbles).
def step_concrete(p):
    return lowpass(mix(tick3(0.03, 700, 3500, 0.006) * 0.7, thump(120 * p, 60 * p, 0.2, 0.025) * 0.7,
                       at(bandpass(noise3(0.18), 900, 4000) * env(samples(0.18), 0.02, 0.03) * 0.25, 0.02, 0.2)), 7000)
def step_grass(p):
    crackle = np.zeros(samples(0.2))
    for _ in range(14):
        k = samples(rng3.uniform(0, 0.09))
        c = tick3(0.008, 1500 * p, 6000, 0.0015) * rng3.uniform(0.3, 1)
        crackle[k:k + len(c)] += c
    rustle = bandpass(noise3(0.2), 1000, 5000) * env(samples(0.2), 0.01, 0.05) * 0.5
    return lowpass(crackle * 0.8 + rustle + thump(90, 50, 0.2, 0.02) * 0.3, 8000)
def step_wood(p):
    return mix(tick3(0.02, 1200, 4500, 0.004) * 0.5, thump(200 * p, 120 * p, 0.22, 0.03) * 0.8,
               modes(((240 * p, 0.35, 0.05), (470 * p, 0.2, 0.035), (890 * p, 0.08, 0.02)), 0.22))
def step_metal(p):
    return lowpass(mix(tick3(0.02, 1500, 6000, 0.003) * 0.5, thump(160, 90, 0.25, 0.02) * 0.4,
                       modes(((430 * p, 0.25, 0.12), (1070 * p, 0.2, 0.09), (1890 * p, 0.12, 0.07), (2950 * p, 0.08, 0.05)), 0.25)), 9000)
def step_water(p):
    out = (bandpass(noise3(0.32), 400, 3000) * env(samples(0.32), 0.004, 0.06) * 0.6
           + lowpass(noise3(0.32), 700) * env(samples(0.32), 0.02, 0.09) * 0.5)
    for _ in range(5):
        out += at(bubble(rng3.uniform(400, 1200) * p, rng3.uniform(0.03, 0.05)) * rng3.uniform(0.1, 0.25), rng3.uniform(0.02, 0.15), 0.32)
    return lowpass(out, 6000)
for surface, make in (("concrete", step_concrete), ("grass", step_grass), ("wood", step_wood), ("metal", step_metal), ("water", step_water)):
    SFX3[f"step_{surface}_a"] = norm(make(1.0), 0.5)
    SFX3[f"step_{surface}_b"] = norm(make(0.9), 0.5)

# A splash: a body going into the water: the plunge, the burst, the wash, then the drops falling back.
def splash():
    out = (thump(110, 45, 1.1, 0.12) * 0.7
           + bandpass(noise3(1.1), 800, 5000) * env(samples(1.1), 0.003, 0.08)
           + bandpass(noise3(1.1), 250, 2000) * env(samples(1.1), 0.01, 0.3) * 0.6)
    for _ in range(30):
        start = 0.1 + rng3.exponential(0.22)
        if start < 1.0:
            out += at(bubble(rng3.uniform(700, 2400), rng3.uniform(0.02, 0.06)) * rng3.uniform(0.05, 0.2) * (1 - start), start, 1.1)
    return lowpass(out, 7000)
SFX3["splash"] = norm(splash(), 0.8)

# The ambience loops (seamless: noise filtered round the loop, every event wrapped by render_loop, every swell a whole
# number of cycles). The day: the city's traffic far off (a bed and cars passing by) and birds. The night: the wind,
# crickets and zombies groaning far away. A rooftop: a stronger wind with a whistle. The park's fountain: the falling
# water and its drops.
def loop_band(sec, lo, hi): return bandpass(noise3(sec), lo, hi)
def chirp(f0, f1, sec, wobble=0.0):
    x = t(sec); f = f0 + (f1 - f0) * x / sec + wobble * np.sin(2 * np.pi * 38 * x)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) + 0.15 * np.sin(2 * ph)) * np.sin(np.pi * x / sec) ** 2
def birds(length):
    ev = []
    for start in np.sort(rng3.uniform(0, length, 7)):
        f = rng3.uniform(2600, 4200); pos = start
        for _ in range(int(rng3.integers(2, 6))):
            sec = rng3.uniform(0.05, 0.12)
            up = rng3.random() < 0.5
            ev.append((pos, chirp(f * (0.8 if up else 1.15), f * (1.15 if up else 0.8), sec, rng3.uniform(0, 120)) * rng3.uniform(0.5, 1)))
            pos += sec + rng3.uniform(0.04, 0.12)
    return lowpass(render_loop(ev, length), 7000, circular=True)
def far(sig, tail=0.8):
    """Far off: dulled and smeared by a short decaying tail (circular: for loops)."""
    n = len(sig); ir = np.zeros(n); m = samples(tail)
    ir[:m] = rng3.standard_normal(m) * np.exp(-np.arange(m) / (m / 5)) * 0.04
    ir[0] = 1.0
    return np.fft.irfft(np.fft.rfft(sig) * np.fft.rfft(ir), n)
x12 = t(12.0)  # 12 s loops: every swell a whole number of cycles in 12 s
traffic = lowpass(noise3(12.0), 260, circular=True) * (1 + 0.25 * np.sin(2 * np.pi * x12 / 12))
passes = render_loop([(start, loop_band(4.0, 180, 1200) * hump(samples(4.0), 0.5, 0.5) * 0.5) for start in (1.5, 5.8, 9.5)], 12.0)
hiss12 = render_loop([(start, loop_band(4.0, 1500, 4000) * hump(samples(4.0), 0.5, 0.5) * 0.1) for start in (1.5, 5.8, 9.5)], 12.0)
SFX3["amb_day"] = norm(traffic + passes + hiss12 + 0.12 * norm(birds(12.0), 1.0), 0.45)
gust12 = 0.6 + 0.3 * np.sin(2 * np.pi * x12 / 12) + 0.1 * np.sin(2 * np.pi * 3 * x12 / 12 + 1.0)
night_wind = loop_band(12.0, 180, 800) * gust12 + 0.15 * loop_band(12.0, 1200, 2600) * gust12 ** 2
cricket_ev = []
for start in np.arange(0.0, 12.0, 0.75):
    for k in range(3):
        sec = 0.015; x = t(sec)
        cricket_ev.append((start + rng3.uniform(-0.05, 0.05) + k * 0.025, np.sin(2 * np.pi * 4400 * x) * np.sin(np.pi * x / sec) ** 2 * 0.04))
crickets = render_loop(cricket_ev, 12.0)
groans = render_loop([(2.5, lowpass(groan(1.6, 74, 61201), 500)), (8.2, lowpass(groan(1.3, 88, 61202), 450) * 0.8)], 12.0)
SFX3["amb_night"] = norm(norm(night_wind, 1.0) + crickets * 4 + 0.22 * norm(far(groans), 1.0), 0.45)
x8b = t(8.0)
gust8 = 0.55 + 0.3 * np.sin(2 * np.pi * x8b / 8) + 0.15 * np.sin(2 * np.pi * 3 * x8b / 8 + 0.7)
roof = loop_band(8.0, 150, 1200) * gust8 + 0.25 * loop_band(8.0, 1800, 5000) * gust8 ** 2
whistle = norm(narrow(8.0, 880, 25), 1.0) * gust8 ** 3 * 0.35 + norm(narrow(8.0, 1320, 30), 1.0) * gust8 ** 4 * 0.15
SFX3["amb_roof"] = norm(norm(roof, 1.0) + whistle, 0.45)
x6 = t(6.0)
water_bed = loop_band(6.0, 300, 4000) * (1 + 0.1 * np.sin(2 * np.pi * 3 * x6 / 6)) * 0.5 + loop_band(6.0, 150, 600) * 0.45
drops = render_loop([(rng3.uniform(0, 6.0), bubble(rng3.uniform(600, 2500), rng3.uniform(0.01, 0.03), 0.6) * rng3.uniform(0.05, 0.25)) for _ in range(720)], 6.0)
SFX3["amb_fountain"] = norm(lowpass(norm(water_bed, 1.0) + 0.6 * norm(drops, 1.0), 6000, circular=True), 0.5)

# The UI stings: a task done (a bright arpeggio and a sparkle), a purchase (the register's clack, the drawer, two
# coins), an event starting (a low brass stab under a siren's two wails) and ending (the siren falling into a chord).
SFX3["task_done"] = norm(mix(
    *[at(bell(note(m), 0.7, 0.3), i * 0.08, 0.95) for i, m in enumerate((84, 88, 91))],
    at(bell(note(96), 0.65, 0.5) * 0.6, 0.26, 0.95),
    *[at(pluck(note(m), 0.7, 0.4) * 0.4, 0.16, 0.95) for m in (72, 76, 79)]), 0.6)
SFX3["purchase"] = norm(mix(
    at(mix(tick3(0.02, 1500, 6000, 0.004), thump(400, 250, 0.1, 0.02) * 0.4), 0, 0.8),
    at(bandpass(noise3(0.12), 800, 3000) * hump(samples(0.12), 0.3, 0.5) * 0.3, 0.03, 0.8),
    at(bell(note(93), 0.5, 0.18), 0.1, 0.8),
    at(bell(note(100), 0.6, 0.25), 0.17, 0.8)), 0.6)
def saw_chord(midis, sec, cutoff):
    x = t(sec); s = np.zeros_like(x)
    for m in midis:
        s += 2 * ((x * note(m)) % 1) - 1
    return lowpass(s / len(midis), cutoff)
def siren(sec, wails, lo, hi):
    x = t(sec); f = lo + (hi - lo) * (0.5 - 0.5 * np.cos(2 * np.pi * x * wails / sec))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return lowpass(np.sin(ph) + 0.3 * np.sin(3 * ph), 3000) * env(len(x), 0.05, 10) * np.clip((sec - x) / 0.2, 0, 1)
SFX3["event_start"] = norm(mix(
    at(saw_chord((45, 52, 57), 0.8, 900) * env(samples(0.8), 0.01, 0.4) * 0.6, 0, 1.5),
    at(siren(1.5, 2, 620, 1000) * 0.45, 0, 1.5)), 0.65)
def glide(sec, f0, f1):
    x = t(sec); f = f0 + (f1 - f0) * (x / sec) ** 0.7
    return lowpass(np.sin(2 * np.pi * np.cumsum(f) / SR), 3000) * np.clip(x / 0.03, 0, 1) * np.clip((sec - x) / 0.1, 0, 1)
SFX3["event_end"] = norm(mix(
    at(glide(0.35, 900, 500) * 0.25, 0, 1.2),
    *[at(pluck(note(m), 0.8, 0.4), 0.25 + i * 0.07, 1.2) for i, m in enumerate((60, 64, 67, 72))],
    at(bell(note(84), 0.7, 0.4) * 0.3, 0.5, 1.2)), 0.6)
LOOPED |= {"amb_day", "amb_night", "amb_roof", "amb_fountain"}

# ── Write the sheets ──────────────────────────────────────────────────────────
REGIONS_PATH = os.path.join(HERE, "regions.json")
OLD = json.load(open(REGIONS_PATH)) if os.path.exists(REGIONS_PATH) else {}
OLD_PCM = OLD.get("pcm_sha256", {})
def build_sheet(items, gap):
    # Positions are counted in whole samples so every region starts exactly where its sound does (a float sum of
    # int(gap * SR) drifted a sample per gap and made the engine loop click).
    regions = {}; parts = []; pos = 0; gap_n = round(gap * SR)
    for key, sig in items:
        regions[key] = [round(pos / SR, 6), round(len(sig) / SR, 6)]
        parts.append(sig); pos += len(sig)
        parts.append(np.zeros(gap_n)); pos += gap_n
    pcm = (np.clip(np.concatenate(parts), -1, 1) * 32767).astype("<i2").tobytes()
    return regions, pcm, pos / SR
SHEETS = [("sfx", list(SFX.items()), 0.3), ("music", [(k, v[0]) for k, v in MUSIC.items()], 0.5),
          ("sfx2", list(SFX2.items()), 0.3), ("sfx3", list(SFX3.items()), 0.3)]
built = {name: build_sheet(items, gap) for name, items, gap in SHEETS}
# 6.12: an uploaded sheet keeps its .ogg byte for byte unless it is named (--sheets): check first, write nothing on a
# problem (a kept sheet whose regions moved would play the wrong sounds from its old upload).
plan = {}
for name, (regions, pcm, _) in built.items():
    ogg = os.path.join(HERE, name + ".ogg")
    if not os.path.exists(ogg) or name in REWRITE or "all" in REWRITE:
        plan[name] = "write"
        continue
    if name in OLD and OLD[name] != regions:
        sys.exit(f"{name}: its sounds moved (the regions changed) but {name}.ogg is kept as uploaded: run with --sheets {name} and upload it again")
    if OLD_PCM.get(name) not in (None, hashlib.sha256(pcm).hexdigest()):
        print(f"note: {name}'s sounds changed; {name}.ogg was kept (run with --sheets {name} to rewrite it, then upload it again)")
    plan[name] = "kept"
hashes = {}
for name, (regions, pcm, _) in built.items():
    hashes[name] = hashlib.sha256(pcm).hexdigest() if plan[name] == "write" else OLD_PCM.get(name) or hashlib.sha256(pcm).hexdigest()
    if plan[name] != "write":
        continue
    wav = os.path.join(HERE, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm)
    ogg = os.path.join(HERE, name + ".ogg")
    # (6.12: bitexact: the same samples give the same file, no random stream serial, no encoder version tag)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5",
                    "-fflags", "+bitexact", "-flags:a", "+bitexact", ogg], check=True)
    os.remove(wav)
sfx_regions, music_regions, sfx2_regions, sfx3_regions = (built[n][0] for n in ("sfx", "music", "sfx2", "sfx3"))
json.dump({"sfx": sfx_regions, "music": music_regions, "sfx2": sfx2_regions, "sfx3": sfx3_regions, "looped": sorted(LOOPED),
           "pcm_sha256": hashes}, open(REGIONS_PATH, "w"), indent=2)

# Keep the asset ids already pasted into SoundSheet (a re-run must not wipe them; upload the new files and update).
sheet_path = os.path.join(ROOT, "src", "shared", "SoundSheet.luau")
old_ids = {"SfxId": "", "MusicId": "", "Sfx2Id": "", "Sfx3Id": ""}
if os.path.exists(sheet_path):
    import re
    for key in old_ids:
        m = re.search(r'SoundSheet\.' + key + r' = "([^"]*)"', open(sheet_path).read())
        if m:
            old_ids[key] = m.group(1)
# (a sheet written anew is a new file: its old id would play the old sounds; it must be uploaded again)
for name, key in (("sfx", "SfxId"), ("music", "MusicId"), ("sfx2", "Sfx2Id"), ("sfx3", "Sfx3Id")):
    if plan[name] == "write" and old_ids[key]:
        print(f"note: {name}.ogg was written anew: upload it and replace SoundSheet.{key} (it still holds the old upload)")
lua = ["--!strict",
       "-- The game's own sounds (art/audio/make_audio.py writes this file): two audio assets, sfx.ogg and music.ogg,",
       "-- and where each sound / music loop sits in them (start, length in seconds; client/Sounds.luau plays the region).",
       "-- Upload art/audio/sfx.ogg and art/audio/music.ogg (Asset Manager → Import) and paste the ids below.",
       "-- 5.7: art/audio/sfx2.ogg holds the world's sounds (Sfx2); until its id is pasted, those play a stand-in from",
       "-- Sfx or stay silent (client/Sounds.luau).",
       "-- 6.12: art/audio/sfx3.ogg holds the doors, the horns, the footsteps by surface, the splash, the ambience loops and",
       "-- the UI stings (Sfx3); until its id is pasted, those play a stand-in from Sfx / Sfx2 or stay silent",
       "-- (client/Sounds.luau FALLBACK; art/audio/NAHRAT-SFX3.md says how to upload it).",
       "", "local SoundSheet = {}", "",
       f'SoundSheet.SfxId = "{old_ids["SfxId"]}" -- "rbxassetid://…" of art/audio/sfx.ogg',
       f'SoundSheet.MusicId = "{old_ids["MusicId"]}" -- "rbxassetid://…" of art/audio/music.ogg',
       f'SoundSheet.Sfx2Id = "{old_ids["Sfx2Id"]}" -- "rbxassetid://…" of art/audio/sfx2.ogg',
       f'SoundSheet.Sfx3Id = "{old_ids["Sfx3Id"]}" -- "rbxassetid://…" of art/audio/sfx3.ogg (6.12)', "",
       "SoundSheet.Sfx = {"]
for k, (s, l) in sfx_regions.items():
    lua.append(f"\t{k} = {{ {s}, {l} }},")
lua += ["} :: { [string]: { number } }", "", "SoundSheet.Music = {"]
for k, (s, l) in music_regions.items():
    lua.append(f"\t{k} = {{ {s}, {l} }},")
lua += ["} :: { [string]: { number } }", "", "SoundSheet.Sfx2 = {"]
for k, (s, l) in sfx2_regions.items():
    lua.append(f"\t{k} = {{ {s}, {l} }},")
lua += ["} :: { [string]: { number } }", "", "SoundSheet.Sfx3 = {"]
for k, (s, l) in sfx3_regions.items():
    lua.append(f"\t{k} = {{ {s}, {l} }},")
lua += ["} :: { [string]: { number } }", "", "-- Sounds that loop (their region repeats seamlessly).",
        "SoundSheet.Looped = { " + ", ".join(f"{k} = true" for k in sorted(LOOPED)) + " } :: { [string]: boolean }", "", "return SoundSheet", ""]
open(sheet_path, "w").write("\n".join(lua))
print("  ".join(f"{name}: {len(dict(items))} sounds, {built[name][2]:.1f} s ({plan[name]})" for name, items, _ in SHEETS))
