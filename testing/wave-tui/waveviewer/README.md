# WaveViewer

A professional terminal-based waveform viewer for 24-bit signed hex sample data.
Built with **curses** and designed for large-scale audio analysis right in your
terminal.

## Installation

```bash
pip install -r requirements.txt
```

Or install directly:

```bash
pip install -e .
```

## Dependencies

- **Python 3.11+**
- *No third-party packages required.* Only the Python standard library
  (``curses``, ``csv``, ``argparse``, ``math``, etc.).

## Usage

```bash
python waveviewer.py <path-to-hex-file>
```

Or if installed:

```bash
waveviewer <path-to-hex-file>
```

### Input format

The input file should contain one 24-bit signed hex value per line:

```
0x7FFFFF
0x400000
0x000000
0xFFFFFF
0x800000
```

Lines with ``0x`` prefix are accepted. Blank lines and ``#`` comments are ignored.

## Controls

| Key | Action |
|---|---|
| `←` / `→` | Pan left / right |
| `Shift+←` / `Shift+→` | Fast pan |
| `+` / `-` | Zoom in / out |
| `Home` | Beginning of data |
| `End` | End of data |
| `PageUp` / `PageDown` | Large jump |
| `f` | Fit waveform to window |
| `z` | Reset zoom |
| `c` | Center view on data midpoint |
| `0` | Toggle zero axis |
| `g` | Toggle grid |
| `t` | Toggle point / line mode |
| `s` | Cycle scaling mode |
| `i` | Toggle statistics panel |
| `m` | Toggle minimap |
| `j` | Jump to sample number |
| `?` | Help overlay |
| `q` / `Esc` | Quit |

## Scaling modes

| Mode | Description |
|---|---|
| **auto** | Scale to the visible data range |
| **fixed** | Scale to full 24-bit range (-8388608 to 8388607) |
| **normalized** | Normalise visible data to [0, 1] |
| **zero_centred** | Centre the scale around zero |

## Export

Press `e` to export the visible samples to ``waveform_export.csv``.

## Architecture

```
waveviewer/
├── waveviewer.py         # Launcher / CLI entry point
├── __main__.py           # ``python -m waveviewer`` support
├── __init__.py           # Package metadata
├── app.py                # Curses event loop and drawing orchestration
├── parser.py             # 24-bit signed hex file parsing
├── renderer.py           # Decimation, scaling, row mapping
├── colours.py            # Colour palette and curses initialisation
├── navigation.py         # Key-to-viewport mapping
├── stats.py              # Descriptive statistics for sample regions
├── minimap.py            # Miniature overview bar
├── ui.py                 # Status bar, stats panel, help overlay
├── export.py             # CSV and ASCII export
├── config.py             # Data classes and constants
├── requirements.txt
└── README.md
```

### Key design decisions

- **Min-max decimation**: Each output column shows the min and max of the
  corresponding sample range, preventing signal peaks from being missed during
  zoom-out.
- **Unicode line drawing**: Connected waveform mode uses ``─``, ``╱``, ``╲``
  characters with trajectory-aware selection.
- **Modular**: Each concern lives in its own module.  The renderer knows nothing
  about curses; the UI modules know nothing about parsing.
- **No external dependencies**: Pure Python 3.11+ standard library.

## Future improvements

- PNG / SVG export via optional third-party libraries
- Multi-channel waveform display
- Spectrogram overlay
- Vim-style search (find sample closest to value N)
- Named markers / cue points
- Configurable colour themes
- Mouse wheel support
- Wave file (``.wav``) import
- Real-time audio input monitoring
