#!/bin/sh

echo "Настройка гостевой сети..."

# 1. Настройка сетевого интерфейса (отдельная подсеть 192.168.2.x)
uci set network.guest=interface
uci set network.guest.proto='static'
uci set network.guest.ipaddr='192.168.2.1'
uci set network.guest.netmask='255.255.255.0'

# 2. Настройка Wi-Fi на radio1
uci set wireless.guest_net=wifi-iface
uci set wireless.guest_net.device='radio1'
uci set wireless.guest_net.mode='ap'
uci set wireless.guest_net.network='guest'
uci set wireless.guest_net.ssid='Guest_WiFi'     # Имя вашей гостевой сети
uci set wireless.guest_net.encryption='psk2'
uci set wireless.guest_net.key='12345678'         # Ваш пароль
uci set wireless.guest_net.isolate='1'            # Изоляция клиентов (гости не видят друг друга)

# 3. Настройка DHCP сервера для выдачи IP-адресов гостям
uci set dhcp.guest=dhcp
uci set dhcp.guest.interface='guest'
uci set dhcp.guest.start='100'
uci set dhcp.guest.limit='150'
uci set dhcp.guest.leasetime='12h'

# 4. Настройка файрвола
# Создаем зону firewall для гостей
uci set firewall.guest=zone
uci set firewall.guest.name='guest'
uci set firewall.guest.network='guest'
uci set firewall.guest.input='REJECT'             # Запрещаем доступ к админке роутера
uci set firewall.guest.output='ACCEPT'
uci set firewall.guest.forward='REJECT'           # Запрещаем доступ к основной LAN сети

# Разрешаем выход из гостевой сети в интернет (forward zone guest -> wan)
uci set firewall.guest_wan=forwarding
uci set firewall.guest_wan.src='guest'
uci set firewall.guest_wan.dest='wan'

# Разрешаем DNS-запросы (порт 53), чтобы у гостей открывались сайты
uci set firewall.guest_dns=rule
uci set firewall.guest_dns.name='Allow-DNS-Guest'
uci set firewall.guest_dns.src='guest'
uci set firewall.guest_dns.dest_port='53'
uci set firewall.guest_dns.proto='tcp udp'
uci set firewall.guest_dns.target='ACCEPT'

# Разрешаем DHCP-запросы (порт 67), чтобы устройства получали IP-адреса
uci set firewall.guest_dhcp=rule
uci set firewall.guest_dhcp.name='Allow-DHCP-Guest'
uci set firewall.guest_dhcp.src='guest'
uci set firewall.guest_dhcp.dest_port='67'
uci set firewall.guest_dhcp.proto='udp'
uci set firewall.guest_dhcp.target='ACCEPT'

echo "Сохранение изменений..."
uci commit

echo "Перезапуск сервисов..."
/etc/init.d/network reload
/etc/init.d/dnsmasq reload
/etc/init.d/firewall reload
wifi reload

echo "Готово! Сеть Guest_WiFi успешно запущена."