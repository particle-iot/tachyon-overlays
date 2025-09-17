#!/bin/bash
TEMP_DIR=$1

echo "Running local setup for test-overlay..."
echo "Creating a temporary file on the host..."
echo "Hello from the host!" > "$TEMP_DIR/host-temp-file.txt"
echo "Host setup complete."