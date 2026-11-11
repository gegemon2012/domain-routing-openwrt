#!/bin/sh

echo "=== RECURSIVE DNS & NTP SETUP (ROBUST) ==="

# 1. Подготовка NTP
sed -i '/time.cloudflare.com/d; /time.google.com/d; /ntp.yandex.ru/d' /etc/hosts 2>/dev/null
echo "162.159.200.1 time.cloudflare.com" >> /etc/hosts
echo "216.239.35.0 time.google.com" >> /etc/hosts
echo "213.180.193.1 ntp.yandex.ru" >> /etc/hosts

uci -q del_list system.ntp.server
uci add_list system.ntp.server='ntp.yandex.ru'
uci add_list system.ntp.server='ntp1.vniiftri.ru'
uci add_list system.ntp.server='0.ru.pool.ntp.org'
uci add_list system.ntp.server='time.google.com'
uci add_list system.ntp.server='time.cloudflare.com'
uci set system.ntp.enabled='1'
uci commit system
/etc/init.d/sysntpd restart 2>/dev/null

echo "[1/5] NTP настроен."

# 2. Установка пакетов с таймером ожидания 15 секунд
echo "[2/5] Установка пакетов..."
echo "[?] Нажмите ЛЮБУЮ клавишу в течение 15 сек, чтобы ОТМЕНИТЬ установку пакетов."

# Используем /dev/tty, чтобы read корректно считывал нажатия с клавиатуры даже при запуске через curl/sh
if read -t 15 -n 1 -r < /dev/tty 2>/dev/null; then
    echo -e "\n[!] Установка пакетов отменена пользователем."
else
    echo -e "\n[+] Время ожидания истекло (или нет терминала). Продолжаем установку..."
    opkg update
    opkg install unbound-daemon luci-app-unbound unbound-anchor \
                 https-dns-proxy luci-app-https-dns-proxy || {
        echo "[!] Ошибка установки пакетов. Проверьте интернет-соединение."
        exit 1
    }
fi

# 3. Настройка постоянного хранения root.key и Unbound
echo "[3/5] Настройка Unbound и постоянного root.key..."

mkdir -p /etc/unbound
chown -R unbound:unbound /etc/unbound 2>/dev/null

# Генерация / обновление root.key в постоянную память (/etc/unbound)
unbound-anchor -a /etc/unbound/root.key || echo "[!] Использован встроенный root key"

# Конфигурация Unbound (форвардер через локальные DoH прокси)
uci -q delete unbound.@unbound[0]
uci add unbound unbound
uci set unbound.@unbound[0].enabled='1'
uci set unbound.@unbound[0].validator='1'
uci set unbound.@unbound[0].port='5353'
uci set unbound.@unbound[0].listen_port='5353'
uci set unbound.@unbound[0].localservice='1'
uci set unbound.@unbound[0].recursion='passive'

uci add_list unbound.@unbound[0].unbound_conf='server:'
uci add_list unbound.@unbound[0].unbound_conf='auto-trust-anchor-file: "/etc/unbound/root.key"'
uci add_list unbound.@unbound[0].unbound_conf='forward-zone:'
uci add_list unbound.@unbound[0].unbound_conf='name: "."'
uci add_list unbound.@unbound[0].unbound_conf='forward-first: no'
uci add_list unbound.@unbound[0].unbound_conf='forward-addr: 127.0.0.1@5053'
uci add_list unbound.@unbound[0].unbound_conf='forward-addr: 127.0.0.1@5054'
uci commit unbound

echo "[3/5] Unbound настроен."

# 4. Настройка https-dns-proxy (с раздельными bootstrap-серверами)
echo "[4/5] Настройка https-dns-proxy (DoH)..."

# Очистка старых конфигураций https-dns-proxy
while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done

# Экземпляр 1: Cloudflare (порт 5053) — бутстрап через Cloudflare и Quad9
uci add https-dns-proxy https-dns-proxy
uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='1.1.1.1,9.9.9.9'
uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://cloudflare-dns.com/dns-query'
uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5053'

# Экземпляр 2: Google (порт 5054) — бутстрап через Google и OpenDNS
uci add https-dns-proxy https-dns-proxy
uci set https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='8.8.8.8,208.67.222.222'
uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://dns.google/dns-query'
uci set https-dns-proxy.@https-dns-proxy[-1].listen_addr='127.0.0.1'
uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5054'

uci commit https-dns-proxy

# 5. Настройка Dnsmasq
echo "[5/5] Настройка цепочки Dnsmasq..."
uci -q delete dhcp.@dnsmasq[0].server
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci commit dhcp

# Перезапуск всех сервисов
/etc/init.d/https-dns-proxy enable
/etc/init.d/https-dns-proxy restart
/etc/init.d/unbound restart
/etc/init.d/dnsmasq restart

echo "=== ГОТОВО! Схема успешно применена ==="
echo "Проверка работы DNS встроенным nslookup:"
sleep 2
nslookup google.com 127.0.0.1
echo "   date                  # время"
echo "   nslookup google.com   # DNS"
echo "   logread | tail -50    # логи при проблемах"
