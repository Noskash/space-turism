"""Generates the game's chiptune sound effects (mono 16-bit WAV, 22050 Hz).

Standard library only. Run from anywhere:  python sounds/gen_sounds.py
Each sound is a small function below; tweak and re-run, Godot re-imports the WAVs.
Loops (hum, downlink) are written loop-friendly; Sfx.gd turns looping on in code.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.dirname(os.path.abspath(__file__))
rng = random.Random(42)


def n(seconds):
    return int(seconds * RATE)


def square(phase, duty=0.5):
    return 1.0 if (phase % 1.0) < duty else -1.0


def tri(phase):
    p = phase % 1.0
    return 4 * p - 1 if p < 0.5 else 3 - 4 * p


def env(i, total, attack=0.005, release=None):
    """Linear attack, then linear decay to 0 at the end (or after `release` seconds)."""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    length = total / RATE if release is None else release
    return a * max(0.0, 1.0 - t / length)


def tone(freq_from, freq_to, seconds, wave_fn=square, volume=0.5, attack=0.005, duty=0.5, curve=1.0):
    total = n(seconds)
    out, phase = [], 0.0
    for i in range(total):
        k = (i / total) ** curve
        f = freq_from + (freq_to - freq_from) * k
        phase += f / RATE
        s = wave_fn(phase, duty) if wave_fn is square else wave_fn(phase)
        out.append(s * volume * env(i, total, attack))
    return out


def noise(seconds, volume=0.5, smooth=0.0, attack=0.002, step=1):
    """White noise; `smooth` (0..0.99) is a one-pole low-pass, `step` holds samples (crunchier)."""
    total = n(seconds)
    out, lp, held = [], 0.0, 0.0
    for i in range(total):
        if i % step == 0:
            held = rng.uniform(-1, 1)
        lp = lp * smooth + held * (1 - smooth)
        out.append(lp * volume * env(i, total, attack))
    return out


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def mix(*parts):
    length = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(length)]


def silence(seconds):
    return [0.0] * n(seconds)


def save(name, samples):
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))
    print("wrote", path)


def note(semitones_from_a4):
    return 440.0 * 2 ** (semitones_from_a4 / 12)


# --- UI ---------------------------------------------------------------------------------
def ui_hover():
    return tone(1320, 1320, 0.035, volume=0.18, duty=0.25)


def ui_click():
    return seq(tone(660, 660, 0.04, volume=0.3), tone(990, 990, 0.07, volume=0.3))


# --- crew / stations --------------------------------------------------------------------
def step():
    return noise(0.04, volume=0.35, smooth=0.85)


def dock():
    return seq(tone(330, 330, 0.03, volume=0.3, duty=0.25), tone(660, 660, 0.06, volume=0.3, duty=0.25))


def undock():
    return seq(tone(660, 660, 0.03, volume=0.25, duty=0.25), tone(330, 330, 0.06, volume=0.25, duty=0.25))


def select():
    return tone(880, 880, 0.04, volume=0.22, duty=0.125)


def toggle():
    return mix(tone(520, 260, 0.08, volume=0.3), noise(0.03, volume=0.25, smooth=0.3))


def work_tick():
    return tone(700, 700, 0.03, volume=0.2, duty=0.25)


def denied():
    return seq(tone(140, 140, 0.09, volume=0.35), silence(0.03), tone(110, 110, 0.14, volume=0.35))


# --- mission events -----------------------------------------------------------------------
def fixed():
    notes = [0, 4, 7, 12]  # major arpeggio from C5
    return seq(*[tone(note(3 + s), note(3 + s), 0.07, volume=0.3, duty=0.25) for s in notes])


def alarm():
    beep = lambda f: tone(f, f, 0.12, volume=0.32, duty=0.5, attack=0.003)
    return seq(beep(988), silence(0.03), beep(740), silence(0.03), beep(988), silence(0.03), beep(740))


def explode():
    body = noise(0.7, volume=0.8, smooth=0.6, step=3)
    thump = tone(160, 40, 0.35, wave_fn=tri, volume=0.7, curve=0.5)
    return mix(body, thump)


def fizzle():
    return noise(0.3, volume=0.3, smooth=0.95)


def burn():
    total = n(0.8)
    rumble = noise(0.8, volume=0.9, smooth=0.93)
    # swell in, then fade out
    return [s * min(1.0, i / n(0.08)) for i, s in enumerate(rumble)]


def brownout():
    return mix(tone(600, 50, 0.8, wave_fn=tri, volume=0.5, curve=0.6), noise(0.15, volume=0.3, smooth=0.5))


def toast():
    return tone(1046, 1046, 0.03, volume=0.12, duty=0.25)


# --- loops --------------------------------------------------------------------------------
def downlink():
    """0.4 s of data chirps; loops seamlessly (every chirp ends at zero)."""
    out = []
    while len(out) < n(0.4) - n(0.03):
        f = rng.choice([1568, 1760, 2093, 2349])
        out += tone(f, f, 0.025, volume=0.13, duty=0.25, attack=0.001)
        out += silence(0.008)
    return out + silence(0.4 - len(out) / RATE)


def hum():
    """4 s ship ambience: low engine drone + air. Whole cycles of every partial -> seamless loop."""
    seconds = 4.0
    total = n(seconds)
    out, lp = [], 0.0
    for i in range(total):
        t = i / RATE
        drone = 0.20 * math.sin(2 * math.pi * 55 * t) + 0.08 * math.sin(2 * math.pi * 110 * t)
        drone *= 0.85 + 0.15 * math.sin(2 * math.pi * 0.5 * t)  # slow breathing
        lp = lp * 0.97 + rng.uniform(-1, 1) * 0.03
        out.append(drone + lp * 0.6)
    fade = n(0.05)  # hide the noise seam
    for i in range(fade):
        k = i / fade
        out[i] = out[i] * k + out[total - fade + i] * (1 - k)
    return out[: total - fade]


SOUNDS = {
    "ui_hover": ui_hover, "ui_click": ui_click,
    "step": step, "dock": dock, "undock": undock, "select": select, "toggle": toggle,
    "work_tick": work_tick, "denied": denied,
    "fixed": fixed, "alarm": alarm, "explode": explode, "fizzle": fizzle, "burn": burn,
    "brownout": brownout, "toast": toast,
    "downlink": downlink, "hum": hum,
}

if __name__ == "__main__":
    for name, fn in SOUNDS.items():
        save(name, fn())
