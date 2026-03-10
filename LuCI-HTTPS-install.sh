#!/bin/sh

# Функция для вывода цветного текста
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }

# Проверка наличия файлов сертификатов
CERT_FILE="/etc/uhttpd.crt"
KEY_FILE="/etc/uhttpd.key"

# Обновляем список пакетов
yellow "Обновление списка пакетов..."
opkg update

# 1. Установка необходимых пакетов
yellow "Установка luci-ssl..."
opkg install luci-ssl

# 2. Проверка и обработка существующих сертификатов
if [ -f "$CERT_FILE" ] || [ -f "$KEY_FILE" ]; then
    yellow "Найдены существующие файлы сертификатов:"
    [ -f "$CERT_FILE" ] && echo "  - $CERT_FILE"
    [ -f "$KEY_FILE" ] && echo "  - $KEY_FILE"
    
    echo ""
    echo "Выберите действие:"
    echo "1) Оставить существующие сертификаты"
    echo "2) Удалить старые и создать новые"
    echo "3) Прервать выполнение скрипта"
    echo ""
    
    while true; do
        read -p "Введите номер действия (1-3): " choice
        case $choice in
            1)
                green "Оставляем существующие сертификаты."
                break
                ;;
            2)
                yellow "Удаление старых сертификатов..."
                rm -f "$CERT_FILE" "$KEY_FILE"
                green "Старые сертификаты удалены."
                break
                ;;
            3)
                red "Выполнение скрипта прервано пользователем."
                exit 0
                ;;
            *)
                red "Неверный выбор. Пожалуйста, введите 1, 2 или 3."
                ;;
        esac
    done
fi

# 3. Генерация новых сертификатов, если файлы не существуют
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    yellow "Генерация новых сертификатов с помощью px5g-mbedtls..."
    
    # Создаем сертификат с дополнительными параметрами для большей совместимости
    px5g-mbedtls self-signed \
        -o "$CERT_FILE" \
        -k "$KEY_FILE" \
        -d 730 \
        -O "OpenWrt Router" \
        -C "RU" \
        -S "Moscow" \
        -N "LuCI HTTPS Certificate"
    
    if [ $? -eq 0 ]; then
        green "Сертификаты успешно созданы."
    else
        red "Ошибка при создании сертификатов!"
        exit 1
    fi
else
    green "Используются существующие сертификаты."
fi

# 4. Настройка прав доступа
yellow "Настройка прав доступа к сертификатам..."
chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"
green "Права установлены."

# 5. Настройка веб-сервера uhttpd для работы с HTTPS
yellow "Настройка конфигурации uhttpd..."

# Резервное копирование конфигурации
cp /etc/config/uhttpd /etc/config/uhttpd.backup.$(date +%Y%m%d_%H%M%S)
green "Создана резервная копия /etc/config/uhttpd"

# Указываем пути к сертификатам
sed -i 's/\# option cert/option cert/g' /etc/config/uhttpd
sed -i 's/\# option key/option key/g' /etc/config/uhttpd
sed -i "s|option cert.*|option cert '$CERT_FILE'|g" /etc/config/uhttpd
sed -i "s|option key.*|option key '$KEY_FILE'|g" /etc/config/uhttpd

# Добавляем HTTPS порты, если их нет
if ! grep -q "list listen_https '0.0.0.0:443'" /etc/config/uhttpd; then
    sed -i "/config uhttpd main/a \	list listen_https '0.0.0.0:443'" /etc/config/uhttpd
    green "Добавлен HTTPs порт для IPv4"
fi

if ! grep -q "list listen_https '\[::]:443'" /etc/config/uhttpd; then
    sed -i "/config uhttpd main/a \	list listen_https '[::]:443'" /etc/config/uhttpd
    green "Добавлен HTTPs порт для IPv6"
fi

# 6. Проверка конфигурации перед перезапуском
yellow "Проверка конфигурации uhttpd..."
if uhttpd -t -f /etc/config/uhttpd; then
    green "Конфигурация корректна."
    
    # 7. Перезапуск uhttpd
    yellow "Перезапуск uhttpd..."
    /etc/init.d/uhttpd restart
    
    if [ $? -eq 0 ]; then
        green "uhttpd успешно перезапущен."
    else
        red "Ошибка при перезапуске uhttpd!"
        exit 1
    fi
else
    red "Ошибка в конфигурации uhttpd! Восстановление из резервной копии..."
    cp /etc/config/uhttpd.backup.* /etc/config/uhttpd
    exit 1
fi

# 8. Получение IP адреса роутера
IP_ADDR=$(ip -4 addr show br-lan 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -z "$IP_ADDR" ]; then
    IP_ADDR=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
fi
if [ -z "$IP_ADDR" ]; then
    IP_ADDR="192.168.1.1"
fi

# 9. Финальное сообщение
echo ""
green "====================================================="
green "       НАСТРОЙКА HTTPS ДОСТУПА ЗАВЕРШЕНА"
green "====================================================="
echo ""
green "Попробуйте открыть в браузере:"
green "🔒 https://$IP_ADDR"
echo ""
yellow "⚠️  Важно:"
yellow "   - Используется самоподписанный сертификат"
yellow "   - Браузер покажет предупреждение о безопасности"
yellow "   - Это нормально для самоподписанных сертификатов"
echo ""
yellow "Для просмотра информации о сертификате:"
echo "   openssl x509 -in $CERT_FILE -text -noout"
echo ""
green "====================================================="

# 10. Проверка доступности HTTPS
yellow "Проверка доступности HTTPS порта..."
if netstat -tln | grep -q ':443'; then
    green "✅ Порт 443 (HTTPS) открыт и слушает"
else
    red "❌ Порт 443 не найден! Что-то пошло не так."
fi