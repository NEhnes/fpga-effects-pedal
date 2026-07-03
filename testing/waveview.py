#!/usr/bin/env python3
"""Terminal waveform viewer for 24-bit signed .hex files (one value per line)."""

import sys
import curses
import argparse
import traceback

SUNSET_GRAD_RGB = [
    (200, 200, 255),  # soft periwinkle
    (170, 160, 225),  # iris
    (150, 120, 212),  # medium indigo
    (170, 110, 220),  # soft amethyst
    (191, 123, 178),  # berry
    (200, 130, 162),  # light fuschia
]


def rgb_to_xterm(r, g, b):
    """Approximate RGB to nearest xterm-256 colour index."""
    r6 = int(round(r / 255 * 5))
    g6 = int(round(g / 255 * 5))
    b6 = int(round(b / 255 * 5))
    return 16 + 36 * r6 + 6 * g6 + b6


def read_hex_file(path):
    """Parse a .hex file with one 24-bit hex value per line."""
    vals = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.lower().startswith("0x"):
                line = line[2:]
            
            try:
                v = int(line, 16) & 0xFFFFFF
                if v & 0x800000:  # sign-extend 24-bit two's complement
                    v = v - 0x1000000
                vals.append(v)
            except ValueError:
                pass # Skip invalid lines cleanly
    return vals


def init_colours(stdscr):
    """Define curses colour pairs 1-6 from the sunset palette."""
    curses.start_color()
    curses.use_default_colors()
    
    if curses.COLORS >= 256:
        palette = [rgb_to_xterm(*c) for c in SUNSET_GRAD_RGB]
        for i, col in enumerate(palette, start=1):
            try:
                curses.init_pair(i, col, -1)
            except curses.error:
                pass
    else:
        for i in range(1, 7):
            curses.init_pair(i, curses.COLOR_MAGENTA, -1)


def draw_wave(stdscr, data, offset, zoom):
    """Render the waveform connecting points via Bresenham's line algorithm."""
    height, width = stdscr.getmaxyx()
    plot_rows = height - 2  # leave bottom row for status

    if not data:
        stdscr.addstr(0, 0, "No data loaded.")
        stdscr.refresh()
        stdscr.getch()
        return ord("q"), offset, zoom

    # Ensure offset is valid
    offset = max(0, min(offset, len(data) - 1))
    if offset + zoom > len(data):
        zoom = len(data) - offset

    # Decimate to fit width
    step = max(1, zoom // width)
    view = data[offset:offset + zoom]
    sampled = [view[i] for i in range(0, len(view), step)][:width]

    if not sampled:
        sampled = [0]

    # Map values to terminal rows (invert: row 0 = top = max positive)
    lo, hi = min(sampled), max(sampled)
    span = hi - lo if hi != lo else 1
    rows = [int((1 - (v - lo) / span) * (plot_rows - 1)) for v in sampled]

    stdscr.erase()
    
    # Draw logic
    for x in range(len(rows)):
        r = rows[x]
        colour = (x % 6) + 1
        attr = curses.color_pair(colour)
        
        # Plot the very first point
        if x == 0:
            if 0 <= r < plot_rows:
                try:
                    stdscr.addstr(r, x, "─", attr)
                except curses.error:
                    pass
            continue

        # Bresenham's algorithm to connect (x-1, prev_r) to (x, r)
        x0, y0 = x - 1, rows[x-1]
        x1, y1 = x, r
        
        dx = abs(x1 - x0)
        dy = abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        
        while True:
            if 0 <= y0 < plot_rows and 0 <= x0 < width:
                # Select the appropriate character based on trajectory
                if y0 == y1:
                    char = "─"
                elif x0 == x1:
                    char = "│"
                elif (sx > 0 and sy > 0) or (sx < 0 and sy < 0):
                    char = "╲"
                else:
                    char = "╱"
                
                try:
                    stdscr.addstr(y0, x0, char, attr)
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

    # Status bar (clipped slightly to prevent terminal scrolling crash)
    start_idx = offset
    end_idx = min(offset + zoom, len(data))
    status = f"  [{start_idx}–{end_idx}] of {len(data)}   zoom={zoom}"
    try:
        stdscr.addstr(height - 1, 0, status[:width - 1], curses.A_REVERSE)
    except curses.error:
        pass

    stdscr.refresh()
    try:
        key = stdscr.getch()
    except KeyboardInterrupt:
        key = ord("q")

    return key, offset, zoom


def handle_key(key, offset, zoom, data_len, width):
    """Translate a keypress into new (offset, zoom)."""
    delta = max(1, zoom // 8)

    if key in (curses.KEY_RIGHT, ord("l")):
        offset = min(offset + delta, max(0, data_len - zoom))
    elif key in (curses.KEY_LEFT, ord("h")):
        offset = max(0, offset - delta)
    elif key == curses.KEY_HOME:
        offset = 0
    elif key == curses.KEY_END:
        offset = max(0, data_len - zoom)
    elif key in (ord("+"), ord("=")):
        zoom = max(10, zoom // 2)
    elif key in (ord("-"), ord("_")):
        zoom = min(data_len, zoom * 2)

    zoom = max(10, min(zoom, data_len))
    offset = max(0, min(offset, data_len - zoom))
    return offset, zoom


def main(stdscr, data):
    init_colours(stdscr)
    try:
        curses.curs_set(0)
    except curses.error:
        pass

    height, width = stdscr.getmaxyx()
    zoom = max(500, 10)
    offset = 0
    running = True

    while running:
        try:
            key, offset, zoom = draw_wave(stdscr, data, offset, zoom)
        except KeyboardInterrupt:
            break
            
        if key in (ord("q"), 27): # 27 is Escape
            running = False
        elif key == curses.KEY_RESIZE:
            curses.update_lines_cols()
        else:
            offset, zoom = handle_key(key, offset, zoom, len(data), width)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Terminal waveform viewer for 24-bit signed .hex files"
    )
    parser.add_argument("hexfile", help="Path to the .hex file")
    args = parser.parse_args()

    try:
        samples = read_hex_file(args.hexfile)
        if not samples:
            sys.exit("Error: No valid data found in file.")
    except Exception as e:
        sys.exit(f"Error reading file: {e}")

    # Launch with crash protection
    try:
        curses.wrapper(main, samples)
    except Exception as e:
        with open("crash_report.log", "w") as f:
            traceback.print_exc(file=f)
        print(f"\nThe script crashed unexpectedly! Details were saved to 'crash_report.log'.")
