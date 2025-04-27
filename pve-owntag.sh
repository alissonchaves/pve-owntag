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
if ! pveversion | grep -Eq "pve-manager/8.[0-4]"; then
  msg_error "This version of Proxmox Virtual Environment is not supported"
  msg_error "⚠️ Requires Proxmox Virtual Environment Version 8.0 or later."
  msg_error "Exiting..."
  sleep 2
  exit
fi

# Check if jq is installed
if ! command -v jq &>/dev/null; then
  msg_info "Installing jq..."
  apt-get update && apt-get install -y jq
  msg_ok "jq installed successfully."
else
  msg_ok "jq is already installed."
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
# Process VMs
for vmid_node in $(pvesh get /cluster/resources --type vm --output-format=json | jq -r '.[] | "\(.vmid)|\(.node)"'); do
  vmid=$(echo "$vmid_node" | cut -d'|' -f1)
  node=$(echo "$vmid_node" | cut -d'|' -f2)
  echo "Processing VMID $vmid"

  # Search the log for the creation of this VM
  
  log_file=$(find /var/log/pve/tasks/ -type f -name '*qmclone*' | xargs grep -l "Logical volume \"vm-${vmid}-disk-0\" created." || true)

  if [[ -n "$log_file" ]]; then
  filename=$(basename "$log_file")
  filename="${filename%:}"        # Remove trailing colon
  owner=${filename##*:}           # After the last :
  owner=${owner%@*}                # Before the @
  owner="owner_${owner}"           # Add prefix
  echo "  -> Found owner: $owner"

  # Fetch current tags
  current_tags=$(pvesh get /nodes/"$node"/qemu/"$vmid"/config --output-format=json | jq -r '.tags')

  # Prepare new list of tags
  if [[ "$current_tags" == "null" || -z "$current_tags" ]]; then
    new_tags="$owner"
  else
    # Check if it already exists
    if [[ "$current_tags" == *"$owner"* ]]; then
    echo "  -> Owner already present in tags. Skipping update."
    continue
    else
    new_tags="$current_tags;$owner"
    fi
  fi

  # Update tags
  echo "  -> Updating tags to: $new_tags"
  pvesh set /nodes/"$node"/qemu/"$vmid"/config --tags "$new_tags"
  else
  echo "  -> No clone log found for VMID $vmid."
  fi

done
# done

}
# Main loop
while true; do
  generate_tags
  sleep "$LOOP_INTERVAL"
done
EOF

# Load the systemd service and start the service
systemctl daemon-reload
systemctl enable pve-owntag.service
systemctl start pve-owntag.service

msg_ok "Installation complete. The service is now running."

exit
# End of script