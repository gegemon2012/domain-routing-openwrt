#!/bin/sh

# 1. IPv6 Меню (с правкой ULA для устранения задержек)
echo -e "\n--- Шаг 1: IPv6 ---"
echo "1) Полностью отключить (убрать ошибки в логах и задержки в браузере)"
echo "2) Включить (стандартные настройки)"
echo "3) Пропустить"
printf "Выбор: "
read choice

case "$choice" in
    1)
        echo "Отключение IPv6 и очистка ULA префикса..."
        # Удаляем интерфейс wan6
        uci -q delete network.wan6
        
        # Отключаем анонсы и DHCPv6 на LAN
        uci set dhcp.lan.ra='disabled'
        uci set dhcp.lan.dhcpv6='disabled'
        uci set dhcp.lan.ra_management='0'
        
        # ВАЖНО: Очищаем ULA префикс, чтобы роутер не создавал адреса fd45:...
        uci set network.globals.ula_prefix=''
        
        uci commit
        /etc/init.d/odhcpd stop
        /etc/init.d/odhcpd disable
        /etc/init.d/network restart
        echo "✅ IPv6 полностью отключен, локальные адреса (ULA) удалены."
        ;;
    2)
        echo "Включение IPv6..."
        uci set network.wan6=interface
        uci set network.wan6.proto='dhcpv6'
        uci set network.wan6.device='@wan'
        
        # Возвращаем стандартный префикс (если был пустой)
        [ -z "$(uci get network.globals.ula_prefix 2>/dev/null)" ] && uci set network.globals.ula_prefix='fd00::/48'
        
        uci set dhcp.lan.ra='server'
        uci set dhcp.lan.dhcpv6='server'
        uci set dhcp.lan.ra_management='1'
        
        uci commit
        /etc/init.d/odhcpd enable
        /etc/init.d/odhcpd start
        /etc/init.d/network restart
        echo "✅ IPv6 включен."
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
