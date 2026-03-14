#!/bin/sh

echo "========================================="
echo "  Настройка рекурсивного DNS-резолвера"
echo "  с DNSSEC на OpenWRT (УНИВЕРСАЛЬНЫЙ)"
echo "========================================="
echo ""

# 1. Обновление списка пакетов
echo "[1/10] Обновление списка пакетов..."
opkg update

# 2. Установка необходимых пакетов
echo "[2/10] Установка пакетов..."
opkg install unbound-daemon luci-app-unbound bind-dig drill

# 3. Остановка DNS-сервисов перед настройкой
echo "[3/10] Остановка DNS-сервисов..."
/etc/init.d/dnsmasq stop 2>/dev/null
/etc/init.d/unbound stop 2>/dev/null
/etc/init.d/https-dns-proxy stop 2>/dev/null
killall dnsmasq unbound https-dns-proxy 2>/dev/null
sleep 2

# 4. Сохраняем локальные настройки
echo "[4/10] Сохранение настроек сети..."
lan_domain=$(uci get dhcp.@dnsmasq[0].domain 2>/dev/null || echo "lan")
lan_address=$(uci get network.lan.ipaddr)
router_name=$(uci get system.@system[0].hostname)
echo "   Домен: $lan_domain"
echo "   IP роутера: $lan_address"
echo "   Имя роутера: $router_name"

# 5. Настройка Unbound (рекурсивный резолвер на порту 5353)
echo "[5/10] Настройка Unbound..."
uci set unbound.@unbound[0].listen_port='5353'
uci set unbound.@unbound[0].rebind_protection='1'
uci set unbound.@unbound[0].dnssec='1'
uci set unbound.@unbound[0].validator='1'
uci set unbound.@unbound[0].unbound_control='1'
uci set unbound.@unbound[0].localservice='0'
# Разрешаем запросы из локальной сети
uci set unbound.@unbound[0].query_minimize='1'

# 6. Настройка локальной зоны для Unbound
echo "[6/10] Настройка локальной зоны..."
# Удаляем старые записи если есть
while uci delete unbound.@unbound_zone[0] 2>/dev/null; do :; done
# Создаем новую зону для локальных имен
uci add unbound unbound_zone
uci set unbound.@unbound_zone[-1].type='static'
uci set unbound.@unbound_zone[-1].zone_name="$lan_domain"
# Добавляем сам роутер в локальную зону Unbound
while uci delete unbound.@unbound_static[0] 2>/dev/null; do :; done
uci add unbound unbound_static
uci set unbound.@unbound_static[-1].name="$router_name"
uci set unbound.@unbound_static[-1].address="$lan_address"

uci commit unbound

# 7. Настройка dnsmasq (пересылка запросов в Unbound)
echo "[7/10] Привязка dnsmasq к Unbound..."
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].localservice='1'
uci del dhcp.@dnsmasq[0].server 2>/dev/null
uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5353"
uci commit dhcp

# 8. Очистка временных файлов DNS (важно для бесконфликтной работы)
echo "[8/10] Очистка кэша и старых конфигов..."
rm -f /tmp/dnsmasq.d/* 2>/dev/null

# 9. Применение настроек и запуск
echo "[9/10] Запуск сервисов..."
/etc/init.d/unbound enable
/etc/init.d/unbound restart
sleep 2
/etc/init.d/dnsmasq restart

# 10. УНИВЕРСАЛЬНЫЙ БЛОК: Совместимость с обходчиками блокировок
echo "[10/10] Проверка установленных дополнений..."

# Для ruantiblock
if command -v ruantiblock >/dev/null 2>&1; then
    echo "   🔎 Обнаружен ruantiblock. Перезапуск..."
    /etc/init.d/ruantiblock restart 2>/dev/null
    echo "   ✅ ruantiblock обновлен"
fi

# Для getdomains
if [ -x "/etc/init.d/getdomains" ]; then
    echo "   🔎 Обнаружен getdomains. Восстановление списков..."
    /etc/init.d/getdomains start
    sleep 3
    /etc/init.d/dnsmasq restart 2>/dev/null
    echo "   ✅ Списки getdomains восстановлены"
fi

# ФИНАЛЬНЫЕ ПРОВЕРКИ
echo -e "\n[Проверка] Тестирование DNSSEC..."
if command -v dig >/dev/null 2>&1; then
    # Тест валидной подписи
    echo -n "   Тест cloudflare.com (DNSSEC): "
    if dig cloudflare.com +dnssec 2>/dev/null | grep -q "ad;"; then
        echo "✅ (AD флаг получен)"
    else
        echo "❌ (флаг AD отсутствует)"
    fi
    
    # Тест невалидной подписи
    echo -n "   Тест sigfail.ippacket.stream: "
    if dig sigfail.ippacket.stream +short 2>/dev/null | grep -q "SERVFAIL"; then
        echo "✅ (SERVFAIL - правильно)"
    else
        echo "❌ (ошибка - подпись должна быть невалидна)"
    fi
else
    echo "   ⚠️ dig не установлен, пропускаем проверку DNSSEC"
fi

# Проверка локального имени
echo -e "\n[Проверка] Локальное имя роутера:"
if nslookup "$router_name.$lan_domain" 127.0.0.1 >/dev/null 2>&1; then
    ip_addr=$(nslookup "$router_name.$lan_domain" 127.0.0.1 2>/dev/null | grep Address | tail -1 | awk '{print $2}')
    echo "   ✅ $router_name.$lan_domain = $ip_addr"
else
    echo "   ❌ Не удаётся разрешить $router_name.$lan_domain"
fi

echo ""
echo "========================================="
echo "  НАСТРОЙКА ЗАВЕРШЕНА УСПЕШНО"
echo "  Теперь ваш DNS рекурсивный и защищен,"
echo "  а списки обхода блокировок активны."
echo "========================================="
