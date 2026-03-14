#!/bin/sh

# 1. Обновление и установка
echo "--- Шаг 1: Установка необходимых пакетов ---"
opkg update && opkg install luci-ssl px5g-mbedtls luci-app-uhttpd

# 2. Сбор данных для сертификата
echo "--- Шаг 2: Настройка данных сертификата ---"
echo "Оставьте поле пустым и нажмите Enter, чтобы использовать значение по умолчанию."

read -p "Страна (C) [RU]: " cert_c
cert_c=${cert_c:-RU}

read -p "Область/Край (ST) [State]: " cert_st
cert_st=${cert_st:-State}

read -p "Город (L) [City]: " cert_l
cert_l=${cert_l:-City}

read -p "Организация (O) [OpenWrt]: " cert_o
cert_o=${cert_o:-OpenWrt}

read -p "Общее имя/Хост (CN) [Router]: " cert_cn
cert_cn=${cert_cn:-Router}

# 3. Генерация сертификатов
CERT_FILE="/etc/uhttpd.crt"
KEY_FILE="/etc/uhttpd.key"

if [ -f "$CERT_FILE" ] || [ -f "$KEY_FILE" ]; then
    printf "\nФайлы сертификатов уже существуют. Перезаписать их? (y/n): "
    read confirmation
    if [ "$confirmation" = "y" ]; then
        echo "Генерируем новые ключи..."
        px5g selfsigned -der -days 3650 -newkey rsa:4096 -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -subj "/C=$cert_c/ST=$cert_st/L=$cert_l/O=$cert_o/CN=$cert_cn"
    else
        echo "Используем старые сертификаты."
    fi
else
    echo "Генерируем новые сертификаты..."
    px5g selfsigned -der -days 3650 -newkey rsa:4096 -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -subj "/C=$cert_c/ST=$cert_st/L=$cert_l/O=$cert_o/CN=$cert_cn"
fi

# 4. Настройка редиректа
echo -e "\n--- Шаг 3: Настройка UCI ---"
printf "Включить автоматический редирект с HTTP на HTTPS? (y/n): "
read do_redirect

# 5. Применение настроек UCI
# Добавляем порты (UCI аккуратно обработает дубликаты)
uci add_list uhttpd.main.listen_https='0.0.0.0:443'
uci add_list uhttpd.main.listen_https='[::]:443'
uci set uhttpd.main.cert="$CERT_FILE"
uci set uhttpd.main.key="$KEY_FILE"

if [ "$do_redirect" = "y" ]; then
    echo "Редирект ВКЛЮЧЕН."
    uci set uhttpd.main.redirect_https='1'
else
    echo "Редирект ОТКЛЮЧЕН."
    uci set uhttpd.main.redirect_https='0'
fi

uci commit uhttpd

# 6. Финал
echo "Перезапуск uHTTPd..."
/etc/init.d/uhttpd restart

echo -e "\nГотово! Текущие настройки портов и сертификата:"
uci show uhttpd.main | grep -E 'listen_https|cert|key|redirect_https'
