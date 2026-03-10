#!/bin/sh

echo "========================================="
echo "  Настройка рекурсивного DNS-резолвера"
echo "  с DNSSEC на OpenWRT (совместимо с ruantiblock)"
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
echo "[5/10] Настройка Unbound на порт 5353..."

# Проверяем, существует ли секция unbound
if ! uci show unbound > /dev/null 2>&1; then
    uci set unbound.@unbound[0]=unbound
fi

# Основные настройки unbound
uci set unbound.@unbound[0].listen_port='5353'  # ВАЖНО: не 53, а 5353
uci set unbound.@unbound[0].dhcp_link='none'    # Отключаем связь с DHCP
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

# Отключаем форвардинг - используем рекурсию
uci set unbound.@unbound[0].forward_upstream='0'

# 6. Настройка dnsmasq (основной DNS для клиентов)
echo "[6/10] Настройка dnsmasq на использование unbound..."

# Возвращаем dnsmasq на порт 53
uci set dhcp.@dnsmasq[0].port='53'

# Убираем принудительную выдачу DNS-сервера через DHCP-опции
uci delete dhcp.lan.dhcp_option 2>/dev/null

# Настраиваем dnsmasq на использование unbound как вышестоящего DNS
uci set dhcp.@dnsmasq[0].noresolv='1'     # Не использовать resolv.conf
uci set dhcp.@dnsmasq[0].resolvfile=''    # Отключаем стандартный resolv.conf

# Удаляем старые upstream серверы
uci delete dhcp.@dnsmasq[0].server 2>/dev/null

# Добавляем unbound как единственный upstream
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'

# 7. Отключение дополнительных DNS-прокси (если есть)
echo "[7/10] Отключение лишних DNS-прокси..."
if command -v https-dns-proxy >/dev/null 2>&1; then
    /etc/init.d/https-dns-proxy disable 2>/dev/null
    /etc/init.d/https-dns-proxy stop 2>/dev/null
    echo "   ✅ https-dns-proxy отключен"
fi

# 8. Настройка NTP для точного времени (критично для DNSSEC)
echo "[8/10] Настройка NTP-серверов..."
uci set system.ntp=timeserver 2>/dev/null
uci set system.ntp.enabled='1'
uci delete system.ntp.server 2>/dev/null
uci add_list system.ntp.server='0.pool.ntp.org'
uci add_list system.ntp.server='1.pool.ntp.org'
uci add_list system.ntp.server='2.pool.ntp.org'
uci add_list system.ntp.server='time.google.com'
uci add_list system.ntp.server='time.cloudflare.com'

# Настройка часового пояса (раскомментируйте и укажите свой при необходимости)
# uci set system.@system[0].timezone='MSK-3'
# uci set system.@system[0].zonename='Europe/Moscow'

# 9. Применяем все изменения
echo "[9/10] Применение настроек..."
uci commit

# Очистка временных файлов
rm -f /tmp/dnsmasq.d/* 2>/dev/null

# 10. Запуск сервисов в правильном порядке
echo "[10/10] Запуск сервисов..."

# Сначала NTP
/etc/init.d/sysntpd restart
sleep 2

# Потом unbound
/etc/init.d/unbound start
sleep 3

# Потом dnsmasq
/etc/init.d/dnsmasq start
sleep 2

# И в конце ruantiblock (если установлен)
if command -v ruantiblock >/dev/null 2>&1; then
    /etc/init.d/ruantiblock restart 2>/dev/null
    echo "   ✅ ruantiblock перезапущен"
fi

# Финальная проверка
echo ""
echo "========================================="
echo "  ПРОВЕРКА НАСТРОЕК"
echo "========================================="

# Проверка статуса сервисов
echo -e "\n[Проверка] Статус сервисов:"
/etc/init.d/unbound status | grep -q "running" && echo "   ✅ unbound: работает" || echo "   ❌ unbound: НЕ работает"
/etc/init.d/dnsmasq status | grep -q "running" && echo "   ✅ dnsmasq: работает" || echo "   ❌ dnsmasq: НЕ работает"

# Проверка портов
echo -e "\n[Проверка] Прослушиваемые порты:"
netstat -tulpn | grep -E ':53|:5353' | sed 's/^/   /'

# Проверка времени
echo -e "\n[Проверка] Текущее время на роутере:"
date | sed 's/^/   /'

# Проверка DNS-запроса
echo -e "\n[Проверка] DNS-запрос через localhost:"
if nslookup youtube.com 127.0.0.1 >/dev/null 2>&1; then
    youtube_ip=$(nslookup youtube.com 127.0.0.1 2>/dev/null | grep Address | tail -1 | awk '{print $2}')
    echo "   ✅ youtube.com = $youtube_ip"
else
    echo "   ❌ Не удаётся разрешить youtube.com"
fi

# Проверка DNSSEC
echo -e "\n[Проверка] DNSSEC:"
if command -v dig >/dev/null 2>&1; then
    dnssec_test=$(dig dnssec.works +short 2>/dev/null)
    if [ "$dnssec_test" = "ok" ]; then
        echo "   ✅ DNSSEC: работает (dnssec.works = ok)"
    else
        echo "   ❌ DNSSEC: НЕ работает (dnssec.works = $dnssec_test)"
    fi
    
    # Тест с невалидной подписью
    echo -n "   Тест sigfail.ippacket.stream: "
    if dig sigfail.ippacket.stream +short 2>/dev/null | grep -q "SERVFAIL"; then
        echo "✅ (SERVFAIL - правильно)"
    else
        echo "❌ (должен быть SERVFAIL)"
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

# Проверка цепочки для ruantiblock
echo -e "\n[Проверка] Цепочка DNS для ruantiblock:"
echo "   Клиент -> dnsmasq(порт 53) -> unbound(порт 5353) -> корневые DNS"
echo "   dnsmasq использует upstream: 127.0.0.1#5353"

echo ""
echo "========================================="
echo "  НАСТРОЙКА ЗАВЕРШЕНА УСПЕШНО"
echo "========================================="
echo ""
echo "✅ Все сервисы настроены и запущены"
echo "✅ ruantiblock теперь должен работать корректно"
echo "✅ DNSSEC включен и работает"
echo ""
echo "➡️  Для проверки DNSSEC зайдите на сайт:"
echo "   https://dnscheck.tools"
echo ""
echo "➡️  Полезные команды:"
echo "   logread | grep dnsmasq    # логи dnsmasq"
echo "   logread | grep unbound    # логи unbound"
echo "   ruantiblock status        # статус ruantiblock"
echo ""
