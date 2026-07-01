#!/usr/bin/env python3
"""
hex24_to_wav.py

Convert a hex file of 24-bit signed samples (one 6-digit hex value per
line, two's complement — matching wav_to_hex24.py's output / typical
$readmemh format) back into a playable 24-bit signed PCM WAV file.

Usage:
    python3 hex24_to_wav.py input.hex output.wav --rate 48000 --channels 1

Notes:
    - If the hex file was generated with --channel both (interleaved
      L,R), set --channels 2 and lines will be paired up as L,R,L,R,...
    - Each line should contain a 6-digit hex value (e.g. 0A1B2C or
      FF8000). Whitespace and blank lines are ignored.
"""

import wave
import sys
import argparse


def hex24_to_signed_int(h: str) -> int:
    """Convert a 6-digit two's-complement hex string to a signed 24-bit integer."""
    val = int(h, 16)
    if val & 0x800000:          # sign bit set -> negative
        val -= 0x1000000
    return val


def signed_int_to_bytes(val: int) -> bytes:
    """Convert a signed 24-bit integer to 3 little-endian bytes."""
    if val < 0:
        val += 0x1000000
    return (val & 0xFFFFFF).to_bytes(3, byteorder="little", signed=False)


def convert(in_path: str, out_path: str, sample_rate: int, n_channels: int):
    with open(in_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    if n_channels == 1:
        n_frames = len(lines)
    else:
        if len(lines) % n_channels != 0:
            sys.exit(
                f"Error: {len(lines)} hex values is not evenly divisible "
                f"by {n_channels} channels."
            )
        n_frames = len(lines) // n_channels

    print(f"Hex samples: {len(lines)}")
    print(f"Channels:    {n_channels}")
    print(f"Sample rate: {sample_rate} Hz")
    print(f"Frames:      {n_frames}")
    print(f"Duration:    {n_frames / sample_rate:.3f} s")

    raw = bytearray()
    for h in lines:
        val = hex24_to_signed_int(h)
        raw += signed_int_to_bytes(val)

    with wave.open(out_path, "wb") as wav:
        wav.setnchannels(n_channels)
        wav.setsampwidth(3)  # 24-bit
        wav.setframerate(sample_rate)
        wav.writeframes(bytes(raw))

    print(f"Wrote {out_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Convert 24-bit signed hex data back into a WAV file."
    )
    parser.add_argument("input_hex", help="Path to input .hex file")
    parser.add_argument("output_wav", help="Path to output WAV file")
    parser.add_argument(
        "--rate", type=int, default=48000, help="Sample rate in Hz (default: 48000)"
    )
    parser.add_argument(
        "--channels",
        type=int,
        default=1,
        choices=[1, 2],
        help="Number of channels (default: 1 = mono)",
    )
    args = parser.parse_args()

    convert(args.input_hex, args.output_wav, args.rate, args.channels)
