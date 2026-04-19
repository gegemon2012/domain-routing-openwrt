#!/bin/sh

# 1. IPv6 Меню (с таймером 10 секунд)
echo -e "\n--- Шаг 1: IPv6 ---"
echo "1) Полностью отключить (убрать ошибки в логах и задержки в браузере)"
echo "2) Включить (стандартные настройки)"
echo "3) Пропустить"

# Таймер: если за 10 секунд выбор не сделан, скрипт идет дальше
printf "Выбор (тайм-аут 10 сек): "
if read -t 10 choice; then
    case "$choice" in
        1)
            echo "Отключение IPv6 и очистка ULA префикса..."
            uci -q delete network.wan6
            uci set dhcp.lan.ra='disabled'
            uci set dhcp.lan.dhcpv6='disabled'
            uci set dhcp.lan.ra_management='0'
            uci set network.globals.ula_prefix=''
            uci commit
            /etc/init.d/odhcpd stop
            /etc/init.d/odhcpd disable
            /etc/init.d/network reload
            echo "✅ IPv6 полностью отключен, локальные адреса (ULA) удалены."
            ;;
        2)
            echo "Включение IPv6..."
            uci set network.wan6=interface
            uci set network.wan6.proto='dhcpv6'
            uci set network.wan6.device='@wan'
            [ -z "$(uci get network.globals.ula_prefix 2>/dev/null)" ] && uci set network.globals.ula_prefix='fd00::/48'
            uci set dhcp.lan.ra='server'
            uci set dhcp.lan.dhcpv6='server'
            uci set dhcp.lan.ra_management='1'
            uci commit
            /etc/init.d/odhcpd enable
            /etc/init.d/odhcpd start
            /etc/init.d/network reload
            echo "✅ IPv6 включен."
            ;;
        *)
            echo "Пропущено."
            ;;
    esac
else
    echo -e "\nВремя вышло. Настройка IPv6 пропущена автоматически."
fi

# 2. Процессор и irqbalance
echo -e "\n--- Шаг 2: Проверка CPU и IRQ ---"
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
if [ "$CPU_CORES" -gt 1 ]; then
    echo "Ядер: $CPU_CORES. Установка irqbalance..."
    opkg update
    opkg install irqbalance luci-app-irqbalance
    
    # ПРИНУДИТЕЛЬНАЯ ИНИЦИАЛИЗАЦИЯ
    # Иногда Luci-приложение блокирует автозапуск, пока не будет создан конфиг
    [ ! -f /etc/config/irqbalance ] && touch /etc/config/irqbalance
    
    # Включаем через стандартный скрипт
    /etc/init.d/irqbalance enable
    
    # Если сервис все равно "Disabled" в Luci, используем прямой запуск
    /etc/init.d/irqbalance start
    
    # Проверка: если не запустился, пробуем форсировать через UCI
    uci set irqbalance.irqbalance.enabled='1'
    uci commit irqbalance
    
    echo "✅ irqbalance активирован."
else
    echo "Одноядерный CPU. Пропуск."
fi

# 3. ZRAM (50% от ОЗУ)
echo -e "\n--- Шаг 3: Настройка ZRAM (50%) ---"
opkg install zram-swap kmod-zram

TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_MB=$(( TOTAL_RAM_KB / 1024 ))
ZRAM_SIZE=$(( TOTAL_RAM_MB / 2 ))
[ "$ZRAM_SIZE" -gt 2048 ] && ZRAM_SIZE=2048

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

uci set system.@system[0].zram_size_mb="$ZRAM_SIZE"
uci set system.@system[0].zram_comp_algo="$ALGO"
/etc/init.d/zram restart

# 4. Устанавливаем период (frequency) Watchdog в 50 секунд
uci set system.@system[0].watchdog_period='50'

# 5. Устанавливаем таймаут (timeout) Watchdog в 300 секунд
uci set system.@system[0].watchdog_timeout='300'

# Сохраняем изменения
uci commit system

echo -e "\nОптимизация завершена!"
