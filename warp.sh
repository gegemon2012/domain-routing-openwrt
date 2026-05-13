#!/bin/bash
set -euo pipefail

# ========= Цвета =========
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ========= Пути / глобальные =========
WARP_DIR="/etc/warp-manager"
WARP_CONF="$WARP_DIR/config"
WARP_LOG="/var/log/warp-manager.log"

WGCF_BIN="/root/wgcf"
WGCF_VERSION="latest"

AWG_WARP_DIR="/opt/warp"
AWG_WARP_CONF="$AWG_WARP_DIR/warp.conf"
AWG_MARKER_BEGIN="# --- WARP-MANAGER BEGIN ---"
AWG_MARKER_END="# --- WARP-MANAGER END ---"

CONTAINER=""

# ========= Общие функции =========
die() { echo -e "${RED}[ERROR]${NC} $*" >&2; echo "[$(date '+%F %T')] ERROR: $*" >>"$WARP_LOG"; exit 1; }
log() { echo "[$(date '+%F %T')] $*" >>"$WARP_LOG"; }

check_root() { [[ $EUID -ne 0 ]] && die "Запустите от root"; }

check_deps() {
    local need=(curl jq sha256sum docker gpg)
    local miss=()
    for c in "${need[@]}"; do
        command -v "$c" &>/dev/null || miss+=("$c")
    done
    if ((${#miss[@]} > 0)); then
        echo -e "${CYAN}Установка зависимостей: ${miss[*]}${NC}"
        apt-get update -y
        apt-get install -y "${miss[@]}"
    fi
}

validate_name() {
    [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]] || die "Недопустимое имя: $1"
}

safe_path() {
    local f="$1" dir="$2"
    local abs
    abs=$(readlink -f "$f" 2>/dev/null || true)
    [[ -n "$abs" && "$abs" == "$dir"* ]] || die "Небезопасный путь: $f"
}

read_port() {
    local prompt="$1" var
    while true; do
        read -r -p "$prompt" var
        [[ "$var" =~ ^[0-9]+$ ]] || { echo -e "${RED}Только числа.${NC}"; continue; }
        (( var >= 1024 && var <= 65535 )) || { echo -e "${RED}Диапазон 1024–65535.${NC}"; continue; }
        echo "$var"; return 0
    done
}

get_system_stats() {
    local cores load mem disk up
    cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
    load=$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null)
    mem=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "%d/%dMB (%.1f%%)", $3, $2, $3/$2*100}')
    disk=$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s/%s (%s)", $3, $2, $5}')
    up=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /; s/,.*load.*//')

    echo -e "${CYAN}Системная информация${NC}\n"
    echo -e "  Uptime:   ${GREEN}${up}${NC}"
    echo -e "  CPU:      ${GREEN}${cores} cores${NC}"
    echo -e "  Load:     ${GREEN}${load}${NC}"
    echo -e "  RAM:      ${GREEN}${mem}${NC}"
    echo -e "  Disk /:   ${GREEN}${disk}${NC}"
}

# ========= Конфиг =========
init_dirs() {
    mkdir -p "$WARP_DIR"
    chmod 700 "$WARP_DIR"
    touch "$WARP_LOG"
    chmod 600 "$WARP_LOG"
}

init_config() {
    init_dirs
    if [[ ! -f "$WARP_CONF" ]]; then
        umask 077
        cat >"$WARP_CONF" <<EOF
SOCKS_PORT="40000"
MODE=""
CONTAINER=""
EOF
        chmod 600 "$WARP_CONF"
    fi
    # shellcheck disable=SC1090
    source "$WARP_CONF"
    SOCKS_PORT="${SOCKS_PORT:-40000}"
    CONTAINER="${CONTAINER:-}"
}

save_cfg() {
    local key="$1" val="$2"
    validate_name "$key"
    safe_path "$WARP_CONF" "$WARP_DIR"
    local esc; esc=$(printf '%q' "$val")
    if grep -q "^${key}=" "$WARP_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${esc}|" "$WARP_CONF"
    else
        echo "${key}=${esc}" >>"$WARP_CONF"
    fi
}

# ========= Docker / AmneziaWG =========
dexec() {
    docker exec "$CONTAINER" sh -c "$*" 2>/dev/null || die "docker exec error: $*"
}

pick_container() {
    if [[ -n "$CONTAINER" ]]; then
        validate_name "$CONTAINER"
        docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || CONTAINER=""
    fi
    if [[ -z "$CONTAINER" ]]; then
        mapfile -t arr < <(docker ps --format '{{.Names}}' | grep -i amnezia || true)
        ((${#arr[@]} == 0)) && die "Контейнеры Amnezia не найдены"
        if ((${#arr[@]} == 1)); then
            CONTAINER="${arr[0]}"
        else
            echo -e "${CYAN}Доступные контейнеры Amnezia:${NC}"
            local i=1
            for c in "${arr[@]}"; do echo "  $i) $c"; ((i++)); done
            while true; do
                read -r -p "Выберите контейнер: " ch
                [[ "$ch" =~ ^[0-9]+$ ]] || continue
                (( ch>=1 && ch<=${#arr[@]} )) || continue
                CONTAINER="${arr[ch-1]}"
                break
            done
        fi
        save_cfg "CONTAINER" "$CONTAINER"
    fi
    validate_name "$CONTAINER"
    dexec "[ -d /opt/amnezia/awg ]" || die "В контейнере $CONTAINER нет /opt/amnezia/awg (это не AmneziaWG)"
}

# ========= wgcf: получение последней версии =========
wgcf_fetch_latest() {
    echo -e "${CYAN}Получение последней версии wgcf с GitHub...${NC}"
    local api="https://api.github.com/repos/ViRb3/wgcf/releases/latest"
    local json
    json=$(curl --fail --tlsv1.2 --proto '=https' -s "$api") || die "GitHub API недоступен"

    local tag asset_bin asset_sha
    tag=$(echo "$json" | jq -r '.tag_name') || die "Не удалось получить tag_name"
    asset_bin=$(echo "$json" | jq -r '.assets[].browser_download_url | select(contains(\"linux_amd64\"))')
    asset_sha=$(echo "$json" | jq -r '.assets[].browser_download_url | select(endswith(\"sha256\"))')

    [[ -z "$asset_bin" ]] && die "Не найден бинарник wgcf"
    [[ -z "$asset_sha" ]] && die "Не найден файл sha256"

    echo -e "${CYAN}Скачивание SHA256...${NC}"
    curl --fail --tlsv1.2 --proto '=https' -s "$asset_sha" -o /root/wgcf.sha256 || die "Ошибка скачивания sha256"
    local expected
    expected=$(awk '{print $1}' /root/wgcf.sha256)

    echo -e "${CYAN}Скачивание wgcf ${tag}...${NC}"
    curl --fail --tlsv1.2 --proto '=https' -L "$asset_bin" -o /root/wgcf.tmp || die "Ошибка скачивания wgcf"

    echo -e "${CYAN}Проверка SHA256...${NC}"
    local got
    got=$(sha256sum /root/wgcf.tmp | awk '{print $1}')
    [[ "$got" == "$expected" ]] || die "Хеш wgcf не совпадает!"

    mv /root/wgcf.tmp "$WGCF_BIN"
    chmod 700 "$WGCF_BIN"
    echo -e "${GREEN}wgcf обновлён до версии ${tag}.${NC}"
    log "wgcf updated to $tag"
}

install_wgcf() {
    [[ -x "$WGCF_BIN" ]] && return
    wgcf_fetch_latest
}

generate_wgcf_profile() {
    echo -e "${CYAN}Регистрация WARP через wgcf...${NC}"
    (cd /root && yes | "$WGCF_BIN" register) || true
    echo -e "${CYAN}Генерация профиля wgcf...${NC}"
    (cd /root && yes | "$WGCF_BIN" generate)
    [[ -f /root/wgcf-profile.conf ]] || die "wgcf-profile.conf не создан"
}

# ========= WARP для 3X-UI (warp-cli, SOCKS) =========
is_warp_installed_3xui() { command -v warp-cli &>/dev/null; }

get_warp_ip_3xui() {
    init_config
    curl --fail --tlsv1.2 --proto '=https' -s4 --max-time 5 \
        --proxy "socks5h://127.0.0.1:${SOCKS_PORT}" ifconfig.me 2>/dev/null || echo "N/A"
}

show_status_3xui() {
    init_config
    echo -e "${CYAN}Статус WARP (3X‑UI / SOCKS)${NC}\n"
    if ! is_warp_installed_3xui; then
        echo -e "  ${YELLOW}cloudflare-warp не установлен.${NC}"
        return
    fi
    local st
    st=$(warp-cli --accept-tos status 2>/dev/null || true)
    echo -e "${GREEN}${st}${NC}\n"
    echo -e "  SOCKS:  ${GREEN}127.0.0.1:${SOCKS_PORT}${NC}"
    echo -e "  WARP IP через SOCKS: ${GREEN}$(get_warp_ip_3xui)${NC}"
}

install_warp_3xui() {
    check_root; check_deps; init_config
    if ! is_warp_installed_3xui; then
        echo -e "${CYAN}Установка cloudflare-warp...${NC}"
        curl --fail --tlsv1.2 --proto '=https' https://pkg.cloudflareclient.com/pubkey.gpg \
            | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp.gpg
        local codename; codename=$( . /etc/os-release; echo "$VERSION_CODENAME" )
        echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ ${codename} main" \
            > /etc/apt/sources.list.d/cloudflare-warp.list
        apt-get update -y
        apt-get install -y cloudflare-warp
    fi

    echo -e "${CYAN}Настройка SOCKS‑прокси WARP...${NC}"
    warp-cli --accept-tos registration new || true
    warp-cli --accept-tos mode proxy
    warp-cli --accept-tos proxy port "$SOCKS_PORT"
    warp-cli --accept-tos connect

    echo -e "${GREEN}WARP для 3X‑UI настроен. SOCKS: 127.0.0.1:${SOCKS_PORT}${NC}"
    log "3XUI WARP installed, port=$SOCKS_PORT"
}

uninstall_warp_3xui() {
    check_root
    if ! is_warp_installed_3xui; then
        echo -e "${YELLOW}cloudflare-warp не установлен.${NC}"
        return
    fi
    warp-cli --accept-tos disconnect || true
    warp-cli --accept-tos registration delete || true
    rm -f /var/lib/cloudflare-warp/reg.json 2>/dev/null || true
    echo -e "${GREEN}Конфигурация WARP для 3X‑UI удалена (пакет оставлен).${NC}"
    log "3XUI WARP config removed"
}

show_3xui_json() {
    init_config
    echo -e "${CYAN}JSON Outbound для 3X‑UI (SOCKS через WARP)${NC}\n"
    cat <<EOF
{
  "tag": "warp",
  "protocol": "socks",
  "settings": {
    "servers": [
      {
        "address": "127.0.0.1",
        "port": ${SOCKS_PORT}
      }
    ]
  }
}
EOF

    echo
    echo -e "${CYAN}Пример routing rule (только отдельные домены через WARP)${NC}\n"
    cat <<EOF
{
  "outboundTag": "warp",
  "domain": [
    "geosite:openai",
    "geosite:netflix",
    "geosite:disney",
    "geosite:spotify",
    "domain:chat.openai.com",
    "domain:claude.ai"
  ]
}
EOF
    echo
}

show_3xui_guide() {
    init_config
    echo -e "${CYAN}Пошаговая настройка 3X‑UI с WARP (SOCKS)${NC}\n"
    echo -e "1. В панели 3X‑UI открой: Настройки Xray → Outbounds"
    echo -e "2. Добавь outbound:"
    echo -e "   - tag: warp"
    echo -e "   - protocol: socks"
    echo -e "   - address: 127.0.0.1"
    echo -e "   - port: ${SOCKS_PORT}"
    echo
    echo -e "3. В Routing Rules добавь правило с outboundTag: warp и доменами (см. JSON выше)."
    echo -е "4. Перезапусти Xray."
    echo
}

# ========= WARP внутри AmneziaWG =========
install_warp_awg() {
    check_root; check_deps; init_config; pick_container; install_wgcf; generate_wgcf_profile

    echo -e "${CYAN}Копирование профиля в контейнер...${NC}"
    dexec "mkdir -p '$AWG_WARP_DIR'"
    docker cp /root/wgcf-profile.conf "$CONTAINER:$AWG_WARP_CONF"
    dexec "chmod 600 '$AWG_WARP_CONF'"

    echo -e "${CYAN}Поднятие интерфейса warp внутри контейнера...${NC}"
    dexec "wg-quick down '$AWG_WARP_CONF' >/dev/null 2>&1 || true"
    dexec "wg-quick up '$AWG_WARP_CONF'"

    echo -e "${GREEN}WARP внутри AmneziaWG поднят (интерфейс warp).${NC}"
    log "AWG WARP installed in container $CONTAINER"
}

uninstall_warp_awg() {
    check_root; check_deps; init_config; pick_container
    echo -e "${CYAN}Отключение и удаление WARP из AmneziaWG...${NC}"
    dexec "wg-quick down '$AWG_WARP_CONF' >/dev/null 2>&1 || true"
    dexec "rm -f '$AWG_WARP_CONF'"
    dexec "sed -i '/$AWG_MARKER_BEGIN/,/$AWG_MARKER_END/d' /opt/amnezia/start.sh || true"
    echo -e "${GREEN}WARP для AmneziaWG удалён.${NC}"
    log "AWG WARP removed from container $CONTAINER"
}

awg_status() {
    check_root; check_deps; init_config; pick_container
    echo -e "${CYAN}Статус WARP внутри AmneziaWG${NC}\n"
    if ! dexec "ip addr show warp >/dev/null 2>&1"; then
        echo -e "  ${YELLOW}Интерфейс warp не найден.${NC}"
        return
    fi
    dexec "ip addr show warp" | sed 's/^/  /'
    echo
    echo -e "  ${CYAN}wg show для warp:${NC}"
    dexec "wg show" | sed 's/^/  /'
    echo
}

awg_show_clients() {
    check_root; check_deps; init_config; pick_container
    local table="/opt/amnezia/awg/clientsTable"
    echo -e "${CYAN}Клиенты AmneziaWG (из ${table})${NC}\n"
    if ! dexec "[ -f '$table' ]"; then
        echo "  clientsTable не найден"
        return
    fi
    dexec "cat '$table'" | sed 's/^/  /'
    echo
}

wgcf_update_and_reload_awg() {
    check_root; check_deps; init_config; pick_container
    wgcf_fetch_latest
    generate_wgcf_profile
    docker cp /root/wgcf-profile.conf "$CONTAINER:$AWG_WARP_CONF"
    dexec "chmod 600 '$AWG_WARP_CONF'"
    dexec "wg-quick down '$AWG_WARP_CONF' >/dev/null 2>&1 || true"
    dexec "wg-quick up '$AWG_WARP_CONF'"
    echo -e "${GREEN}wgcf обновлён и warp перезапущен.${NC}"
    log "AWG WARP wgcf updated and warp restarted in container $CONTAINER"
}

# ========= Генерация systemd-юнитов =========
create_systemd_units() {
    check_root; init_config

    echo -e "${CYAN}Создание systemd-юнитов...${NC}"

    cat >/etc/systemd/system/warp-3xui.service <<EOF
[Unit]
Description=Cloudflare WARP SOCKS proxy for 3X-UI
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/warp-cli --accept-tos mode proxy
ExecStart=/usr/bin/warp-cli --accept-tos proxy port $(. "$WARP_CONF"; echo "\${SOCKS_PORT:-40000}")
ExecStart=/usr/bin/warp-cli --accept-tos connect
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    cat >/etc/systemd/system/warp-awg.service <<EOF
[Unit]
Description=WARP (warp interface) inside AmneziaWG container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/warp-manager.sh --wgcf-update-awg
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    cat >/etc/systemd/system/warp-wgcf-update.service <<EOF
[Unit]
Description=Update wgcf profile and restart warp inside AmneziaWG

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/warp-manager.sh --wgcf-update-awg
EOF

    cat >/etc/systemd/system/warp-wgcf-update.timer <<EOF
[Unit]
Description=Daily wgcf update for WARP in AmneziaWG

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    echo -e "${GREEN}systemd-юниты созданы. Включи их при необходимости:${NC}"
    echo "  systemctl enable --now warp-3xui.service"
    echo "  systemctl enable --now warp-awg.service"
    echo "  systemctl enable --now warp-wgcf-update.timer"
}

# ========= Подменю =========
menu_3xui() {
    check_root; check_deps; init_config
    while true; do
        clear
        echo -e "${CYAN}3X‑UI / WARP (SOCKS)${NC}\n"
        echo "1) Установить/настроить WARP"
        echo "2) Показать JSON Outbound / Routing"
        echo "3) Показать инструкцию по настройке"
        echo "4) Показать статус WARP"
        echo "5) Удалить WARP (конфиг)"
        echo "0) Назад"
        read -r -p "Выбор: " ch
        case "$ch" in
            1) install_warp_3xui; read -r -p "Enter...";;
            2) show_3xui_json; read -r -p "Enter...";;
            3) show_3xui_guide; read -r -p "Enter...";;
            4) show_status_3xui; read -r -p "Enter...";;
            5) uninstall_warp_3xui; read -r -p "Enter...";;
            0) break;;
        esac
    done
}

menu_awg() {
    check_root; check_deps; init_config
    while true; do
        clear
        echo -e "${CYAN}AmneziaWG / WARP внутри контейнера${NC}\n"
        echo "1) Установить/настроить WARP (warp-интерфейс)"
        echo "2) Обновить wgcf + перезапустить warp"
        echo "3) Показать список клиентов AmneziaWG"
        echo "4) Показать статус WARP (интерфейс warp)"
        echo "5) Удалить WARP (из контейнера)"
        echo "0) Назад"
        read -r -p "Выбор: " ch
        case "$ch" in
            1) install_warp_awg; read -r -p "Enter...";;
            2) wgcf_update_and_reload_awg; read -r -p "Enter...";;
            3) awg_show_clients; read -r -p "Enter...";;
            4) awg_status; read -r -p "Enter...";;
            5) uninstall_warp_awg; read -r -p "Enter...";;
            0) break;;
        esac
    done
}

# ========= Главное меню =========
menu() {
    check_root; check_deps; init_config
    while true; do
        clear
        echo -e "${CYAN}WARP Manager (3X‑UI + AmneziaWG)${NC}\n"
        echo "1) 3X‑UI / WARP (SOCKS‑прокси)"
        echo "2) AmneziaWG / WARP внутри контейнера"
        echo "3) Показать системную информацию"
        echo "4) Создать systemd-юниты (3X‑UI, AmneziaWG, wgcf-update)"
        echo "0) Выход"
        echo
        read -r -p "Выбор: " ch
        case "$ch" in
            1) menu_3xui ;;
            2) menu_awg ;;
            3) get_system_stats; read -r -p "Enter...";;
            4) create_systemd_units; read -r -p "Enter...";;
            0) exit 0;;
        esac
    done
}

# ========= Точка входа =========
case "${1:-}" in
    --wgcf-update-awg) wgcf_update_and_reload_awg ;;
    *) menu ;;
esac
