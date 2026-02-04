#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# verificar root
[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} Debes ejecutar este script como usuario root!\n" && exit 1

# verificar sistema operativo
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}No se detecto la version del sistema, por favor contacta al autor del script!${plain}\n" && exit 1
fi

########################
# Analisis de parametros
########################
VERSION_ARG=""
API_HOST_ARG=""
NODE_ID_ARG=""
API_KEY_ARG=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api-host)
                API_HOST_ARG="$2"; shift 2 ;;
            --node-id)
                NODE_ID_ARG="$2"; shift 2 ;;
            --api-key)
                API_KEY_ARG="$2"; shift 2 ;;
            -h|--help)
                echo "Uso: $0 [version] [--api-host URL] [--node-id ID] [--api-key KEY]"
                exit 0 ;;
            --*)
                echo "Parametro desconocido: $1"; exit 1 ;;
            *)
                # Compatible con el primer parametro posicional como numero de version
                if [[ -z "$VERSION_ARG" ]]; then
                    VERSION_ARG="$1"; shift
                else
                    shift
                fi ;;
        esac
    done
}

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}Fallo al detectar la arquitectura, usando arquitectura por defecto: ${arch}${plain}"
fi

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "Este software no soporta sistemas de 32 bits (x86), por favor usa un sistema de 64 bits (x86_64). Si la deteccion es incorrecta, contacta al autor"
    exit 2
fi

# version del sistema operativo
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Por favor usa CentOS 7 o una version superior!${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}Nota: CentOS 7 no puede usar el protocolo hysteria1/2!${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Por favor usa Ubuntu 16 o una version superior!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Por favor usa Debian 8 o una version superior!${plain}\n" && exit 1
    fi
fi

install_base() {
    # Version optimizada: verificacion e instalacion por lotes, reduciendo llamadas al sistema
    need_install_apt() {
        local packages=("$@")
        local missing=()

        # Verificar paquetes instalados por lotes
        local installed_list=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | sort)

        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done

        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "Instalando paquetes faltantes: ${missing[*]}"
            apt-get update -y >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" >/dev/null 2>&1
        fi
    }

    need_install_yum() {
        local packages=("$@")
        local missing=()

        # Verificar paquetes instalados por lotes
        local installed_list=$(rpm -qa --qf '%{NAME}\n' 2>/dev/null | sort)

        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done

        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "Instalando paquetes faltantes: ${missing[*]}"
            yum install -y "${missing[@]}" >/dev/null 2>&1
        fi
    }

    need_install_apk() {
        local packages=("$@")
        local missing=()

        # Verificar paquetes instalados por lotes
        local installed_list=$(apk info 2>/dev/null | sort)

        for p in "${packages[@]}"; do
            if ! echo "$installed_list" | grep -q "^${p}$"; then
                missing+=("$p")
            fi
        done

        if [[ ${#missing[@]} -gt 0 ]]; then
            echo "Instalando paquetes faltantes: ${missing[*]}"
            apk add --no-cache "${missing[@]}" >/dev/null 2>&1
        fi
    }

    # Instalar todos los paquetes necesarios de una vez
    if [[ x"${release}" == x"centos" ]]; then
        # Verificar e instalar epel-release
        if ! rpm -q epel-release >/dev/null 2>&1; then
            echo "Instalando repositorio EPEL..."
            yum install -y epel-release >/dev/null 2>&1
        fi
        need_install_yum wget curl unzip tar cronie socat ca-certificates pv
        update-ca-trust force-enable >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"alpine" ]]; then
        need_install_apk wget curl unzip tar socat ca-certificates pv
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"debian" ]]; then
        need_install_apt wget curl unzip tar cron socat ca-certificates pv
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"ubuntu" ]]; then
        need_install_apt wget curl unzip tar cron socat ca-certificates pv
        update-ca-certificates >/dev/null 2>&1 || true
    elif [[ x"${release}" == x"arch" ]]; then
        echo "Actualizando base de datos de paquetes..."
        pacman -Sy --noconfirm >/dev/null 2>&1
        # --needed omitira los paquetes ya instalados, muy eficiente
        echo "Instalando paquetes necesarios..."
        pacman -S --noconfirm --needed wget curl unzip tar cronie socat ca-certificates pv >/dev/null 2>&1
    fi
}

# 0: ejecutando, 1: no ejecutando, 2: no instalado
check_status() {
    if [[ ! -f /usr/local/v2node/v2node ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service v2node status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status v2node | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

generate_v2node_config() {
        local api_host="$1"
        local node_id="$2"
        local api_key="$3"

        mkdir -p /etc/v2node >/dev/null 2>&1
        cat > /etc/v2node/config.json <<EOF
{
    "Log": {
        "Level": "warning",
        "Output": "",
        "Access": "none"
    },
    "Nodes": [
        {
            "ApiHost": "${api_host}",
            "NodeID": ${node_id},
            "ApiKey": "${api_key}",
            "Timeout": 15
        }
    ]
}
EOF
        echo -e "${green}Archivo de configuracion de V2node generado, reiniciando servicio${plain}"
        if [[ x"${release}" == x"alpine" ]]; then
            service v2node restart
        else
            systemctl restart v2node
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}v2node reiniciado exitosamente${plain}"
        else
            echo -e "${red}v2node posiblemente fallo al iniciar, usa v2node log para ver los registros${plain}"
        fi
}

install_v2node() {
    local version_param="$1"
    if [[ -e /usr/local/v2node/ ]]; then
        rm -rf /usr/local/v2node/
    fi

    mkdir /usr/local/v2node/ -p
    cd /usr/local/v2node/

    if  [[ -z "$version_param" ]] ; then
        last_version=$(curl -Ls "https://api.github.com/repos/wyx2685/v2node/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Fallo al detectar la version de v2node, puede ser por exceder el limite de la API de Github. Intenta mas tarde o especifica la version manualmente${plain}"
            exit 1
        fi
        echo -e "${green}Ultima version detectada: ${last_version}, iniciando instalacion...${plain}"
        url="https://github.com/wyx2685/v2node/releases/download/${last_version}/v2node-linux-${arch}.zip"
        curl -sL "$url" | pv -s 30M -W -N "Progreso de descarga" > /usr/local/v2node/v2node-linux.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Fallo al descargar v2node, asegurate de que tu servidor pueda descargar archivos de Github${plain}"
            exit 1
        fi
    else
    last_version=$version_param
        url="https://github.com/wyx2685/v2node/releases/download/${last_version}/v2node-linux-${arch}.zip"
        curl -sL "$url" | pv -s 30M -W -N "Progreso de descarga" > /usr/local/v2node/v2node-linux.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Fallo al descargar v2node $1, asegurate de que esta version exista${plain}"
            exit 1
        fi
    fi

    unzip v2node-linux.zip
    rm v2node-linux.zip -f
    chmod +x v2node
    mkdir /etc/v2node/ -p
    cp geoip.dat /etc/v2node/
    cp geosite.dat /etc/v2node/
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/v2node -f
        cat <<EOF > /etc/init.d/v2node
#!/sbin/openrc-run

name="v2node"
description="v2node"

command="/usr/local/v2node/v2node"
command_args="server"
command_user="root"

pidfile="/run/v2node.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/v2node
        rc-update add v2node default
        echo -e "${green}v2node ${last_version}${plain} instalacion completada, configurado para iniciar automaticamente"
    else
        rm /etc/systemd/system/v2node.service -f
        cat <<EOF > /etc/systemd/system/v2node.service
[Unit]
Description=v2node Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/v2node/
ExecStart=/usr/local/v2node/v2node server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop v2node
        systemctl enable v2node
        echo -e "${green}v2node ${last_version}${plain} instalacion completada, configurado para iniciar automaticamente"
    fi

    if [[ ! -f /etc/v2node/config.json ]]; then
        # Si se pasaron parametros completos por CLI, generar configuracion directamente y omitir interaccion
        if [[ -n "$API_HOST_ARG" && -n "$NODE_ID_ARG" && -n "$API_KEY_ARG" ]]; then
            generate_v2node_config "$API_HOST_ARG" "$NODE_ID_ARG" "$API_KEY_ARG"
            echo -e "${green}Se genero /etc/v2node/config.json segun los parametros${plain}"
            first_install=false
        else
            cp config.json /etc/v2node/
            first_install=true
        fi
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service v2node start
        else
            systemctl start v2node
        fi
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}v2node reiniciado exitosamente${plain}"
        else
            echo -e "${red}v2node posiblemente fallo al iniciar, usa v2node log para ver los registros${plain}"
        fi
        first_install=false
    fi


    curl -o /usr/bin/v2node -Ls https://raw.githubusercontent.com/demianrey/v2node_DR/mod/script/v2node.sh
    chmod +x /usr/bin/v2node

    cd $cur_dir
    rm -f install.sh
    echo "------------------------------------------"
    echo -e "Uso del script de administracion: "
    echo "------------------------------------------"
    echo "v2node              - Mostrar menu de administracion (mas funciones)"
    echo "v2node start        - Iniciar v2node"
    echo "v2node stop         - Detener v2node"
    echo "v2node restart      - Reiniciar v2node"
    echo "v2node status       - Ver estado de v2node"
    echo "v2node enable       - Habilitar inicio automatico de v2node"
    echo "v2node disable      - Deshabilitar inicio automatico de v2node"
    echo "v2node log          - Ver registros de v2node"
    echo "v2node generate     - Generar archivo de configuracion de v2node"
    echo "v2node update       - Actualizar v2node"
    echo "v2node update x.x.x - Actualizar v2node a version especifica"
    echo "v2node install      - Instalar v2node"
    echo "v2node uninstall    - Desinstalar v2node"
    echo "v2node version      - Ver version de v2node"
    echo "------------------------------------------"

    if [[ $first_install == true ]]; then
        read -rp "Se detecto que es tu primera instalacion de v2node, deseas generar /etc/v2node/config.json automaticamente? (y/n): " if_generate
        if [[ "$if_generate" =~ ^[Yy]$ ]]; then
            # Recopilar parametros interactivamente, proporcionando valores de ejemplo
            read -rp "Direccion API del panel [formato: https://example.com/]: " api_host
            api_host=${api_host:-https://example.com/}
            read -rp "ID del nodo: " node_id
            node_id=${node_id:-1}
            read -rp "Clave de comunicacion del nodo: " api_key

            # Generar archivo de configuracion (sobrescribe la plantilla copiada del paquete)
            generate_v2node_config "$api_host" "$node_id" "$api_key"
        else
            echo "${green}Se omitio la generacion automatica de configuracion. Para generar despues, ejecuta: v2node generate${plain}"
        fi
    fi
}

parse_args "$@"
echo -e "${green}Iniciando instalacion${plain}"
install_base
install_v2node "$VERSION_ARG"
