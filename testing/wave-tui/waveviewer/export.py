"""Export visible waveform data to external formats."""

from __future__ import annotations

import csv
import os
from typing import TextIO


def export_csv(samples: list[int], path: str) -> str:
    """Write *samples* to a CSV file at *path*.

    Returns the absolute path of the written file.
    """
    path = os.path.abspath(path)
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["sample_index", "value"])
        for i, val in enumerate(samples):
            writer.writerow([i, val])
    return path


def export_ascii_wave(
    samples: list[int],
    path: str,
    width: int = 80,
    height: int = 20,
) -> str:
    """Render a simple ASCII-art waveform and save to *path*.

    Uses the same approach as the terminal renderer but writes to a file
    instead.  This produces a portable text representation.
    """
    if not samples:
        raise ValueError("No samples to export.")

    path = os.path.abspath(path)

    step = max(1, len(samples) // width)
    sampled = [samples[i] for i in range(0, len(samples), step)][:width]

    lo, hi = min(sampled), max(sampled)
    span = hi - lo if hi != lo else 1

    lines: list[list[str]] = [[" "] * width for _ in range(height)]

    for x, v in enumerate(sampled):
        row = int((1 - (v - lo) / span) * (height - 1))
        row = max(0, min(row, height - 1))
        lines[row][x] = "."

    # Connect with lines using simple braille-like approach
    for x in range(1, len(sampled)):
        y0 = int((1 - (sampled[x - 1] - lo) / span) * (height - 1))
        y1 = int((1 - (sampled[x] - lo) / span) * (height - 1))
        y0, y1 = max(0, min(y0, height - 1)), max(0, min(y1, height - 1))

        if y0 == y1:
            if lines[y0][x] == " ":
                lines[y0][x] = "-"
        else:
            step_y = 1 if y1 > y0 else -1
            for y in range(y0, y1 + step_y, step_y):
                if 0 <= y < height:
                    lines[y][x] = ":" if lines[y][x] == " " else lines[y][x]

    with open(path, "w") as f:
        f.write(f"ASCII Waveform Export — {len(samples)} samples\n")
        f.write(f"Range: [{lo}, {hi}]\n")
        f.write("-" * (width + 2) + "\n")
        for row in lines:
            f.write("|" + "".join(row) + "|\n")
        f.write("-" * (width + 2) + "\n")

    return path