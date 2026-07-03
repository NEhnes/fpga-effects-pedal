#!/usr/bin/env python3
import sys
import os
import plotext as plt

def parse_24bit_signed_hex(hex_string):
    """Converts a 24-bit hex string to a signed integer (two's complement)."""
    hex_string = hex_string.strip()
    
    # Ignore empty lines
    if not hex_string:
        return None
        
    # Remove '0x' prefix if present
    if hex_string.lower().startswith('0x'):
        hex_string = hex_string[2:]
        
    try:
        val = int(hex_string, 16)
        # If the 24th bit is set (0x800000), it's a negative number
        if val >= 0x800000:
            val -= 0x1000000
        return val
    except ValueError:
        print(f"Warning: Could not parse '{hex_string}' as hex. Skipping.")
        return None

def main():
    # Check for correct arguments
    if len(sys.argv) != 2:
        print("Usage: ./term_wave.py <input.hex>")
        sys.exit(1)

    filepath = sys.argv[1]
    
    if not os.path.isfile(filepath):
        print(f"Error: File '{filepath}' not found.")
        sys.exit(1)

    data_points = []

    # Read and parse the file
    with open(filepath, 'r') as file:
        for line in file:
            val = parse_24bit_signed_hex(line)
            if val is not None:
                data_points.append(val)
                
            # Stop after 500 valid data points
            if len(data_points) == 500:
                break

    if not data_points:
        print("Error: No valid hex data found in the file.")
        sys.exit(1)

    # Configure the Plotext terminal UI
    plt.clear_figure()
    plt.plot(data_points, marker="braille") 
    plt.title(f"Low-Level Waveform: {os.path.basename(filepath)} (First {len(data_points)} samples)")
    plt.xlabel("Sample Index")
    plt.ylabel("Amplitude (24-bit signed)")
    
    # Apply a clean theme suited for terminal windows
    plt.theme("clear")
    plt.plotsize(100, 30) # Adjusts width and height of the graph in characters
    
    # Render to terminal
    plt.show()

if __name__ == "__main__":
    main()
