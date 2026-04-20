#!/bin/sh

echo "=== RECURSIVE DNS & NTP FIX (FULL & OPTIMIZED) ==="

# 1. NTP Fix (Запись в hosts для старта при "холодном" DNS)
sed -i '/time.cloudflare.com/d; /time.google.com/d; /ntp.yandex.ru/d' /etc/hosts
echo "162.159.200.1 time.cloudflare.com" >> /etc/hosts
echo "216.239.35.0 time.google.com" >> /etc/hosts
echo "213.180.193.1 ntp.yandex.ru" >> /etc/hosts
echo "[1/4] IP адреса NTP добавлены в /etc/hosts."

# Настройка системного NTP через UCI
echo "Конфигурация NTP серверов..."
uci del system.ntp.server 2>/dev/null
uci add_list system.ntp.server='ntp.yandex.ru'
uci add_list system.ntp.server='ntp1.vniiftri.ru'
uci add_list system.ntp.server='0.ru.pool.ntp.org'
uci add_list system.ntp.server='time.google.com'
uci add_list system.ntp.server='time.cloudflare.com'
uci set system.ntp.enabled='1'
uci set system.ntp.enable_server='0'
uci commit system
/etc/init.d/sysntpd restart

# 2. Установка Unbound (с вашим таймером на 15 секунд)
DO_OPKG=1
echo "[?] Установить Unbound? Нажмите ЛЮБУЮ клавишу за 15 сек для ОТМЕНЫ."
if read -t 15 -n 1; then
    echo -e "\n[!] Шаг установки пропущен по запросу пользователя."
    DO_OPKG=0
else
    echo -e "\n[2/4] Обновление и установка Unbound..."
    opkg update
    opkg install unbound-daemon luci-app-unbound bind-dig unbound-anchor
fi

# 3. Настройка Unbound и DNSSEC
echo "[3/4] Настройка Unbound (Устранение Crash Loop)..."

# Удаляем файл, который мешает UCI-конфигурации (причина ошибки bind socket)
[ -f /etc/unbound/unbound.conf ] && mv /etc/unbound/unbound.conf /etc/unbound/unbound.conf.bak

# Временный DNS для скачивания ключей
echo "nameserver 77.88.8.8" > /tmp/resolv.conf.auto

mkdir -p /var/lib/unbound
echo "Генерация ключей DNSSEC..."
unbound-anchor -a /var/lib/unbound/root.key
sleep 1 

# КРИТИЧНО: Права доступа
chown -R unbound:unbound /var/lib/unbound
chmod 644 /var/lib/unbound/root.key 2>/dev/null

# Чистая настройка UCI
uci del unbound.@unbound[0] 2>/dev/null
uci add unbound unbound
uci set unbound.@unbound[0].validator='1' # DNSSEC включен
uci set unbound.@unbound[0].port='5353'
uci set unbound.@unbound[0].listen_port='5353'
uci set unbound.@unbound[0].localservice='1'
uci add_list unbound.@unbound[0].unbound_conf='auto-trust-anchor-file: "/var/lib/unbound/root.key"'
uci commit unbound

/etc/init.d/unbound restart

# 4. Привязка к Dnsmasq
echo "[4/4] Перенаправление Dnsmasq -> Unbound (5353)..."

# Очистка серверов без лишних уведомлений об ошибках
while uci get dhcp.@dnsmasq[0].server >/dev/null 2>&1; do
    uci del_list dhcp.@dnsmasq[0].server=$(uci get dhcp.@dnsmasq[0].server | head -n 1)
done

uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'
uci add_list dhcp.@dnsmasq[0].server='8.8.8.8' # Резерв для стабильности времени
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].cachesize='1000'
uci commit dhcp

/etc/init.d/unbound restart
/etc/init.d/dnsmasq restart

echo "=== ГОТОВО! Проверьте время (date) и DNS (nslookup google.com 127.0.0.1 5353) ==="
