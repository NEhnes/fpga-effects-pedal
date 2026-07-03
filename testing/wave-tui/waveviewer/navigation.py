"""Keyboard-driven navigation state updates.

All modifier-free movement is handled here; the caller dispatches key codes
and receives an updated :class:`Viewport`.

Keys follow the specification:

  ============ =============================
  Key          Action
  ============ =============================
  ``h``/``←``  Pan left
  ``l``/``→``  Pan right
  ``+``/``-``  Zoom in / out
  ``Home``     Beginning of data
  ``End``      End of data
  ``PgUp/PgDn``Large jump
  ``f``        Fit waveform
  ``z``        Reset zoom
  ``c``        Center view
  ``0``        Toggle zero axis
  ``g``        Jump to sample  (handled by caller)
  ``G``        Toggle grid
  ``t``/``P``  Toggle point / line mode
  ``L``        Toggle line mode  (same as ``P``)
  ``s``        Cycle scaling mode
  ``i``        Toggle statistics
  ``m``        Toggle minimap
  ``?``        Toggle help
  ``q``/``Esc``Quit
  ============ =============================
"""

from __future__ import annotations

import curses

from waveviewer.config import (
    Viewport,
    FAST_PAN_FACTOR,
    PAN_FACTOR,
    PAGE_PAN_FACTOR,
    ZOOM_FACTOR,
    MIN_ZOOM,
)


def _next_scale(mode: str) -> str:
    """Cycle forward through scaling modes."""
    modes = ["auto", "fixed", "normalized", "zero_centred"]
    idx = modes.index(mode) if mode in modes else 0
    return modes[(idx + 1) % len(modes)]


def handle_key(key: int, vp: Viewport, data_len: int) -> Viewport | None:
    """Process a single keypress and return an updated *Viewport*.

    Returns *None* when the key signals "quit".  For all other keys the
    returned viewport is guaranteed to be clamped.
    """
    # Shallow copy so we can mutate and clamp
    vp = Viewport(
        offset=vp.offset,
        zoom=vp.zoom,
        show_zero_axis=vp.show_zero_axis,
        show_grid=vp.show_grid,
        show_stats=vp.show_stats,
        show_minimap=vp.show_minimap,
        show_help=vp.show_help,
        scale_mode=vp.scale_mode,
        display_mode=vp.display_mode,
        fixed_min=vp.fixed_min,
        fixed_max=vp.fixed_max,
    )

    delta = max(1, vp.zoom // PAN_FACTOR)
    fast_delta = max(1, vp.zoom // FAST_PAN_FACTOR)
    page_delta = max(1, vp.zoom // PAGE_PAN_FACTOR)

    # ── Quit ─────────────────────────────────────────────────────
    if key in (ord("q"), 27):  # 27 = Escape
        return None

    # ── Pan ──────────────────────────────────────────────────────
    if key in (curses.KEY_RIGHT, ord("l")):  # lowercase L
        vp.offset = min(vp.offset + delta, max(0, data_len - vp.zoom))
    elif key in (curses.KEY_LEFT, ord("h")):
        vp.offset = max(0, vp.offset - delta)

    # ── Fast pan (shifted arrows) ────────────────────────────────
    elif hasattr(curses, "KEY_SRIGHT") and key == curses.KEY_SRIGHT:
        vp.offset = min(vp.offset + fast_delta, max(0, data_len - vp.zoom))
    elif hasattr(curses, "KEY_SLEFT") and key == curses.KEY_SLEFT:
        vp.offset = max(0, vp.offset - fast_delta)

    # ── Jumps ────────────────────────────────────────────────────
    elif key == curses.KEY_HOME:
        vp.offset = 0
    elif key == curses.KEY_END:
        vp.offset = max(0, data_len - vp.zoom)
    elif key == curses.KEY_NPAGE:  # Page Down
        vp.offset = min(vp.offset + page_delta, max(0, data_len - vp.zoom))
    elif key == curses.KEY_PPAGE:  # Page Up
        vp.offset = max(0, vp.offset - page_delta)

    # ── Zoom ─────────────────────────────────────────────────────
    elif key in (ord("+"), ord("=")):
        vp.zoom = max(MIN_ZOOM, vp.zoom // ZOOM_FACTOR)
    elif key in (ord("-"), ord("_")):
        vp.zoom = min(data_len, vp.zoom * ZOOM_FACTOR)

    # ── Fit / Reset / Center ─────────────────────────────────────
    elif key in (ord("f"), ord("F")):
        vp.offset = 0
        vp.zoom = data_len
    elif key in (ord("z"), ord("Z")):
        vp.zoom = max(MIN_ZOOM * 100, data_len // 10)
        vp.offset = 0
    elif key in (ord("c"), ord("C")):
        half = vp.zoom // 2
        mid = data_len // 2
        vp.offset = max(0, min(mid - half, data_len - vp.zoom))

    # ── Display mode toggles ─────────────────────────────────────
    # 'L' (uppercase) = toggle line mode; 't' / 'P' = toggle point mode
    # Both toggle between line and point.
    elif key in (ord("L"), ord("P"), ord("t"), ord("T")):
        vp.display_mode = "point" if vp.display_mode == "line" else "line"

    # ── Toggles ──────────────────────────────────────────────────
    elif key == ord("0"):
        vp.show_zero_axis = not vp.show_zero_axis
    elif key == ord("G"):  # uppercase G = toggle grid
        vp.show_grid = not vp.show_grid
    elif key in (ord("s"), ord("S")):
        vp.scale_mode = _next_scale(vp.scale_mode)
    elif key in (ord("i"), ord("I")):
        vp.show_stats = not vp.show_stats
    elif key in (ord("m"), ord("M")):
        vp.show_minimap = not vp.show_minimap

    # ── Help ─────────────────────────────────────────────────────
    elif key == ord("?"):
        vp.show_help = not vp.show_help

    # ── 'g' (lowercase) is handled by the caller (jump prompt) ──
    # If it reaches here, it's a no-op.

    vp.clamp(data_len)
    return vp