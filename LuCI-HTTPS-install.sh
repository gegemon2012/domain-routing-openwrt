#!/bin/sh

# 1. Установка пакетов
echo "Обновление списка пакетов и установка mbedtls..."
opkg update
opkg install libmbedtls uhttpd-mod-mbedtls px5g-mbedtls

# 2. Логика проверки и выбора для сертификата
CERT_FILE="/etc/uhttpd.crt"
KEY_FILE="/etc/uhttpd.key"

if [ -f "$CERT_FILE" ]; then
    echo "-------------------------------------------------------"
    echo "Внимание: SSL-сертификат уже существует ($CERT_FILE)."
    echo "1) Пропустить генерацию и использовать текущий"
    echo "2) Удалить старый и сгенерировать новый"
    echo "-------------------------------------------------------"
    printf "Выберите вариант (1/2): "
    read choice

    case "$choice" in
        2)
            echo "Удаление старых ключей и генерация новых..."
            rm -f "$CERT_FILE" "$KEY_FILE"
            px5g selfsigned -der -days 3650 -newkey rsa:4096 \
                -keyout "$KEY_FILE" -out "$CERT_FILE" \
                -subj /C=RU/ST=State/L=City/O=OpenWrt/CN=Router
            ;;
        *)
            echo "Используем существующий сертификат."
            ;;
    esac
else
    echo "Сертификаты не найдены. Генерация..."
    px5g selfsigned -der -days 3650 -newkey rsa:2048 \
        -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -subj /C=RU/ST=State/L=City/O=OpenWrt/CN=Router
fi

# 3. Настройка uHTTPd через UCI
echo "Настройка параметров UCI..."

# Очистка старых портов для избежания дублей
uci del uhttpd.main.listen_https

# Добавление портов
uci add_list uhttpd.main.listen_https='0.0.0.0:443'
uci add_list uhttpd.main.listen_https='[::]:443'

# Привязка файлов
uci set uhttpd.main.cert="$CERT_FILE"
uci set uhttpd.main.key="$KEY_FILE"
uci set uhttpd.main.redirect_https='1'

# Применение изменений
uci commit uhttpd

# 4. Перезапуск
echo "Перезапуск веб-сервера..."
/etc/init.d/uhttpd restart

echo "Настройка завершена успешно!"