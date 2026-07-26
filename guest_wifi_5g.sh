#!/bin/sh

# Функция для удаления гостевой сети
remove_guest_network() {
    echo "Удаление настроек гостевой сети..."

    # Удаляем настройки интерфейсов и Wi-Fi
    uci delete network.guest 2>/dev/null
    uci delete wireless.guest_net 2>/dev/null
    uci delete dhcp.guest 2>/dev/null

    # Удаляем настройки файрвола
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

    echo "Гостевая сеть успешно удалена!"
}

# Функция для создания гостевой сети
setup_guest_network() {
    echo "Настройка гостевой сети..."

    # 1. Сетевой интерфейс
    uci set network.guest=interface
    uci set network.guest.proto='static'
    uci set network.guest.ipaddr='192.168.2.1'
    uci set network.guest.netmask='255.255.255.0'

    # 2. Wi-Fi на radio1
    uci set wireless.guest_net=wifi-iface
    uci set wireless.guest_net.device='radio1'
    uci set wireless.guest_net.mode='ap'
    uci set wireless.guest_net.network='guest'
    uci set wireless.guest_net.ssid='Guest_WiFi'
    uci set wireless.guest_net.encryption='psk2'
    uci set wireless.guest_net.key='12345678'
    uci set wireless.guest_net.isolate='1'

    # 3. DHCP сервер
    uci set dhcp.guest=dhcp
    uci set dhcp.guest.interface='guest'
    uci set dhcp.guest.start='100'
    uci set dhcp.guest.limit='150'
    uci set dhcp.guest.leasetime='12h'

    # 4. Файрвол
    uci set firewall.guest=zone
    uci set firewall.guest.name='guest'
    uci set firewall.guest.network='guest'
    uci set firewall.guest.input='REJECT'
    uci set firewall.guest.output='ACCEPT'
    uci set firewall.guest.forward='REJECT'

    uci set firewall.guest_wan=forwarding
    uci set firewall.guest_wan.src='guest'
    uci set firewall.guest_wan.dest='wan'

    uci set firewall.guest_dns=rule
    uci set firewall.guest_dns.name='Allow-DNS-Guest'
    uci set firewall.guest_dns.src='guest'
    uci set firewall.guest_dns.dest_port='53'
    uci set firewall.guest_dns.proto='tcp udp'
    uci set firewall.guest_dns.target='ACCEPT'

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

    echo "Готово! Гостевая сеть запущенна."
}

# Выбор действия по аргументу команды
case "$1" in
    start)
        setup_guest_network
        ;;
    remove)
        remove_guest_network
        ;;
    *)
        echo "Использование: $0 {start|remove}"
        echo "  start  - Создать и запустить гостевую сеть"
        echo "  remove - Полностью удалить гостевую сеть"
        exit 1
        ;;
esac
