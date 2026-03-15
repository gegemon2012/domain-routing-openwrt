#!/bin/sh

# 1. Проверка количества ядер процессора
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
echo "Обнаружено ядер: $CPU_CORES"

# Обновляем списки пакетов
opkg update

# 2. Настройка irqbalance (для 2+ ядер)
if [ "$CPU_CORES" -ge 2 ]; then
    echo "Многоядерный процессор. Установка irqbalance..."
    opkg install irqbalance luci-app-irqbalance
    /etc/init.d/irqbalance enable
    /etc/init.d/irqbalance start
else
    echo "Одноядерный процессор. Пропуск irqbalance."
fi

# 3. Установка компонентов zram
echo "Установка модулей zram и библиотек сжатия..."
opkg install kmod-zram zram-swap kmod-lib-lz4 kmod-lib-zstd

# 4. Расчет памяти и настройка UCI
echo "Настройка параметров в system.@system[0]..."

# Получаем объем RAM в килобайтах из /proc/meminfo
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Считаем 50% от объема и переводим в Мегабайты
# Делим на 1024 (в МБ) и еще на 2 (половина) = делим на 2048
ZRAM_SIZE_MB=$(( MEM_TOTAL_KB / 2048 ))

echo "Рассчитанный размер zram: $ZRAM_SIZE_MB MB"

# Устанавливаем параметры, которые использует ваш /etc/init.d/zram
uci set system.@system[0].zram_size_mb="$ZRAM_SIZE_MB"
uci set system.@system[0].zram_comp_algo='zstd'
uci set system.@system[0].zram_priority='100'

# Применяем изменения в конфиг
uci commit system

# 5. Перезапуск сервиса
echo "Перезагрузка zram для применения изменений..."
/etc/init.d/zram stop
sleep 2
/etc/init.d/zram start

echo "----------------------------------------"
echo "Оптимизация завершена успешно."
/etc/init.d/zram status
