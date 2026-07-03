#!/usr/bin/env python3
"""WaveViewer — Terminal waveform viewer launcher.

Usage:
    ./waveviewer.py <path-to-hex-file>
"""

from __future__ import annotations

import argparse
import curses
import sys
import traceback

from parser import read_samples


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Terminal waveform viewer for 24-bit signed hex data.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Keyboard controls:\n"
            "  ← →          Pan\n"
            "  Shift+← →    Fast pan\n"
            "  +/-          Zoom in/out\n"
            "  Home/End     Beginning/end of data\n"
            "  PgUp/PgDn    Large jump\n"
            "  f            Fit waveform\n"
            "  z            Reset zoom\n"
            "  c            Center view\n"
            "  0            Toggle zero axis\n"
            "  g            Toggle grid\n"
            "  t            Toggle point/line mode\n"
            "  s            Cycle scaling mode\n"
            "  i            Toggle statistics\n"
            "  m            Toggle minimap\n"
            "  j            Jump to sample\n"
            "  ?            Help\n"
            "  q/Esc        Quit\n"
        ),
    )
    parser.add_argument("hexfile", help="Path to 24-bit signed hex data file")
    args = parser.parse_args()

    try:
        samples = read_samples(args.hexfile)
        if not samples:
            sys.exit("Error: No valid data found in file.")
    except FileNotFoundError as e:
        sys.exit(f"Error: {e}")
    except ValueError as e:
        sys.exit(f"Error: {e}")
    except Exception as e:
        sys.exit(f"Error reading file: {e}")

    from app import run

    try:
        curses.wrapper(run, samples, args.hexfile)
    except KeyboardInterrupt:
        pass
    except Exception:
        with open("waveviewer_crash.log", "w") as f:
            traceback.print_exc(file=f)
        print(
            "\nWaveViewer crashed unexpectedly. "
            "Details saved to 'waveviewer_crash.log'.",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()