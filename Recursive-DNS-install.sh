#!/bin/sh

echo "========================================="
echo "  Настройка рекурсивного DNS-резолвера"
echo "  с DNSSEC на OpenWRT"
echo "========================================="
echo ""

# 1. Обновление списка пакетов
echo "[1/10] Обновление списка пакетов..."
opkg update

# 2. Установка необходимых пакетов
echo "[2/10] Установка пакетов..."
opkg install unbound-daemon luci-app-unbound bind-dig drill

# 3. Сохраняем локальные настройки
echo "[3/10] Сохранение настроек сети..."
lan_domain=$(uci get dhcp.@dnsmasq[0].domain 2>/dev/null || echo "lan")
lan_address=$(uci get network.lan.ipaddr)
router_name=$(uci get system.@system[0].hostname)
echo "   Домен: $lan_domain"
echo "   IP роутера: $lan_address"
echo "   Имя роутера: $router_name"

# 4. Перенос DNS-функции dnsmasq на другой порт
echo "[4/10] Перенос dnsmasq на порт 53535..."
uci set dhcp.@dnsmasq[0].port=53535

# 5. Настройка DHCP-опций (удаляем старые, добавляем правильные)
echo "[5/10] Настройка DHCP-опций..."
uci delete dhcp.lan.dhcp_option 2>/dev/null
uci add_list dhcp.lan.dhcp_option="6,$lan_address"

# 6. Настройка NTP для точного времени (критично для DNSSEC)
echo "[6/10] Настройка NTP-серверов..."
uci set system.ntp=timeserver 2>/dev/null
uci set system.ntp.enabled='1'
uci delete system.ntp.server 2>/dev/null
uci add_list system.ntp.server='0.pool.ntp.org'
uci add_list system.ntp.server='1.pool.ntp.org'
uci add_list system.ntp.server='2.pool.ntp.org'
uci add_list system.ntp.server='time.google.com'
uci add_list system.ntp.server='time.cloudflare.com'

# Настройка часового пояса (по желанию - замените на свой)
# uci set system.@system[0].timezone='MSK-3'
# uci set system.@system[0].zonename='Europe/Moscow'

# 7. Настройка Unbound (рекурсивный резолвер с DNSSEC)
echo "[7/10] Настройка Unbound..."

# Проверяем, существует ли секция unbound
if ! uci show unbound > /dev/null 2>&1; then
    uci set unbound.@unbound[0]=unbound
fi

# Основные настройки
uci set unbound.@unbound[0].dhcp_link='dnsmasq'
uci set unbound.@unbound[0].listen_port='53'
uci set unbound.@unbound[0].domain="$lan_domain"
uci set unbound.@unbound[0].domain_type='static'

# Включаем DNSSEC (самое важное!)
uci set unbound.@unbound[0].validator='1'

# Включаем управление
uci set unbound.@unbound[0].unbound_control='1'

# Защита от DNS-реббиндинга
uci set unbound.@unbound[0].rebind_protection='1'

# Добавляем записи для самого роутера
uci set unbound.@unbound[0].add_local_fqdn='1'
uci set unbound.@unbound[0].add_wan_fqdn='1'

# 8. Применяем все изменения
echo "[8/10] Применение настроек..."
uci commit

# 9. Перезапуск сервисов
echo "[9/10] Перезапуск сервисов..."

# Останавливаем старые процессы
killall dnsmasq 2>/dev/null
rm -f /var/etc/dnsmasq.conf.cfg* 2>/dev/null

# Запускаем сервисы
/etc/init.d/sysntpd restart
sleep 2
/etc/init.d/dnsmasq restart
sleep 2
/etc/init.d/unbound restart
sleep 3

# 10. Финальная проверка
echo ""
echo "========================================="
echo "  ПРОВЕРКА НАСТРОЕК"
echo "========================================="

# Проверка статуса сервисов
echo -e "\n[10/10] Статус сервисов:"
/etc/init.d/dnsmasq status | grep -q "running" && echo "✅ dnsmasq: работает" || echo "❌ dnsmasq: НЕ работает"
/etc/init.d/unbound status | grep -q "running" && echo "✅ unbound: работает" || echo "❌ unbound: НЕ работает"

# Проверка портов
echo -e "\nПрослушиваемые порты:"
netstat -tulpn | grep -E ':53|:53535' | sed 's/^/   /'

# Проверка времени
echo -e "\nТекущее время на роутере:"
date | sed 's/^/   /'

# Проверка DNSSEC
echo -e "\nПроверка DNSSEC:"
if command -v dig >/dev/null 2>&1; then
    dnssec_test=$(dig dnssec.works +short 2>/dev/null)
    if [ "$dnssec_test" = "ok" ]; then
        echo "✅ DNSSEC: работает (dnssec.works = ok)"
    else
        echo "❌ DNSSEC: НЕ работает (dnssec.works = $dnssec_test)"
    fi
    
    # Тест с невалидной подписью
    echo -n "   Тест sigfail.ippacket.stream: "
    if dig sigfail.ippacket.stream +short 2>/dev/null | grep -q "SERVFAIL"; then
        echo "✅ (SERVFAIL - правильно)"
    else
        echo "❌ (должен быть SERVFAIL)"
    fi
else
    echo "⚠️ dig не установлен, пропускаем проверку DNSSEC"
fi

# Локальное имя
echo -e "\nПроверка локального имени:"
if nslookup "$router_name.$lan_domain" 127.0.0.1 >/dev/null 2>&1; then
    ip_addr=$(nslookup "$router_name.$lan_domain" 127.0.0.1 2>/dev/null | grep Address | tail -1 | awk '{print $2}')
    echo "✅ $router_name.$lan_domain = $ip_addr"
else
    echo "❌ Не удаётся разрешить $router_name.$lan_domain"
fi

echo ""
echo "========================================="
echo "  НАСТРОЙКА ЗАВЕРШЕНА"
echo "========================================="
echo ""
echo "➡️  Для проверки DNSSEC зайдите на сайт:"
echo "   https://dnscheck.tools"
echo ""
echo "➡️  Команды для ручной проверки:"
echo "   dig sigok.ippacket.stream +dnssec | grep flags"
echo "   dig sigfail.ippacket.stream"
echo ""
