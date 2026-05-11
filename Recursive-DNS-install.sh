#!/bin/sh

echo "=== RECURSIVE DNS & NTP FIX (OFFLINE-READY) ==="

# 1. Подготовка NTP
sed -i '/time.cloudflare.com/d; /time.google.com/d; /ntp.yandex.ru/d' /etc/hosts 2>/dev/null
echo "162.159.200.1 time.cloudflare.com" >> /etc/hosts
echo "216.239.35.0 time.google.com" >> /etc/hosts
echo "213.180.193.1 ntp.yandex.ru" >> /etc/hosts

# Настройка системного NTP
uci -q del_list system.ntp.server
uci add_list system.ntp.server='ntp.yandex.ru'
uci add_list system.ntp.server='ntp1.vniiftri.ru'
uci add_list system.ntp.server='0.ru.pool.ntp.org'
uci add_list system.ntp.server='time.google.com'
uci add_list system.ntp.server='time.cloudflare.com'
uci set system.ntp.enabled='1'
uci commit system
/etc/init.d/sysntpd restart 2>/dev/null

echo "[1/4] NTP настроен."

# 2. Установка пакетов
echo "[?] Установить пакеты? Нажмите ЛЮБУЮ клавишу за 15 сек для ОТМЕНЫ."
if read -t 15 -n 1; then
    echo -e "\n[!] Установка пакетов пропущена."
else
    echo -e "\n[2/4] Обновление и установка пакетов..."
    opkg update
    opkg install unbound-daemon luci-app-unbound bind-dig unbound-anchor \
                 https-dns-proxy luci-app-https-dns-proxy
fi

# 3. Настройка Unbound
echo "[3/4] Настройка Unbound + DNSSEC..."

[ -f /etc/unbound/unbound.conf ] && mv /etc/unbound/unbound.conf /etc/unbound/unbound.conf.bak 2>/dev/null

mkdir -p /var/lib/unbound
chown -R unbound:unbound /var/lib/unbound 2>/dev/null

# Инициализация root key (DNSSEC)
unbound-anchor -a /var/lib/unbound/root.key || echo "[!] Использован встроенный root key"

uci -q delete unbound.@unbound[0]
uci add unbound unbound
uci set unbound.@unbound[0].validator='1'
uci set unbound.@unbound[0].port='5353'
uci set unbound.@unbound[0].listen_port='5353'
uci set unbound.@unbound[0].localservice='1'
uci add_list unbound.@unbound[0].unbound_conf='auto-trust-anchor-file: "/var/lib/unbound/root.key"'
uci commit unbound

/etc/init.d/unbound restart

echo "[3/4] Unbound запущен на порту 5353."

# 4. Настройка цепочки DNS (Dnsmasq)
echo "[4/4] Настройка цепочки DNS (Unbound → DoH → Quad9)..."

# Полная очистка старых серверов
uci -q delete dhcp.@dnsmasq[0].server
uci -q delete dhcp.@dnsmasq[0].noresolv

# Добавляем серверы по приоритету
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'   # Unbound (главный)
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5053'   # https-dns-proxy (Cloudflare)
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5054'   # https-dns-proxy (Google)
uci add_list dhcp.@dnsmasq[0].server='9.9.9.9'          # Quad9 — резерв

uci set dhcp.@dnsmasq[0].strictorder='1'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci commit dhcp

# Перезапуск сервисов
/etc/init.d/https-dns-proxy enable 2>/dev/null
/etc/init.d/https-dns-proxy restart 2>/dev/null
/etc/init.d/unbound restart
/etc/init.d/dnsmasq restart

echo "=== ГОТОВО! ==="
echo "Проверьте:"
echo "   date                  # время"
echo "   nslookup google.com   # DNS"
echo "   logread | tail -50    # логи при проблемах"
