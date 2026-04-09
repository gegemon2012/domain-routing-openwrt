#!/bin/sh

# 1. IPv6 Меню (с правкой ULA и чисткой Firewall)
echo -e "\n--- Шаг 1: IPv6 и Firewall ---"
echo "1) Полностью отключить (Сеть + ULA + Правила в Firewall)"
echo "2) Включить (Стандартные настройки + Правила в Firewall)"
echo "3) Пропустить"
printf "Выбор: "
read choice

case "$choice" in
    1)
        echo "Отключение IPv6, очистка ULA и удаление правил Firewall..."
        
        # --- Настройки сети ---
        uci -q delete network.wan6
        uci set dhcp.lan.ra='disabled'
        uci set dhcp.lan.dhcpv6='disabled'
        uci set dhcp.lan.ra_management='0'
        uci set network.globals.ula_prefix=''
        
        # --- Очистка Firewall от IPv6 (Мусор) ---
        # Удаляем специфические правила по именам, которые обычно есть в OpenWrt
        uci -q delete firewall.allow_dhcpv6
        uci -q delete firewall.allow_mld
        uci -q delete firewall.allow_icmpv6_input
        uci -q delete firewall.allow_icmpv6_forward
        
        # Дополнительный поиск и удаление правил по полю family 'ipv6'
        while uci show firewall | grep -q "family='ipv6'"; do
            RULE_INDEX=$(uci show firewall | grep "family='ipv6'" | head -n1 | cut -d'.' -f2 | cut -d'=' -f1)
            uci -q delete firewall.$RULE_INDEX
        done

        uci commit
        /etc/init.d/odhcpd stop
        /etc/init.d/odhcpd disable
        /etc/init.d/network restart
        /etc/init.d/firewall restart
        echo "✅ IPv6 полностью отключен. Firewall очищен от правил IPv6."
        ;;
    2)
        echo "Включение IPv6 и восстановление правил..."
        
        # --- Настройки сети ---
        uci set network.wan6=interface
        uci set network.wan6.proto='dhcpv6'
        uci set network.wan6.device='@wan'
        [ -z "$(uci get network.globals.ula_prefix 2>/dev/null)" ] && uci set network.globals.ula_prefix='fd00::/48'
        uci set dhcp.lan.ra='server'
        uci set dhcp.lan.dhcpv6='server'
        uci set dhcp.lan.ra_management='1'
        
        # --- Восстановление базовых правил Firewall (IPv6) ---
        # Добавляем Allow-DHCPv6
        uci set firewall.allow_dhcpv6=rule
        uci set firewall.allow_dhcpv6.name='Allow-DHCPv6'
        uci set firewall.allow_dhcpv6.src='wan'
        uci set firewall.allow_dhcpv6.proto='udp'
        uci set firewall.allow_dhcpv6.dest_port='546'
        uci set firewall.allow_dhcpv6.family='ipv6'
        uci set firewall.allow_dhcpv6.target='ACCEPT'

        # Добавляем базовый ICMPv6 Input
        uci set firewall.allow_icmpv6_input=rule
        uci set firewall.allow_icmpv6_input.name='Allow-ICMPv6-Input'
        uci set firewall.allow_icmpv6_input.src='wan'
        uci set firewall.allow_icmpv6_input.proto='icmp'
        uci add_list firewall.allow_icmpv6_input.icmp_type='echo-request'
        uci add_list firewall.allow_icmpv6_input.icmp_type='echo-reply'
        uci add_list firewall.allow_icmpv6_input.icmp_type='destination-unreachable'
        uci add_list firewall.allow_icmpv6_input.icmp_type='packet-too-big'
        uci add_list firewall.allow_icmpv6_input.icmp_type='time-exceeded'
        uci add_list firewall.allow_icmpv6_input.icmp_type='bad-header'
        uci add_list firewall.allow_icmpv6_input.icmp_type='unknown-header-type'
        uci add_list firewall.allow_icmpv6_input.icmp_type='router-solicitation'
        uci add_list firewall.allow_icmpv6_input.icmp_type='neighbour-solicitation'
        uci add_list firewall.allow_icmpv6_input.icmp_type='router-advertisement'
        uci add_list firewall.allow_icmpv6_input.icmp_type='neighbour-advertisement'
        uci set firewall.allow_icmpv6_input.family='ipv6'
        uci set firewall.allow_icmpv6_input.target='ACCEPT'

        uci commit
        /etc/init.d/odhcpd enable
        /etc/init.d/odhcpd start
        /etc/init.d/network restart
        /etc/init.d/firewall restart
        echo "✅ IPv6 включен. Базовые правила Firewall восстановлены."
        ;;
    *)
        echo "Пропущено."
        ;;
esac

# 2. Процессор и irqbalance
echo "--- Шаг 2: Проверка CPU и IRQ ---"
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
if [ "$CPU_CORES" -gt 1 ]; then
    echo "Ядер: $CPU_CORES. Установка irqbalance..."
    opkg update
    opkg install irqbalance
    LUCI_IRQ=$(opkg list | grep luci-app-irqbalance | awk '{print $1}' | head -n 1)
    [ -n "$LUCI_IRQ" ] && opkg install "$LUCI_IRQ"
    /etc/init.d/irqbalance enable
    /etc/init.d/irqbalance start
else
    echo "Одноядерный CPU. Пропуск."
fi

# 3. ZRAM (50% от ОЗУ)
echo -e "\n--- Шаг 3: Настройка ZRAM (50%) ---"
opkg update
opkg install zram-swap kmod-zram

# Вычисляем 50% от общего ОЗУ
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$(( TOTAL_RAM_KB / 1024 ))
ZRAM_SIZE=$(( TOTAL_RAM_MB / 2 ))

# Ограничение: не больше 2ГБ (на случай если это Mini PC с большим ОЗУ)
[ "$ZRAM_SIZE" -gt 2048 ] && ZRAM_SIZE=2048

# Поиск лучшего алгоритма
modprobe zram 2>/dev/null
ALGO="lzo"
for a in zstd lz4 lzo; do
    if grep -q "$a" /sys/block/zram0/comp_algorithm 2>/dev/null; then
        ALGO=$a
        break
    fi
done

echo "Общее ОЗУ: $TOTAL_RAM_MB MiB. Назначаем ZRAM: $ZRAM_SIZE MiB."
echo "Алгоритм сжатия: $ALGO"

# Запись в UCI (именно эти параметры читает ваш /etc/init.d/zram)
uci set system.@system[0].zram_size_mb="$ZRAM_SIZE"
uci set system.@system[0].zram_comp_algo="$ALGO"
uci commit system

# Перезапуск сервиса
/etc/init.d/zram restart

echo -e "\nОптимизация завершена!"
