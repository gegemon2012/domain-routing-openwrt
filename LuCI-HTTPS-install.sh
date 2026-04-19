#!/bin/sh

# 1. Проверка установки (Таймер 10 сек)
echo "--- Шаг 1: Установка пакетов (HTTPS) ---"
echo "Нажмите ЛЮБУЮ клавишу за 10 сек, чтобы ПРОПУСТИТЬ установку пакетов."
echo "(Пропускайте, если luci-ssl и px5g уже вшиты в прошивку)"

if read -t 10 -n 1; then
    echo -e "\n[!] Установка пропущена. Переходим к настройке сертификатов."
else
    echo -e "\n[+] Обновление и установка..."
    opkg update
    # Используем standalone версию для экономии места и независимости от библиотек
    opkg install luci-ssl px5g-standalone luci-app-uhttpd
fi

# 2. Сбор данных для сертификата
echo -e "\n--- Шаг 2: Настройка данных сертификата ---"
# Используем автоматические значения, если пользователь нажмет Enter
printf "Общее имя/Хост (CN) [OpenWrt]: "
read cert_cn
cert_cn=${cert_cn:-OpenWrt}

CERT_FILE="/etc/uhttpd.crt"
KEY_FILE="/etc/uhttpd.key"

# 3. Генерация сертификатов
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    printf "Файлы сертификатов уже существуют. Перезаписать? (y/n): "
    read confirmation
    [ "$confirmation" != "y" ] && REGEN=0 || REGEN=1
else
    REGEN=1
fi

if [ "$REGEN" -eq 1 ]; then
    echo "Генерируем сертификат (RSA 2048 для экономии CPU)..."
    # Для 16мб роутера 2048 бит — оптимальный баланс скорости и защиты
    px5g selfsigned -der -days 3650 -newkey rsa:4096 -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -subj "/C=RU/ST=State/L=City/O=OpenWrt/CN=$cert_cn"
fi

# 4. Настройка UCI
echo -e "\n--- Шаг 3: Настройка UCI и Редирект ---"
printf "Включить редирект HTTP -> HTTPS? (y/n): "
read do_redirect

uci set uhttpd.main.cert="$CERT_FILE"
uci set uhttpd.main.key="$KEY_FILE"
uci add_list uhttpd.main.listen_https='0.0.0.0:443'
uci add_list uhttpd.main.listen_https='[::]:443'

if [ "$do_redirect" = "y" ]; then
    uci set uhttpd.main.redirect_https='1'
else
    uci set uhttpd.main.redirect_https='0'
fi

uci commit uhttpd

# 5. Финал
echo "Перезапуск сервера..."
/etc/init.d/uhttpd restart
echo "✅ Готово! Теперь LuCI доступен по HTTPS."
