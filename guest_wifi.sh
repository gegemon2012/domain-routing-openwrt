#!/bin/sh

# Функция для полного удаления гостевых сетей
remove_guest_network() {
    echo "Удаление настроек гостевой сети (2.4G и 5G)..."

    # Удаляем обе Wi-Fi точки
    uci delete wireless.guest_net_24 2>/dev/null
    uci delete wireless.guest_net_50 2>/dev/null

    # Удаляем сетевой интерфейс и DHCP
    uci delete network.guest 2>/dev/null
    uci delete dhcp.guest 2>/dev/null

    # Удаляем правила файрвола
    uci delete firewall.guest 2>/dev/null
    uci delete firewall.guest_wan 2>/dev/null
    uci delete firewall.guest_dns 2>/dev/null
    uci delete firewall.guest_dhcp 2>/dev/null

    echo "Сохранение изменений..."
    uci commit

    echo "Перезапуск служб..."
    /etc/init.d/network reload
    /etc/init.d/dnsmasq reload
    /etc/init.d/firewall reload
    wifi reload

    echo "Гостевые сети Guest_WiFi_2.4g и Guest_WiFi_5g успешно удалены!"
}

# Функция для создания гостевых сетей
setup_guest_network() {
    echo "Настройка гостевых сетей..."

    # 1. Сетевой интерфейс (общий мост для 2.4G и 5G)
    uci set network.guest=interface
    uci set network.guest.proto='static'
    uci set network.guest.device='br-guest'      # Создаем виртуальный мост br-guest
    uci set network.guest.type='bridge'          # Объявляем его как bridge
    uci set network.guest.ipaddr='192.168.2.1'
    uci set network.guest.netmask='255.255.255.0'

    # 2. Wi-Fi точка на radio0 (2.4G)
    uci set wireless.guest_net_24=wifi-iface
    uci set wireless.guest_net_24.device='radio0'
    uci set wireless.guest_net_24.mode='ap'
    uci set wireless.guest_net_24.network='guest'
    uci set wireless.guest_net_24.ssid='Guest_WiFi_2.4g'
    uci set wireless.guest_net_24.encryption='psk2'
    uci set wireless.guest_net_24.key='12345678'
    uci set wireless.guest_net_24.isolate='1'

    # 3. Wi-Fi точка на radio1 (5G)
    uci set wireless.guest_net_50=wifi-iface
    uci set wireless.guest_net_50.device='radio1'
    uci set wireless.guest_net_50.mode='ap'
    uci set wireless.guest_net_50.network='guest'
    uci set wireless.guest_net_50.ssid='Guest_WiFi_5g'
    uci set wireless.guest_net_50.encryption='psk2'
    uci set wireless.guest_net_50.key='12345678'
    uci set wireless.guest_net_50.isolate='1'

    # 4. DHCP сервер (общий для обоих диапазонов)
    uci set dhcp.guest=dhcp
    uci set dhcp.guest.interface='guest'
    uci set dhcp.guest.start='100'
    uci set dhcp.guest.limit='150'
    uci set dhcp.guest.leasetime='12h'

    # 5. Настройка файрвола (Изоляция + Доступ в интернет)
    uci set firewall.guest=zone
    uci set firewall.guest.name='guest'
    uci set firewall.guest.network='guest'
    uci set firewall.guest.input='REJECT'
    uci set firewall.guest.output='ACCEPT'
    uci set firewall.guest.forward='REJECT'

    uci set firewall.guest_wan=forwarding
    uci set firewall.guest_wan.src='guest'
    uci set firewall.guest_wan.dest='wan'

    # Разрешаем DNS (порт 53)
    uci set firewall.guest_dns=rule
    uci set firewall.guest_dns.name='Allow-DNS-Guest'
    uci set firewall.guest_dns.src='guest'
    uci set firewall.guest_dns.dest_port='53'
    uci set firewall.guest_dns.proto='tcp udp'
    uci set firewall.guest_dns.target='ACCEPT'

    # Разрешаем DHCP (порт 67)
    uci set firewall.guest_dhcp=rule
    uci set firewall.guest_dhcp.name='Allow-DHCP-Guest'
    uci set firewall.guest_dhcp.src='guest'
    uci set firewall.guest_dhcp.dest_port='67'
    uci set firewall.guest_dhcp.proto='udp'
    uci set firewall.guest_dhcp.target='ACCEPT'

    echo "Сохранение изменений..."
    uci commit

    echo "Перезапуск служб..."
    /etc/init.d/network reload
    /etc/init.d/dnsmasq reload
    /etc/init.d/firewall reload
    wifi reload

    echo "Готово! Гостевые сети Guest_WiFi_2.4g и Guest_WiFi_5g запущены."
}

# Обработка аргументов
case "$1" in
    start)
        setup_guest_network
        ;;
    remove)
        remove_guest_network
        ;;
    *)
        echo "Использование: $0 {start|remove}"
        echo "  start  - Создать и запустить гостевые сети (2.4G и 5G)"
        echo "  remove - Полностью удалить все гостевые сети"
        exit 1
        ;;
esac
