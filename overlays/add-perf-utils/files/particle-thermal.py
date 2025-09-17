#!/usr/bin/python3

import os
import time
import curses
import argparse
import csv
import sys

app_version = '1.0.0'

# Define the directory path where thermal zone files are located
THERMAL_DIR = "/sys/class/thermal"
REFRESH_INTERVAL = 1  # 1 second interval for data refresh

def get_cooling_device(zone_path):
    """Fetch the cooling device information from the config file."""
    config_file_path = os.path.join(zone_path, "config")
    cooling_device = ""
    
    try:
        with open(config_file_path, 'r') as f:
            for line in f:
                if line.startswith("device"):
                    cooling_device = line.split("device", 1)[1].strip()
                    break
    except FileNotFoundError:
        pass  # Leave cooling_device as "" if file is not found
    
    return cooling_device

def get_thermal_data():
    """Fetch thermal zone data."""
    data = []
    zones = [zone for zone in os.listdir(THERMAL_DIR) if zone.startswith('thermal_zone')]
    
    for zone in zones:
        zone_path = os.path.join(THERMAL_DIR, zone)

        # Extract the number following "thermal_zone" for the "Item" column
        item_number = zone.replace("thermal_zone", "")

        try:
            with open(os.path.join(zone_path, "type"), 'r') as f:
                name = f.read().strip()
        except FileNotFoundError:
            name = "N/A"

        try:
            with open(os.path.join(zone_path, "temp"), 'r') as f:
                temperature_raw = f.read().strip()
                temperature = int(temperature_raw) / 1000.0  # Convert from millidegrees Celsius to Celsius
        except (FileNotFoundError, ValueError, OSError):
            temperature = "N/A"  # Handle invalid data or file not found

        try:
            with open(os.path.join(zone_path, "policy"), 'r') as f:
                policy = f.read().strip()
        except FileNotFoundError:
            policy = "N/A"

        # Fetch cooling device information
        cooling_device = get_cooling_device(zone_path)

        data.append((name, item_number, temperature, policy, cooling_device))

    # Sort data by the "Name" column
    data.sort(key=lambda x: x[0].lower())  # Sort case-insensitively by name
    return data

def output_data_as_csv(data, delimiter=','):
    """Output the thermal data as CSV or tab-separated."""
    writer = csv.writer(sys.stdout, delimiter=delimiter)
    headers = ["Name", "Zone", "Temperature", "Policy", "Cooling"]
    writer.writerow(headers)
    for row in data:
        writer.writerow(row)

def draw_table(stdscr, data, selected_row_idx, scroll_offset):
    """Draw the table on the screen."""
    stdscr.clear()

    # Define headers
    headers = ["Name", "Zone", "Temperature", "Policy", "Cooling"]

    # Set color pair for headers (blue text on yellow background)
    curses.init_color(11, 0, 0, 500)       # Dark blue
    curses.init_pair(1, 11, curses.COLOR_YELLOW)

    # Determine window size
    h, w = stdscr.getmaxyx()

    # Check if there's enough room to draw the version line at the bottom
    if h < 3:
        stdscr.addstr(0, 0, "Terminal too small to display data.".center(w))
        stdscr.refresh()
        return

    # Display headers with blue text on white background across the full row
    stdscr.attron(curses.color_pair(1))
    stdscr.addstr(0, 0, f"{headers[0]:<20} {headers[1]:<10} {headers[2]:<20} {headers[3]:<20} {headers[4]:<30}".ljust(w))
    stdscr.attroff(curses.color_pair(1))

    # Display thermal zone data, scrollable if data exceeds screen height
    max_visible_rows = h - 2  # Subtract 2 to leave room for the version and hint line
    visible_data = data[scroll_offset:scroll_offset + max_visible_rows]

    for idx, row in enumerate(visible_data):
        # Trim "Cooling" column text to fit within the available space
        cooling_trimmed = row[4][:w - 80] if len(row[4]) > (w - 80) else row[4]
        row_str = f"{row[0]:<20} {row[1]:<10} {row[2]:<20} {row[3]:<20} {cooling_trimmed:<30}"
        if idx == selected_row_idx - scroll_offset:
            stdscr.attron(curses.A_REVERSE)
            stdscr.addstr(idx + 1, 0, row_str)
            stdscr.attroff(curses.A_REVERSE)
        else:
            stdscr.addstr(idx + 1, 0, row_str)

    # Display scroll indicator if necessary
    if len(data) > max_visible_rows:
        scrollbar_height = min(max_visible_rows, h - 3)
        scroll_indicator_position = int((scroll_offset / (len(data) - max_visible_rows)) * (scrollbar_height - 1))
        for i in range(scrollbar_height):
            if i == scroll_indicator_position:
                stdscr.addstr(i + 1, w - 1, '█')
            else:
                stdscr.addstr(i + 1, w - 1, '|')

    # Display version and hint line at the bottom
    if h > 1:
        stdscr.attron(curses.color_pair(1))
        stdscr.addstr(h - 1, 0, f"Version: {app_version} | Press ESC to exit ")
        stdscr.attroff(curses.color_pair(1))

    stdscr.refresh()

def run_curses_ui():
    """Runs the curses UI."""
    curses.wrapper(main)

def main(stdscr):
    # Initialize curses settings
    curses.curs_set(0)  # Hide cursor
    stdscr.nodelay(True)  # Make getch non-blocking

    selected_row_idx = 0
    scroll_offset = 0

    # Timer to refresh data
    last_refresh_time = time.time()
    data = get_thermal_data()  # Initial data fetch

    while True:
        # Handle keyboard inputs
        key = stdscr.getch()
        max_visible_rows = stdscr.getmaxyx()[0] - 2

        if key == curses.KEY_UP and selected_row_idx > 0:
            selected_row_idx -= 1
            if selected_row_idx < scroll_offset:
                scroll_offset -= 1

        elif key == curses.KEY_DOWN and selected_row_idx < len(data) - 1:
            selected_row_idx += 1
            if selected_row_idx >= scroll_offset + max_visible_rows:
                scroll_offset += 1

        elif key == curses.KEY_NPAGE:  # Page Down
            if selected_row_idx < len(data) - max_visible_rows:
                selected_row_idx += max_visible_rows
                scroll_offset += max_visible_rows
            else:
                selected_row_idx = len(data) - 1
                scroll_offset = max(0, len(data) - max_visible_rows)

        elif key == curses.KEY_PPAGE:  # Page Up
            if selected_row_idx > max_visible_rows:
                selected_row_idx -= max_visible_rows
                scroll_offset -= max_visible_rows
            else:
                selected_row_idx = 0
                scroll_offset = 0

        elif key == curses.KEY_HOME:  # Home key
            selected_row_idx = 0
            scroll_offset = 0

        elif key == curses.KEY_END:  # End key
            selected_row_idx = len(data) - 1
            scroll_offset = max(0, len(data) - max_visible_rows)

        elif key == 27:  # Escape key
            break  # Exit the loop when the Escape key is pressed

        elif key != -1 and chr(key).isalpha():  # Jump to the first matching "Name" field
            letter = chr(key).lower()
            for idx, row in enumerate(data):
                if row[0].lower().startswith(letter):
                    selected_row_idx = idx
                    if selected_row_idx < scroll_offset:
                        scroll_offset = selected_row_idx
                    elif selected_row_idx >= scroll_offset + max_visible_rows:
                        scroll_offset = selected_row_idx - max_visible_rows + 1
                    break

        # Check if it's time to refresh the data
        if time.time() - last_refresh_time > REFRESH_INTERVAL:
            data = get_thermal_data()  # Refresh data
            last_refresh_time = time.time()

            # Draw the table with the latest data
            draw_table(stdscr, data, selected_row_idx, scroll_offset)

if __name__ == "__main__":
    # Argument parser for command line options
    parser = argparse.ArgumentParser(description="Thermal Zone Monitor")
    parser.add_argument('-v', '--version', action='version', version=f'%(prog)s {app_version}')
    parser.add_argument('--run-once', choices=['csv', 'tsv'], help='Run once and output data as CSV or TSV')
    args = parser.parse_args()

    if args.run_once:
        data = get_thermal_data()
        delimiter = ',' if args.run_once == 'csv' else '\t'
        output_data_as_csv(data, delimiter=delimiter)
    else:
        # Run the curses UI
        run_curses_ui()

    sys.exit(0)