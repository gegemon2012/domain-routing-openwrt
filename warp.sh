#!/bin/bash
set -euo pipefail

# ==========================
#  Глобальные настройки
# ==========================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

WARP_DIR="/etc/warp-manager"
WARP_CONF="$WARP_DIR/config"
WARP_LOG="/var/log/warp-manager.log"

WGCF_BIN="/root/wgcf"
WGCF_VERSION="2.2.30"
# ВАЖНО: сюда подставить реальный sha256 для нужного релиза wgcf
WGCF_SHA="sha256:fc443008fe29a6f0b05b45d27436b7ce89e87a6836718597ccb39e41da418304"

AWG_WARP_DIR="/opt/warp"
AWG_WARP_CONF="$AWG_WARP_DIR/warp.conf"
AWG_MARKER_BEGIN="# --- WARP-MANAGER BEGIN ---"
AWG_MARKER_END="# --- WARP-MANAGER END ---"

# ==========================
#  Общие функции безопасности
# ==========================
die() { echo -e "${RED}[ERROR]${NC} $*" >&2; echo "[$(date '+%F %T')] ERROR: $*" >>"$WARP_LOG"; exit 1; }
log() { echo "[$(date '+%F %T')] $*" >>"$WARP_LOG"; }

check_root() { [[ $EUID -ne 0 ]] && die "Запустите от root"; }

validate_name() {
    [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]] || die "Недопустимое имя: $1"
}

safe_path() {
    local f="$1" dir="$2"
    local abs
    abs=$(readlink -f "$f" 2>/dev/null || true)
    [[ -n "$abs" && "$abs" == "$dir"* ]] || die "Небезопасный путь: $f"
}

download_sha() {
    local url="$1" out="$2" sha="$3"
    curl --fail --tlsv1.2 --proto '=https' -L "$url" -o "$out.tmp" || die "Скачивание $url"
    local got
    got=$(sha256sum "$out.tmp" | awk '{print $1}')
    [[ "$got" == "$sha" ]] || { rm -f "$out.tmp"; die "Хеш не совпадает для $url"; }
    mv "$out.tmp" "$out"
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

# ==========================
#  Конфиг
# ==========================
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

# ==========================
#  Docker / AmneziaWG
# ==========================
CONTAINER="${CONTAINER:-}"

dexec() {
    docker exec "$CONTAINER" sh -c "$*" 2>/dev/null || die "docker exec error: $*"
}

pick_container() {
    if [[ -n "${CONTAINER:-}" ]]; then
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

# ==========================
#  WARP для 3X-UI (warp-cli, SOCKS)
# ==========================
is_warp_installed_3xui() { command -v warp-cli &>/dev/null; }

install_warp_3xui() {
    check_root; init_config
    if is_warp_installed_3xui; then
        echo -e "${YELLOW}cloudflare-warp уже установлен.${NC}"
    else
        echo -e "${CYAN}Установка cloudflare-warp...${NC}"
        curl --fail --tlsv1.2 --proto '=https' https://pkg.cloudflareclient.com/pubkey.gpg \
            | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp.gpg
        echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ $(. /etc/os-release; echo "$VERSION_CODENAME") main" \
            > /etc/apt/sources.list.d/cloudflare-warp.list
        apt-get update -y
        apt-get install -y cloudflare-warp
    fi

    echo -e "${CYAN}Регистрация и настройка SOCKS‑прокси...${NC}"
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

# ==========================
#  wgcf + WARP внутри AmneziaWG
# ==========================
install_wgcf() {
    [[ -x "$WGCF_BIN" ]] && return
    [[ "$WGCF_SHA" == "PUT_REAL_SHA256_HERE" ]] && die "Укажи реальный WGCF_SHA в скрипте"
    echo -e "${CYAN}Скачивание wgcf...${NC}"
    local arch; arch=$(uname -m)
    local wa
    case "$arch" in
        x86_64) wa="amd64" ;;
        aarch64) wa="arm64" ;;
        armv7l) wa="armv7" ;;
        *) die "Архитектура не поддерживается: $arch" ;;
    esac
    local url="https://github.com/ViRb3/wgcf/releases/download/v${WGCF_VERSION}/wgcf_${WGCF_VERSION}_linux_${wa}"
    download_sha "$url" "$WGCF_BIN" "$WGCF_SHA"
    chmod 700 "$WGCF_BIN"
}

generate_wgcf_profile() {
    echo -e "${CYAN}Регистрация WARP через wgcf...${NC}"
    (cd /root && yes | "$WGCF_BIN" register) || true
    echo -e "${CYAN}Генерация профиля wgcf...${NC}"
    (cd /root && yes | "$WGCF_BIN" generate)
    [[ -f /root/wgcf-profile.conf ]] || die "wgcf-profile.conf не создан"
}

install_warp_awg() {
    check_root; init_config; pick_container; install_wgcf; generate_wgcf_profile

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
    check_root; init_config; pick_container
    echo -e "${CYAN}Отключение и удаление WARP из AmneziaWG...${NC}"
    dexec "wg-quick down '$AWG_WARP_CONF' >/dev/null 2>&1 || true"
    dexec "rm -f '$AWG_WARP_CONF'"
    dexec "sed -i '/$AWG_MARKER_BEGIN/,/$AWG_MARKER_END/d' /opt/amnezia/start.sh || true"
    echo -e "${GREEN}WARP для AmneziaWG удалён.${NC}"
    log "AWG WARP removed from container $CONTAINER"
}

# ==========================
#  Авто‑обновление wgcf + перезапуск warp (AmneziaWG)
#  (используется systemd‑юнитом warp-wgcf-update.service)
# ==========================
wgcf_update_and_reload_awg() {
    check_root; init_config; pick_container; install_wgcf

    echo -e "${CYAN}Обновление профиля wgcf и перезапуск warp...${NC}"
    generate_wgcf_profile
    docker cp /root/wgcf-profile.conf "$CONTAINER:$AWG_WARP_CONF"
    dexec "chmod 600 '$AWG_WARP_CONF'"
    dexec "wg-quick down '$AWG_WARP_CONF' >/dev/null 2>&1 || true"
    dexec "wg-quick up '$AWG_WARP_CONF'"
    echo -e "${GREEN}wgcf обновлён, warp перезапущен.${NC}"
    log "AWG WARP wgcf updated and warp restarted in container $CONTAINER"
}

# ==========================
#  Меню
# ==========================
menu() {
    check_root; init_config
    while true; do
        clear
        echo -e "${CYAN}WARP Manager (3X‑UI + AmneziaWG)${NC}\n"
        echo "1) Установить/настроить WARP для 3X‑UI (SOCKS)"
        echo "2) Установить/настроить WARP внутри AmneziaWG (warp-интерфейс)"
        echo "3) Удалить WARP (только 3X‑UI)"
        echo "4) Удалить WARP (только AmneziaWG)"
        echo "5) Обновить wgcf + перезапустить warp (AmneziaWG)"
        echo "0) Выход"
        echo
        read -r -p "Выбор: " ch
        case "$ch" in
            1) install_warp_3xui; read -r -p "Enter...";;
            2) install_warp_awg; read -r -p "Enter...";;
            3) uninstall_warp_3xui; read -r -p "Enter...";;
            4) uninstall_warp_awg; read -r -p "Enter...";;
            5) wgcf_update_and_reload_awg; read -r -p "Enter...";;
            0) exit 0;;
        esac
    done
}

# ==========================
#  Точка входа
# ==========================
if [[ "${1:-}" == "--wgcf-update-awg" ]]; then
    wgcf_update_and_reload_awg
else
    menu
fi
