"""UI panels — status bar, statistics panel, and help overlay."""

from __future__ import annotations

import curses
import os

from waveviewer.colours import DIM_TEXT, HELP_BORDER
from waveviewer.config import Viewport, MAX_FILENAME_LEN
from waveviewer.stats import RegionStats


# ── Status bar ────────────────────────────────────────────────────────────

def draw_status_bar(
    stdscr,
    filename: str,
    data_len: int,
    vp: Viewport,
    width: int,
) -> None:
    """Render the status bar on the last terminal line."""
    height, _ = stdscr.getmaxyx()
    y = height - 1

    if y < 0:
        return

    zoom_pct = 100.0 * vp.zoom / data_len if data_len > 0 else 0.0

    # Shorten filename
    fname = os.path.basename(filename)
    if len(fname) > MAX_FILENAME_LEN:
        fname = "…" + fname[-(MAX_FILENAME_LEN - 1):]

    # Scale mode abbreviation
    scale_abbr = {
        "auto": "AUTO",
        "fixed": "FXD",
        "normalized": "NRM",
        "zero_centred": "Z.C",
    }.get(vp.scale_mode, "AUTO")

    grid_str = "G" if vp.show_grid else "g"
    zero_str = "0" if vp.show_zero_axis else "z"
    disp_str = "LINE" if vp.display_mode == "line" else "DOT"

    parts = [
        f" {fname} ",
        f" [{vp.offset}–{vp.offset + vp.zoom}] ",
        f" {zoom_pct:.1f}% ",
        f" {vp.zoom} / {data_len} ",
        f" {scale_abbr} ",
        f" {disp_str} ",
        f" {grid_str}{zero_str} ",
    ]

    line = "│".join(parts)

    # Truncate to fit
    if len(line) > width - 1:
        line = line[:width - 1]
    line = line.ljust(width - 1)

    try:
        stdscr.addstr(y, 0, line, curses.A_REVERSE)
    except curses.error:
        pass


# ── Statistics panel ──────────────────────────────────────────────────────

def draw_stats_panel(
    stdscr,
    stats: RegionStats,
    vp: Viewport,
    width: int,
) -> None:
    """Render the statistics overlay in the top-right corner."""
    if not vp.show_stats:
        return

    # Format numeric values
    lines_fmt = [
        f" Samples: {stats.sample_count}",
        f" Min:     {stats.minimum:>+10.0f}",
        f" Max:     {stats.maximum:>+10.0f}",
        f" Mean:    {stats.mean:>+10.2f}",
        f" RMS:     {stats.rms:>10.2f}",
        f" Pk–Pk:   {stats.peak_to_peak:>10.0f}",
        f" DR:      {stats.dynamic_range_db:>6.1f} dB",
    ]

    panel_width = 26
    panel_x = max(0, width - panel_width - 2)
    panel_y = 1

    # Draw border
    for i, line in enumerate(lines_fmt):
        y = panel_y + i
        if y < 0:
            continue
        try:
            stdscr.addstr(y, panel_x, " " + line.ljust(panel_width - 1),
                          curses.color_pair(DIM_TEXT))
        except curses.error:
            pass


# ── Help overlay ──────────────────────────────────────────────────────────

HELP_TEXT = [
    "  ┌────────────────────────────────────────────────────────────┐",
    "  │                     WaveViewer Help                        │",
    "  ├────────────────────────────────────────────────────────────┤",
    "  │  ← →        Pan                                           │",
    "  │  Shift+← →   Fast pan                                     │",
    "  │  + / -       Zoom in / out                                │",
    "  │  Home / End  Beginning / End of data                      │",
    "  │  PgUp/PgDn   Large jump                                   │",
    "  │  f           Fit waveform to window                       │",
    "  │  z           Reset zoom                                   │",
    "  │  c           Center view                                  │",
    "  │  0           Toggle zero axis                             │",
    "  │  g           Jump to sample number                       │",
    "  │  G           Toggle grid                                 │",
    "  │  t/P/L       Toggle line / point mode                    │",
    "  │  s           Cycle scaling mode                           │",
    "  │  i           Toggle statistics                            │",
    "  │  m           Toggle minimap                               │",
    "  │  ?           Toggle this help                             │",
    "  │  q / Esc     Quit                                         │",
    "  ├────────────────────────────────────────────────────────────┤",
    "  │  Scaling modes: auto | fixed | normalized | zero-centred  │",
    "  │  Display modes: line (connected) | point (dots)           │",
    "  └────────────────────────────────────────────────────────────┘",
]

HELP_WIDTH = 64
HELP_HEIGHT = len(HELP_TEXT)


def draw_help(stdscr, vp: Viewport, term_width: int, term_height: int) -> None:
    """Render the centred help overlay."""
    if not vp.show_help:
        return

    x = max(0, (term_width - HELP_WIDTH) // 2)
    y = max(0, (term_height - HELP_HEIGHT) // 2)

    for i, line in enumerate(HELP_TEXT):
        cy = y + i
        if cy >= term_height:
            break
        try:
            if i == 0 or i == HELP_HEIGHT - 1 or "├" in line or "└" in line:
                stdscr.addstr(cy, x, line, curses.color_pair(HELP_BORDER))
            else:
                stdscr.addstr(cy, x, line, curses.color_pair(DIM_TEXT))
        except curses.error:
            pass