#!/usr/bin/env python3
"""
gen_samples.py — Guitar-like sample generator for I2S transceiver simulation.

Generates a .hex file consumed by Verilog's $readmemh, producing a waveform
that imitates a plucked guitar string (sine-sum with decay + noise attack).
"""

import argparse
import json
import math
import os
import random
import sys

# ══════════════════════════════════════════════════════════════════════════════
#  USER PARAMETERS — tweak these to generate different tones
# ══════════════════════════════════════════════════════════════════════════════

# Fundamental frequencies in Hz (standard guitar tuning by default)
# E2=82.41, A2=110.00, D3=146.83, G3=196.00, B3=246.94, E4=329.63
FREQUENCIES_HZ = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]

# Mix weights for each frequency (amplitude, 0.0–1.0)
# Default: strum all strings equally
FREQUENCY_GAINS = [0.4, 0.4, 0.5, 0.6, 0.7, 0.8]

# Decay envelope: how fast each frequency fades (per-sample multiplier)
# 1.0 = no decay, 0.999 = slow decay, 0.99 = fast decay
DECAY_RATES = [0.9995, 0.9995, 0.9990, 0.9985, 0.9980, 0.9970]

# Noise component: adds a percussive "pick" transient
# The noise fades quickly — simulates the attack of a plectrum
NOISE_GAIN = 0.15       # initial noise amplitude (0.0–1.0)
NOISE_DECAY = 0.98      # per-sample noise decay multiplier

# Output format
SAMPLE_RATE = 48000      # Hz
NUM_SAMPLES = 48000      # 1 second of audio at 48 kHz
BIT_DEPTH = 24           # bits per sample

# ── Generated sound type ──
# "pluck"  = Karplus-Strong-like string pluck (default, sounds like guitar)
# "chord"  = sum-of-sines with decay (cleaner, more synthetic)
# "arpeggio" = frequencies ring in one at a time
SOUND_TYPE = "pluck"

# ══════════════════════════════════════════════════════════════════════════════


def load_frequencies_json(path="frequencies.json"):
    """Load frequency configuration from JSON file if it exists."""
    if not os.path.exists(path):
        return None

    with open(path, "r") as f:
        cfg = json.load(f)

    params = {}
    params["frequencies_hz"] = cfg.get("frequencies_hz", FREQUENCIES_HZ)
    params["frequency_gains"] = cfg.get("frequency_gains", FREQUENCY_GAINS)
    params["decay_rates"] = cfg.get("decay_rates", DECAY_RATES)
    params["noise_gain"] = cfg.get("noise_gain", NOISE_GAIN)
    params["noise_decay"] = cfg.get("noise_decay", NOISE_DECAY)
    params["sound_type"] = cfg.get("sound_type", SOUND_TYPE)

    # Validate lengths match
    n_freq = len(params["frequencies_hz"])
    if len(params["frequency_gains"]) != n_freq:
        print(f"Warning: frequency_gains length ({len(params['frequency_gains'])}) "
              f"does not match frequencies_hz ({n_freq}). Padding/truncating.")
        params["frequency_gains"] = (params["frequency_gains"] + [0.5] * n_freq)[:n_freq]
    if len(params["decay_rates"]) != n_freq:
        print(f"Warning: decay_rates length ({len(params['decay_rates'])}) "
              f"does not match frequencies_hz ({n_freq}). Padding/truncating.")
        params["decay_rates"] = (params["decay_rates"] + [0.999] * n_freq)[:n_freq]

    print(f"Loaded configuration from {path}")
    return params


def generate_pluck(num_samples, sample_rate, frequencies_hz, frequency_gains,
                   decay_rates, noise_gain, noise_decay, rng):
    """Generate 'pluck' waveform: sum of decaying sines + noise burst."""
    samples = [0.0] * num_samples

    # Sum of decaying sines
    for freq, gain, decay in zip(frequencies_hz, frequency_gains, decay_rates):
        omega = 2.0 * math.pi * freq / sample_rate
        env = 1.0
        for n in range(num_samples):
            samples[n] += gain * math.sin(omega * n) * env
            env *= decay

    # Add white noise burst (pick attack)
    if noise_gain > 0:
        noise_env = 1.0
        for n in range(num_samples):
            samples[n] += noise_env * rng.uniform(-1.0, 1.0) * noise_gain
            noise_env *= noise_decay

    return samples


def generate_chord(num_samples, sample_rate, frequencies_hz, frequency_gains,
                   decay_rates, rng):
    """Generate 'chord' waveform: sum of decaying sines, no noise."""
    return generate_pluck(num_samples, sample_rate, frequencies_hz,
                          frequency_gains, decay_rates, 0.0, 1.0, rng)


def generate_arpeggio(num_samples, sample_rate, frequencies_hz, frequency_gains,
                      decay_rates, rng):
    """Generate 'arpeggio' waveform: frequencies fade in sequentially."""
    samples = [0.0] * num_samples
    n_freqs = len(frequencies_hz)
    stride = num_samples // n_freqs

    for i, (freq, gain, decay) in enumerate(zip(frequencies_hz, frequency_gains, decay_rates)):
        onset = i * stride
        omega = 2.0 * math.pi * freq / sample_rate

        for n in range(onset, num_samples):
            # Attack envelope: fade in over first 512 samples
            t = n - onset
            attack = min(1.0, t / 512.0)
            env = attack * (decay ** t)
            samples[n] += gain * math.sin(omega * t) * env

    return samples


def quantize(samples, bit_depth):
    """Quantize float samples to signed integer and clip."""
    max_val = (1 << (bit_depth - 1)) - 1
    min_val = -(1 << (bit_depth - 1))

    # Find peak for normalization hint (but don't auto-normalize)
    peak = max(abs(s) for s in samples) or 1.0

    quantized = []
    clipped = 0
    for s in samples:
        # Scale so peak fills about 90% of range (headroom)
        scaled = s / peak * max_val * 0.9
        sample = int(round(scaled))
        if sample > max_val:
            sample = max_val
            clipped += 1
        elif sample < min_val:
            sample = min_val
            clipped += 1
        quantized.append(sample)

    return quantized, clipped, peak


def to_twos_complement_hex(value, bit_depth):
    """Convert signed integer to two's complement hex string."""
    if value < 0:
        value = (1 << bit_depth) + value
    return f"{value:0{bit_depth // 4}X}"


def compute_stats(samples, bit_depth):
    """Compute RMS and peak from float samples."""
    n = len(samples)
    if n == 0:
        return 0.0, 0.0
    peak = max(abs(s) for s in samples)
    rms = math.sqrt(sum(s * s for s in samples) / n)
    return peak, rms


def main():
    parser = argparse.ArgumentParser(
        description="Generate guitar-like samples for I2S simulation")
    parser.add_argument("--output", "-o", default="samples.hex",
                        help="Output .hex file path (default: samples.hex)")
    parser.add_argument("--seed", type=int, default=None,
                        help="Random seed for reproducible noise")
    parser.add_argument("--config", "-c", default="frequencies.json",
                        help="Path to JSON config file (default: frequencies.json)")
    args = parser.parse_args()

    # Load config from JSON (overrides defaults if present)
    cfg = load_frequencies_json(args.config)
    if cfg:
        frequencies_hz = cfg["frequencies_hz"]
        frequency_gains = cfg["frequency_gains"]
        decay_rates = cfg["decay_rates"]
        noise_gain = cfg["noise_gain"]
        noise_decay = cfg["noise_decay"]
        sound_type = cfg["sound_type"]
    else:
        frequencies_hz = FREQUENCIES_HZ
        frequency_gains = FREQUENCY_GAINS
        decay_rates = DECAY_RATES
        noise_gain = NOISE_GAIN
        noise_decay = NOISE_DECAY
        sound_type = SOUND_TYPE

    # Seeded RNG
    rng = random.Random(args.seed)

    # Generate waveform
    print(f"Generating {NUM_SAMPLES} samples at {SAMPLE_RATE} Hz "
          f"({NUM_SAMPLES / SAMPLE_RATE:.2f}s)")
    print(f"Sound type: {sound_type}")
    print(f"Frequencies: {frequencies_hz}")

    if sound_type == "pluck":
        samples = generate_pluck(NUM_SAMPLES, SAMPLE_RATE, frequencies_hz,
                                 frequency_gains, decay_rates,
                                 noise_gain, noise_decay, rng)
    elif sound_type == "chord":
        samples = generate_chord(NUM_SAMPLES, SAMPLE_RATE, frequencies_hz,
                                 frequency_gains, decay_rates, rng)
    elif sound_type == "arpeggio":
        samples = generate_arpeggio(NUM_SAMPLES, SAMPLE_RATE, frequencies_hz,
                                    frequency_gains, decay_rates, rng)
    else:
        print(f"Unknown sound type '{sound_type}', falling back to 'pluck'")
        samples = generate_pluck(NUM_SAMPLES, SAMPLE_RATE, frequencies_hz,
                                 frequency_gains, decay_rates,
                                 noise_gain, noise_decay, rng)

    # Quantize to 24-bit signed
    quantized, clipped, peak_float = quantize(samples, BIT_DEPTH)

    # Compute stats
    duration = NUM_SAMPLES / SAMPLE_RATE
    max_val = (1 << (BIT_DEPTH - 1)) - 1
    peak_quantized = max(abs(v) for v in quantized) or 1
    rms_quantized = math.sqrt(sum(v * v for v in quantized) / len(quantized))

    # Print summary
    print(f"\nSummary:")
    print(f"  Sample rate  : {SAMPLE_RATE} Hz")
    print(f"  Duration     : {duration:.2f} s")
    print(f"  Bit depth    : {BIT_DEPTH}-bit")
    print(f"  Num samples  : {NUM_SAMPLES}")
    print(f"  Peak (FS)    : {peak_quantized} ({peak_quantized / max_val * 100:.1f}%)")
    print(f"  RMS (FS)     : {rms_quantized:.1f} ({rms_quantized / max_val * 100:.1f}%)")
    if clipped > 0:
        print(f"  Clipped      : {clipped} samples ({clipped / NUM_SAMPLES * 100:.2f}%)")
    else:
        print(f"  Clipped      : 0 samples")
    print(f"  Output       : {args.output}")

    # Write .hex file
    lines = []
    for val in quantized:
        lines.append(to_twos_complement_hex(val, BIT_DEPTH))

    with open(args.output, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"\nWrote {len(lines)} lines to {args.output}")


if __name__ == "__main__":
    main()