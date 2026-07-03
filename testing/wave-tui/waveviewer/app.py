"""Main application controller — curses event loop and drawing orchestration."""

from __future__ import annotations

import curses
import os

from waveviewer.colours import ZERO_AXIS, GRID, HIGHLIGHT, DIM_TEXT
from waveviewer.config import Viewport, MINIMAP_HEIGHT, STATUS_BAR_HEIGHT
from waveviewer.minimap import draw_minimap
from waveviewer.renderer import (
    decimate,
    scale_pairs,
    compute_rows,
    grid_row_indices,
    zero_axis_row,
)
from waveviewer.stats import compute_stats
from waveviewer.ui import draw_status_bar, draw_stats_panel, draw_help
from waveviewer.navigation import handle_key


# ── Unicode drawing characters ───────────────────────────────────────────

_CHAR_DOT = "\u00b7"
_CHAR_HORIZ = "\u2500"
_CHAR_VERT = "\u2502"
_CHAR_SLASH_UP = "\u2571"
_CHAR_SLASH_DN = "\u2572"
_CHAR_GRID = "\u2504"


# ── Bresenham line ───────────────────────────────────────────────────────

def _bresenham_line(
    x0: int, y0: int, x1: int, y1: int,
    ch: str, target,
    colour_pair: int,
    y_min: int, y_max: int,
) -> None:
    """Draw a line from *(x0, y0)* to *(x1, y1)* using Bresenham's algorithm.

    Writes character *ch* to *target* (a curses window) at each cell along the
    line, clipped to *[y_min, y_max)*.
    """
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy

    while True:
        if y_min <= y0 < y_max:
            try:
                target.addstr(y0, x0, ch, colour_pair)
            except curses.error:
                pass
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x0 += sx
        if e2 < dx:
            err += dx
            y0 += sy


# ── Drawing helpers ──────────────────────────────────────────────────────

def _draw_point_mode(stdscr, rows: list[int], plot_rows: int) -> None:
    """Draw each sample as a single dot character."""
    for x, r in enumerate(rows):
        if 0 <= r < plot_rows:
            colour = (x % 6) + 1
            try:
                stdscr.addstr(r, x, _CHAR_DOT,
                              curses.color_pair(colour) | curses.A_DIM)
            except curses.error:
                pass


def _draw_line_mode(stdscr, rows: list[int], plot_rows: int) -> None:
    """Draw connected waveform using Bresenham lines with slope-aware chars."""
    if not rows:
        return

    # First point
    if 0 <= rows[0] < plot_rows:
        try:
            stdscr.addstr(rows[0], 0, _CHAR_DOT, curses.color_pair(1))
        except curses.error:
            pass

    for x in range(1, len(rows)):
        x0, y0 = x - 1, rows[x - 1]
        x1, y1 = x, rows[x]
        colour = (x % 6) + 1
        attr = curses.color_pair(colour)

        if y1 > y0:
            ch = _CHAR_SLASH_UP  # rising left-to-right
        elif y1 < y0:
            ch = _CHAR_SLASH_DN  # falling left-to-right
        else:
            ch = _CHAR_HORIZ

        _bresenham_line(x0, y0, x1, y1, ch, stdscr, attr, 0, plot_rows)


def _draw_vertical_whiskers(stdscr, pairs_norm: list[tuple[float, float]],
                            plot_rows: int) -> None:
    """Draw min-max vertical bars when the range spans > 1 row."""
    for x, (mn, mx) in enumerate(pairs_norm):
        lo_row = int((1.0 - mx) * (plot_rows - 1))   # max → top
        hi_row = int((1.0 - mn) * (plot_rows - 1))   # min → bottom
        colour = (x % 6) + 1

        if abs(hi_row - lo_row) > 1:
            for span_r in range(min(lo_row, hi_row), max(lo_row, hi_row) + 1):
                if 0 <= span_r < plot_rows:
                    try:
                        stdscr.addstr(span_r, x, _CHAR_VERT,
                                      curses.color_pair(colour) | curses.A_DIM)
                    except curses.error:
                        pass


def _draw_zero_axis(stdscr, z_row: int | None, plot_rows: int,
                    width: int) -> None:
    """Draw a cyan horizontal zero-axis line."""
    if z_row is None or z_row < 0 or z_row >= plot_rows:
        return
    try:
        stdscr.addstr(z_row, 0, _CHAR_HORIZ * width,
                      curses.color_pair(ZERO_AXIS) | curses.A_DIM)
    except curses.error:
        pass


def _draw_grid(stdscr, plot_rows: int, width: int, vp: Viewport) -> None:
    """Draw dim horizontal grid lines."""
    if not vp.show_grid:
        return
    for r in grid_row_indices(plot_rows):
        if r < 0 or r >= plot_rows:
            continue
        try:
            stdscr.addstr(r, 0, _CHAR_GRID * width,
                          curses.color_pair(GRID))
        except curses.error:
            pass


def _draw_scale_labels(stdscr, data_min: int, data_max: int,
                       plot_rows: int) -> None:
    """Draw min/max scale labels on the left edge."""
    try:
        stdscr.addstr(0, 0, str(data_max), curses.color_pair(DIM_TEXT))
    except curses.error:
        pass
    try:
        stdscr.addstr(max(0, plot_rows - 1), 0, str(data_min),
                      curses.color_pair(DIM_TEXT))
    except curses.error:
        pass


def _draw_filename_header(stdscr, filename: str, width: int) -> None:
    """Draw highlighted filename at the top centre."""
    fname = os.path.basename(filename)
    if len(fname) > width - 6:
        fname = "\u2026" + fname[-(width - 7):]

    line = f"  {fname}  "
    x = max(0, (width - len(line)) // 2)
    try:
        stdscr.addstr(0, x, line, curses.color_pair(HIGHLIGHT))
    except curses.error:
        pass


# ── Jump-to-sample prompt ────────────────────────────────────────────────

def _prompt_jump(stdscr, vp: Viewport, data_len: int) -> None:
    """Prompt the user for a sample index and jump to it."""
    try:
        curses.echo()
        curses.curs_set(1)
        stdscr.addstr(0, 0, "Jump to sample: ", curses.A_REVERSE)
        stdscr.clrtoeol()
        stdscr.refresh()

        buf = ""
        while True:
            ch = stdscr.getch()
            if ch in (ord("\n"), ord("\r")):
                break
            elif ch == 27:  # Escape
                buf = ""
                break
            elif ch in (curses.KEY_BACKSPACE, 127):
                buf = buf[:-1]
            elif ord("0") <= ch <= ord("9"):
                buf += chr(ch)

            stdscr.addstr(0, 0, "Jump to sample: ", curses.A_REVERSE)
            stdscr.addstr(buf, curses.A_REVERSE)
            stdscr.clrtoeol()
            stdscr.refresh()

        curses.noecho()
        curses.curs_set(0)
        stdscr.move(0, 0)
        stdscr.refresh()

        if buf:
            idx = int(buf)
            idx = max(0, min(idx, data_len - 1))
            half = vp.zoom // 2
            vp.offset = max(0, min(idx - half, data_len - vp.zoom))
            vp.clamp(data_len)
    except curses.error:
        try:
            curses.noecho()
            curses.curs_set(0)
        except curses.error:
            pass


def _do_export(stdscr, data: list[int], vp: Viewport) -> None:
    """Export visible samples to CSV."""
    from waveviewer.export import export_csv

    visible = data[vp.offset: vp.offset + vp.zoom]
    path = export_csv(visible, "waveform_export.csv")

    rows, cols = stdscr.getmaxyx()
    msg = f" Exported {len(visible)} samples to {path} "
    try:
        stdscr.addstr(rows - 2, 0, msg[:cols - 1],
                      curses.color_pair(HIGHLIGHT))
        stdscr.refresh()
        curses.napms(1500)
    except curses.error:
        pass


# ── Main loop ────────────────────────────────────────────────────────────

def run(stdscr, data: list[int], filename: str) -> None:
    """Curses main loop — draw, handle input, repeat."""
    # Import here so the package import is always safe (curses init in wrapper)
    from waveviewer.colours import init_colours

    init_colours(stdscr)

    try:
        curses.curs_set(0)
    except curses.error:
        pass

    stdscr.keypad(True)
    stdscr.timeout(0)  # Non-blocking getch for resize detection

    vp = Viewport(offset=0, zoom=len(data))
    running = True

    while running:
        try:
            curses.update_lines_cols()
        except curses.error:
            pass

        height, width = stdscr.getmaxyx()

        if height < 5 or width < 20:
            stdscr.erase()
            msg = "Terminal too small \u2014 resize to at least 20\u00d75"
            try:
                stdscr.addstr(0, 0, msg, curses.A_REVERSE)
                stdscr.refresh()
                curses.napms(1000)
            except curses.error:
                pass
            continue

        # Terminal dimensions for the plot area
        min_used = STATUS_BAR_HEIGHT
        if vp.show_minimap:
            min_used += MINIMAP_HEIGHT
        plot_rows = height - min_used
        plot_width = width

        data_min = min(data) if data else 0
        data_max = max(data) if data else 0

        # ── Render pipeline ────────────────────────────────────
        pairs_int = decimate(data, vp.offset, vp.zoom, plot_width)
        pairs_norm = scale_pairs(pairs_int, vp, data_min, data_max)
        rows = compute_rows(pairs_norm, plot_rows)

        visible_data = data[vp.offset: vp.offset + vp.zoom]
        stats = compute_stats(visible_data)

        stdscr.erase()

        # Layer 1: Grid (behind everything)
        _draw_grid(stdscr, plot_rows, plot_width, vp)

        # Layer 2: Zero axis
        if vp.show_zero_axis:
            z_row = zero_axis_row(plot_rows, data_min, data_max, vp)
            _draw_zero_axis(stdscr, z_row, plot_rows, plot_width)

        # Layer 3: Filename header
        _draw_filename_header(stdscr, filename, plot_width)

        # Layer 4: Waveform (point or line mode)
        if vp.display_mode == "line" and len(rows) > 1:
            _draw_line_mode(stdscr, rows, plot_rows)
            _draw_vertical_whiskers(stdscr, pairs_norm, plot_rows)
        else:
            _draw_point_mode(stdscr, rows, plot_rows)

        # Layer 5: Scale labels
        _draw_scale_labels(stdscr, data_min, data_max, plot_rows)

        # Layer 6: Stats panel
        draw_stats_panel(stdscr, stats, vp, plot_width)

        # Layer 7: Minimap
        draw_minimap(stdscr, len(data), vp, height, plot_width)

        # Layer 8: Status bar
        draw_status_bar(stdscr, filename, len(data), vp, plot_width)

        # Layer 9: Help overlay (topmost)
        draw_help(stdscr, vp, plot_width, height)

        stdscr.refresh()

        # ── Input ──────────────────────────────────────────────
        try:
            key = stdscr.getch()
        except KeyboardInterrupt:
            break

        if key == curses.KEY_RESIZE:
            continue
        if key == -1:
            continue  # No input (timeout)

        # Special commands with interactive prompts
        if key in (ord("g"),):  # lowercase 'g' = jump (caller handles prompt)
            _prompt_jump(stdscr, vp, len(data))
            continue
        if key in (ord("e"), ord("E")):
            _do_export(stdscr, data, vp)
            continue

        result = handle_key(key, vp, len(data))
        if result is None:
            running = False
        else:
            vp = result