# -*- coding: utf-8 -*-
"""
Procedural SFX generator for Lone Wolf.

Every sound is synthesised from scratch (noise + oscillators + envelopes),
so the whole audio set is original and carries no third-party licence.

Usage:  python tools/gen_sfx.py
Output: assets/audio/sfx/*.wav   (44.1 kHz, 16-bit mono)
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "audio", "sfx")

# ----------------------------------------------------------------- primitives

def noise(dur, seed=None):
    rnd = random.Random(seed)
    return [rnd.uniform(-1.0, 1.0) for _ in range(int(SR * dur))]


def sine(dur, f0, f1=None):
    n = int(SR * dur)
    f1 = f0 if f1 is None else f1
    out, phase = [0.0] * n, 0.0
    for i in range(n):
        t = i / float(n - 1) if n > 1 else 0.0
        f = f0 * (f1 / f0) ** t if f0 > 0 and f1 > 0 else f0
        phase += 2.0 * math.pi * f / SR
        out[i] = math.sin(phase)
    return out


def lowpass(sig, cutoff, poles=1):
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    out = list(sig)
    for _ in range(poles):
        y = 0.0
        for i, x in enumerate(out):
            y = (1.0 - a) * x + a * y
            out[i] = y
    return out


def highpass(sig, cutoff, poles=1):
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    out = list(sig)
    for _ in range(poles):
        y, prev = 0.0, 0.0
        for i, x in enumerate(out):
            y = a * (y + x - prev)
            prev = x
            out[i] = y
    return out


def decay(sig, tau, attack=0.0008):
    """Exponential decay with a short attack ramp so nothing clicks."""
    n = len(sig)
    na = max(1, int(SR * attack))
    out = [0.0] * n
    for i in range(n):
        env = (i / float(na)) if i < na else math.exp(-(i - na) / (SR * tau))
        out[i] = sig[i] * env
    return out


def mix(*layers):
    n = max(len(l) for l in layers)
    out = [0.0] * n
    for l in layers:
        for i, v in enumerate(l):
            out[i] += v
    return out


def gain(sig, g):
    return [s * g for s in sig]


def pad(sig, dur):
    n = int(SR * dur)
    if len(sig) < n:
        return sig + [0.0] * (n - len(sig))
    return sig[:n]


def delay(sig, seconds):
    return [0.0] * int(SR * seconds) + list(sig)


def normalize(sig, peak=0.89):
    m = max(abs(s) for s in sig) or 1.0
    k = peak / m
    # gentle saturation instead of a hard ceiling
    return [math.tanh(s * k * 1.15) * 0.92 for s in sig]


def write(name, sig):
    sig = normalize(sig)
    path = os.path.join(OUT, name + ".wav")
    w = wave.open(path, "wb")
    try:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in sig))
    finally:
        w.close()
    return path, len(sig) / float(SR)

# -------------------------------------------------------------------- designs

def gunshot(crack_tau, body_f, body_tau, tail_tau, bright, seed, dur):
    """Layered gunshot: transient crack + low body thump + filtered tail."""
    crack = decay(highpass(noise(dur, seed), bright, 2), crack_tau)
    body = decay(sine(dur, body_f, body_f * 0.45), body_tau)
    tail = decay(lowpass(noise(dur, seed + 1), bright * 0.35, 2), tail_tau, attack=0.004)
    click = pad(decay(highpass(noise(0.01, seed + 2), 4000), 0.0015), dur)
    return mix(gain(crack, 0.95), gain(body, 0.75), gain(tail, 0.38), gain(click, 0.5))


def mech_click(seed, tone, tau=0.012, dur=0.09):
    """A single mechanical click: magazine catch, bolt, trigger."""
    n = decay(highpass(noise(dur, seed), 1800, 2), tau)
    t = decay(sine(dur, tone, tone * 0.7), tau * 0.8)
    return mix(gain(n, 0.9), gain(t, 0.35))


def blip(f0, f1, dur, tau):
    return decay(sine(dur, f0, f1), tau, attack=0.002)


def chord(freqs, dur, tau, spread=0.045):
    layers = []
    for i, f in enumerate(freqs):
        layers.append(delay(decay(sine(dur, f), tau, attack=0.006), spread * i))
    return mix(*layers)

# ---------------------------------------------------------------------- build

def main():
    if not os.path.isdir(OUT):
        os.makedirs(OUT)
    made = []

    # --- weapon fire -------------------------------------------------------
    made.append(write("wpn_pistol_fire", gunshot(0.055, 130, 0.075, 0.20, 2400, 11, 0.32)))
    made.append(write("wpn_smg_fire", gunshot(0.030, 165, 0.045, 0.12, 3000, 23, 0.20)))
    made.append(write("wpn_rifle_fire", gunshot(0.060, 110, 0.090, 0.26, 2100, 37, 0.40)))
    made.append(write("wpn_sniper_fire", gunshot(0.110, 62, 0.190, 0.85, 1500, 53, 1.10)))
    made.append(write("wpn_shotgun_fire", gunshot(0.085, 85, 0.130, 0.45, 1200, 71, 0.60)))

    # --- handling ----------------------------------------------------------
    made.append(write("wpn_dry_fire", mech_click(101, 2600, 0.006, 0.06)))
    made.append(write("wpn_mag_out",
                      mix(mech_click(103, 900, 0.020, 0.22),
                          gain(pad(mech_click(104, 1500, 0.010), 0.22), 0.4))))
    made.append(write("wpn_mag_in",
                      pad(delay(mech_click(105, 700, 0.028, 0.21), 0.05), 0.26)))
    made.append(write("wpn_bolt",
                      mix(pad(mech_click(107, 1400, 0.016, 0.18), 0.26),
                          pad(delay(mech_click(108, 1000, 0.020, 0.11), 0.07), 0.26))))
    made.append(write("wpn_swap", mech_click(109, 1200, 0.022, 0.16)))

    # --- impacts / feedback ------------------------------------------------
    made.append(write("impact_concrete", decay(highpass(noise(0.16, 131), 900, 2), 0.030)))
    made.append(write("impact_metal",
                      mix(decay(highpass(noise(0.30, 137), 1600, 2), 0.035),
                          gain(decay(sine(0.30, 2400, 1700), 0.12), 0.45))))
    made.append(write("impact_flesh", decay(lowpass(noise(0.20, 139), 700, 2), 0.045)))
    made.append(write("hitmarker", blip(1450, 1450, 0.07, 0.022)))
    made.append(write("hitmarker_headshot",
                      mix(pad(blip(1900, 1900, 0.09, 0.026), 0.14),
                          pad(delay(blip(2600, 2600, 0.09, 0.026), 0.045), 0.14))))
    made.append(write("bullet_whizby",
                      gain(decay(lowpass(noise(0.22, 149), 2600, 1), 0.055, 0.02), 0.8)))

    # --- movement ----------------------------------------------------------
    for i in range(1, 4):
        made.append(write("footstep_%d" % i,
                          decay(lowpass(noise(0.13, 150 + i), 1100 + i * 190, 2), 0.026)))
    made.append(write("jump", decay(lowpass(noise(0.12, 161), 900, 2), 0.020)))
    made.append(write("land",
                      mix(decay(lowpass(noise(0.22, 163), 620, 2), 0.045),
                          gain(decay(sine(0.22, 95, 55), 0.06), 0.5))))

    # --- match flow --------------------------------------------------------
    made.append(write("death", blip(420, 90, 0.85, 0.26)))
    made.append(write("round_win", chord([523.25, 659.25, 783.99], 1.0, 0.34)))
    made.append(write("round_lose", chord([392.0, 311.13, 261.63], 1.1, 0.36)))
    made.append(write("match_win", chord([523.25, 659.25, 783.99, 1046.5], 1.7, 0.52, 0.075)))
    made.append(write("match_lose", chord([349.23, 261.63, 207.65], 1.7, 0.55, 0.075)))
    made.append(write("countdown_beep", blip(880, 880, 0.15, 0.05)))
    made.append(write("countdown_go", blip(1320, 1320, 0.40, 0.14)))

    # --- ui ----------------------------------------------------------------
    made.append(write("ui_click", blip(1100, 900, 0.06, 0.018)))
    made.append(write("ui_hover", gain(blip(1600, 1600, 0.04, 0.011), 0.55)))

    for path, dur in made:
        print("  %-28s %5.2fs" % (os.path.basename(path), dur))
    print("")
    print("%d sound effects written to assets/audio/sfx/" % len(made))


if __name__ == "__main__":
    main()
