"""Minimap — miniature overview of the entire waveform with viewport highlight."""

from __future__ import annotations

import curses

from waveviewer.colours import MINIMAP, HIGHLIGHT, DIM_TEXT
from waveviewer.config import Viewport


def draw_minimap(
    stdscr,
    data_len: int,
    vp: Viewport,
    height: int,
    width: int,
) -> int:
    """Render the minimap at the bottom of the terminal.

    The minimap occupies *height* lines (typically 3).  Returns the number of
    rows consumed so the caller can adjust the plot area.

    Layout::

      ──────── samples ────────
      ████████████████████████████████████████████████████
                    [═══════════════]

    The first line is a label, the second is the full-data bar, and the third
    shows the viewport bracket.
    """
    if data_len == 0 or not vp.show_minimap:
        return 0

    rows_used = 3
    plot_top = height - rows_used

    if plot_top < 0:
        return 0

    # Determine the bar width (use most of the terminal width)
    bar_width = max(10, width - 4)
    bar_start = 2

    # ── Label line ───────────────────────────────────────────
    label = f"  Overview — {data_len} samples  "
    try:
        stdscr.addstr(plot_top, 0, label, curses.color_pair(DIM_TEXT))
    except curses.error:
        pass

    # ── Full-data bar (line 2) ───────────────────────────────
    # Use a dense block character
    bar_char = "█"
    bar_line = bar_char * bar_width
    try:
        stdscr.addstr(plot_top + 1, bar_start, bar_line,
                      curses.color_pair(MINIMAP))
    except curses.error:
        pass

    # ── Viewport bracket (line 3) ────────────────────────────
    bracket_char = "═"
    edge_char = "▌"

    start_frac = vp.offset / data_len
    end_frac = (vp.offset + vp.zoom) / data_len

    bracket_start = bar_start + int(start_frac * bar_width)
    bracket_end = bar_start + int(end_frac * bar_width)

    bracket_start = max(bar_start, bracket_start)
    bracket_end = min(bar_start + bar_width, bracket_end)

    bracket_len = max(1, bracket_end - bracket_start)

    # Build the bracket line
    bracket_line = " " * (bracket_start - bar_start)
    if bracket_len == 1:
        bracket_line += "▌"
    else:
        bracket_line += edge_char + bracket_char * (bracket_len - 2) + edge_char

    # Pad to full width
    bracket_line = bracket_line.ljust(bar_width)

    try:
        stdscr.addstr(plot_top + 2, bar_start, bracket_line,
                      curses.color_pair(HIGHLIGHT))
    except curses.error:
        pass

    return rows_used