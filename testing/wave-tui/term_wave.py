#!/usr/bin/env python3
import sys
import os
import plotext as plt

def parse_24bit_signed_hex(hex_string):
    """Converts a 24-bit hex string to a signed integer (two's complement)."""
    hex_string = hex_string.strip()

    if not hex_string:
        return None

    if hex_string.lower().startswith('0x'):
        hex_string = hex_string[2:]

    try:
        val = int(hex_string, 16)
        if val >= 0x800000:
            val -= 0x1000000
        return val
    except ValueError:
        return None


def load_file(filepath, max_points=500):
    """Load up to max_points valid samples from a hex file."""
    if not os.path.isfile(filepath):
        print(f"Error: File '{filepath}' not found.")
        sys.exit(1)

    data = []

    with open(filepath, 'r') as f:
        for line in f:
            val = parse_24bit_signed_hex(line)
            if val is not None:
                data.append(val)
            if len(data) == max_points:
                break

    return data


def main():
    # Expect exactly two files
    if len(sys.argv) != 3:
        print("Usage: ./term_wave.py <input1.hex> <input2.hex>")
        sys.exit(1)

    file1 = sys.argv[1]
    file2 = sys.argv[2]

    data1 = load_file(file1)
    data2 = load_file(file2)

    if not data1 and not data2:
        print("Error: No valid data found in either file.")
        sys.exit(1)

    # Align lengths for plotting (truncate to shortest)
    n = min(len(data1), len(data2))
    data1 = data1[:n]
    data2 = data2[:n]

    plt.clear_figure()

    # Plot both waveforms
    plt.plot(data1, label=os.path.basename(file1))
    plt.plot(data2, label=os.path.basename(file2))

    plt.title("Dual Waveform Comparison (24-bit signed hex)")
    plt.xlabel("Sample Index")
    plt.ylabel("Amplitude")

    plt.theme("dark")
    plt.plotsize(100, 30)

    plt.show()


if __name__ == "__main__":
    main()
