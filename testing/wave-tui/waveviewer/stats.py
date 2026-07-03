"""Statistics computed over the visible sample region."""

from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass
class RegionStats:
    """Statistics for a region of sample data."""

    minimum: float = 0.0
    maximum: float = 0.0
    mean: float = 0.0
    rms: float = 0.0
    peak_to_peak: float = 0.0
    dynamic_range_db: float = 0.0
    sample_count: int = 0


def compute_stats(samples: list[int]) -> RegionStats:
    """Compute descriptive statistics over *samples*.

    Returns a :class:`RegionStats` with all fields populated.  For an empty
    list the returned stats will contain zeros.
    """
    if not samples:
        return RegionStats()

    n = len(samples)
    mn = min(samples)
    mx = max(samples)
    total = sum(samples)
    mean = total / n

    sq_sum = sum((s - mean) ** 2 for s in samples)
    rms = math.sqrt(sq_sum / n) if n > 1 else 0.0

    p2p = mx - mn

    # Dynamic range in dB (relative to full 24-bit scale if p2p is small)
    if p2p > 0:
        dr_db = 20.0 * math.log10(p2p / 2.0) if p2p / 2.0 > 0 else 0.0
    else:
        dr_db = 0.0

    return RegionStats(
        minimum=float(mn),
        maximum=float(mx),
        mean=mean,
        rms=rms,
        peak_to_peak=float(p2p),
        dynamic_range_db=dr_db,
        sample_count=n,
    )