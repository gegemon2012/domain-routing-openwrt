# Обновим список пакетов
opkg update

# 1. Установка необходимых пакетов
opkg install luci-ssl

# 2. Генерация самоподписанного сертификата с помощью px5g-mbedtls
#    Создаем сертификат (ca.crt) и ключ (ca.key) сроком на 730 дней (2 года).
#    Примечание: Если файлы уже существуют, команда выдаст ошибку.
#    В таком случае удалите старые файлы или выполните команду генерации вручную.
px5g-mbedtls self-signed -o /etc/uhttpd.crt -k /etc/uhttpd.key -d 730

# 3. Настройка прав доступа (на всякий случай)
chmod 600 /etc/uhttpd.key
chmod 644 /etc/uhttpd.crt

# 4. Настройка веб-сервера uhttpd для работы с HTTPS
#    Добавляем или раскомментируем строки в конфигурационном файле.
#    Следующие команды sed аккуратно заменят или добавят нужные строки.

# Указываем пути к только что созданным ключу и сертификату
sed -i 's\# option cert\option cert\g' /etc/config/uhttpd
sed -i 's\# option key\option key\g' /etc/config/uhttpd
sed -i "s\option cert.*\option cert '/etc/uhttpd.crt'\g" /etc/config/uhttpd
sed -i "s\option key.*\option key '/etc/uhttpd.key'\g" /etc/config/uhttpd

# Добавляем порт 443 (стандартный HTTPS) в список прослушиваемых адресов,
# если его там еще нет. Команда добавит прослушивание всех интерфейсов.
# Проверьте, не появилась ли строка с [::]:443 (IPv6), это нормально.
grep -q "list listen_https '0.0.0.0:443'" /etc/config/uhttpd || sed -i "/config uhttpd main/a \	list listen_https '0.0.0.0:443'" /etc/config/uhttpd

# Для поддержки IPv6 можно также добавить (опционально):
grep -q "list listen_https '\[::]:443'" /etc/config/uhttpd || sed -i "/config uhttpd main/a \	list listen_https '[::]:443'" /etc/config/uhttpd

# 5. Перезапуск uhttpd для применения настроек
/etc/init.d/uhttpd restart

# 6. Сообщаем результат
echo "Настройка завершена. Попробуйте открыть в браузере https://192.168.1.1 (или ваш IP роутера)."