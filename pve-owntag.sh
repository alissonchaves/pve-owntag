#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Alisson Chaves
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/alissonchaves/qm-iptag

# Função para exibir o cabeçalho
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

# Farbvariablen
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
RD=$(echo "\033[01;31m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD=" "
CM=" ✔️ ${CL}"
CROSS=" ✖️ ${CL}"

# Função para habilitar o tratamento de erros no script
catch_errors() {
  set -Eeuo pipefail
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}

# Função chamada quando ocorre um erro
error_handler() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
}

# Função para exibir um spinner enquanto o processo está em andamento
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

# Função para exibir uma mensagem informativa
msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
  spinner &
  SPINNER_PID=$!
}

# Função para exibir uma mensagem de sucesso
msg_ok() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

# Função para exibir uma mensagem de erro
msg_error() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID >/dev/null; then kill $SPINNER_PID >/dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

# Confirmar se o usuário deseja continuar com a instalação
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

# Verificar a versão do Proxmox
if ! pveversion | grep -Eq "pve-manager/8.[0-3]"; then
  msg_error "This version of Proxmox Virtual Environment is not supported"
  msg_error "⚠️ Requires Proxmox Virtual Environment Version 8.0 or later."
  msg_error "Exiting..."
  sleep 2
  exit
fi

# O restante do instalador e configuração do script seguem abaixo
INSTALL_DIR="/opt/pve-owntag"
SERVICE_FILE="/etc/systemd/system/pve-owntag.service"
CONFIG_FILE="$INSTALL_DIR/pve-owntag.conf"

# Criar o diretório de instalação
mkdir -p "$INSTALL_DIR"

# Baixar o script principal
cat << 'EOF' > "$INSTALL_DIR/pve-owntag"
#!/bin/bash

# Carregar as configurações do arquivo
source "/opt/pve-owntag/pve-owntag.conf"

# Função para gerar as tags
generate_tags() {
    # Obter a lista de VMs e Containers, pegando apenas o ID
    mapfile -t list < <(qm list | grep -vE "VMID|template" | awk '{print $1}')
    mapfile -t list_containers < <(pct list | grep -vE "VMID|template" | awk '{print $1}')

    # Unir as listas de VMs e Containers
    list=("${list[@]}" "${list_containers[@]}")

    for item in "${list[@]}"; do
        # Buscar dentro de todos os arquivos em /var/log/pve/tasks/ e encontrar o mais recente
        latest_file=$(find /var/log/pve/tasks/ -type f -name "*:${item}:*" -exec ls -t {} + | head -n 1)

        if [ -n "$latest_file" ]; then
            # Determinar se é VM ou Container
            if [[ "$(qm list | awk -v id="$item" '$1 == id {print $1}')" == "$item" ]]; then
                tipo="vm"
            elif [[ "$(pct list | awk -v id="$item" '$1 == id {print $1}')" == "$item" ]]; then
                tipo="container"
            fi

            # Extrair o nome do usuário do nome do arquivo (agora o campo 8)
            usuario=$(basename "$latest_file" | cut -d':' -f8 | cut -d'@' -f1)

            # Adicionar o prefixo "OWNER_" à tag
            usuario="owner_${usuario}"

            # Obter as tags atuais
            if [ "$tipo" == "vm" ]; then
                tags_atuais=$(qm config "${item}" | grep -i "tags" | cut -d':' -f2 | tr -d '[:space:]')
            elif [ "$tipo" == "container" ]; then
                tags_atuais=$(pct config "${item}" | grep -i "tags" | cut -d':' -f2 | tr -d '[:space:]')
            fi

            # Substituir as tags que começam com "owner_" pela nova tag "owner_$usuario"
if [ -n "$tags_atuais" ]; then
    # Substituir qualquer tag existente com o prefixo "owner_" pela nova tag
    tags_atuais=$(echo "$tags_atuais" | sed -E "s/\bowner_[^,]*\b/$usuario/g")
    # Adicionar a nova tag se não existir
    if [[ ! "$tags_atuais" =~ "$usuario" ]]; then
        tags_atuais="${tags_atuais},${usuario}"
    fi
else
    # Se não houver tags, adicionar a nova tag como a única
    tags_atuais="${usuario}"
fi


            # Adicionar a nova tag à VM ou Container
            if [ "$tipo" == "vm" ]; then
                echo "Executing: qm set ${item} -tags \"${tags_atuais}\""
                qm set "${item}" -tags "${tags_atuais}"
            elif [ "$tipo" == "container" ]; then
                echo "Executing: pct set ${item} -tags \"${tags_atuais}\""
                pct set "${item}" -tags "${tags_atuais}"
            fi
        fi
    done
}

# Função para verificar a interface de rede (usando o parâmetro FW_NET_INTERFACE_CHECK_INTERVAL)
check_network_interface() {
    while true; do
        sleep "$FW_NET_INTERFACE_CHECK_INTERVAL"
        # Lógica para verificar a interface de rede, você pode adicionar comandos específicos aqui.
        # Exemplo: Verificar se a interface está ativa ou algo relacionado à rede.
        echo "Verificando a interface de rede..."
    done
}

# Função para forçar a atualização (usando o parâmetro FORCE_UPDATE_INTERVAL)
force_update() {
    while true; do
        sleep "$FORCE_UPDATE_INTERVAL"
        # Lógica para forçar atualização, pode ser uma verificação de status ou alguma atualização necessária.
        echo "Forçando atualização..."
    done
}

# Loop infinito para rodar as funções e gerenciar intervalos
while true; do
    generate_tags
    check_network_interface &
    force_update &
    sleep "$LOOP_INTERVAL"
done
EOF

# Torna o script executável
chmod +x "$INSTALL_DIR/pve-owntag"

# Criar o arquivo de configuração
cat << 'EOF' > "$CONFIG_FILE"
# Configuração do PVE OWNER Tag
LOOP_INTERVAL=60
FW_NET_INTERFACE_CHECK_INTERVAL=60
QM_STATUS_CHECK_INTERVAL=-1
FORCE_UPDATE_INTERVAL=1800
EOF

# Criar o arquivo de serviço do systemd
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

# Carregar o serviço systemd e iniciar o serviço
systemctl daemon-reload
systemctl enable pve-owntag.service
systemctl start pve-owntag.service

msg_ok "Installation complete. The service is now running."

exit
