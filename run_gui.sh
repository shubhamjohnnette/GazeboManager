#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_SCRIPT="$SCRIPT_DIR/gazebo_gui.py"

echo "================================"
echo "Starting GazeboManager GUI..."
echo "================================"

# Check Python 3
if ! command -v python3 &>/dev/null; then
    echo "[ERROR] Python 3 is not installed on this system."
    exit 1
fi

# Ensure scripts have executable permissions
chmod +x "$SCRIPT_DIR/check.sh" "$SCRIPT_DIR/setup_gazebo.sh" "$GUI_SCRIPT" 2>/dev/null || true

if [ ! -f "$GUI_SCRIPT" ]; then
    echo "[ERROR] GUI script not found at $GUI_SCRIPT."
    exit 1
fi

# Run GUI
python3 "$GUI_SCRIPT" "$@"
