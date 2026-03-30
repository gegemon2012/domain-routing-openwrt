#!/bin/sh

# Функция управления IPv6
manage_ipv6() {
    echo ""
    echo "=========================================="
    echo "   Управление протоколом IPv6"
    echo "=========================================="
    echo "1) Полностью отключить (рекомендуется при отсутствии поддержки провайдером)"
    echo "2) Включить/Восстановить (стандартные настройки OpenWrt)"
    echo "3) Оставить без изменений"
    printf "Выберите вариант (1-3): "
    read ipv6_opt

    case $ipv6_opt in
        1)
            echo "--- Отключение IPv6 ---"
            # Удаление WAN6 интерфейса
            if uci get network.wan6 >/dev/null 2>&1; then
                uci delete network.wan6
                echo "[+] Интерфейс WAN6 удален"
            fi

            # Отключение RA и DHCPv6 на LAN
            uci set dhcp.lan.ra='disabled'
            uci set dhcp.lan.dhcpv6='disabled'
            uci set dhcp.lan.ra_management='0'
            echo "[+] Раздача IPv6 в локальной сети отключена"

            # Остановка службы odhcpd (источник ошибок в логах)
            /etc/init.d/odhcpd stop
            /etc/init.d/odhcpd disable
            echo "[+] Служба odhcpd остановлена и выключена"

            uci commit
            /etc/init.d/network restart
            echo "IPv6 успешно отключен."
            ;;
        2)
            echo "--- Включение IPv6 ---"
            # Восстановление интерфейса WAN6
            uci set network.wan6=interface
            uci set network.wan6.proto='dhcpv6'
            uci set network.wan6.device='@wan'
            echo "[+] Интерфейс WAN6 восстановлен"

            # Включение RA и DHCPv6 на LAN
            uci set dhcp.lan.ra='server'
            uci set dhcp.lan.dhcpv6='server'
            uci set dhcp.lan.ra_management='1'
            echo "[+] Раздача IPv6 в локальной сети включена"

            # Включение службы odhcpd
            /etc/init.d/odhcpd enable
            /etc/init.d/odhcpd start
            echo "[+] Служба odhcpd запущена"

            uci commit
            /etc/init.d/network restart
            echo "IPv6 восстановлен. Устройствам может потребоваться переподключение."
            ;;
        *)
            echo "Пропуск настройки IPv6."
            ;;
    esac
}

# Далее в вашем скрипте, там где идут основные настройки (например, после оптимизации CPU/ZRAM):
manage_ipv6
