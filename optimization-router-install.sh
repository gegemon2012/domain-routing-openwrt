#!/bin/sh

# 1. Определение количества ядер
# Используем /proc/cpuinfo, так как nproc может быть не установлен
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
echo "Устройство: обнаружено ядер - $CPU_CORES"

# Обновляем пакеты
opkg update

# 2. Настройка IRQ Balance (только для 2+ ядер)
if [ "$CPU_CORES" -ge 2 ]; then
    echo "Многоядерная система. Установка irqbalance..."
    opkg install irqbalance luci-app-irqbalance
    /etc/init.d/irqbalance enable
    /etc/init.d/irqbalance start
else
    echo "Одноядерная система. Пропуск irqbalance."
fi

# 3. Установка компонентов zram
echo "Установка zram и библиотек сжатия (zstd, lz4)..."
opkg install kmod-zram zram-swap kmod-lib-lz4 kmod-lib-zstd

# 4. Расчет памяти и настройка UCI
# Берем данные из meminfo (там значения в kB)
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Считаем 50% от RAM и переводим в MB: (kB / 1024) / 2
# Пример: 4GB RAM (4000000 / 1024 / 2) = ~1953 MB
ZRAM_SIZE_MB=$(( MEM_TOTAL_KB / 2048 ))

echo "Настройка zram: алгоритм ZSTD, размер $ZRAM_SIZE_MB MB"

# Привязываемся к структуре вашего системного конфига
uci set system.@system[0].zram_size_mb="$ZRAM_SIZE_MB"
uci set system.@system[0].zram_comp_algo='zstd'
uci set system.@system[0].zram_priority='100'

# Сохраняем настройки
uci commit system

# 5. Перезапуск сервиса
echo "Перезапуск сервиса zram..."
/etc/init.d/zram stop
# Небольшая пауза для корректного освобождения устройства
sleep 2
/etc/init.d/zram start

echo "----------------------------------------"
echo "Оптимизация завершена!"
# Вывод статуса из вашего скрипта
/etc/init.d/zram status
