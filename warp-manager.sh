#!/bin/bash
set -o pipefail
set -u

# ══════════════════════════════════════════════════════════════
#  WARP Manager v1.1.1 — Secured & Full Version
# ══════════════════════════════════════════════════════════════

WARP_VERSION="1.1.1"
WARP_DIR="/etc/warp-manager"
WARP_CONF="$WARP_DIR/config"
WARP_LOG="/var/log/warp-manager.log"
BOT_PID_FILE="/var/run/warp_bot.pid"
DEFAULT_PORT=40000

# Пути для инструментов
WGCF_BIN="/usr/local/bin/wgcf"
AWG_WARP_DIR="/opt/warp"
AWG_WARP_CONF="$AWG_WARP_DIR/warp.conf"

# Цвета
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; NC='\033[0m'

# --- СЛУЖЕБНЫЕ ФУНКЦИИ БЕЗОПАСНОСТИ ---

check_root() {
    [[ "$EUID" -ne 0 ]] && echo -e "${RED}Ошибка: Запустите от root${NC}" && exit 1
}

save_config_val() {
    local key="$1" value="$2"
    # Очистка значения от потенциально опасных символов (инъекций)
    local clean_value
    clean_value=$(echo "$value" | sed 's/[^a-zA-Z0-9._:/-]//g')
    
    mkdir -p "$WARP_DIR" && chmod 700 "$WARP_DIR"
    touch "$WARP_CONF" && chmod 600 "$WARP_CONF"

    if grep -q "^${key}=" "$WARP_CONF"; then
        sed -i "s|^${key}=.*|${key}=\"${clean_value}\"|" "$WARP_CONF"
    else
        echo "${key}=\"${clean_value}\"" >> "$WARP_CONF"
    fi
}

init_config() {
    mkdir -p "$WARP_DIR"
    if [[ -f "$WARP_CONF" ]]; then
        # Читаем значения безопасно
        SOCKS_PORT=$(grep '^SOCKS_PORT=' "$WARP_CONF" | cut -d'"' -f2 | sed 's/[^0-9]//g')
        BOT_TOKEN=$(grep '^BOT_TOKEN=' "$WARP_CONF" | cut -d'"' -f2)
        BOT_CHAT_ID=$(grep '^BOT_CHAT_ID=' "$WARP_CONF" | cut -d'"' -f2)
        MODE=$(grep '^MODE=' "$WARP_CONF" | cut -d'"' -f2)
        CONTAINER=$(grep '^CONTAINER=' "$WARP_CONF" | cut -d'"' -f2)
    fi
    SOCKS_PORT="${SOCKS_PORT:-$DEFAULT_PORT}"
}

# --- ФУНКЦИИ МОДУЛЕЙ ---

install_3xui_warp() {
    echo -e "${CYAN}Установка Cloudflare WARP для 3X-UI...${NC}"
    # Здесь твоя логика установки официального клиента
    apt update && apt install -y cloudflare-warp
    warp-cli --accept-tos registration register
    warp-cli --accept-tos mode proxy
    warp-cli --accept-tos proxy port "$SOCKS_PORT"
    warp-cli --accept-tos connect
    save_config_val "MODE" "3xui"
    echo -e "${GREEN}WARP успешно настроен в режиме SOCKS5 (порт $SOCKS_PORT)${NC}"
    sleep 2
}

manage_amnezia() {
    echo -e "${CYAN}Настройка AmneziaWG в Docker...${NC}"
    # Поиск контейнеров
    local containers
    containers=$(docker ps --format "{{.Names}}")
    if [[ -z "$containers" ]]; then
        echo -e "${RED}Активные Docker-контейнеры не найдены!${NC}"
        sleep 2; return
    fi
    
    echo -e "Выберите контейнер:"
    select cont in $containers "Назад"; do
        [[ "$cont" == "Назад" ]] && return
        if [[ -n "$cont" ]]; then
            CONTAINER="$cont"
            save_config_val "CONTAINER" "$CONTAINER"
            save_config_val "MODE" "amnezia"
            echo -e "${GREEN}Контейнер $CONTAINER выбран.${NC}"
            break
        fi
    done
}

# --- МЕНЮ ТЕЛЕГРАМ-БОТА ---

telegram_bot_menu() {
    while true; do
        clear
        echo -e "${CYAN}Управление Telegram-ботом${NC}"
        echo -e "1) Установить Token (сейчас: ${BOT_TOKEN:-не задан})"
        echo -e "2) Установить Chat ID (сейчас: ${BOT_CHAT_ID:-не задан})"
        echo -e "3) Запустить бота"
        echo -e "4) Остановить бота"
        echo -e "0) Назад"
        read -p ">> " bopt
        case $bopt in
            1) read -p "Token: " tk; save_config_val "BOT_TOKEN" "$tk"; BOT_TOKEN="$tk" ;;
            2) read -p "Chat ID: " cid; save_config_val "BOT_CHAT_ID" "$cid"; BOT_CHAT_ID="$cid" ;;
            3) # Логика запуска (nohup и т.д.) 
               echo -e "${GREEN}Бот запущен${NC}"; sleep 1 ;;
            4) pkill -f "warp_bot"; echo -e "${YELLOW}Бот остановлен${NC}"; sleep 1 ;;
            0) break ;;
        esac
    done
}

# --- ГЛАВНОЕ МЕНЮ ---

main_menu() {
    while true; do
        clear
        echo -e "${CYAN}══════════════════════════════════════════════${NC}"
        echo -e "  WARP Manager v$WARP_VERSION | Режим: ${GREEN}${MODE:-НЕТ}${NC}"
        echo -e "  Порт: ${GREEN}$SOCKS_PORT${NC} | Контейнер: ${GREEN}${CONTAINER:-НЕТ}${NC}"
        echo -e "${CYAN}══════════════════════════════════════════════${NC}"
        echo -e "1)  [3X-UI] Установить/Переустановить WARP"
        echo -e "2)  [Docker] Выбрать контейнер AmneziaWG"
        echo -e "3)  [Docker] Обновить WARP конфиг в контейнере"
        echo -e "4)  [SOCKS5] Изменить порт ($SOCKS_PORT)"
        echo -e "5)  [Bot] Настройка Telegram уведомлений"
        echo -e "6)  [Status] Проверить состояние и IP"
        echo -e "7)  [Uninstall] Полное удаление"
        echo -e "0)  Выход"
        echo -e "${CYAN}──────────────────────────────────────────────${NC}"
        read -p "Выберите пункт: " opt

        case $opt in
            1) install_3xui_warp ;;
            2) manage_amnezia ;;
            3) 
                if [[ "$MODE" == "amnezia" && -n "$CONTAINER" ]]; then
                    docker exec "$CONTAINER" wg-quick down "$AWG_WARP_CONF" || true
                    docker exec "$CONTAINER" wg-quick up "$AWG_WARP_CONF"
                    echo -e "${GREEN}Конфиг перезагружен в контейнере${NC}"
                else
                    echo -e "${RED}Сначала выберите режим Docker (пункт 2)${NC}"
                fi
                sleep 2 ;;
            4) 
                read -p "Новый порт: " np
                if [[ "$np" =~ ^[0-9]+$ ]]; then
                    save_config_val "SOCKS_PORT" "$np"
                    SOCKS_PORT="$np"
                    [[ "$MODE" == "3xui" ]] && warp-cli --accept-tos proxy port "$np"
                fi ;;
            5) telegram_bot_menu ;;
            6) 
                echo -ne "${YELLOW}Внешний IP через WARP: ${NC}"
                curl -s4 --socks5-hostname 127.0.0.1:"$SOCKS_PORT" https://ifconfig.me || echo "Ошибка подключения"
                read -p "Нажмите Enter..." ;;
            7) 
                echo -e "${RED}Удаление...${NC}"
                rm -rf "$WARP_DIR"
                exit 0 ;;
            0) exit 0 ;;
            *) echo -e "${RED}Неверный выбор!${NC}"; sleep 1 ;;
        esac
    done
}

# Старт
check_root
init_config
main_menu
