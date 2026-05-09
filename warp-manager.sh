#!/bin/bash
set -o pipefail
set -u

# ══════════════════════════════════════════════════════════════
#  WARP Manager v1.1 — Hardened Version
# ══════════════════════════════════════════════════════════════

WARP_VERSION="1.1"
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
NC='\033[0m'

SOCKS_PORT=""
MY_IP=""
BOT_TOKEN=""
BOT_CHAT_ID=""
MODE=""

CONTAINER=""
AWG_VPN_CONF=""
AWG_SUBNET=""
AWG_WARP_EXIT_IP=""
declare -a AWG_SELECTED_IPS=()
declare -a AWG_CLIENT_IPS=()
declare -A AWG_CLIENT_NAMES=()

# ====================== SECURITY ======================
log_action() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$WARP_LOG" 2>/dev/null || true; }

check_root() {
    [ "$EUID" -ne 0 ] && { echo -e "${RED}[ERROR] Запустите от root!${NC}"; exit 1; }
}

is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/32)?$ ]] || return 1
    ip="${ip%/32}"
    IFS='.' read -r a b c d <<< "$ip"
    for octet in "$a" "$b" "$c" "$d"; do
        ((octet >= 0 && octet <= 255)) || return 1
    done
    return 0
}

sanitize_ip() {
    local ip="${1%/32}"
    is_valid_ipv4 "$ip" && echo "$ip" || echo "0.0.0.0"
}

# ====================== CONFIG ======================
init_config() {
    mkdir -p "$WARP_DIR"
    [ ! -f "$WARP_CONF" ] && cat > "$WARP_CONF" <<'CONF'
SOCKS_PORT="40000"
BOT_TOKEN=""
BOT_CHAT_ID=""
MODE=""
CONTAINER=""
CONF
    source "$WARP_CONF"
    SOCKS_PORT="${SOCKS_PORT:-$DEFAULT_PORT}"
}

save_config_val() {
    local key="$1" value="$2"
    value="${value//\"/\\\"}"
    if grep -q "^${key}=" "$WARP_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$WARP_CONF"
    else
        echo "${key}=\"${value}\"" >> "$WARP_CONF"
    fi
    source "$WARP_CONF"
}

has_3xui_mode() { [[ "$MODE" == "3xui" || "$MODE" == "both" ]]; }
has_awg_mode()  { [[ "$MODE" == "amnezia" || "$MODE" == "both" ]]; }

# ====================== MODE DETECTION ======================
detect_mode() {
    source "$WARP_CONF" 2>/dev/null
    if [[ "$MODE" =~ ^(3xui|amnezia|both)$ ]]; then return 0; fi

    local has_docker=0 has_amnezia=0 has_3xui=0
    command -v docker &>/dev/null && has_docker=1

    if [ "$has_docker" -eq 1 ]; then
        local awg_ct=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^amnezia-awg' | head -1)
        [ -n "$awg_ct" ] && has_amnezia=1
    fi
    systemctl is-active x-ui &>/dev/null 2>&1 && has_3xui=1
    [ "$has_3xui" -eq 0 ] && command -v x-ui &>/dev/null && has_3xui=1

    if [ "$has_amnezia" -eq 1 ] && [ "$has_3xui" -eq 1 ]; then MODE="both"
    elif [ "$has_amnezia" -eq 1 ]; then MODE="amnezia"
    elif [ "$has_3xui" -eq 1 ]; then MODE="3xui"
    else
        echo -e "\n${YELLOW}Выберите режим:${NC}"
        echo "1) 3X-UI"
        echo "2) AmneziaWG"
        echo "3) Оба"
        read -p "Выбор: " ch
        case "$ch" in 1) MODE="3xui";; 2) MODE="amnezia";; 3) MODE="both";; *) MODE="3xui";; esac
    fi
    save_config_val "MODE" "$MODE"
}

# ====================== RUN STARTUP ======================
run_startup() {
    check_root
    init_config
    detect_mode
    get_my_ip

    echo -e "\n${GREEN}WARP Manager v${WARP_VERSION} запущен (${MODE})${NC}\n"
    # Здесь можно добавить вызов главного меню
    show_menu
}

get_my_ip() {
    MY_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || echo "N/A")
}

# ====================== MAIN MENU ======================
show_menu() {
    echo -e "\n${CYAN}Главное меню:${NC}"
    echo "1) Установить WARP"
    echo "0) Выход"
    read -p "Выбор: " ch
    case "$ch" in
        0) exit 0 ;;
        *) echo "Функция в разработке..." ;;
    esac
}

# ====================== ENTRY POINT ======================
case "${1:-}" in
    --bot-daemon)
        init_config
        echo "Bot daemon mode (заглушка)"
        ;;
    *)
        run_startup
        ;;
esac
