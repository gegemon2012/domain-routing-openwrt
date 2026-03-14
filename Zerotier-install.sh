#!/bin/sh

# 1. Проверка установки пакета
if ! command -v zerotier-cli >/dev/null 2>&1; then
    echo "Установка ZeroTier..."
    opkg update && opkg install zerotier
else
    echo "ZeroTier уже установлен."
fi

# 2. Получение Network ID
# Проверяем, есть ли уже настроенный ID в системе
OLD_ID=$(uci -q get zerotier.ztnoname.join)

if [ -n "$OLD_ID" ]; then
    echo "Найден существующий Network ID: $OLD_ID"
    echo "Хотите изменить его? (y/n)"
    read change_id
    if [ "$change_id" = "y" ]; then
        echo "Введите новый ZeroTier Network ID:"
        read ZT_ID
    else
        ZT_ID=$OLD_ID
    fi
else
    echo "Введите ваш ZeroTier Network ID:"
    read ZT_ID
fi

# 3. Настройка ZeroTier
echo "Настройка конфигов..."
uci set zerotier.ztnoname=zerotier
uci set zerotier.ztnoname.enabled='1'
# Очищаем список и добавляем новый ID
uci del_list zerotier.ztnoname.join="$OLD_ID" 2>/dev/null
uci add_list zerotier.ztnoname.join="$ZT_ID"
uci commit zerotier

# 4. Настройка сети (Интерфейс)
# Создаем интерфейс 'zerotier', если его нет
if ! uci -q get network.zerotier >/dev/null; then
    uci set network.zerotier=interface
    uci set network.zerotier.proto='none'
    uci set network.zerotier.device='zt+'
    uci commit network
fi

# 5. Настройка Firewall (Зона и Forwarding)
# Проверяем наличие зоны 'zerotier', чтобы не плодить дубликаты
if ! uci -q get firewall.zerotier_zone >/dev/null; then
    # Создаем именованную секцию для удобного управления
    uci set firewall.zerotier_zone=zone
    uci set firewall.zerotier_zone.name='zerotier'
    uci set firewall.zerotier_zone.input='ACCEPT'
    uci set firewall.zerotier_zone.forward='ACCEPT'
    uci set firewall.zerotier_zone.output='ACCEPT'
    uci set firewall.zerotier_zone.network='zerotier'
    uci set firewall.zerotier_zone.masq='1'
    uci set firewall.zerotier_zone.mtu_fix='1'
    
    # Forwarding LAN -> ZeroTier
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='lan'
    uci set firewall.@forwarding[-1].dest='zerotier'
    
    # Forwarding ZeroTier -> LAN
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src='zerotier'
    uci set firewall.@forwarding[-1].dest='lan'
    
    uci commit firewall
fi

# 6. Применение настроек и запуск
echo "Перезапуск сервисов..."
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/zerotier enable
/etc/init.d/zerotier start

echo "Ожидание инициализации (10 сек)..."
sleep 10

# 7. Финальный статус
NODE_ID=$(zerotier-cli status | awk '{print $3}')

echo "------------------------------------------------------"
if [ "$NODE_ID" = "ONLINE" ] || [ -n "$NODE_ID" ]; then
    echo "Успех! Ваш Node ID: $NODE_ID"
    echo "Не забудьте авторизовать это устройство в панели ZeroTier Central."
else
    echo "Ошибка: ZeroTier не смог запуститься. Проверьте 'logread | grep zerotier'"
fi
echo "------------------------------------------------------"
