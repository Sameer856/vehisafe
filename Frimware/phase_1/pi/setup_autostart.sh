#!/bin/bash

# Ensure the script is run with sudo
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root (sudo ./setup_autostart.sh)"
  exit 1
fi

# Get the absolute directory where this installer script resides
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PYTHON_BIN=$(which python3)

if [ -z "$PYTHON_BIN" ]; then
  echo "Error: python3 not found. Please install python3 first."
  exit 1
fi

echo "=============================================="
echo "    VEHISAFE AUTOSTART SERVICE INSTALLER      "
echo "=============================================="
echo "Working Directory: $SCRIPT_DIR"
echo "Python Executable: $PYTHON_BIN"
echo "Script Target:     $SCRIPT_DIR/main.py"
echo "----------------------------------------------"

SERVICE_FILE="/etc/systemd/system/vehisafe.service"

echo "Creating systemd service configuration..."

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=VehiSafe System Service
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=$SCRIPT_DIR
ExecStart=$PYTHON_BIN main.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vehisafe

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd daemon configs..."
systemctl daemon-reload

echo "Registering VehiSafe to start automatically on system boot..."
systemctl enable vehisafe.service

echo "Starting VehiSafe service now..."
systemctl restart vehisafe.service

echo "----------------------------------------------"
echo "[SUCCESS] VehiSafe autostart service initialized!"
echo "----------------------------------------------"
echo "To check background process status:  sudo systemctl status vehisafe"
echo "To watch logs in real-time:         journalctl -u vehisafe -f"
echo "To stop the background service:     sudo systemctl stop vehisafe"
echo "To restart the service:             sudo systemctl restart vehisafe"
echo "=============================================="
