#!/bin/sh

# Простой скрипт настройки HTTPS для OpenWrt

# Цветной вывод
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }

CERT_FILE="/etc/uhttpd.crt"
KEY_FILE="/etc/uhttpd.key"

# Обновление и установка пакетов
yellow "Установка необходимых пакетов..."
opkg update
opkg install luci-ssl px5g-mbedtls

# Проверка наличия сертификатов
if [ -f "$CERT_FILE" ] || [ -f "$KEY_FILE" ]; then
    yellow "Найдены существующие сертификаты:"
    [ -f "$CERT_FILE" ] && echo "  - $CERT_FILE"
    [ -f "$KEY_FILE" ] && echo "  - $KEY_FILE"
    
    echo ""
    echo "1) Оставить существующие"
    echo "2) Удалить и создать новые"
    echo "3) Выйти"
    read -p "Выберите действие (1-3): " choice
    
    case $choice in
        2)
            yellow "Удаление старых сертификатов..."
            rm -f "$CERT_FILE" "$KEY_FILE"
            ;;
        3)
            red "Выход"
            exit 0
            ;;
        *)
            green "Оставляем существующие сертификаты"
            SKIP_GENERATION=1
            ;;
    esac
fi

# Генерация новых сертификатов если нужно
if [ ! -f "$CERT_FILE" ] && [ -z "$SKIP_GENERATION" ]; then
    yellow "Генерация новых сертификатов..."
    px5g-mbedtls self-signed -o "$CERT_FILE" -k "$KEY_FILE" -d 730
    
    if [ $? -eq 0 ]; then
        green "Сертификаты созданы"
    else
        red "Ошибка создания сертификатов"
        exit 1
    fi
fi

# Настройка прав
chmod 600 "$KEY_FILE" 2>/dev/null
chmod 644 "$CERT_FILE" 2>/dev/null

# Резервная копия конфигурации
cp /etc/config/uhttpd /etc/config/uhttpd.backup 2>/dev/null

# Настройка uhttpd
sed -i 's/^[[:space:]]*#\?[[:space:]]*option cert.*/option cert '\'$CERT_FILE\''/' /etc/config/uhttpd
sed -i 's/^[[:space:]]*#\?[[:space:]]*option key.*/option key '\'$KEY_FILE\''/' /etc/config/uhttpd

# Добавление HTTPS портов если их нет
grep -q "list listen_https '0.0.0.0:443'" /etc/config/uhttpd || \
    sed -i "/config uhttpd main/a \	list listen_https '0.0.0.0:443'" /etc/config/uhttpd

grep -q "list listen_https '\[::]:443'" /etc/config/uhttpd || \
    sed -i "/config uhttpd main/a \	list listen_https '[::]:443'" /etc/config/uhttpd

# Перезапуск uhttpd
yellow "Перезапуск uhttpd..."
/etc/init.d/uhttpd restart

# Получение IP
IP_ADDR=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")

# Итог
echo ""
green "========================================"
green "      HTTPS НАСТРОЕН"
green "========================================"
echo ""
green "Сайт: https://$IP_ADDR"
echo ""
yellow "Предупреждение браузера - это нормально"
echo ""