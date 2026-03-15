#!/bin/sh

# 1. Проверка ядер
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
echo "Обнаружено ядер: $CPU_CORES"

opkg update

if [ "$CPU_CORES" -ge 2 ]; then
    echo "Установка irqbalance для $CPU_CORES ядер..."
    opkg install irqbalance luci-app-irqbalance
    /etc/init.d/irqbalance enable
    /etc/init.d/irqbalance start
fi

# 2. Установка модулей zram
echo "Установка модулей zram и библиотек сжатия..."
opkg install kmod-zram zram-swap kmod-lib-lz4 kmod-lib-zstd

# 3. Настройка через системный конфиг (как требует ваш /etc/init.d/zram)
echo "Применение настроек в system.@system[0]..."

# Вычисляем 50% оперативной памяти для zram
total_mem=$(free -m | awk '/Mem:/ {print $2}')
zram_size=$((total_mem / 2))

# Устанавливаем параметры в существующую секцию system
uci set system.@system[0].zram_size_mb="$zram_size"
uci set system.@system[0].zram_comp_algo='zstd'
uci set system.@system[0].zram_priority='100'

uci commit system

# 4. Перезапуск
echo "Перезапуск zram с новыми параметрами ($zram_size MB, zstd)..."
/etc/init.d/zram stop
/etc/init.d/zram start

echo "Готово. Проверка статуса:"
/etc/init.d/zram status
