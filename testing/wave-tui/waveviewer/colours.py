"""Colour palette and curses colour management.

Preserves the sunset / periwinkle gradient from the original WaveViewer
and extends it with semantic colour pairs for UI elements.
"""

from __future__ import annotations

import curses

# ── Sunset gradient (pairs 1-6) ──────────────────────────────────────────
SUNSET_GRAD_RGB: list[tuple[int, int, int]] = [
    (200, 200, 255),  # 1  soft periwinkle
    (170, 160, 225),  # 2  iris
    (150, 120, 212),  # 3  medium indigo
    (170, 110, 220),  # 4  soft amethyst
    (191, 123, 178),  # 5  berry
    (200, 130, 162),  # 6  light fuschia
]

# ── Semantic colours (used via pair constants below) ─────────────────────
ZERO_AXIS_RGB = (80, 200, 220)  # cyan
GRID_RGB = (50, 50, 60)  # very dim grey
HIGHLIGHT_RGB = (255, 200, 100)  # warm gold
DIM_TEXT_RGB = (140, 140, 155)  # muted lavender-grey
MINIMAP_RGB = (100, 100, 130)  # muted indigo
HELP_BORDER_RGB = (180, 140, 200)  # light violet

# ── Curses colour-pair constants ────────────────────────────────────────
# These are set at runtime by init_colours().
# Waveform colours: pairs 1-6
WAVEFORM = 0  # will be 1-6 cycled at draw time
ZERO_AXIS = 7
GRID = 8
HIGHLIGHT = 9
DIM_TEXT = 10
MINIMAP = 11
HELP_BORDER = 12
STATUS_BAR = 13
STATS_PANEL = 14


def rgb_to_xterm(r: int, g: int, b: int) -> int:
    """Approximate an RGB triple to the nearest xterm-256 colour index."""
    r6 = int(round(r / 255 * 5))
    g6 = int(round(g / 255 * 5))
    b6 = int(round(b / 255 * 5))
    return 16 + 36 * r6 + 6 * g6 + b6


def _init_pair_safe(pair_num: int, fg: int, bg: int = -1) -> None:
    """Wrapper around curses.init_pair that ignores errors."""
    try:
        curses.init_pair(pair_num, fg, bg)
    except curses.error:
        pass


def init_colours(stdscr) -> None:
    """Set up all curses colour pairs from the palette."""
    curses.start_color()
    curses.use_default_colors()

    if curses.COLORS >= 256:
        # Sunset gradient: pairs 1-6
        palette = [rgb_to_xterm(*c) for c in SUNSET_GRAD_RGB]
        for i, col in enumerate(palette, start=1):
            _init_pair_safe(i, col, -1)

        # Semantic colours
        _init_pair_safe(7, rgb_to_xterm(*ZERO_AXIS_RGB), -1)
        _init_pair_safe(8, rgb_to_xterm(*GRID_RGB), -1)
        _init_pair_safe(9, rgb_to_xterm(*HIGHLIGHT_RGB), -1)
        _init_pair_safe(10, rgb_to_xterm(*DIM_TEXT_RGB), -1)
        _init_pair_safe(11, rgb_to_xterm(*MINIMAP_RGB), -1)
        _init_pair_safe(12, rgb_to_xterm(*HELP_BORDER_RGB), -1)
    else:
        # Fallback to basic colours
        for i in range(1, 7):
            _init_pair_safe(i, curses.COLOR_MAGENTA, -1)
        _init_pair_safe(7, curses.COLOR_CYAN, -1)
        _init_pair_safe(8, curses.COLOR_BLACK, -1)
        _init_pair_safe(9, curses.COLOR_YELLOW, -1)
        _init_pair_safe(10, curses.COLOR_WHITE, -1)
        _init_pair_safe(11, curses.COLOR_BLUE, -1)
        _init_pair_safe(12, curses.COLOR_MAGENTA, -1)