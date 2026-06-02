#!/bin/sh

# ============================================================================
# Скрипт для настройки раздельной маршрутизации на OpenWrt 25.12.x
# Использует только nftset (без ipset)
# Поддерживает WireGuard, AmneziaWG, OpenVPN, Sing-box, tun2socks
# ============================================================================

set -e

# Цветные выводы
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Проверка версии OpenWrt
check_version() {
    source /etc/os-release 2>/dev/null || {
        echo -e "${RED}Cannot determine OpenWrt version${NC}"
        exit 1
    }
    
    VERSION_ID=$(echo "$VERSION" | cut -d. -f1)
    
    if [ "$VERSION_ID" -ne 25 ]; then
        echo -e "${RED}This script only supports OpenWrt 25.12.x and above${NC}"
        echo -e "${YELLOW}Current version: $OPENWRT_RELEASE${NC}"
        echo -e "${YELLOW}For older versions, use the original script from itdoginfo${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ OpenWrt version: $OPENWRT_RELEASE${NC}"
}

# Проверка пакетного менеджера (apk для 25.12+)
check_package_manager() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        echo -e "${GREEN}✓ Using apk package manager${NC}"
    else
        echo -e "${RED}apk package manager not found (required for OpenWrt 25.12+)${NC}"
        exit 1
    fi
}

# Проверка доступности репозиториев
check_repo() {
    echo -e "${BLUE}Checking repository availability...${NC}"
    if ! apk update 2>&1 | grep -q "OK"; then
        echo -e "${RED}Repository check failed. Check internet connection.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Repository OK${NC}"
}

# Установка необходимых пакетов
install_packages() {
    echo -e "${BLUE}Installing required packages...${NC}"
    
    PACKAGES="curl nano dnsmasq-full"
    
    for pkg in $PACKAGES; do
        if apk list --installed 2>/dev/null | grep -q "^$pkg"; then
            echo -e "${GREEN}✓ $pkg already installed${NC}"
        else
            echo -e "${YELLOW}Installing $pkg...${NC}"
            apk add "$pkg"
            echo -e "${GREEN}✓ $pkg installed${NC}"
        fi
    done
    
    # Удаляем dnsmasq если он есть, используем только dnsmasq-full
    if apk list --installed 2>/dev/null | grep -q "^dnsmasq" && ! apk list --installed 2>/dev/null | grep -q "^dnsmasq-full"; then
        echo -e "${YELLOW}Replacing dnsmasq with dnsmasq-full...${NC}"
        apk del dnsmasq
        apk add dnsmasq-full
    fi
}

# Настройка dnsmasq для работы с nftset
setup_dnsmasq() {
    echo -e "${BLUE}Configuring dnsmasq for nftset support...${NC}"
    
    # Настройка confdir
    if ! uci get dhcp.@dnsmasq[0].confdir 2>/dev/null | grep -q "/tmp/dnsmasq.d"; then
        uci set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
        echo -e "${GREEN}✓ confdir set to /tmp/dnsmasq.d${NC}"
    fi
    
    # Отключаем resolv.conf если не используем системный DNS
    uci set dhcp.@dnsmasq[0].noresolv='1'
    
    uci commit dhcp
    
    # Создаем директорию для конфигов
    mkdir -p /tmp/dnsmasq.d
}

# Маршрутизация для VPN (hotplug скрипты)
setup_vpn_routes() {
    local tunnel=$1
    local dev=$2
    
    echo -e "${BLUE}Setting up VPN routes for $tunnel...${NC}"
    
    cat > /etc/hotplug.d/iface/30-vpnroute << EOF
#!/bin/sh
[ "\$ACTION" = "ifup" ] || exit 0
[ "\$INTERFACE" = "$dev" ] || exit 0

sleep 5
ip route add table vpn default dev $dev
EOF
    
    cp /etc/hotplug.d/iface/30-vpnroute /etc/hotplug.d/net/30-vpnroute
    chmod +x /etc/hotplug.d/iface/30-vpnroute
    chmod +x /etc/hotplug.d/net/30-vpnroute
    
    echo -e "${GREEN}✓ VPN routes configured${NC}"
}

# Настройка таблиц маршрутизации
setup_routing_tables() {
    echo -e "${BLUE}Setting up routing tables...${NC}"
    
    # Добавляем таблицу vpn
    if ! grep -q "100 vpn" /etc/iproute2/rt_tables; then
        echo '100 vpn' >> /etc/iproute2/rt_tables
        echo -e "${GREEN}✓ Routing table 'vpn' added${NC}"
    fi
    
    # Добавляем правило маркировки
    if ! uci show network | grep -q "mark0x1"; then
        uci add network rule
        uci set network.@rule[-1].name='mark0x1'
        uci set network.@rule[-1].mark='0x1'
        uci set network.@rule[-1].priority='100'
        uci set network.@rule[-1].lookup='vpn'
        uci commit network
        echo -e "${GREEN}✓ Routing rule added${NC}"
    fi
}

# Создание nftset для доменов
setup_nftset() {
    echo -e "${BLUE}Creating nftset for domain routing...${NC}"
    
    # Создаем nftset через UCI (для dhcp)
    if ! uci show dhcp 2>/dev/null | grep -q "@nftset.*name='vpn_domains'"; then
        uci add dhcp nftset
        uci set dhcp.@nftset[-1].name='vpn_domains'
        uci set dhcp.@nftset[-1].family='ipv4'
        uci commit dhcp
        echo -e "${GREEN}✓ nftset 'vpn_domains' created${NC}"
    fi
}

# Создание правил firewall для nftset
setup_firewall_rules() {
    echo -e "${BLUE}Setting up firewall rules for nftset...${NC}"
    
    # Удаляем старые правила если есть
    local old_rule=$(uci show firewall 2>/dev/null | grep "mark_domains" | head -1 | cut -d'[' -f2 | cut -d']' -f1)
    if [ -n "$old_rule" ]; then
        uci delete firewall.@rule[$old_rule] 2>/dev/null
    fi
    
    # Создаем новое правило
    uci add firewall rule
    uci set firewall.@rule[-1].name='mark_domains'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest='*'
    uci set firewall.@rule[-1].proto='all'
    uci set firewall.@rule[-1].nftset='vpn_domains'
    uci set firewall.@rule[-1].set_mark='0x1'
    uci set firewall.@rule[-1].target='MARK'
    uci set firewall.@rule[-1].family='ipv4'
    uci commit firewall
    
    echo -e "${GREEN}✓ Firewall rule added for nftset${NC}"
}

# Настройка зон firewall для интерфейсов
setup_firewall_zone() {
    local tunnel=$1
    local interface=$2
    
    echo -e "${BLUE}Configuring firewall zone for $tunnel...${NC}"
    
    # Проверяем существует ли зона
    if uci show firewall 2>/dev/null | grep -q "@zone.*name='$tunnel'"; then
        echo -e "${YELLOW}Zone $tunnel already exists, skipping...${NC}"
        return
    fi
    
    # Создаем зону
    uci add firewall zone
    uci set firewall.@zone[-1].name="$tunnel"
    uci set firewall.@zone[-1].network="$interface"
    uci set firewall.@zone[-1].forward='REJECT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].input='REJECT'
    uci set firewall.@zone[-1].masq='1'
    uci set firewall.@zone[-1].mtu_fix='1'
    uci set firewall.@zone[-1].family='ipv4'
    
    # Создаем forwarding из LAN в VPN
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].name="${tunnel}-lan"
    uci set firewall.@forwarding[-1].dest="$tunnel"
    uci set firewall.@forwarding[-1].src='lan'
    uci set firewall.@forwarding[-1].family='ipv4'
    
    uci commit firewall
    
    echo -e "${GREEN}✓ Firewall zone '$tunnel' configured${NC}"
}

# Настройка WireGuard
setup_wireguard() {
    echo -e "${GREEN}Configuring WireGuard...${NC}"
    
    if ! apk list --installed 2>/dev/null | grep -q "wireguard-tools"; then
        echo -e "${YELLOW}Installing wireguard-tools...${NC}"
        apk add wireguard-tools
    fi
    
    setup_vpn_routes "wg" "wg0"
    
    # Запрос параметров
    read -p "Enter private key: " WG_PRIVATE_KEY
    
    while true; do
        read -p "Enter internal IP with subnet (e.g., 192.168.100.5/24): " WG_IP
        echo "$WG_IP" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]+$' && break
        echo -e "${RED}Invalid IP format${NC}"
    done
    
    read -p "Enter peer public key: " WG_PUBLIC_KEY
    read -p "Enter preshared key (optional, press Enter to skip): " WG_PRESHARED_KEY
    read -p "Enter endpoint host (domain or IP): " WG_ENDPOINT
    read -p "Enter endpoint port [51820]: " WG_ENDPOINT_PORT
    WG_ENDPOINT_PORT=${WG_ENDPOINT_PORT:-51820}
    
    # Настройка интерфейса
    uci set network.wg0=interface
    uci set network.wg0.proto='wireguard'
    uci set network.wg0.private_key="$WG_PRIVATE_KEY"
    uci set network.wg0.listen_port='51820'
    uci set network.wg0.addresses="$WG_IP"
    
    # Настройка peer
    if ! uci show network | grep -q "wireguard_wg0"; then
        uci add network wireguard_wg0
    fi
    
    uci set network.@wireguard_wg0[0]=wireguard_wg0
    uci set network.@wireguard_wg0[0].name='wg0_client'
    uci set network.@wireguard_wg0[0].public_key="$WG_PUBLIC_KEY"
    [ -n "$WG_PRESHARED_KEY" ] && uci set network.@wireguard_wg0[0].preshared_key="$WG_PRESHARED_KEY"
    uci set network.@wireguard_wg0[0].route_allowed_ips='0'
    uci set network.@wireguard_wg0[0].persistent_keepalive='25'
    uci set network.@wireguard_wg0[0].endpoint_host="$WG_ENDPOINT"
    uci set network.@wireguard_wg0[0].allowed_ips='0.0.0.0/0'
    uci set network.@wireguard_wg0[0].endpoint_port="$WG_ENDPOINT_PORT"
    
    uci commit network
    
    setup_firewall_zone "wg" "wg0"
}

# Установка AmneziaWG пакетов
install_awg_packages() {
    echo -e "${BLUE}Installing AmneziaWG packages...${NC}"
    
    # Получаем информацию о системе
    PKGARCH=$(apk list --available 2>/dev/null | head -1 | cut -d'.' -f2 || echo "mips_24kc")
    TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
    SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
    VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
    
    PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
    BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"
    
    AWG_DIR="/tmp/amneziawg"
    mkdir -p "$AWG_DIR"
    
    # Установка amneziawg-tools
    if ! apk list --installed 2>/dev/null | grep -q "amneziawg-tools"; then
        AMNEZIAWG_TOOLS_FILENAME="amneziawg-tools${PKGPOSTFIX}"
        curl -L -o "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME" "${BASE_URL}v${VERSION}/${AMNEZIAWG_TOOLS_FILENAME}"
        apk add --allow-untrusted "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME"
    fi
    
    # Установка kmod-amneziawg
    if ! apk list --installed 2>/dev/null | grep -q "kmod-amneziawg"; then
        KMOD_AMNEZIAWG_FILENAME="kmod-amneziawg${PKGPOSTFIX}"
        curl -L -o "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME" "${BASE_URL}v${VERSION}/${KMOD_AMNEZIAWG_FILENAME}"
        apk add --allow-untrusted "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME"
    fi
    
    rm -rf "$AWG_DIR"
    echo -e "${GREEN}✓ AmneziaWG packages installed${NC}"
}

# Настройка AmneziaWG
setup_amneziawg() {
    echo -e "${GREEN}Configuring AmneziaWG...${NC}"
    
    install_awg_packages
    setup_vpn_routes "awg" "awg0"
    
    # Запрос параметров (аналогично WireGuard + Amnezia специфичные параметры)
    read -p "Enter private key: " AWG_PRIVATE_KEY
    
    while true; do
        read -p "Enter internal IP with subnet: " AWG_IP
        echo "$AWG_IP" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]+$' && break
        echo -e "${RED}Invalid IP format${NC}"
    done
    
    read -p "Enter peer public key: " AWG_PUBLIC_KEY
    read -p "Enter preshared key (optional): " AWG_PRESHARED_KEY
    read -p "Enter endpoint host: " AWG_ENDPOINT
    read -p "Enter endpoint port [51820]: " AWG_ENDPOINT_PORT
    AWG_ENDPOINT_PORT=${AWG_ENDPOINT_PORT:-51820}
    
    # Amnezia специфичные параметры
    read -p "Enter Jc value: " AWG_JC
    read -p "Enter Jmin value: " AWG_JMIN
    read -p "Enter Jmax value: " AWG_JMAX
    read -p "Enter S1 value: " AWG_S1
    read -p "Enter S2 value: " AWG_S2
    read -p "Enter H1 value: " AWG_H1
    read -p "Enter H2 value: " AWG_H2
    read -p "Enter H3 value: " AWG_H3
    read -p "Enter H4 value: " AWG_H4
    
    # Настройка интерфейса
    uci set network.awg0=interface
    uci set network.awg0.proto='amneziawg'
    uci set network.awg0.private_key="$AWG_PRIVATE_KEY"
    uci set network.awg0.listen_port='51820'
    uci set network.awg0.addresses="$AWG_IP"
    
    uci set network.awg0.awg_jc="$AWG_JC"
    uci set network.awg0.awg_jmin="$AWG_JMIN"
    uci set network.awg0.awg_jmax="$AWG_JMAX"
    uci set network.awg0.awg_s1="$AWG_S1"
    uci set network.awg0.awg_s2="$AWG_S2"
    uci set network.awg0.awg_h1="$AWG_H1"
    uci set network.awg0.awg_h2="$AWG_H2"
    uci set network.awg0.awg_h3="$AWG_H3"
    uci set network.awg0.awg_h4="$AWG_H4"
    
    # Настройка peer
    if ! uci show network | grep -q "amneziawg_awg0"; then
        uci add network amneziawg_awg0
    fi
    
    uci set network.@amneziawg_awg0[0]=amneziawg_awg0
    uci set network.@amneziawg_awg0[0].name='awg0_client'
    uci set network.@amneziawg_awg0[0].public_key="$AWG_PUBLIC_KEY"
    [ -n "$AWG_PRESHARED_KEY" ] && uci set network.@amneziawg_awg0[0].preshared_key="$AWG_PRESHARED_KEY"
    uci set network.@amneziawg_awg0[0].route_allowed_ips='0'
    uci set network.@amneziawg_awg0[0].persistent_keepalive='25'
    uci set network.@amneziawg_awg0[0].endpoint_host="$AWG_ENDPOINT"
    uci set network.@amneziawg_awg0[0].allowed_ips='0.0.0.0/0'
    uci set network.@amneziawg_awg0[0].endpoint_port="$AWG_ENDPOINT_PORT"
    
    uci commit network
    
    setup_firewall_zone "awg" "awg0"
}

# Настройка OpenVPN
setup_openvpn() {
    echo -e "${GREEN}Configuring OpenVPN (manual setup required)...${NC}"
    
    if ! apk list --installed 2>/dev/null | grep -q "openvpn"; then
        apk add openvpn openssl
    fi
    
    setup_vpn_routes "ovpn" "tun0"
    setup_firewall_zone "ovpn" "tun0"
    
    echo -e "${YELLOW}OpenVPN zone configured. You need to manually setup the tunnel${NC}"
    echo "Configuration guide: https://itdog.info/nastrojka-klienta-openvpn-na-openwrt/"
}

# Настройка Sing-box
setup_singbox() {
    echo -e "${GREEN}Configuring Sing-box...${NC}"
    
    if ! apk list --installed 2>/dev/null | grep -q "sing-box"; then
        apk add sing-box
    fi
    
    setup_vpn_routes "singbox" "tun0"
    setup_firewall_zone "singbox" "tun0"
    
    # Создаем базовый конфиг
    if [ ! -f /etc/sing-box/config.json ]; then
        mkdir -p /etc/sing-box
        cat > /etc/sing-box/config.json << 'EOF'
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "tun",
      "interface_name": "tun0",
      "inet4_address": "172.19.0.1/30",
      "auto_route": false,
      "strict_route": false,
      "stack": "system",
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
    fi
    
    echo -e "${YELLOW}Edit /etc/sing-box/config.json to add your proxy configuration${NC}"
    echo "Documentation: https://sing-box.sagernet.org/configuration/outbound/"
}

# Настройка tun2socks
setup_tun2socks() {
    echo -e "${GREEN}Configuring tun2socks (manual setup required)...${NC}"
    
    setup_vpn_routes "tun2socks" "tun0"
    setup_firewall_zone "tun2socks" "tun0"
    
    echo -e "${YELLOW}tun2socks zone configured. You need to manually setup the tunnel${NC}"
    echo "Guide: https://cli.co/VNZISEM"
}

# Выбор типа туннеля
select_tunnel() {
    echo ""
    echo -e "${BLUE}Select VPN tunnel type:${NC}"
    echo "1) WireGuard"
    echo "2) Amnezia WireGuard"
    echo "3) OpenVPN (manual config)"
    echo "4) Sing-box (Shadowsocks/VMess/VLESS)"
    echo "5) tun2socks (manual config)"
    echo "6) Skip VPN setup"
    
    while true; do
        read -p "Enter choice [1-6]: " choice
        case $choice in
            1) setup_wireguard; break ;;
            2) setup_amneziawg; break ;;
            3) setup_openvpn; break ;;
            4) setup_singbox; break ;;
            5) setup_tun2socks; break ;;
            6) echo -e "${YELLOW}Skipping VPN setup${NC}"; break ;;
            *) echo -e "${RED}Invalid choice${NC}" ;;
        esac
    done
}

# Скрипт для загрузки списков доменов
create_getdomains_script() {
    echo -e "${BLUE}Creating domain list download script...${NC}"
    
    cat > /etc/init.d/getdomains << 'EOF'
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=0

start() {
    local DOMAINS_URL="$1"
    
    [ -z "$DOMAINS_URL" ] && DOMAINS_URL="https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/inside-dnsmasq-nfset.lst"
    
    local count=0
    while [ $count -lt 10 ]; do
        if curl -s -m 5 -f "https://github.com" >/dev/null 2>&1; then
            curl -s -f "$DOMAINS_URL" -o /tmp/dnsmasq.d/domains.lst
            if [ -s /tmp/dnsmasq.d/domains.lst ] && dnsmasq --test -C /tmp/dnsmasq.d/domains.lst >/dev/null 2>&1; then
                /etc/init.d/dnsmasq restart
                echo "Domain list updated successfully"
                break
            fi
        else
            echo "Internet not available, retry $((count+1))/10"
            sleep 30
            count=$((count+1))
        fi
    done
}

stop() {
    rm -f /tmp/dnsmasq.d/domains.lst
    /etc/init.d/dnsmasq restart
}

restart() {
    stop
    start
}
EOF
    
    chmod +x /etc/init.d/getdomains
    /etc/init.d/getdomains enable
    
    # Добавляем в cron (каждые 8 часов)
    if ! crontab -l 2>/dev/null | grep -q "/etc/init.d/getdomains start"; then
        (crontab -l 2>/dev/null; echo "0 */8 * * * /etc/init.d/getdomains start") | crontab -
        /etc/init.d/cron restart
    fi
    
    echo -e "${GREEN}✓ getdomains script created${NC}"
}

# Выбор страны для списка доменов
select_country() {
    echo ""
    echo -e "${BLUE}Select domain list for routing:${NC}"
    echo "1) Russia (inside) - you are inside Russia"
    echo "2) Russia (outside) - you are outside Russia"
    echo "3) Ukraine"
    echo "4) Skip domain list setup"
    
    while true; do
        read -p "Enter choice [1-4]: " choice
        case $choice in
            1) 
                create_getdomains_script "https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/inside-dnsmasq-nfset.lst"
                break
                ;;
            2)
                create_getdomains_script "https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Russia/outside-dnsmasq-nfset.lst"
                break
                ;;
            3)
                create_getdomains_script "https://raw.githubusercontent.com/itdoginfo/allow-domains/main/Ukraine/inside-dnsmasq-nfset.lst"
                break
                ;;
            4)
                echo -e "${YELLOW}Skipping domain list setup${NC}"
                break
                ;;
            *) echo -e "${RED}Invalid choice${NC}" ;;
        esac
    done
}

# Выбор DNS резолвера
select_dns_resolver() {
    echo ""
    echo -e "${BLUE}Select DNS resolver:${NC}"
    echo "1) No additional resolver (use default)"
    echo "2) DNSCrypt-proxy2 (~10MB)"
    echo "3) Stubby (lightweight, ~36KB)"
    
    while true; do
        read -p "Enter choice [1-3]: " choice
        case $choice in
            1)
                echo -e "${YELLOW}Using default DNS resolver${NC}"
                break
                ;;
            2)
                echo -e "${BLUE}Installing DNSCrypt-proxy2...${NC}"
                apk add dnscrypt-proxy2
                sed -i 's/^# server_names =.*/server_names = ["cloudflare", "google"]/' /etc/dnscrypt-proxy2/dnscrypt-proxy.toml
                service dnscrypt-proxy restart
                
                uci set dhcp.@dnsmasq[0].noresolv='1'
                uci del_list dhcp.@dnsmasq[0].server='*' 2>/dev/null
                uci add_list dhcp.@dnsmasq[0].server='127.0.0.53#53'
                uci commit dhcp
                break
                ;;
            3)
                echo -e "${BLUE}Installing Stubby...${NC}"
                apk add stubby
                
                uci set dhcp.@dnsmasq[0].noresolv='1'
                uci del_list dhcp.@dnsmasq[0].server='*' 2>/dev/null
                uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5453'
                uci commit dhcp
                break
                ;;
            *) echo -e "${RED}Invalid choice${NC}" ;;
        esac
    done
    
    /etc/init.d/dnsmasq restart
}

# Финишная настройка и перезапуск
finalize() {
    echo ""
    echo -e "${BLUE}Applying all configurations...${NC}"
    
    # Перезапускаем network
    /etc/init.d/network restart
    
    # Перезапускаем firewall
    /etc/init.d/firewall reload
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Setup completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Note:${NC}"
    echo "1. If you chose manual configuration, set up your tunnel"
    echo "2. Domain lists will be updated automatically every 8 hours"
    echo "3. Check routing with: ip rule show"
    echo "4. Check nftsets with: nft list sets"
    echo ""
}

# Main execution
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}OpenWrt 25.12.x Selective Routing Setup${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # Проверки
    check_version
    check_package_manager
    check_repo
    
    # Базовая настройка
    install_packages
    setup_dnsmasq
    setup_routing_tables
    setup_nftset
    setup_firewall_rules
    
    # Выбор туннеля
    select_tunnel
    
    # Дополнительные настройки
    select_dns_resolver
    select_country
    
    # Финализация
    finalize
}

# Запуск
main
