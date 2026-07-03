"""Default configuration and constants."""

from dataclasses import dataclass, field


@dataclass
class Viewport:
    """Navigation state describing the visible window into the sample data."""

    offset: int = 0
    zoom: int = 1000
    show_zero_axis: bool = True
    show_grid: bool = False
    show_stats: bool = False
    show_minimap: bool = True
    show_help: bool = False
    scale_mode: str = "auto"  # auto | fixed | normalized | zero_centred
    display_mode: str = "line"  # line | point

    # Fixed scaling range (full 24-bit signed)
    fixed_min: int = -8388608
    fixed_max: int = 8388607

    def clamp(self, data_len: int) -> None:
        """Ensure offset and zoom are within valid bounds."""
        if data_len == 0:
            self.offset = 0
            self.zoom = 1
            return
        self.zoom = max(10, min(self.zoom, data_len))
        self.offset = max(0, min(self.offset, data_len - self.zoom))


# Pan and zoom constants
PAN_FACTOR = 8  # 1/8th of visible range per arrow key press
FAST_PAN_FACTOR = 2  # 1/2 of visible range per shifted arrow press
PAGE_PAN_FACTOR = 1  # full visible range per Page key
ZOOM_FACTOR = 2  # multiply/divide zoom per +/-
MIN_ZOOM = 10

# Display limits
MAX_FILENAME_LEN = 60
STATUS_BAR_HEIGHT = 1
MINIMAP_HEIGHT = 3