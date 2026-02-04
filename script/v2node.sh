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

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [por defecto $2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Deseas reiniciar v2node" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Presiona Enter para volver al menu principal: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/demianrey/v2node_DR/mod/script/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "Ingresa la version especifica (por defecto ultima): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/demianrey/v2node_DR/mod/script/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}Actualizacion completada, v2node se ha reiniciado automaticamente. Usa v2node log para ver los registros${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "v2node intentara reiniciarse automaticamente despues de modificar la configuracion"
    vi /etc/v2node/config.json
    sleep 2
    restart
    check_status
    case $? in
        0)
            echo -e "Estado de v2node: ${green}Ejecutando${plain}"
            ;;
        1)
            echo -e "Se detecto que v2node no esta iniciado o fallo el reinicio automatico. Deseas ver los registros? [Y/n]" && echo
            read -e -rp "(por defecto: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "Estado de v2node: ${red}No instalado${plain}"
    esac
}

uninstall() {
    confirm "Estas seguro de que deseas desinstalar v2node?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        service v2node stop
        rc-update del v2node
        rm /etc/init.d/v2node -f
    else
        systemctl stop v2node
        systemctl disable v2node
        rm /etc/systemd/system/v2node.service -f
        systemctl daemon-reload
        systemctl reset-failed
    fi
    rm /etc/v2node/ -rf
    rm /usr/local/v2node/ -rf

    echo ""
    echo -e "Desinstalacion exitosa. Si deseas eliminar este script, sal del script y ejecuta ${green}rm /usr/bin/v2node -f${plain}"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}v2node ya esta ejecutandose, no es necesario iniciarlo de nuevo. Si deseas reiniciar, selecciona reiniciar${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service v2node start
        else
            systemctl start v2node
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}v2node iniciado exitosamente. Usa v2node log para ver los registros${plain}"
        else
            echo -e "${red}v2node posiblemente fallo al iniciar. Usa v2node log para ver los registros${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        service v2node stop
    else
        systemctl stop v2node
    fi
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}v2node detenido exitosamente${plain}"
    else
        echo -e "${red}v2node fallo al detenerse, posiblemente porque el tiempo de detencion excedio dos segundos. Revisa los registros mas tarde${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        service v2node restart
    else
        systemctl restart v2node
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}v2node reiniciado exitosamente. Usa v2node log para ver los registros${plain}"
    else
        echo -e "${red}v2node posiblemente fallo al iniciar. Usa v2node log para ver los registros${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ x"${release}" == x"alpine" ]]; then
        service v2node status
    else
        systemctl status v2node --no-pager -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add v2node
    else
        systemctl enable v2node
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}v2node configurado para inicio automatico exitosamente${plain}"
    else
        echo -e "${red}Fallo al configurar v2node para inicio automatico${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del v2node
    else
        systemctl disable v2node
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}Inicio automatico de v2node deshabilitado exitosamente${plain}"
    else
        echo -e "${red}Fallo al deshabilitar el inicio automatico de v2node${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}El sistema Alpine no soporta visualizacion de registros por el momento${plain}\n" && exit 1
    else
        journalctl -u v2node.service -e --no-pager -f
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_shell() {
    wget -O /usr/bin/v2node -N --no-check-certificate https://raw.githubusercontent.com/demianrey/v2node_DR/mod/script/v2node.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}Fallo al descargar el script, verifica que tu maquina pueda conectarse a Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/v2node
        echo -e "${green}Script actualizado exitosamente, por favor ejecuta el script de nuevo${plain}" && exit 0
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

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(rc-update show | grep v2node)
        if [[ x"${temp}" == x"" ]]; then
            return 1
        else
            return 0
        fi
    else
        temp=$(systemctl is-enabled v2node)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1;
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}v2node ya esta instalado, no lo instales de nuevo${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}Por favor instala v2node primero${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "Estado de v2node: ${green}Ejecutando${plain}"
            show_enable_status
            ;;
        1)
            echo -e "Estado de v2node: ${yellow}No ejecutando${plain}"
            show_enable_status
            ;;
        2)
            echo -e "Estado de v2node: ${red}No instalado${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Inicio automatico: ${green}Si${plain}"
    else
        echo -e "Inicio automatico: ${red}No${plain}"
    fi
}

show_v2node_version() {
    echo -n "Version de v2node: "
    /usr/local/v2node/v2node version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
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


generate_config_file() {
    # Recopilar parametros interactivamente, proporcionando valores de ejemplo
    read -rp "Direccion API del panel [formato: https://example.com/]: " api_host
    api_host=${api_host:-https://example.com/}
    read -rp "ID del nodo: " node_id
    node_id=${node_id:-1}
    read -rp "Clave de comunicacion del nodo: " api_key

    # Generar archivo de configuracion (sobrescribe la plantilla copiada del paquete)
    generate_v2node_config "$api_host" "$node_id" "$api_key"
}

# Abrir puertos del firewall
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}Puertos del firewall abiertos exitosamente!${plain}"
}

show_usage() {
    echo "Uso del script de administracion de v2node: "
    echo "------------------------------------------"
    echo "v2node              - Mostrar menu de administracion (mas funciones)"
    echo "v2node start        - Iniciar v2node"
    echo "v2node stop         - Detener v2node"
    echo "v2node restart      - Reiniciar v2node"
    echo "v2node status       - Ver estado de v2node"
    echo "v2node enable       - Habilitar inicio automatico de v2node"
    echo "v2node disable      - Deshabilitar inicio automatico de v2node"
    echo "v2node log          - Ver registros de v2node"
    echo "v2node x25519       - Generar clave x25519"
    echo "v2node generate     - Generar archivo de configuracion de v2node"
    echo "v2node update       - Actualizar v2node"
    echo "v2node update x.x.x - Instalar version especifica de v2node"
    echo "v2node install      - Instalar v2node"
    echo "v2node uninstall    - Desinstalar v2node"
    echo "v2node version      - Ver version de v2node"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}Script de administracion de v2node,${plain}${red} no compatible con docker${plain}
--- https://github.com/demianrey/v2node_DR ---
  ${green}0.${plain} Modificar configuracion
————————————————
  ${green}1.${plain} Instalar v2node
  ${green}2.${plain} Actualizar v2node
  ${green}3.${plain} Desinstalar v2node
————————————————
  ${green}4.${plain} Iniciar v2node
  ${green}5.${plain} Detener v2node
  ${green}6.${plain} Reiniciar v2node
  ${green}7.${plain} Ver estado de v2node
  ${green}8.${plain} Ver registros de v2node
————————————————
  ${green}9.${plain} Habilitar inicio automatico de v2node
  ${green}10.${plain} Deshabilitar inicio automatico de v2node
————————————————
  ${green}11.${plain} Ver version de v2node
  ${green}12.${plain} Actualizar script de mantenimiento
  ${green}13.${plain} Generar archivo de configuracion de v2node
  ${green}14.${plain} Abrir todos los puertos de red del VPS
  ${green}15.${plain} Salir del script
 "
 #Actualizaciones futuras pueden agregarse a la cadena anterior
    show_status
    echo && read -rp "Por favor ingresa tu seleccion [0-15]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) check_install && show_v2node_version ;;
        12) update_shell ;;
        13) generate_config_file ;;
        14) open_ports ;;
        15) exit ;;
        *) echo -e "${red}Por favor ingresa un numero correcto [0-15]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "version") check_install 0 && show_v2node_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
