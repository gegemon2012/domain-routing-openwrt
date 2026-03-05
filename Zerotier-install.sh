#!/bin/sh

# 1. Установка
opkg update
opkg install zerotier

# 2. Настройка через UCI (фиксим Invalid argument)
echo "Введите ваш ZeroTier Network ID:"
read ZT_ID

# Удаляем старые записи, если они были, чтобы не плодить ошибки
uci delete zerotier.openwrt_network 2>/dev/null

# Создаем чистую конфигурацию
uci set zerotier.openwrt_network=zerotier
uci set zerotier.openwrt_network.enabled='1'
uci set zerotier.openwrt_network.id="$ZT_ID"
uci commit zerotier

# 3. Настройка сети и Firewall
uci set network.zerotier=interface
uci set network.zerotier.proto='none'
uci set network.zerotier.device='zt+'
uci commit network

# Настройка зоны (используем понятное имя)
uci delete firewall.zt_zone 2>/dev/null
uci set firewall.zt_zone=zone
uci set firewall.zt_zone.name='zerotier'
uci set firewall.zt_zone.input='ACCEPT'
uci set firewall.zt_zone.forward='ACCEPT'
uci set firewall.zt_zone.output='ACCEPT'
uci set firewall.zt_zone.network='zerotier'
uci set firewall.zt_zone.masq='1'
uci commit firewall

# 4. Запуск служб
/etc/init.d/zerotier enable
/etc/init.d/zerotier restart
/etc/init.d/network restart
/etc/init.d/firewall restart

# Даем сервису 5 секунд, чтобы он "проснулся"
echo "Ожидание запуска ZeroTier..."
sleep 5

echo "------------------------------------------------------"
echo "Установка завершена!"
# Пробуем получить ID снова
NODE_ID=$(zerotier-cli status | awk '{print $3}')
if [ -z "$NODE_ID" ]; then
    echo "Ошибка: Сервис еще не запущен. Попробуйте выполнить 'zerotier-cli status' через минуту."
else
    echo "Ваш Node ID: $NODE_ID"
fi
echo "------------------------------------------------------"
