#!/usr/bin/env python3
"""
wav_to_hex24.py

Convert a 24-bit signed PCM WAV file into a hex file suitable for
Verilog $readmemh (one 6-digit hex sample per line, two's complement).

Usage:
    python3 wav_to_hex24.py input.wav output.hex [--channel L|R|both]

Notes:
    - Input WAV must be 24-bit PCM (sampwidth == 3 bytes).
      If you have a different bit depth, re-export from Audacity as
      "WAV (Microsoft) signed 24-bit PCM" first.
    - For stereo files, default is to extract the LEFT channel only.
      Use --channel both to interleave L,R (one per line, L then R).
"""

import wave
import sys
import argparse


def bytes_to_signed_int(b: bytes) -> int:
    """Convert 3 little-endian bytes to a signed 24-bit integer."""
    val = int.from_bytes(b, byteorder="little", signed=False)
    if val & 0x800000:          # sign bit set -> negative
        val -= 0x1000000
    return val


def signed_int_to_hex24(val: int) -> str:
    """Convert a signed 24-bit integer to a 6-digit two's-complement hex string."""
    if val < 0:
        val += 0x1000000
    return f"{val & 0xFFFFFF:06X}"


def convert(in_path: str, out_path: str, channel: str = "L"):
    with wave.open(in_path, "rb") as wav:
        n_channels = wav.getnchannels()
        samp_width = wav.getsampwidth()
        n_frames = wav.getnframes()
        frame_rate = wav.getframerate()

        if samp_width != 3:
            sys.exit(
                f"Error: input is {samp_width * 8}-bit, not 24-bit. "
                f"Re-export as 24-bit signed PCM WAV first."
            )

        print(f"Channels:    {n_channels}")
        print(f"Sample rate: {frame_rate} Hz")
        print(f"Frames:      {n_frames}")
        print(f"Duration:    {n_frames / frame_rate:.3f} s")

        raw = wav.readframes(n_frames)

    bytes_per_frame = samp_width * n_channels
    lines = []

    for i in range(n_frames):
        frame_start = i * bytes_per_frame
        # channel 0 = left (or mono), channel 1 = right
        left_bytes = raw[frame_start: frame_start + samp_width]
        left_val = bytes_to_signed_int(left_bytes)

        if n_channels == 1 or channel.upper() == "L":
            lines.append(signed_int_to_hex24(left_val))
        elif channel.upper() == "R":
            right_start = frame_start + samp_width
            right_bytes = raw[right_start: right_start + samp_width]
            right_val = bytes_to_signed_int(right_bytes)
            lines.append(signed_int_to_hex24(right_val))
        elif channel.lower() == "both":
            right_start = frame_start + samp_width
            right_bytes = raw[right_start: right_start + samp_width]
            right_val = bytes_to_signed_int(right_bytes)
            lines.append(signed_int_to_hex24(left_val))
            lines.append(signed_int_to_hex24(right_val))
        else:
            sys.exit(f"Unknown channel option: {channel}")

    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"Wrote {len(lines)} hex samples to {out_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert 24-bit signed WAV to hex.")
    parser.add_argument("input_wav", help="Path to input 24-bit signed PCM WAV file")
    parser.add_argument("output_hex", help="Path to output .hex file")
    parser.add_argument(
        "--channel",
        default="L",
        choices=["L", "R", "both"],
        help="Which channel to extract for stereo input (default: L)",
    )
    args = parser.parse_args()

    convert(args.input_wav, args.output_hex, args.channel)
