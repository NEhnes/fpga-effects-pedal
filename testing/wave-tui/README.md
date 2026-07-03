# WaveViewer

Terminal waveform viewer for 24-bit signed hex data.

## Usage

```bash
cd waveviewer
python3 waveviewer.py <file.hex>
```

## Controls

| Key | Action |
|---|---|
| `←`/`→` | Pan |
| `+`/`-` | Zoom in/out |
| `g` | Jump to sample |
| `f` | Fit to window |
| `0` | Toggle zero axis |
| `G` | Toggle grid |
| `t` | Toggle line/point mode |
| `s` | Cycle scaling |
| `i` | Toggle stats |
| `m` | Toggle minimap |
| `?` | Help |
| `q` | Quit |

## Input format

One 24-bit hex value per line:

```
0x7FFFFF
0x000000
0x800000
```

Blank lines and `#` comments are OK.

## Dependencies

Python 3.11+ (stdlib only — no extra packages).