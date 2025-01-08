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
            usuario="${CUSTOM_TAG}_$usuario"

            # Obter as tags atuais
            if [ "$tipo" == "vm" ]; then
                tags_atuais=$(qm config "${item}" | grep -i "tags" | cut -d':' -f2 | tr -d '[:space:]')
            elif [ "$tipo" == "container" ]; then
                tags_atuais=$(pct config "${item}" | grep -i "tags" | cut -d':' -f2 | tr -d '[:space:]')
            fi

            # Substituir as tags que começam com "OWNER_" e adicionar a nova tag "OWNER_$usuario"
            if [ -n "$tags_atuais" ]; then
                # Substituir qualquer tag existente com o prefixo "OWNER_" pela nova
                tags_atuais=$(echo "$tags_atuais" | sed -E "s/\bOWNER_[^,]*\b/$usuario/g")
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
