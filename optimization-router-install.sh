#!/bin/sh

# --- Шаг 1: IPv6 ---
echo -e "\n--- Шаг 1: Настройка IPv6 ---"
echo "Выберите действие:"
echo "1) Отключить IPv6"
echo "2) Включить IPv6"
echo "3) Пропустить (тайм-аут 15 сек)"
printf "Ваш выбор: "

# Используем </dev/tty, чтобы read точно перехватил ввод с клавиатуры
if read -t 15 choice < /dev/tty; then
    case "$choice" in
        1)
            uci -q delete network.wan6
            uci set dhcp.lan.ra='disabled'
            uci set dhcp.lan.dhcpv6='disabled'
            uci set network.globals.ula_prefix=''
            uci commit network; uci commit dhcp
            /etc/init.d/odhcpd disable
            /etc/init.d/network reload
            echo "✅ IPv6 полностью отключен." ;;
        2)
            uci set network.wan6=interface
            uci set network.wan6.proto='dhcpv6'
            uci set dhcp.lan.ra='server'
            uci commit network; uci commit dhcp
            /etc/init.d/odhcpd enable
            /etc/init.d/network reload
            echo "✅ IPv6 включен." ;;
        *)
            echo "[-] Пропущено (неверный ввод)." ;;
    esac
else
    echo -e "\n[!] Тайм-аут. Настройка IPv6 пропущена."
fi

# --- Шаг 2: Установка пакетов (irqbalance, zram) ---
echo -e "\n--- Шаг 2: Установка пакетов ---"
echo "Нажмите ЛЮБУЮ клавишу за 15 сек, чтобы ПРОПУСТИТЬ установку пакетов."
if read -t 15 -n 1 < /dev/tty; then
    echo -e "\n[!] Установка пропущена."
else
    echo -e "\n[+] Обновление репозиториев и установка..."
    opkg update
    opkg install irqbalance luci-app-irqbalance zram-swap kmod-zram
fi

# --- Шаг 3: Тонкая настройка системы ---
echo -e "\n--- Шаг 3: Оптимизация системы ---"

# Настройка IRQ (распределение нагрузки на ядра)
if [ -f /etc/config/irqbalance ]; then
    uci set irqbalance.irqbalance.enabled='1'
    uci commit irqbalance
    /etc/init.d/irqbalance enable
    /etc/init.d/irqbalance start
fi

# Настройка ZRAM (50% RAM, lzo для скорости)
TOTAL_RAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
ZRAM_MB=$(( TOTAL_RAM / 2048 ))
[ "$ZRAM_MB" -gt 2048 ] && ZRAM_MB=2048
uci set system.@system[0].zram_size_mb="$ZRAM_MB"
uci set system.@system[0].zram_comp_algo="lzo"

# Настройка Watchdog
uci set system.@system[0].watchdog_period='50'
uci set system.@system[0].watchdog_timeout='300'
uci commit system

# --- Шаг 4: Hardware Flow Offloading ---
echo -e "\n--- Шаг 4: Аппаратное ускорение (Flow Offloading) ---"
# Включаем программное и аппаратное ускорение трафика
uci set firewall.@defaults[0].flow_offloading='1'
uci set firewall.@defaults[0].flow_offloading_hw='1'
uci commit firewall
/etc/init.d/firewall restart

/etc/init.d/zram restart
echo "✅ Оптимизация завершена! Проверьте статус в LuCI (Firewall -> Routing)."
