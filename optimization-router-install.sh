#!/bin/sh

# 1. Проверка процессора и IRQ Balance
echo "--- Проверка процессора ---"
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
echo "Обнаружено ядер: $CPU_CORES"

if [ "$CPU_CORES" -gt 1 ]; then
    echo "Многоядерный процессор. Установка irqbalance..."
    opkg update
    # Пытаемся установить пакеты, если один не найден - не страшно
    opkg install irqbalance
    opkg install luci-app-irqbalance || echo "Предупреждение: luci-app-irqbalance не найден, пропущено."
    
    if [ -f /etc/init.d/irqbalance ]; then
        /etc/init.d/irqbalance enable
        /etc/init.d/irqbalance start
        echo "[OK] Irqbalance активирован."
    fi
fi

# 2. Настройка ZRAM
echo ""
echo "--- Настройка ZRAM ---"
opkg update
opkg install zram-swap kmod-zram
# Пакет luci может называться по-разному в разных версиях
opkg install luci-app-zram-swap || opkg install luci-i18n-zram-swap-ru || echo "Интерфейс Luci для ZRAM не найден."

# ОПРЕДЕЛЕНИЕ РАЗМЕРА (Безопасный метод)
# Берем общее кол-во памяти в Кб и переводим в Мб
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$(( TOTAL_RAM_KB / 1024 ))

# Устанавливаем ZRAM равным объему ОЗУ (но не более 4096Мб для стабильности)
ZRAM_SIZE=$TOTAL_RAM_MB
if [ "$ZRAM_SIZE" -gt 4096 ]; then
    ZRAM_SIZE=4096
fi

# ОПРЕДЕЛЕНИЕ АЛГОРИТМА
# Сначала создаем временное устройство, чтобы проверить доступные алгоритмы
modprobe zram 2>/dev/null
ALGO="lzo"
if [ -f /sys/block/zram0/comp_algorithm ]; then
    for a in zstd lz4 lzo; do
        if grep -q "$a" /sys/block/zram0/comp_algorithm; then
            ALGO=$a
            break
        fi
    done
fi

echo "Общий объем ОЗУ: $TOTAL_RAM_MB MiB"
echo "Выделено под ZRAM: $ZRAM_SIZE MiB"
echo "Выбран алгоритм: $ALGO"

# Запись в UCI
uci set system.@system[0].zram_size_mb="$ZRAM_SIZE"
uci set system.@system[0].zram_comp_algo="$ALGO"
uci commit system

# Перезапуск ZRAM через ваш скрипт /etc/init.d/zram
/etc/init.d/zram stop
sleep 2
/etc/init.d/zram start

# 3. Управление IPv6 (тот же блок)
echo ""
echo "--- Управление IPv6 ---"
echo "1) Отключить 2) Включить 3) Пропустить"
read ipv6_choice
case "$ipv6_choice" in
    1)
        if uci get network.wan6 >/dev/null 2>&1; then uci delete network.wan6; fi
        uci set dhcp.lan.ra='disabled'
        uci set dhcp.lan.dhcpv6='disabled'
        uci set dhcp.lan.ra_management='0'
        /etc/init.d/odhcpd stop
        /etc/init.d/odhcpd disable
        uci commit
        /etc/init.d/network restart
        ;;
esac

echo "Готово! Проверьте статус командой: /etc/init.d/zram status"
