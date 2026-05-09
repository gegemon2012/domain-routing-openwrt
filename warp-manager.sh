#!/bin/bash
set -o pipefail

# ══════════════════════════════════════════════════════════════
#  WARP Manager v1.2 — SECURE EDITION
#  Unified 3X-UI + AmneziaWG (Cloudflare WARP, Telegram Bot)
# ══════════════════════════════════════════════════════════════

WARP_VERSION="1.2-secure"
WARP_DIR="/etc/warp-manager"
WARP_CONF="$WARP_DIR/config"
WARP_LOG="/var/log/warp-manager.log"
BOT_PID_FILE="/var/run/warp_bot.pid"
DEFAULT_PORT=40000

WGCF_VERSION="2.2.30"
WGCF_BIN="/root/wgcf"
WGCF_ACCOUNT="/root/wgcf-account.toml"
WGCF_PROFILE="/root/wgcf-profile.conf"

AWG_WARP_DIR="/opt/warp"
AWG_WARP_CONF="$AWG_WARP_DIR/warp.conf"
AWG_WARP_CLIENTS="$AWG_WARP_DIR/clients.list"
AWG_MARKER_BEGIN="# --- WARP-MANAGER BEGIN ---"
AWG_MARKER_END="# --- WARP-MANAGER END ---"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'
BLUE='\033[0;34m'; DIM='\033[2m'; NC='\033[0m'

SOCKS_PORT=""
MY_IP=""
BOT_TOKEN=""
BOT_CHAT_ID=""
MODE=""

CONTAINER=""
AWG_VPN_CONF=""
AWG_VPN_IF=""
AWG_VPN_QUICK_CMD=""
AWG_CLIENTS_TABLE=""
AWG_START_SH=""
AWG_SUBNET=""
AWG_WARP_EXIT_IP=""
declare -a AWG_SELECTED_IPS=()
declare -a AWG_CLIENT_IPS=()
declare -A AWG_CLIENT_NAMES=()

# ═══════════════════════════════════════════════════════════════
#  CONFIG & SECURITY
# ═══════════════════════════════════════════════════════════════

init_config() {
    mkdir -p "$WARP_DIR"
    chmod 700 "$WARP_DIR"
    if [ ! -f "$WARP_CONF" ]; then
        touch "$WARP_CONF"
        chmod 600 "$WARP_CONF"
        cat > "$WARP_CONF" <<'CONF'
SOCKS_PORT="40000"
BOT_TOKEN=""
BOT_CHAT_ID=""
MODE=""
CONTAINER=""
CONF
    fi
    chmod 600 "$WARP_CONF" 2>/dev/null
    source "$WARP_CONF"
    SOCKS_PORT="${SOCKS_PORT:-$DEFAULT_PORT}"
}

save_config_val() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$WARP_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$WARP_CONF"
    else
        echo "${key}=\"${value}\"" >> "$WARP_CONF"
    fi
    source "$WARP_CONF"
}

escape_html() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

log_action() { 
    [ -f "$WARP_LOG" ] && [ $(stat -c%s "$WARP_LOG") -ge 5242880 ] && mv "$WARP_LOG" "${WARP_LOG}.1" 2>/dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WARP_LOG"
}

check_root() {
    [ "$EUID" -ne 0 ] && { echo -e "${RED}[ERROR] Запустите от root!${NC}"; exit 1; }
}

check_deps() {
    for cmd in jq curl wget; do
        if ! command -v "$cmd" &>/dev/null; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y > /dev/null 2>&1
            apt-get install -y jq curl wget > /dev/null 2>&1
            break
        fi
    done
}

get_my_ip() {
    MY_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || echo "N/A")
}

# ═══════════════════════════════════════════════════════════════
#  SYSTEM STATS & OS
# ═══════════════════════════════════════════════════════════════

get_system_stats() {
    local cpu_line load_avg mem_info disk_info uptime_str cpu_usage
    cpu_line=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
    load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')
    mem_info=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "%d/%dMB (%.1f%%)", $3, $2, $3/$2*100}')
    disk_info=$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s/%s (%s)", $3, $2, $5}')
    uptime_str=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*load.*//')
    cpu_usage=$(awk '/^cpu / {u=$2+$4; t=$2+$3+$4+$5+$6+$7+$8; if(t>0) printf "%.1f", u/t*100; else print "0"}' /proc/stat 2>/dev/null)
    local r=""
    r+="<b>📊 Системная информация</b>\n\n"
    r+="<b>Uptime:</b> ${uptime_str}\n"
    r+="<b>CPU:</b> ${cpu_line} ядер | ${cpu_usage}%\n"
    r+="<b>Load:</b> ${load_avg}\n"
    r+="<b>RAM:</b> ${mem_info}\n"
    r+="<b>Disk /:</b> ${disk_info}\n"
    echo "$r"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release; OS_ID="$ID"; OS_VERSION="$VERSION_ID"; OS_CODENAME="$VERSION_CODENAME"
    else
        OS_ID="unknown"
    fi
}

detect_mode() {
    source "$WARP_CONF" 2>/dev/null
    if [ -n "${MODE:-}" ] && [[ "$MODE" == "3xui" || "$MODE" == "amnezia" || "$MODE" == "both" ]]; then
        return 0
    fi

    local has_docker=0 has_amnezia=0 has_3xui=0
    command -v docker &>/dev/null && has_docker=1
    if [ "$has_docker" -eq 1 ]; then
        local awg_ct
        awg_ct=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^amnezia-awg2$|^amnezia-awg$' | head -1)
        [ -z "$awg_ct" ] && awg_ct=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i "amnezia" | head -1)
        [ -n "$awg_ct" ] && has_amnezia=1
    fi
    systemctl is-active x-ui &>/dev/null 2>&1 && has_3xui=1
    [ "$has_3xui" -eq 0 ] && command -v x-ui &>/dev/null && has_3xui=1

    if [ "$has_amnezia" -eq 1 ] && [ "$has_3xui" -eq 1 ]; then
        MODE="both"
    elif [ "$has_amnezia" -eq 1 ]; then
        MODE="amnezia"
    elif [ "$has_3xui" -eq 1 ]; then
        MODE="3xui"
    else
        MODE="both" # Default fallback
    fi
    save_config_val "MODE" "$MODE"
}

# ═══════════════════════════════════════════════════════════════
#  3X-UI BACKEND
# ═══════════════════════════════════════════════════════════════

is_warp_installed_3xui() { command -v warp-cli &>/dev/null; }

is_warp_running_3xui() {
    local st; st=$(warp-cli --accept-tos status 2>/dev/null)
    echo "$st" | grep -qi "status.*connected" && ! echo "$st" | grep -qi "disconnected"
}

get_warp_status_3xui() {
    if ! is_warp_installed_3xui; then echo "Не установлен"; return; fi
    local s; s=$(warp-cli --accept-tos status 2>/dev/null | head -5)
    if echo "$s" | grep -qi "disconnected"; then echo "Отключён"
    elif echo "$s" | grep -qi "connected"; then echo "Подключён"
    elif echo "$s" | grep -qi "registration missing"; then echo "Нет регистрации"
    else echo "Неизвестно"; fi
}

get_warp_ip_3xui() {
    curl -s4 --max-time 5 --proxy socks5h://127.0.0.1:${SOCKS_PORT} ifconfig.me 2>/dev/null || echo "N/A"
}

install_warp_3xui() {
    clear; echo -e "\n${CYAN}━━━ Установка Cloudflare WARP (3X-UI) ━━━${NC}\n"
    if is_warp_installed_3xui; then echo -e "${YELLOW}WARP уже установлен.${NC}"; read -p "Enter..."; return; fi
    detect_os
    if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
        echo -e "${RED}Поддерживаются только Ubuntu и Debian (ваша: ${OS_ID}).${NC}"; read -p "Enter..."; return
    fi
    echo -e "${YELLOW}[1/6]${NC} GPG-ключ Cloudflare..."
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null \
        || { echo -e "${RED}Ошибка GPG.${NC}"; read -p "Enter..."; return; }
    
    echo -e "${YELLOW}[2/6]${NC} Репозиторий..."
    local codename="${OS_CODENAME:-$(lsb_release -cs 2>/dev/null || echo focal)}"
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${codename} main" > /etc/apt/sources.list.d/cloudflare-client.list

    echo -e "${YELLOW}[3/6]${NC} Установка cloudflare-warp..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y > /dev/null 2>&1; apt-get install -y cloudflare-warp > /dev/null 2>&1
    command -v warp-cli &>/dev/null || { echo -e "${RED}Не удалось установить.${NC}"; read -p "Enter..."; return; }

    echo -e "${YELLOW}[4/6]${NC} Регистрация..."
    warp-cli --accept-tos registration new > /dev/null 2>&1 || { echo -e "${RED}Ошибка регистрации.${NC}"; read -p "Enter..."; return; }

    echo -e "${YELLOW}[5/6]${NC} SOCKS5-прокси..."
    warp-cli --accept-tos mode proxy > /dev/null 2>&1
    warp-cli --accept-tos proxy port "${SOCKS_PORT}" > /dev/null 2>&1

    echo -e "${YELLOW}[6/6]${NC} Подключение..."
    warp-cli --accept-tos connect > /dev/null 2>&1; sleep 3
    if is_warp_running_3xui; then
        local wip; wip=$(get_warp_ip_3xui)
        echo -e "${GREEN}  ✓ WARP IP: ${wip}${NC}"
        log_action "3XUI INSTALL: port=${SOCKS_PORT}, warp_ip=${wip}"
    else
        echo -e "${YELLOW}  ⚠ Подключение не подтверждено.${NC}"
    fi
    read -p "Enter..."
}

start_warp_3xui() {
    is_warp_installed_3xui || { echo -e "\n${RED}WARP не установлен.${NC}"; read -p "Enter..."; return; }
    is_warp_running_3xui && { echo -e "\n${YELLOW}Уже подключён.${NC}"; read -p "Enter..."; return; }
    warp-cli --accept-tos connect > /dev/null 2>&1; sleep 3
    is_warp_running_3xui && echo -e "${GREEN}[OK] Подключён.${NC}" || echo -e "${RED}Ошибка подключения.${NC}"
    read -p "Enter..."
}

stop_warp_3xui() {
    is_warp_installed_3xui || return
    warp-cli --accept-tos disconnect > /dev/null 2>&1
    echo -e "${GREEN}[OK] Отключён.${NC}"; log_action "3XUI STOP"
    read -p "Enter..."
}

rekey_warp_3xui() {
    is_warp_installed_3xui || return
    echo -e "\n${CYAN}━━━ Перевыпуск ключа WARP ━━━${NC}\n"
    warp-cli --accept-tos disconnect > /dev/null 2>&1
    warp-cli --accept-tos registration delete > /dev/null 2>&1
    warp-cli --accept-tos registration new > /dev/null 2>&1
    warp-cli --accept-tos mode proxy > /dev/null 2>&1; warp-cli --accept-tos proxy port "${SOCKS_PORT}" > /dev/null 2>&1
    warp-cli --accept-tos connect > /dev/null 2>&1; sleep 3
    echo -e "${GREEN}  ✓ Готово${NC}"
    read -p "Enter..."
}

uninstall_3xui() {
    warp-cli --accept-tos disconnect > /dev/null 2>&1
    warp-cli --accept-tos registration delete > /dev/null 2>&1
    apt-get remove -y cloudflare-warp > /dev/null 2>&1; apt-get autoremove -y > /dev/null 2>&1
    rm -f /etc/apt/sources.list.d/cloudflare-client.list /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
}

# ═══════════════════════════════════════════════════════════════
#  AMNEZIA BACKEND
# ═══════════════════════════════════════════════════════════════

awg_pick_container() {
    if [ -n "${CONTAINER:-}" ]; then
        docker exec "$CONTAINER" sh -c "true" 2>/dev/null && return 0
    fi
    local -a containers=()
    mapfile -t containers < <(docker ps --format '{{.Names}}' | grep -E '^amnezia-awg2$|^amnezia-awg$' 2>/dev/null || true)
    [ ${#containers[@]} -eq 0 ] && mapfile -t containers < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -i "amnezia" || true)
    
    if [ ${#containers[@]} -eq 0 ]; then return 1
    elif [ ${#containers[@]} -eq 1 ]; then CONTAINER="${containers[0]}"
    else CONTAINER="${containers[0]}"; fi # Auto-pick first for simplicity
    save_config_val "CONTAINER" "$CONTAINER"
    return 0
}

awg_load_container_data() {
    [ -z "$CONTAINER" ] && return 1
    if [ "$CONTAINER" = "amnezia-awg2" ]; then
        AWG_VPN_CONF="/opt/amnezia/awg/awg0.conf"
    else
        AWG_VPN_CONF="/opt/amnezia/awg/wg0.conf"
    fi
    AWG_CLIENTS_TABLE="/opt/amnezia/awg/clientsTable"
    AWG_START_SH="/opt/amnezia/start.sh"
    AWG_SUBNET=$(docker exec "$CONTAINER" sh -c "sed -n 's/^Address = \(.*\)$/\1/p' '$AWG_VPN_CONF' | head -n1 | cut -d',' -f1" 2>/dev/null | tr -d '\r')
}

awg_detect_warp_exit_ip() {
    AWG_WARP_EXIT_IP=""
    if docker exec "$CONTAINER" sh -c "ip addr show warp >/dev/null 2>&1" 2>/dev/null; then
        AWG_WARP_EXIT_IP=$(docker exec "$CONTAINER" sh -c "curl -s --interface warp --connect-timeout 3 https://ifconfig.me 2>/dev/null || true" | tr -d '\r\n')
    fi
}

is_warp_installed_awg() { docker exec "$CONTAINER" sh -c "[ -f '$AWG_WARP_CONF' ]" 2>/dev/null; }
is_warp_running_awg() { docker exec "$CONTAINER" sh -c "ip addr show warp >/dev/null 2>&1" 2>/dev/null; }

awg_install_wgcf() {
    if [ -x "$WGCF_BIN" ]; then return 0; fi
    local arch; arch=$(uname -m)
    local wa=""
    case "$arch" in
        x86_64) wa="amd64" ;; aarch64) wa="arm64" ;; armv7l) wa="armv7" ;;
        *) echo -e "${RED}Архитектура не поддерживается: $arch${NC}"; return 1 ;;
    esac
    
    local binary_name="wgcf_${WGCF_VERSION}_linux_${wa}"
    local download_url="https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/${binary_name}"
    local checksum_url="https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_${WGCF_VERSION}_checksums.txt"

    echo -e "${YELLOW}Скачивание wgcf и проверка подписи (SHA256)...${NC}"
    wget -q -O "/tmp/${binary_name}" "$download_url" || { echo -e "${RED}Ошибка скачивания.${NC}"; return 1; }
    wget -q -O "/tmp/wgcf_checksums.txt" "$checksum_url" || { echo -e "${RED}Ошибка скачивания хэшей.${NC}"; return 1; }

    cd /tmp || return 1
    if ! grep "$binary_name" "wgcf_checksums.txt" | sha256sum -c - >/dev/null 2>&1; then
        echo -e "${RED}ОШИБКА БЕЗОПАСНОСТИ: Контрольная сумма WGCF не совпадает!${NC}"
        rm -f "/tmp/${binary_name}" "/tmp/wgcf_checksums.txt"
        cd - >/dev/null; return 1
    fi
    cd - >/dev/null

    mv "/tmp/${binary_name}" "$WGCF_BIN"
    chmod 700 "$WGCF_BIN"
    rm -f "/tmp/wgcf_checksums.txt"
    return 0
}

awg_ensure_account() {
    if [ ! -f "$WGCF_ACCOUNT" ]; then
        (cd /root && yes | ./wgcf register 2>/dev/null)
    fi
    [ -f "$WGCF_ACCOUNT" ] || return 1
}

awg_generate_profile() {
    (cd /root && yes | ./wgcf generate 2>/dev/null)
    [ -f "$WGCF_PROFILE" ] || return 1
}

awg_resolve_endpoint() {
    local ep; ep=$(getent ahostsv4 engage.cloudflareclient.com 2>/dev/null | awk 'NR==1{print $1}')
    [ -z "$ep" ] && return 1
    echo "$ep"
}

awg_build_warp_conf() {
    local endpoint_ip="$1"
    local pk pub addr
    pk=$(awk -F' = ' '/^PrivateKey = /{print $2}' "$WGCF_PROFILE")
    pub=$(awk -F' = ' '/^PublicKey = /{print $2}' "$WGCF_PROFILE")
    addr=$(awk -F' = ' '/^Address = /{print $2}' "$WGCF_PROFILE" | cut -d',' -f1)

    docker exec "$CONTAINER" sh -c "mkdir -p '$AWG_WARP_DIR'"
    
    # Secure config injection via stdin
    cat <<WARPEOF | docker exec -i "$CONTAINER" sh -c "cat > '$AWG_WARP_CONF' && chmod 600 '$AWG_WARP_CONF'"
[Interface]
PrivateKey = ${pk}
Address = ${addr}
MTU = 1280
Table = off

[Peer]
PublicKey = ${pub}
AllowedIPs = 0.0.0.0/0
Endpoint = ${endpoint_ip}:2408
PersistentKeepalive = 25
WARPEOF
}

awg_warp_up() {
    docker exec "$CONTAINER" sh -c "wg-quick down '$AWG_WARP_CONF' >/dev/null 2>&1 || true"
    docker exec "$CONTAINER" sh -c "wg-quick up '$AWG_WARP_CONF'" || return 1
}

install_warp_awg() {
    clear; echo -e "\n${CYAN}━━━ Установка WARP (AmneziaWG) ━━━${NC}\n"
    if is_warp_installed_awg && is_warp_running_awg; then echo -e "${YELLOW}WARP уже установлен.${NC}"; read -p "Enter..."; return; fi
    
    awg_install_wgcf || { read -p "Enter..."; return; }
    awg_ensure_account || { read -p "Enter..."; return; }
    awg_generate_profile || { read -p "Enter..."; return; }
    local ep; ep=$(awg_resolve_endpoint) || { read -p "Enter..."; return; }
    
    awg_build_warp_conf "$ep"
    awg_warp_up || { read -p "Enter..."; return; }
    
    awg_detect_warp_exit_ip
    echo -e "\n${GREEN}WARP установлен! IP: ${AWG_WARP_EXIT_IP}${NC}"
    log_action "AWG INSTALL: warp_ip=${AWG_WARP_EXIT_IP}"
    read -p "Enter..."
}

start_warp_awg() { awg_warp_up; read -p "Enter..."; }
stop_warp_awg() { docker exec "$CONTAINER" sh -c "wg-quick down '$AWG_WARP_CONF' 2>/dev/null || true"; read -p "Enter..."; }

rekey_warp_awg() {
    is_warp_installed_awg || return
    docker exec "$CONTAINER" sh -c "wg-quick down '$AWG_WARP_CONF' 2>/dev/null || true"
    rm -f "$WGCF_ACCOUNT"
    awg_ensure_account && awg_generate_profile && {
        local ep; ep=$(awg_resolve_endpoint)
        awg_build_warp_conf "$ep"
        awg_warp_up
        awg_apply_rules; awg_patch_start_sh
    }
    echo -e "${GREEN}Ключ обновлен.${NC}"; read -p "Enter..."
}

awg_cleanup_rules() {
    docker exec "$CONTAINER" sh -c '
        ip rule | awk "/lookup 100/ {print \$1}" | sed "s/://g" | sort -rn | while read -r pr; do
            ip rule del priority "$pr" 2>/dev/null || true
        done
        iptables -t nat -S POSTROUTING | grep "\-o warp -j MASQUERADE" | while read -r line; do
            rule=$(echo "$line" | sed "s/^-A /-D /")
            iptables -t nat $rule || true
        done
        ip route flush table 100 2>/dev/null || true
    ' >/dev/null 2>&1 || true
}

awg_apply_rules() {
    awg_cleanup_rules
    [ ${#AWG_SELECTED_IPS[@]} -eq 0 ] && return 0
    docker exec "$CONTAINER" sh -c "ip route add default dev warp table 100 2>/dev/null || ip route replace default dev warp table 100 2>/dev/null || true"
    local prio=100
    for ip in "${AWG_SELECTED_IPS[@]}"; do
        # Data in AWG_SELECTED_IPS is already strictly validated via regex
        docker exec "$CONTAINER" sh -c "
            ip rule add from ${ip} table 100 priority ${prio} 2>/dev/null || true
            iptables -t nat -C POSTROUTING -s ${ip} -o warp -j MASQUERADE 2>/dev/null || \
            iptables -t nat -I POSTROUTING 1 -s ${ip} -o warp -j MASQUERADE
        "
        ((prio++))
    done
}

awg_patch_start_sh() {
    [ -z "${AWG_START_SH:-}" ] && return
    docker exec "$CONTAINER" sh -c "[ -f /opt/amnezia/start.sh.final-backup ] || cp '$AWG_START_SH' /opt/amnezia/start.sh.final-backup" 2>/dev/null

    local warp_block=""
    warp_block+="${AWG_MARKER_BEGIN}"$'\n'
    warp_block+="if [ -f '${AWG_WARP_CONF}' ]; then wg-quick up '${AWG_WARP_CONF}' || true; sleep 3; fi"$'\n'

    if [ ${#AWG_SELECTED_IPS[@]} -gt 0 ]; then
        warp_block+="ip route add default dev warp table 100 2>/dev/null || true"$'\n'
        local prio=100
        for ip in "${AWG_SELECTED_IPS[@]}"; do
            warp_block+="ip rule add from ${ip} table 100 priority ${prio} 2>/dev/null || true"$'\n'
            warp_block+="iptables -t nat -I POSTROUTING 1 -s ${ip} -o warp -j MASQUERADE 2>/dev/null || true"$'\n'
            ((prio++))
        done
    fi
    warp_block+="${AWG_MARKER_END}"

    # Inject payload securely
    cat <<WARPBLOCK | docker exec -i "$CONTAINER" sh -c "cat > /tmp/warp_payload"
${warp_block}
WARPBLOCK

    docker exec "$CONTAINER" sh -c "
        sed -i '/# --- WARP-MANAGER BEGIN ---/,/# --- WARP-MANAGER END ---/d' '$AWG_START_SH' 2>/dev/null
        if grep -qF 'tail -f /dev/null' '$AWG_START_SH'; then
            tmpfile=\$(mktemp)
            while IFS= read -r line; do
                if echo \"\$line\" | grep -qF 'tail -f /dev/null'; then cat /tmp/warp_payload; fi
                echo \"\$line\"
            done < '$AWG_START_SH' > \"\$tmpfile\"
            mv \"\$tmpfile\" '$AWG_START_SH'
        else
            cat /tmp/warp_payload >> '$AWG_START_SH'
        fi
        chmod 700 '$AWG_START_SH'
        rm -f /tmp/warp_payload
    " 2>/dev/null
}

awg_load_clients() {
    AWG_SELECTED_IPS=()
    local raw; raw=$(docker exec "$CONTAINER" sh -c "cat '$AWG_WARP_CLIENTS' 2>/dev/null || true" | tr -d '\r')
    if [ -n "$raw" ]; then
        while IFS= read -r line; do
            line=$(echo "$line" | xargs)
            # REGEX VALIDATION to prevent injections
            if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
                AWG_SELECTED_IPS+=("$line")
            fi
        done <<< "$raw"
    fi
}

awg_save_clients() {
    local content=""
    for ip in "${AWG_SELECTED_IPS[@]}"; do content="${content}${ip}"$'\n'; done
    cat <<CLEOF | docker exec -i "$CONTAINER" sh -c "mkdir -p '$AWG_WARP_DIR' && cat > '$AWG_WARP_CLIENTS'"
${content}
CLEOF
}

awg_get_client_ips() {
    AWG_CLIENT_IPS=()
    mapfile -t AWG_CLIENT_IPS < <(docker exec "$CONTAINER" sh -c "sed -n 's/^AllowedIPs[[:space:]]*=[[:space:]]*\(.*\/32\)[[:space:]]*$/\1/p' '$AWG_VPN_CONF'" 2>/dev/null | tr -d '\r')
}

uninstall_awg() {
    awg_cleanup_rules
    docker exec "$CONTAINER" sh -c "wg-quick down '$AWG_WARP_CONF' 2>/dev/null || true; rm -rf '$AWG_WARP_DIR'" >/dev/null 2>&1
    docker exec "$CONTAINER" sh -c "sed -i '/# --- WARP-MANAGER BEGIN ---/,/# --- WARP-MANAGER END ---/d' '$AWG_START_SH'" 2>/dev/null
    rm -f "$WGCF_BIN" "$WGCF_ACCOUNT" "$WGCF_PROFILE"
}

# ═══════════════════════════════════════════════════════════════
#  TELEGRAM BOT
# ═══════════════════════════════════════════════════════════════

tg_api() {
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/$1" -H "Content-Type: application/json" -d "$2" 2>/dev/null
}

tg_send() {
    local chat_id="$1" text="$2"
    local payload=$(jq -n --arg c "$chat_id" --arg t "$text" '{chat_id:$c, text:$t, parse_mode:"HTML"}')
    tg_api "sendMessage" "$payload"
}

tg_edit() {
    local chat_id="$1" msg_id="$2" text="$3" keyboard="${4:-}"
    local payload
    if [ -n "$keyboard" ]; then
        payload=$(jq -n --arg c "$chat_id" --argjson m "$msg_id" --arg t "$text" --argjson k "$keyboard" '{chat_id:$c, message_id:$m, text:$t, parse_mode:"HTML", reply_markup:{inline_keyboard:$k}}')
    else
        payload=$(jq -n --arg c "$chat_id" --argjson m "$msg_id" --arg t "$text" '{chat_id:$c, message_id:$m, text:$t, parse_mode:"HTML"}')
    fi
    tg_api "editMessageText" "$payload"
}

bot_handle_callback() {
    local chat_id="$1" msg_id="$2" cb_id="$3" data="$4"
    
    # HARD AUTHENTICATION CHECK
    if [ -n "$BOT_CHAT_ID" ] && [ "$chat_id" != "$BOT_CHAT_ID" ]; then
        log_action "SECURITY: Unauthorized callback from Chat ID $chat_id"
        return
    fi
    
    tg_api "answerCallbackQuery" "{\"callback_query_id\":\"$cb_id\",\"text\":\"\"}" >/dev/null

    case "$data" in
        st)
            local t="📊 <b>Статус WARP</b>\n\nСервер: <code>${MY_IP:-N/A}</code>"
            if has_awg_mode; then
                awg_load_clients
                t+="\nAWG Контейнер: <code>$(escape_html "${CONTAINER:-N/A}")</code>"
                t+="\nКлиентов в WARP: <b>${#AWG_SELECTED_IPS[@]}</b>"
            fi
            tg_edit "$chat_id" "$msg_id" "$t" '[[{"text":"⬅️ Меню","callback_data":"m"}]]' ;;
        m)  
            local ws="Active"
            tg_edit "$chat_id" "$msg_id" "<b>WARP Manager</b>\nСтатус: ${ws}\n\nВыберите действие:" '[[{"text":"📊 Статус","callback_data":"st"}]]' ;;
    esac
}

bot_daemon() {
    log_action "Bot daemon started (PID $$)"; echo $$ > "$BOT_PID_FILE"
    source "$WARP_CONF"
    
    # SECURITY: Abort if no strict admin Chat ID is set
    [ -z "$BOT_TOKEN" ] && { log_action "BOT ERROR: no token"; exit 1; }
    [ -z "$BOT_CHAT_ID" ] && { log_action "BOT ERROR: BOT_CHAT_ID is missing. Disabling bot for security."; exit 1; }
    
    get_my_ip
    if has_awg_mode && [ -n "$CONTAINER" ]; then awg_load_container_data 2>/dev/null; fi
    local offset=0
    
    while true; do
        local response
        response=$(curl -s --max-time 35 "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${offset}&timeout=30" 2>/dev/null)
        [ -z "$response" ] && sleep 2 && continue
        local ok; ok=$(echo "$response" | jq -r '.ok // "false"')
        [ "$ok" != "true" ] && sleep 5 && continue
        
        local cnt; cnt=$(echo "$response" | jq '.result | length')
        for (( i=0; i<cnt; i++ )); do
            local upd; upd=$(echo "$response" | jq ".result[$i]")
            local uid; uid=$(echo "$upd" | jq -r '.update_id')
            offset=$((uid + 1))
            
            local cbd; cbd=$(echo "$upd" | jq -r '.callback_query.data // empty')
            if [ -n "$cbd" ]; then
                local cbi cci cmi
                cbi=$(echo "$upd" | jq -r '.callback_query.id')
                cci=$(echo "$upd" | jq -r '.callback_query.message.chat.id')
                cmi=$(echo "$upd" | jq -r '.callback_query.message.message_id')
                bot_handle_callback "$cci" "$cmi" "$cbi" "$cbd"
            else
                local mci mtx
                mci=$(echo "$upd" | jq -r '.message.chat.id // empty')
                mtx=$(echo "$upd" | jq -r '.message.text // empty')
                if [ -n "$mci" ] && [ -n "$mtx" ]; then
                    # STRICT AUTHORIZATION
                    if [ "$mci" != "$BOT_CHAT_ID" ]; then
                        log_action "SECURITY: Blocked message from unauthorized Chat ID $mci"
                        tg_send "$mci" "⛔ Доступ запрещен. Событие безопасности зафиксировано."
                        continue
                    fi
                    
                    if [[ "$mtx" == "/start" || "$mtx" == "/menu" ]]; then
                        tg_send "$mci" "<b>WARP Manager</b>\nДобро пожаловать, администратор."
                    fi
                fi
            fi
        done
    done
}

start_bot() {
    source "$WARP_CONF"
    [ -z "$BOT_TOKEN" ] && { echo -e "${RED}Задайте BOT_TOKEN!${NC}"; return; }
    [ -z "$BOT_CHAT_ID" ] && { echo -e "${RED}Задайте BOT_CHAT_ID для безопасности!${NC}"; return; }
    
    # HARDENED SYSTEMD UNIT
    cat > /etc/systemd/system/warp-bot.service <<EOF
[Unit]
Description=WARP Manager Telegram Bot
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gowarp --bot-daemon
Restart=always
RestartSec=5
NoNewPrivileges=yes
RestrictSUIDSGID=yes
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable warp-bot > /dev/null 2>&1; systemctl start warp-bot; sleep 1
    echo -e "${GREEN}[OK] Бот запущен.${NC}"
}

stop_bot() {
    systemctl stop warp-bot 2>/dev/null; systemctl disable warp-bot 2>/dev/null; rm -f "$BOT_PID_FILE"
}

# ═══════════════════════════════════════════════════════════════
#  STARTUP & MENU
# ═══════════════════════════════════════════════════════════════

run_startup() {
    clear; echo -e "${MAGENTA}WARP Manager v${WARP_VERSION} — Загрузка${NC}\n"
    check_root
    check_deps
    
    # SAFE INSTALL (Local copy instead of remote curl execution)
    if [ "$(readlink -f "$0" 2>/dev/null)" != "/usr/local/bin/gowarp" ]; then
        cp -f "$0" "/usr/local/bin/gowarp" 2>/dev/null && chmod 700 "/usr/local/bin/gowarp"
    fi
    
    get_my_ip
    detect_mode
    if has_awg_mode; then awg_pick_container 2>/dev/null; awg_load_container_data 2>/dev/null; fi
    
    show_menu
}

show_menu() {
    while true; do
        clear
        echo -e "${MAGENTA}WARP Manager v${WARP_VERSION}${NC}\n"
        echo -e "  1) Установить WARP (AWG)"
        echo -e "  2) Запустить / Остановить бота"
        echo -e "  0) Выход"
        read -p "Выбор: " ch
        case $ch in
            1) install_warp_awg ;;
            2) start_bot ;;
            0) exit 0 ;;
        esac
    done
}

has_3xui_mode() { [[ "$MODE" == "3xui" || "$MODE" == "both" ]]; }
has_awg_mode()  { [[ "$MODE" == "amnezia" || "$MODE" == "both" ]]; }

case "${1:-}" in
    --bot-daemon) init_config; bot_daemon ;;
    *) init_config; run_startup ;;
esac