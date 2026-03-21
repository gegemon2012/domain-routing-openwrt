#!/bin/sh

# Определение путей (аналогично оригинальному скрипту)
CONFIG_DIR="/etc/ruantiblock"
EXEC_DIR="/usr/bin"
FILE_MAIN_SCRIPT="${EXEC_DIR}/ruantiblock"
FILE_INIT_SCRIPT="/etc/init.d/ruantiblock"
FILE_UCI_CONFIG="/etc/config/ruantiblock"

echo "--- Начинаю удаление RuAntiBlock ---"

# 1. Остановка сервиса и очистка правил фильтрации
if [ -x "$FILE_MAIN_SCRIPT" ]; then
    echo "Остановка и очистка правил RuAntiBlock..."
    $FILE_MAIN_SCRIPT destroy
fi

if [ -f "$FILE_INIT_SCRIPT" ]; then
    $FILE_INIT_SCRIPT stop
    $FILE_INIT_SCRIPT disable
fi

# 2. Удаление пакетов через opkg
# Список включает основные пакеты проекта
PACKAGES="luci-i18n-ruantiblock-ru luci-app-ruantiblock ruantiblock-mod-lua ruantiblock"

echo "Удаление установленных пакетов..."
for pkg in $PACKAGES; do
    if opkg list-installed | grep -q "^$pkg "; then
        echo "Удаляю $pkg..."
        opkg remove "$pkg" --force-removal-files
    fi
done

# Примечание: Мы НЕ удаляем системные зависимости (tor, dnsmasq-full, https-dns-proxy), 
# так как они могут использоваться другими сервисами. 
# Если вы хотите удалить и их, добавьте их в список PACKAGES выше.

# 3. Удаление конфигурационных файлов
echo "Очистка конфигураций..."
rm -rf "$CONFIG_DIR"
rm -f "$FILE_UCI_CONFIG"
rm -f "$FILE_INIT_SCRIPT"
rm -f "$FILE_MAIN_SCRIPT"

# 4. Очистка Cron задач
echo "Удаление задачи обновления из crontab..."
sed -i "/ruantiblock update/d" /etc/crontabs/root
/etc/init.d/cron restart

# 5. Очистка кэша LuCI
echo "Очистка кэша интерфейса..."
rm -rf /tmp/luci-modulecache/*
rm -f /tmp/luci-indexcache*
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart

# 6. Попытка восстановить настройки DNS (удаление onion из rebind)
uci del_list dhcp.@dnsmasq[0].rebind_domain='onion' 2>/dev/null
uci commit dhcp
/etc/init.d/dnsmasq restart

echo "--- Удаление завершено! ---"
echo "Рекомендуется перезагрузить роутер для полной очистки сетевых правил."