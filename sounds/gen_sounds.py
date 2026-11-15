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


# --- launch -------------------------------------------------------------------------------
def rocket():
    """1 s seamless roar: crunchy low noise + a rough low square. Pitch/volume follow throttle."""
    seconds = 1.0
    total = n(seconds)
    out, lp, lp2, held = [], 0.0, 0.0, 0.0
    for i in range(total):
        if i % 2 == 0:
            held = rng.uniform(-1, 1)
        lp = lp * 0.82 + held * 0.18
        lp2 = lp2 * 0.97 + held * 0.03
        t = i / RATE
        buzz = 0.18 * square(t * 40.0) * (0.6 + 0.4 * math.sin(2 * math.pi * 3 * t))
        out.append(lp * 0.55 + lp2 * 1.6 + buzz)
    fade = n(0.05)
    for i in range(fade):
        k = i / fade
        out[i] = out[i] * k + out[total - fade + i] * (1 - k)
    return out[: total - fade]


def countdown():
    return tone(880, 880, 0.09, volume=0.3, duty=0.5)


def go():
    return tone(1760, 1760, 0.25, volume=0.3, duty=0.5)


def ignition():
    boom = tone(120, 30, 0.6, wave_fn=tri, volume=0.8, curve=0.4)
    hiss = noise(0.9, volume=0.6, smooth=0.7, step=2)
    return mix(boom, hiss)


def stage():
    clunk = seq(tone(200, 90, 0.08, volume=0.6), noise(0.05, volume=0.5, smooth=0.2))
    pop = noise(0.4, volume=0.45, smooth=0.6)
    return seq(clunk, pop)


def orbit():
    notes = [0, 4, 7, 12, 16, 19, 24]
    return seq(*[tone(note(s - 9), note(s - 9), 0.08, volume=0.28, duty=0.25) for s in notes],
               tone(note(15), note(15), 0.4, volume=0.28, duty=0.25))


def lever():
    return mix(tone(300, 300, 0.025, volume=0.25, duty=0.25), noise(0.02, volume=0.2, smooth=0.1))


def creak():
    """Structural stress warning: metal groan."""
    return mix(tone(90, 70, 0.5, wave_fn=tri, volume=0.5, curve=0.5), noise(0.5, volume=0.2, smooth=0.9))


def engine():
    """Cruise engine drone, 2 s seamless: pulsing low thrum."""
    seconds = 2.0
    total = n(seconds)
    out, lp = [], 0.0
    for i in range(total):
        t = i / RATE
        pulse = 0.75 + 0.25 * math.sin(2 * math.pi * 4 * t)
        thrum = 0.22 * tri(t * 82.5) + 0.1 * square(t * 41.25, 0.3)
        lp = lp * 0.9 + rng.uniform(-1, 1) * 0.1
        out.append((thrum + lp * 0.25) * pulse)
    fade = n(0.05)
    for i in range(fade):
        k = i / fade
        out[i] = out[i] * k + out[total - fade + i] * (1 - k)
    return out[: total - fade]


# --- reminders / tutorial -------------------------------------------------------------------
def remind():
    """Clock-like double tick for a ticket (or stage window) running out."""
    return seq(tone(1568, 1568, 0.03, volume=0.22, duty=0.25), silence(0.04),
               tone(1568, 1568, 0.03, volume=0.22, duty=0.25))


def warn():
    """A ticket just crossed 75% of its time: short falling chirp."""
    return seq(tone(1320, 880, 0.08, volume=0.25, duty=0.5), tone(1320, 880, 0.08, volume=0.25, duty=0.5))


def chute():
    """Parachute opening: cloth whoosh + snap."""
    swell = noise(0.5, volume=0.5, smooth=0.85)
    swell = [v * min(1.0, i / n(0.3)) for i, v in enumerate(swell)]
    return seq(swell, tone(220, 140, 0.06, volume=0.4), noise(0.08, volume=0.3, smooth=0.3))


def page():
    """Tutorial pane turn."""
    return seq(tone(988, 988, 0.03, volume=0.18, duty=0.25), tone(1319, 1319, 0.05, volume=0.18, duty=0.25))


def siren():
    """Radiation storm warning: two-tone rising/falling wail (1.2 s)."""
    return seq(tone(520, 880, 0.6, wave_fn=tri, volume=0.38, curve=0.7),
               tone(880, 520, 0.6, wave_fn=tri, volume=0.38, curve=1.4))


def wave_hit():
    """Radiation wave washing over the ship: rising hiss + low throb."""
    total = n(2.0)
    hiss = noise(2.0, volume=0.45, smooth=0.75)
    hiss = [x * min(1.0, i / n(0.9)) for i, x in enumerate(hiss)]
    throb = tone(70, 45, 2.0, wave_fn=tri, volume=0.5, attack=0.5)
    return mix(hiss, throb)


def impact():
    """Dust grain hitting the hull: sharp metallic ping + crunch."""
    ping = tone(2400, 1700, 0.25, wave_fn=tri, volume=0.35, curve=0.4)
    crunch = noise(0.12, volume=0.6, step=2)
    return mix(ping, crunch)


def static():
    """Radio interference, 1 s seamless: crackly band noise."""
    out = noise(1.0, volume=0.25, smooth=0.3, attack=0.0, step=2)
    return [x * (1.0 if rng.random() > 0.03 else 2.2) for x in out]


def hiss():
    """Air venting through a hull breach, 1 s seamless: steady high hiss with a slow flutter."""
    out = noise(1.0, volume=0.3, smooth=0.15, attack=0.0)
    return [x * (0.8 + 0.2 * math.sin(2 * math.pi * 4 * i / len(out))) for i, x in enumerate(out)]


def clank():
    """Toolbox grabbed / put back: two metal knocks."""
    knock = lambda f: mix(tone(f, f * 0.8, 0.09, wave_fn=tri, volume=0.4, curve=0.5), noise(0.04, volume=0.3, step=3))
    return seq(knock(900), silence(0.05), knock(700))


# --- fun pass: burn shove, fire, pings, grades ---------------------------------------------
def klaxon():
    """BRACE: a burn is spooling up. Short harsh two-tone honk (plays every 0.5 s)."""
    return seq(tone(392, 392, 0.12, volume=0.32, duty=0.35), tone(330, 330, 0.16, volume=0.32, duty=0.35))


def whoosh():
    """The burn fires and throws the crew: a falling rush of air."""
    rush = noise(0.45, volume=0.55, smooth=0.6, attack=0.02)
    thump = tone(110, 50, 0.3, wave_fn=tri, volume=0.5)
    return mix(rush, thump)


def ignite():
    """A flame catches: soft whump + crackle."""
    whump = noise(0.35, volume=0.6, smooth=0.85, attack=0.01)
    crackle = [x * (1.0 if rng.random() < 0.08 else 0.0) for x in noise(0.35, volume=0.6, step=2)]
    return mix(whump, crackle)


def fire():
    """Burning, 1 s seamless: low roar + random pops."""
    roar = noise(1.0, volume=0.22, smooth=0.9, attack=0.0)
    pops = [(rng.uniform(-1, 1) * 0.5 if rng.random() < 0.004 else 0.0) for _ in range(n(1.0))]
    return mix(roar, pops)


def spray():
    """Extinguisher, 1 s seamless: wide hiss, a little lower than a breach."""
    out = noise(1.0, volume=0.32, smooth=0.35, attack=0.0)
    return [x * (0.85 + 0.15 * math.sin(2 * math.pi * 7 * i / len(out))) for i, x in enumerate(out)]


def ping():
    """Crew call-out: bright two-note chirp."""
    return seq(tone(note(15), note(15), 0.05, volume=0.3, duty=0.25), tone(note(22), note(22), 0.09, volume=0.3, duty=0.25))


def perfect():
    """PERFECT grade: quick rising arpeggio."""
    return seq(*[tone(note(s), note(s), 0.05, volume=0.25, duty=0.25) for s in (12, 16, 19, 24)])


# --- footsteps + spacewalk (appended: older WAVs stay byte-identical) ---------------------------
def step_walk():
    """Boot on the metal deck: soft low thud + a little grit."""
    return mix(tone(150, 70, 0.06, wave_fn=tri, volume=0.5, curve=0.5), noise(0.03, volume=0.22, smooth=0.55, step=2))


def step_run():
    """Running: heavier thud + a short metallic clink of the deck plate."""
    return mix(tone(180, 75, 0.07, wave_fn=tri, volume=0.6, curve=0.5), noise(0.04, volume=0.32, smooth=0.35, step=3),
               tone(1500, 1200, 0.025, wave_fn=tri, volume=0.07))


def step_eva():
    """Magnetic boot on the hull, heard only through the suit (no air outside): dull muffled clunk."""
    return mix(tone(95, 50, 0.1, wave_fn=tri, volume=0.55, curve=0.5), noise(0.07, volume=0.25, smooth=0.95))


def breath():
    """Inside the helmet, 3.2 s seamless: slow inhale, exhale, pause (starts and ends silent)."""
    total = n(3.2)
    out, lp = [], 0.0
    for i in range(total):
        t = i / RATE
        if t < 1.1:
            a = math.sin(math.pi * t / 1.1) * 0.8
        elif t < 2.5:
            a = math.sin(math.pi * (t - 1.1) / 1.4)
        else:
            a = 0.0
        lp = lp * 0.82 + rng.uniform(-1, 1) * 0.18
        out.append(lp * 0.5 * a)
    return out


def airlock():
    """Airlock cycling: hatch clunk, then the air hisses out (falling), then a click."""
    clunk = mix(tone(120, 60, 0.12, wave_fn=tri, volume=0.6), noise(0.05, volume=0.3, step=4))
    hiss_out = noise(0.9, volume=0.4, smooth=0.3, attack=0.02)
    hiss_out = [x * (1.0 - i / len(hiss_out)) ** 1.5 for i, x in enumerate(hiss_out)]
    click = tone(900, 900, 0.03, wave_fn=square, volume=0.15, duty=0.25)
    return seq(clunk, hiss_out, click)


SOUNDS = {
    "ui_hover": ui_hover, "ui_click": ui_click,
    "step": step, "dock": dock, "undock": undock, "select": select, "toggle": toggle,
    "work_tick": work_tick, "denied": denied,
    "fixed": fixed, "alarm": alarm, "explode": explode, "fizzle": fizzle, "burn": burn,
    "brownout": brownout, "toast": toast,
    "downlink": downlink, "hum": hum,
    "rocket": rocket, "countdown": countdown, "go": go, "ignition": ignition, "stage": stage,
    "orbit": orbit, "lever": lever, "creak": creak, "engine": engine,
    "remind": remind, "warn": warn, "chute": chute, "page": page,
    "siren": siren, "wave": wave_hit, "impact": impact, "static": static,
    "hiss": hiss, "clank": clank,
    "klaxon": klaxon, "whoosh": whoosh, "ignite": ignite, "fire": fire, "spray": spray,
    "ping": ping, "perfect": perfect,
    "step_walk": step_walk, "step_run": step_run, "step_eva": step_eva, "breath": breath, "airlock": airlock,
}

if __name__ == "__main__":
    for name, fn in SOUNDS.items():
        save(name, fn())
