#!/bin/sh

# 1. Проверка процессора и IRQ Balance
echo "--- Проверка процессора ---"
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
echo "Обнаружено ядер: $CPU_CORES"

if [ "$CPU_CORES" -gt 1 ]; then
    echo "Многоядерный процессор. Установка irqbalance..."
    opkg update
    opkg install irqbalance luci-app-irqbalance
    /etc/init.d/irqbalance enable
    /etc/init.d/irqbalance start
    echo "[OK] Irqbalance установлен и запущен."
else
    echo "Одноядерный процессор. Irqbalance не требуется."
fi

# 2. Установка и настройка ZRAM
echo ""
echo "--- Настройка ZRAM ---"
opkg update
opkg install zram-swap luci-app-zram-swap kmod-zram

# Определяем лучший алгоритм сжатия
# Проверяем наличие современных алгоритмов в порядке приоритета
if grep -q "zstd" /sys/block/zram0/comp_algorithm 2>/dev/null; then
    ALGO="zstd"
elif grep -q "lz4" /sys/block/zram0/comp_algorithm 2>/dev/null; then
    ALGO="lz4"
else
    ALGO="lzo"
fi

echo "Выбран алгоритм сжатия: $ALGO"

# Прописываем настройки в UCI (которые подхватит ваш /etc/init.d/zram)
uci set system.@system[0].zram_comp_algo="$ALGO"
# Установим размер zram в 50% от ОЗУ (можно поменять)
uci set system.@system[0].zram_size_mb="$(($(free -m | awk '/Mem:/ {print $2}') / 2))"
uci commit system

/etc/init.d/zram enable
/etc/init.d/zram restart
echo "[OK] ZRAM настроен и запущен."

# 3. Управление IPv6
echo ""
echo "--- Управление IPv6 ---"
echo "1) Отключить IPv6 (рекомендуется при отсутствии поддержки провайдером)"
echo "2) Включить IPv6 (стандартные настройки)"
echo "3) Пропустить"
printf "Ваш выбор: "
read ipv6_choice

case "$ipv6_choice" in
    1)
        echo "Отключаю IPv6..."
        if uci get network.wan6 >/dev/null 2>&1; then uci delete network.wan6; fi
        uci set dhcp.lan.ra='disabled'
        uci set dhcp.lan.dhcpv6='disabled'
        uci set dhcp.lan.ra_management='0'
        /etc/init.d/odhcpd stop
        /etc/init.d/odhcpd disable
        uci commit
        /etc/init.d/network restart
        echo "[OK] IPv6 отключен."
        ;;
    2)
        echo "Включаю IPv6..."
        uci set network.wan6=interface
        uci set network.wan6.proto='dhcpv6'
        uci set network.wan6.device='@wan'
        uci set dhcp.lan.ra='server'
        uci set dhcp.lan.dhcpv6='server'
        uci set dhcp.lan.ra_management='1'
        /etc/init.d/odhcpd enable
        /etc/init.d/odhcpd start
        uci commit
        /etc/init.d/network restart
        echo "[OK] IPv6 включен."
        ;;
    *)
        echo "Изменения IPv6 пропущены."
        ;;
esac

echo ""
echo "Оптимизация завершена успешно!"
