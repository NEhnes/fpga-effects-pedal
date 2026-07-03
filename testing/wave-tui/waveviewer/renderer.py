"""Waveform renderer — core drawing engine.

Decimates sample data intelligently (min-max pair decimation), maps samples to
terminal rows using the configured scaling mode, and draws the waveform using
Unicode line-drawing characters.
"""

from __future__ import annotations

import math

from waveviewer.config import Viewport


# ── Decimation ────────────────────────────────────────────────────────────

def decimate(data: list[int], offset: int, zoom: int, width: int) -> list[tuple[int, int]]:
    """Produce a list of ``(min, max)`` pairs for each output column.

    This is **min-max decimation**: for every pixel column we capture the
    minimum and maximum values in the corresponding sample range.  When the
    samples-per-column ratio is small we fall back to simple sub-sampling.
    """
    if not data:
        return []

    lo = max(0, offset)
    hi = min(offset + zoom, len(data))
    visible = data[lo:hi]

    if not visible:
        return []

    step = max(1, len(visible) // width) if width > 0 else len(visible)
    if step <= 1:
        # One sample per column — wrap as pairs
        return [(v, v) for v in visible[:width]]

    cols: list[tuple[int, int]] = []
    for i in range(0, len(visible), step):
        chunk = visible[i : i + step]
        cols.append((min(chunk), max(chunk)))
        if len(cols) >= width:
            break
    return cols


# ── Scaling ───────────────────────────────────────────────────────────────

def scale_value(
    v: int,
    scale_mode: str,
    data_lo: int,
    data_hi: int,
    fixed_min: int,
    fixed_max: int,
    zero_centred: bool,
) -> float:
    """Map a sample value to a normalised ``[0, 1]`` range.

    ``0.0`` = bottom of the terminal plot area, ``1.0`` = top.
    """
    if scale_mode == "fixed":
        lo, hi = fixed_min, fixed_max
    elif scale_mode == "zero_centred":
        half = max(abs(data_lo), abs(data_hi))
        lo, hi = -half, half
    else:  # auto or normalized
        lo, hi = data_lo, data_hi

    span = hi - lo
    if span == 0:
        return 0.5
    return (v - lo) / span


def scale_pairs(
    pairs: list[tuple[int, int]],
    vp: Viewport,
    data_min: int,
    data_max: int,
) -> list[tuple[float, float]]:
    """Map decimation ``(min, max)`` pairs to normalised ``[0, 1]`` floats."""
    if not pairs:
        return []

    result: list[tuple[float, float]] = []

    if vp.scale_mode == "normalized":
        # Normalise the visible data to [0, 1] range preserving shape
        lo = min(p[0] for p in pairs)
        hi = max(p[1] for p in pairs)
        span = hi - lo if hi != lo else 1
        for mn, mx in pairs:
            result.append(((mn - lo) / span, (mx - lo) / span))
    else:
        for mn, mx in pairs:
            result.append((
                scale_value(mn, vp.scale_mode, data_min, data_max,
                            vp.fixed_min, vp.fixed_max, vp.show_zero_axis),
                scale_value(mx, vp.scale_mode, data_min, data_max,
                            vp.fixed_min, vp.fixed_max, vp.show_zero_axis),
            ))
    return result


# ── Row mapping ───────────────────────────────────────────────────────────

def normalised_to_row(norm: float, plot_rows: int) -> int:
    """Convert a ``[0, 1]`` normalised value to a terminal row index.

    ``0.0`` → bottom row, ``1.0`` → top row (row 0).
    """
    return int((1.0 - norm) * (plot_rows - 1))


def zero_axis_row(plot_rows: int, data_min: int, data_max: int,
                  vp: Viewport) -> int | None:
    """Return the terminal row where the zero axis should be drawn, or *None*."""
    if vp.scale_mode == "normalized":
        return None
    z = scale_value(
        0, vp.scale_mode, data_min, data_max,
        vp.fixed_min, vp.fixed_max, vp.show_zero_axis,
    )
    return normalised_to_row(z, plot_rows)


# ── Line-drawing characters ──────────────────────────────────────────────

_CHAR_HORIZ = "─"
_CHAR_SLASH_UP = "╱"
_CHAR_SLASH_DN = "╲"


def _connector_char(y_prev: float, y_curr: float) -> str:
    """Choose a Unicode line-drawing character for a segment between two points."""
    diff = y_curr - y_prev
    if abs(diff) < 0.3:
        return _CHAR_HORIZ
    return _CHAR_SLASH_UP if diff > 0 else _CHAR_SLASH_DN


# ── Main draw ────────────────────────────────────────────────────────────

def compute_rows(
    pairs: list[tuple[float, float]],
    plot_rows: int,
) -> list[int]:
    """Convert normalised min-max pairs into a single row trace.

    Uses the mid-point of each min-max pair as the primary value.
    """
    rows: list[int] = []
    for mn, mx in pairs:
        mid = (mn + mx) / 2.0
        r = normalised_to_row(mid, plot_rows)
        rows.append(max(0, min(r, plot_rows - 1)))
    return rows


def grid_row_indices(plot_rows: int, spacing: int = 5) -> list[int]:
    """Return row indices where horizontal grid lines should be drawn."""
    return [plot_rows * i // spacing for i in range(1, spacing)]