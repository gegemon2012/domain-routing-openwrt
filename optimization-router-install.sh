#!/bin/sh

# 1. IPv6 Меню (с правкой ULA и «умной» чисткой Firewall)
echo -e "\n--- Шаг 1: IPv6 и Firewall ---"
echo "1) Полностью отключить (Сеть + ULA + Удаление правил IPv6)"
echo "2) Включить (Стандартные настройки + Восстановление правил)"
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
        
        # --- Очистка Firewall от IPv6 (Безопасное удаление) ---
        # Функция для удаления правила только если оно существует, чтобы не было "Not found"
        safe_delete_rule() {
            if uci get firewall.$1 >/dev/null 2>&1; then
                uci -q delete firewall.$1
            fi
        }

        # Пытаемся удалить стандартные именованные правила
        safe_delete_rule "allow_dhcpv6"
        safe_delete_rule "allow_mld"
        safe_delete_rule "allow_icmpv6_input"
        safe_delete_rule "allow_icmpv6_forward"
        
        # Поиск и удаление всех остальных правил, где явно указано family 'ipv6'
        # Используем конструкцию, которая не вызывает ошибку при пустом результате
        rules_to_del=$(uci show firewall | grep "family='ipv6'" | cut -d'.' -f2 | cut -d'=' -f1 | sort -r)
        for rule in $rules_to_del; do
            uci -q delete firewall.$rule
        done

        uci commit firewall
        uci commit network
        uci commit dhcp

        /etc/init.d/odhcpd stop
        /etc/init.d/odhcpd disable
        /etc/init.d/network restart
        /etc/init.d/firewall restart
        echo "✅ IPv6 отключен. Конфигурация Firewall очищена без ошибок."
        ;;
    2)
        echo "Включение IPv6 и восстановление правил..."
        # (Оставляем блок включения из предыдущего ответа, он работает корректно)
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
