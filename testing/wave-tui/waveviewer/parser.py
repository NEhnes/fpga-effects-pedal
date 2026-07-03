"""Parser for 24-bit signed hex sample files.

Each line should contain one 24-bit hex value, optionally prefixed with ``0x``.
Blank lines, comments (``#`` …), and leading/trailing whitespace are handled.
"""

from __future__ import annotations

import os


def parse_24bit_signed(hex_str: str) -> int | None:
    """Parse a single 24-bit signed hex string to an integer.

    Accepts optional ``0x`` prefix, leading/trailing whitespace, and comments
    introduced by ``#``.  Returns *None* for blank / invalid lines (no
    exception raised).
    """
    raw = hex_str.strip()

    # Strip comments
    if "#" in raw:
        raw = raw.split("#", 1)[0].strip()

    if not raw:
        return None

    if raw.lower().startswith("0x"):
        raw = raw[2:]

    if not raw:
        return None

    try:
        val = int(raw, 16)
    except ValueError:
        return None

    # Sign-extend the 24th bit
    if val & 0x800000:
        val -= 0x1000000
    return val


def read_samples(path: str, max_samples: int | None = None) -> list[int]:
    """Read a hex file and return a list of signed 24-bit sample values.

    Parameters
    ----------
    path:
        Path to the input file.
    max_samples:
        Optional cap on the number of samples to read (for testing).

    Raises
    ------
    FileNotFoundError
        If *path* does not exist.
    ValueError
        If *path* contains no valid sample data.
    """
    if not os.path.isfile(path):
        raise FileNotFoundError(f"No such file: {path}")

    samples: list[int] = []
    warnings = 0

    with open(path, "r") as f:
        for line in f:
            val = parse_24bit_signed(line)
            if val is not None:
                samples.append(val)
                if max_samples is not None and len(samples) >= max_samples:
                    break
            elif line.strip() and not line.strip().startswith("#"):
                # Non-blank, non-comment line that failed to parse
                warnings += 1

    if not samples:
        raise ValueError(
            f"No valid 24-bit hex sample data found in '{path}'."
        )

    if warnings:
        import sys as _sys

        print(
            f"Warning: {warnings} line(s) could not be parsed in '{path}'.",
            file=_sys.stderr,
        )

    return samples