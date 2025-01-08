#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Alisson Chaves
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/alissonchaves/qm-iptag

# Function to display the header
function header_info {
clear
cat <<"EOF"
    ____ _    ________   ____                                 __             
   / __ \ |  / / ____/  / __ \_      ______  ___  _____      / /_____ _____ _
  / /_/ / | / / __/    / / / / | /| / / __ \/ _ \/ ___/_____/ __/ __ `/ __ `/
 / ____/| |/ / /___   / /_/ /| |/ |/ / / / /  __/ /  /_____/ /_/ /_/ / /_/ / 
/_/     |___/_____/   \____/ |__/|__/_/ /_/\___/_/         \__/\__,_/\__, /  
                                                                    /____/   
EOF
}

clear
header_info
APP="PVE OWNER Tag"
hostname=$(hostname)

# Color variables
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD=" "
CM=" ✔️ ${CL}"
CROSS=" ✖️ ${CL}"

# Function to enable error handling in the script
catch_errors() {
  set -Eeuo pipefail
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}

# Function called when an error occurs
error_handler() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
}

# Function to display a spinner while the process is running
spinner() {
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local spin_i=0
  local interval=0.1
  printf "\e[?25l"

  while true; do
  printf "\r ${YW}%s${CL}" "${frames[spin_i]}"
  spin_i=$(((spin_i + 1) % ${#frames[@]}))
  sleep "$interval"
  done
}

# Function to display an informational message
msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
  spinner &
  SPINNER_PID=$!
}

# Function to display a success message
msg_ok() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

# Function to display an error message
msg_error() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

# Confirm if the user wants to continue with the installation
while true; do
  read -p "This will install ${APP} on ${hostname}. Proceed? (y/n): " yn
  case $yn in
  [Yy]*) break ;;
  [Nn]*)
  msg_error "Installation cancelled."
  exit
  ;;
  *) msg_error "Please answer yes or no." ;;
  esac
done

# Check Proxmox version
if ! pveversion | grep -Eq "pve-manager/8.[0-3]"; then
  msg_error "This version of Proxmox Virtual Environment is not supported"
  msg_error "⚠️ Requires Proxmox Virtual Environment Version 8.0 or later."
  msg_error "Exiting..."
  sleep 2
  exit
fi

# The rest of the script's installer and configuration continues below
INSTALL_DIR="/opt/pve-owntag"
SERVICE_FILE="/etc/systemd/system/pve-owntag.service"
CONFIG_FILE="$INSTALL_DIR/pve-owntag.conf"

# Create installation directory
mkdir -p "$INSTALL_DIR"

# Download the main script
cat << 'EOF' > "$INSTALL_DIR/pve-owntag"
[...]
EOF

# Make the script executable
chmod +x "$INSTALL_DIR/pve-owntag"

# Create the configuration file
cat << 'EOF' > "$CONFIG_FILE"
# PVE OWNER Tag Configuration
LOOP_INTERVAL=300
FW_NET_INTERFACE_CHECK_INTERVAL=60
QM_STATUS_CHECK_INTERVAL=-1
FORCE_UPDATE_INTERVAL=1800
EOF

# Create the systemd service file
cat << 'EOF' > "$SERVICE_FILE"
[Unit]
Description=PVE OWNER Tag Service
After=network.target

[Service]
ExecStart=/opt/pve-owntag/pve-owntag
Restart=always
User=root
WorkingDirectory=/opt/pve-owntag

[Install]
WantedBy=multi-user.target
EOF

# Load the systemd service and start it
systemctl daemon-reload
systemctl enable pve-owntag.service
systemctl start pve-owntag.service

msg_ok "Installation complete. The service is now running."

exit
