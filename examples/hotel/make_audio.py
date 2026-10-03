#!/usr/bin/env python3
"""Synthesizes the hotel's music and sounds (numpy only, seeded) and encodes them to Ogg
Vorbis with ffmpeg: the lobby's soft jazz loop, the hotel's eerie hum, the Watcher's chase
music, and the Howl's rumble and scream, a door, a drawer and the death sting."""
import os
import subprocess
import wave
import numpy as np

here = os.path.dirname(os.path.abspath(__file__))
SR = 32000
rng = np.random.default_rng(11)


def t_of(sec):
    return np.arange(int(sec * SR)) / SR


def note(n):  # MIDI number -> Hz
    return 440.0 * 2 ** ((n - 69) / 12)


def env(n, a=0.01, d=0.3, s=0.6, r=0.2, length=None):
    length = length or n / SR
    t = np.arange(n) / SR
    e = np.ones(n) * s
    e[t < a] = t[t < a] / a
    m = (t >= a) & (t < a + d)
    e[m] = 1 - (1 - s) * (t[m] - a) / d
    rel = t > length - r
    e[rel] *= np.clip((length - t[rel]) / r, 0, 1)
    return e


def lowpass(x, cutoff):
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    f *= 1 / (1 + (freqs / cutoff) ** 4)
    return np.fft.irfft(f, len(x))


def bandpass(x, lo, hi):
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    f *= (1 / (1 + (freqs / hi) ** 4)) * (1 - 1 / (1 + (freqs / lo) ** 4))
    return np.fft.irfft(f, len(x))


def saw(freq, t):
    return 2 * ((freq * t) % 1.0) - 1


def place(buf, sig, at):
    i = int(at * SR)
    j = min(len(buf), i + len(sig))
    if i < len(buf):
        buf[i:j] += sig[: j - i]


def reverb(x, amount=0.3, times=(0.031, 0.047, 0.071, 0.097, 0.131)):
    out = x.copy()
    for k, d in enumerate(times):
        n = int(d * SR)
        g = amount * (0.7 ** k)
        for rep in range(1, 6):
            if n * rep >= len(x):
                break
            out[n * rep:] += x[: -n * rep] * g * (0.6 ** rep)
    return out


def loopable(x, fade=0.4):
    # The tail fades into the start: no click where the loop wraps.
    n = int(fade * SR)
    x = x.copy()
    head = x[:n].copy()
    x[:n] = head * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
    return x[:-n]


def save(name, x, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    wav = os.path.join(here, 'assets', name + '.wav')
    with wave.open(wav, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    ogg = os.path.join(here, 'assets', name + '.ogg')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '4', ogg], check=True)
    os.remove(wav)
    print(name, os.path.getsize(ogg) // 1024, 'KB')


def epiano(freq, length):
    t = t_of(length)
    tone = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * 2 * freq * t) * np.exp(-t * 3) + 0.12 * np.sin(2 * np.pi * 3.01 * freq * t) * np.exp(-t * 6)
    return tone * np.exp(-t * 1.6) * env(len(t), 0.005, 0.1, 1, 0.08)


def lobby():
    bpm = 84
    beat = 60 / bpm
    bars = 16
    total = bars * 4 * beat + 0.4
    out = np.zeros(int(total * SR))
    chords = [[57, 60, 64, 67], [50, 53, 57, 60], [55, 59, 62, 65], [48, 52, 55, 59]]  # Am7 Dm7 G7 Cmaj7
    bass = [45, 38, 43, 36]
    melody = [76, 74, 72, 71, 72, 74, 76, 79, 77, 76, 74, 72, 71, 72, 69, 67]
    for bar in range(bars):
        c = chords[bar % 4]
        t0 = bar * 4 * beat
        for k, n in enumerate(c):
            place(out, epiano(note(n), beat * 3.6) * 0.16, t0 + k * 0.012)
            place(out, epiano(note(n), beat * 1.4) * 0.09, t0 + 2.5 * beat)
        for k in range(4):
            tb = t_of(beat * 0.9)
            place(out, np.sin(2 * np.pi * note(bass[bar % 4] + (7 if k == 2 else 0)) * tb) * np.exp(-tb * 2.5) * 0.35, t0 + k * beat)
            # brushed hat
            nz = rng.standard_normal(int(0.08 * SR)) * np.exp(-np.arange(int(0.08 * SR)) / SR * 50)
            place(out, bandpass(nz, 4000, 9000) * (0.08 if k % 2 else 0.05), t0 + k * beat + beat * 0.5)
        if bar % 2 == 1:
            for k in range(2):
                n = melody[(bar * 2 + k) % len(melody)]
                place(out, epiano(note(n), beat * 1.8) * 0.18, t0 + (1 + 2 * k) * beat)
    return loopable(reverb(lowpass(out, 6000), 0.25))


def hotel():
    total = 40.4
    t = t_of(total)
    drone = sum(saw(note(n) * (1 + det), t) for n, det in [(33, 0), (33, 0.004), (40, -0.003), (45, 0.002)])
    drone = lowpass(drone, 280) * 0.5
    drone *= 0.7 + 0.3 * np.sin(2 * np.pi * t / 10)
    wind = bandpass(rng.standard_normal(len(t)), 200, 900) * (0.25 + 0.2 * np.sin(2 * np.pi * t / 13 + 1))
    out = drone + wind * 0.6
    # Distant metallic tones now and then.
    for at in [3.2, 11.7, 19.9, 27.3, 34.6]:
        n = rng.choice([69, 72, 75, 78])
        tt = t_of(5)
        bell = (np.sin(2 * np.pi * note(n) * tt) + 0.5 * np.sin(2 * np.pi * note(n) * 2.76 * tt)) * np.exp(-tt * 0.9)
        place(out, bell * 0.18, at)
    return loopable(reverb(out, 0.4))


def drum_kick():
    tt = t_of(0.35)
    f = 120 * np.exp(-tt * 18) + 45
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 7)


def drum_snare():
    tt = t_of(0.25)
    return (bandpass(rng.standard_normal(len(tt)), 1200, 7000) * 0.8 + np.sin(2 * np.pi * 190 * tt) * 0.5) * np.exp(-tt * 14)


def chase():
    bpm = 152
    beat = 60 / bpm
    bars = 16
    total = bars * 4 * beat + 0.4
    out = np.zeros(int(total * SR))
    roots = [45, 45, 46, 44]  # A A Bb G#: dread
    for bar in range(bars):
        t0 = bar * 4 * beat
        r = roots[(bar // 2) % 4]
        for k in range(4):
            place(out, drum_kick() * 0.9, t0 + k * beat)
            if k in (1, 3):
                place(out, drum_snare() * 0.55, t0 + k * beat)
        # A driving bass on eighths.
        for k in range(8):
            tb = t_of(beat * 0.45)
            n = r - 12 + (12 if k % 4 == 3 else 0)
            b = lowpass(saw(note(n), tb), 700) * env(len(tb), 0.003, 0.1, 0.7, 0.05)
            place(out, b * 0.5, t0 + k * beat / 2)
        # Staccato string stabs on the off-beats, a minor chord that slides.
        for k in [0.5, 1.5, 2.5, 3.0, 3.5]:
            ts = t_of(beat * 0.3)
            stab = sum(saw(note(n), ts) for n in [r + 12, r + 15, r + 19])
            place(out, lowpass(stab, 3000) * env(len(ts), 0.002, 0.08, 0.4, 0.05) * 0.16, t0 + k * beat)
        # A screaming high tremolo that comes in for the second half.
        if bar >= 8:
            tt = t_of(4 * beat)
            trem = np.sin(2 * np.pi * note(r + 36) * tt) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 12 * tt)))
            place(out, trem * 0.05 * (bar - 7) / 8, t0)
        # Hi-hats on sixteenths.
        for k in range(16):
            n = int(0.04 * SR)
            hat = bandpass(rng.standard_normal(n), 6000, 12000) * np.exp(-np.arange(n) / SR * 90)
            place(out, hat * (0.12 if k % 2 == 0 else 0.07), t0 + k * beat / 4)
    return loopable(reverb(out, 0.12), 0.15)


def howl_near():
    total = 4.5
    t = t_of(total)
    rise = np.clip(t / total, 0, 1) ** 1.6
    rumble = lowpass(rng.standard_normal(len(t)), 160) * 3
    sweep = saw(30 + 50 * rise, t) * 0.4
    buzz = np.sign(np.sin(2 * np.pi * 50 * t)) * 0.08 * (rng.random(len(t)) > 0.6)  # flickering lights
    out = (rumble + lowpass(sweep, 400) + buzz) * (0.1 + rise)
    return out * env(len(t), 0.4, 0.1, 1, 0.3)


def howl_scream():
    total = 2.4
    t = t_of(total)
    mod = np.sin(2 * np.pi * 6 * t) * 120 + np.sin(2 * np.pi * 0.9 * t) * 300
    fm = np.sin(2 * np.pi * np.cumsum(620 + mod) / SR)
    screech = fm + 0.6 * np.sin(2 * np.pi * np.cumsum(1250 + mod * 2) / SR)
    roar = lowpass(rng.standard_normal(len(t)), 900) * 1.5
    out = screech * 0.5 + roar
    return loopable(out, 0.3)


def door():
    total = 0.9
    t = t_of(total)
    f = 520 + 260 * np.sin(2 * np.pi * 1.3 * t) + rng.standard_normal(len(t)).cumsum() * 0.02
    creak = np.sin(2 * np.pi * np.cumsum(f) / SR) * (0.5 + 0.5 * (np.sin(2 * np.pi * 34 * t) > 0))
    thud = lowpass(rng.standard_normal(len(t)), 300) * np.exp(-(t - 0.75).clip(0) * 20) * (t > 0.75) * 3
    return lowpass(creak, 3000) * env(len(t), 0.02, 0.1, 0.8, 0.2) * 0.4 + thud


def drawer():
    total = 0.5
    t = t_of(total)
    slide = bandpass(rng.standard_normal(len(t)), 400, 2500) * env(len(t), 0.02, 0.1, 0.8, 0.15)
    knock = lowpass(rng.standard_normal(len(t)), 500) * np.exp(-(t - 0.4).clip(0) * 30) * (t > 0.4) * 2
    return slide * 0.6 + knock


def sting():
    total = 2.2
    t = t_of(total)
    chord = sum(saw(note(n), t) for n in [40, 41, 46, 52, 53, 59])
    hit = lowpass(chord, 2500) * np.exp(-t * 1.5)
    boom = drum_kick()
    out = hit * 0.6
    place(out, boom * 2.0, 0)
    noise = bandpass(rng.standard_normal(len(t)), 1500, 8000) * np.exp(-t * 4)
    return reverb(out + noise * 0.5, 0.3)


save('lobby', lobby(), 0.7)
save('hotel', hotel(), 0.6)
save('chase', chase(), 0.85)
save('howl_near', howl_near(), 0.95)
save('howl_scream', howl_scream(), 0.9)
save('door', door(), 0.8)
save('drawer', drawer(), 0.7)
save('sting', sting(), 0.95)
