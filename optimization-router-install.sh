#!/bin/sh

# --- Блок выбора IPv6 ---
echo -e "\n--- Шаг 1: IPv6 ---"
printf "1) Отключить, 2) Включить, 3) Пропустить (тайм-аут 10 сек): "
if read -t 10 choice; then
    case "$choice" in
        1)
            uci -q delete network.wan6
            uci set dhcp.lan.ra='disabled'
            uci set dhcp.lan.dhcpv6='disabled'
            uci set network.globals.ula_prefix=''
            uci commit; /etc/init.d/odhcpd disable; /etc/init.d/network reload
            echo "✅ IPv6 отключен." ;;
        2)
            uci set network.wan6=interface
            uci set network.wan6.proto='dhcpv6'
            uci set dhcp.lan.ra='server'
            uci commit; /etc/init.d/odhcpd enable; /etc/init.d/network reload
            echo "✅ IPv6 включен." ;;
    esac
fi

# --- Блок установки пакетов (с возможностью пропуска) ---
INSTALL_REQUIRED=1
echo -e "\n--- Шаг 2: Установка пакетов (irqbalance, zram) ---"
echo "Нажмите ЛЮБУЮ клавишу за 10 сек, чтобы ПРОПУСТИТЬ установку и обновление."
if read -t 10 -n 1; then
    echo -e "\n[!] Установка пропущена. Настраиваем только конфиги."
    INSTALL_REQUIRED=0
else
    echo -e "\n[+] Начинаем установку..."
    opkg update
    opkg install irqbalance luci-app-irqbalance zram-swap kmod-zram
fi

# --- Блок настройки UCI (выполняется всегда) ---
echo -e "\n--- Шаг 3: Тонкая настройка системы ---"

# Настройка IRQ
if [ -f /etc/config/irqbalance ]; then
    uci set irqbalance.irqbalance.enabled='1'
    uci commit irqbalance
    /etc/init.d/irqbalance enable
    /etc/init.d/irqbalance start
fi

# Настройка ZRAM (50% RAM)
TOTAL_RAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
ZRAM_MB=$(( TOTAL_RAM / 2048 ))
[ "$ZRAM_MB" -gt 2048 ] && ZRAM_MB=2048
uci set system.@system[0].zram_size_mb="$ZRAM_MB"
uci set system.@system[0].zram_comp_algo="lzo"

# Watchdog
uci set system.@system[0].watchdog_period='50'
uci set system.@system[0].watchdog_timeout='300'

uci commit system
/etc/init.d/zram restart
echo "✅ Оптимизация завершена!"
