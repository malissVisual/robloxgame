#!/usr/bin/env python3
"""
Zombie Delivery's own sounds and music, synthesized from scratch (numpy + ffmpeg): minimal and soft, nothing
borrowed. Writes two files for Roblox (one upload each, the game plays regions of them):
  sfx.ogg    every sound effect one after another (src/shared/SoundSheet.luau has the regions)
  music.ogg  four seamless music loops one after another
and regions.json + src/shared/SoundSheet.luau (the regions, the asset ids stay to be filled in).
Run: python3 art/audio/make_audio.py   (from zombie-delivery/)
"""
import json, math, os, subprocess, wave
import numpy as np

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

# ── Write the sheets ──────────────────────────────────────────────────────────
def write_sheet(items, name, gap):
    # Positions are counted in whole samples so every region starts exactly where its sound does (a float sum of
    # int(gap * SR) drifted a sample per gap and made the engine loop click).
    regions = {}; parts = []; pos = 0; gap_n = round(gap * SR)
    for key, sig in items:
        regions[key] = [round(pos / SR, 6), round(len(sig) / SR, 6)]
        parts.append(sig); pos += len(sig)
        parts.append(np.zeros(gap_n)); pos += gap_n
    data = np.concatenate(parts)
    pos = pos / SR
    wav = os.path.join(HERE, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(data, -1, 1) * 32767).astype("<i2").tobytes())
    ogg = os.path.join(HERE, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
    os.remove(wav)
    return regions, pos
sfx_regions, sfx_len = write_sheet(list(SFX.items()), "sfx", 0.3)
music_regions, music_len = write_sheet([(k, v[0]) for k, v in MUSIC.items()], "music", 0.5)
json.dump({"sfx": sfx_regions, "music": music_regions, "looped": sorted(LOOPED)}, open(os.path.join(HERE, "regions.json"), "w"), indent=2)

# Keep the asset ids already pasted into SoundSheet (a re-run must not wipe them; upload the new files and update).
sheet_path = os.path.join(ROOT, "src", "shared", "SoundSheet.luau")
old_ids = {"SfxId": "", "MusicId": ""}
if os.path.exists(sheet_path):
    import re
    for key in old_ids:
        m = re.search(r'SoundSheet\.' + key + r' = "([^"]*)"', open(sheet_path).read())
        if m:
            old_ids[key] = m.group(1)
lua = ["--!strict",
       "-- The game's own sounds (art/audio/make_audio.py writes this file): two audio assets, sfx.ogg and music.ogg,",
       "-- and where each sound / music loop sits in them (start, length in seconds; client/Sounds.luau plays the region).",
       "-- Upload art/audio/sfx.ogg and art/audio/music.ogg (Asset Manager → Import) and paste the ids below.",
       "", "local SoundSheet = {}", "",
       f'SoundSheet.SfxId = "{old_ids["SfxId"]}" -- "rbxassetid://…" of art/audio/sfx.ogg',
       f'SoundSheet.MusicId = "{old_ids["MusicId"]}" -- "rbxassetid://…" of art/audio/music.ogg', "",
       "SoundSheet.Sfx = {"]
for k, (s, l) in sfx_regions.items():
    lua.append(f"\t{k} = {{ {s}, {l} }},")
lua += ["} :: { [string]: { number } }", "", "SoundSheet.Music = {"]
for k, (s, l) in music_regions.items():
    lua.append(f"\t{k} = {{ {s}, {l} }},")
lua += ["} :: { [string]: { number } }", "", "-- Sounds that loop (their region repeats seamlessly).",
        "SoundSheet.Looped = { " + ", ".join(f"{k} = true" for k in sorted(LOOPED)) + " } :: { [string]: boolean }", "", "return SoundSheet", ""]
open(sheet_path, "w").write("\n".join(lua))
print(f"sfx: {len(SFX)} sounds, {sfx_len:.1f} s;  music: {len(MUSIC)} loops, {music_len:.1f} s")
