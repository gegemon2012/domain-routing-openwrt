#!/bin/sh

# 1. Обновление списков и установка
opkg update
opkg install zerotier

# 2. Настройка базового конфига ZeroTier
ZT_CONF="/etc/config/zerotier"

echo "Введите ваш ZeroTier Network ID:"
read ZT_ID

# Включаем сервис и задаем ID через UCI (это надежнее, чем awk/sed)
uci set zerotier.sample_config.enabled='1'
uci set zerotier.sample_config.join='$ZT_ID'
# Если в вашем конфиге используется другая секция вместо sample_config, 
# скрипт ниже создаст стандартную структуру:
if [ $? -ne 0 ]; then
    uci set zerotier.openwrt_network=zerotier
    uci set zerotier.openwrt_network.enabled='1'
    uci set zerotier.openwrt_network.id='$ZT_ID'
fi
uci commit zerotier

# 3. Создание сетевого интерфейса в OpenWrt
# Это то, чего не хватало: привязываем виртуальное устройство zt+ к системе
uci set network.zerotier=interface
uci set network.zerotier.proto='none'
uci set network.zerotier.device='zt+'
uci commit network

# 4. Настройка Firewall (Зоны и правила)
# Удаляем старую зону, если она была, чтобы избежать дублей
uci delete firewall.zerotier_zone 2>/dev/null
uci set firewall.zerotier_zone=zone
uci set firewall.zerotier_zone.name='zerotier'
uci set firewall.zerotier_zone.input='ACCEPT'
uci set firewall.zerotier_zone.forward='ACCEPT'
uci set firewall.zerotier_zone.output='ACCEPT'
uci set firewall.zerotier_zone.network='zerotier'
uci set firewall.zerotier_zone.masq='1'
uci set firewall.zerotier_zone.mtu_fix='1'

# Разрешаем пересылку трафика между LAN и ZeroTier
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='zerotier'

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='zerotier'
uci set firewall.@forwarding[-1].dest='lan'

# Разрешаем входящий трафик для самого ZeroTier (UDP 9993) на WAN
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-ZeroTier-UDP'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='9993'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall

# 5. Перезапуск всех служб
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/zerotier enable
/etc/init.d/zerotier restart

echo "------------------------------------------------------"
echo "Установка завершена!"
echo "ВАЖНО: Зайдите в панель my.zerotier.com и АВТОРИЗУЙТЕ роутер."
echo "Ваш Node ID: $(zerotier-cli status | awk '{print $3}')"
echo "------------------------------------------------------"
