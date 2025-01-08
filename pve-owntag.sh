#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Alisson Chaves
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/alissonchaves/pve-owntag

# Function to display the header
function header_info {
clear
cat <<"EOF"
    ____ _    ________   ____                                 __             
   / __ \ |  / / ____/  / __ \_      ______  ___  _____      / /_____ _____ _
  / /_/ / | / / __/    / / / / | /| / / __ \/ _ \/ ___/_____/ __/ __ / __ /
 / ____/| |/ / /___   / /_/ /| |/ |/ / / / /  __/ /  /_____/ /_/ /_/ / /_/ / 
/_/     |___/_____/   \____/ |__/|__/_/ /_/\___/_/         \__/\__,_/\__, /  
                                                                    /____/   
EOF
}

clear
header_info
APP="PVE OWNER Tag"
hostname=$(hostname)

# Farbvariablen
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

# Function to display a spinner while the process is in progress
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

# Confirm that the user wants to continue with the installation
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

# The rest of the script installer and configuration follows below.
INSTALL_DIR="/opt/pve-owntag"
SERVICE_FILE="/lib/systemd/system/pve-owntag.service"
CONFIG_FILE="$INSTALL_DIR/pve-owntag.conf"

# Create the installation directory
mkdir -p "$INSTALL_DIR"

# Download the main script
cat << 'EOF' > "$INSTALL_DIR/pve-owntag"
#!/bin/bash

# Load settings from file
source "/opt/pve-owntag/pve-owntag.conf"

# Function to generate tags
generate_tags() {
    # Get the list of VMs and Containers, taking only the ID
    mapfile -t list < <(qm list | grep -vE "VMID|template" | awk '{print $1}')
    mapfile -t list_containers < <(pct list | grep -vE "VMID|template" | awk '{print $1}')

    # Merge lists of VMs and Containers
    list=("${list[@]}" "${list_containers[@]}")

    for item in "${list[@]}"; do
        # Search through all files in /var/log/pve/tasks/ and find the most recent one
        latest_file=$(grep -l -r "\-${item}\-" /var/log/pve/tasks/ | xargs ls -t | head -n 1 | grep clone)

        if [ -n "$latest_file" ]; then
            # Determine if it is a VM or Container
            if [[ "$(qm list | awk -v id="$item" '$1 == id {print $1}')" == "$item" ]]; then
                type="vm"
            elif [[ "$(pct list | awk -v id="$item" '$1 == id {print $1}')" == "$item" ]]; then
                type="container"
            fi

            # Extract username from filename (field 8)
            user=$(basename "$latest_file" | cut -d':' -f8 | cut -d'@' -f1)

            # Add the prefix "owner_" to the tag
            user="owner_${user}"

            # Get current tags
            if [ "$type" == "vm" ]; then
                current_tags=$(qm config "${item}" | grep -i "tags" | cut -d':' -f2 | tr -d '[:space:]')
            elif [ "$type" == "container" ]; then
                current_tags=$(pct config "${item}" | grep -i "tags" | cut -d':' -f2 | tr -d '[:space:]')
            fi

            # Replace tags starting with "owner_" with the new tag "owner_$user"
            if [ -n "$current_tags" ]; then
                # Replace any existing tag with the "owner_" prefix with the new tag
                current_tags=$(echo "$current_tags" | sed -E "s/\bowner_[^,]*\b/$user/g")
                # Add new tag if it doesn't exist
                if [[ ! "$current_tags" =~ "$user" ]]; then
                    current_tags="${current_tags},${user}"
                fi
            else
                # If there are no tags, add the new tag as the only one
                current_tags="${user}"
            fi


            # Add the new tag to the VM or Container
            if [ "$type" == "vm" ]; then
                echo "Executing: qm set ${item} -tags \"${current_tags}\""
                qm set "${item}" -tags "${current_tags}"
            elif [ "$type" == "container" ]; then
                echo "Executing: pct set ${item} -tags \"${current_tags}\""
                pct set "${item}" -tags "${current_tags}"
            fi
        fi
    done
}

# Function to check the network interface (using the FW_NET_INTERFACE_CHECK_INTERVAL parameter)
check_network_interface() {
    while true; do
        sleep "$FW_NET_INTERFACE_CHECK_INTERVAL"
        # Logic to check network interface, you can add specific commands here.
        # Example: Check if interface is up or something related to network.
        echo "Checking network interface..."
    done
}

# Function to force update (using the FORCE_UPDATE_INTERVAL parameter)
force_update() {
    while true; do
        sleep "$FORCE_UPDATE_INTERVAL"
        # Logic to force update, could be a status check or some necessary update.
        echo "Forcing update..."
    done
}

# Infinite loop to run functions and manage intervals
while true; do
    generate_tags
    check_network_interface &
    force_update &
    sleep "$LOOP_INTERVAL"
done
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

# Load the systemd service and start the service
systemctl daemon-reload
systemctl enable pve-owntag.service
systemctl start pve-owntag.service

msg_ok "Installation complete. The service is now running."

exit
