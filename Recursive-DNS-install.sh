#!/bin/sh

echo "=== RECURSIVE DNS & NTP FIX ==="

# 1. NTP Fix (Безопасно, всегда вносим правки в hosts)
sed -i '/time.cloudflare.com/d; /time.google.com/d' /etc/hosts
echo "162.159.200.1 time.cloudflare.com" >> /etc/hosts
echo "216.239.35.0 time.google.com" >> /etc/hosts
echo "[1/4] NTP IP добавлены в hosts."

# 2. Установка (с возможностью пропуска)
DO_OPKG=1
echo "[?] Установить Unbound? Нажмите ЛЮБУЮ клавишу за 10 сек для ОТМЕНЫ."
if read -t 10 -n 1; then
    echo -e "\n[!] Шаг установки пропущен."
    DO_OPKG=0
else
    echo -e "\n[2/4] Обновление и установка Unbound..."
    opkg update
    opkg install unbound-daemon luci-app-unbound bind-dig unbound-anchor
fi

# 3. Настройка Unbound
echo "[3/4] Настройка Unbound и DNSSEC..."
mkdir -p /var/lib/unbound
[ ! -f /var/lib/unbound/root.key ] && unbound-anchor -a /var/lib/unbound/root.key
chown -R unbound:unbound /var/lib/unbound

uci del unbound.@unbound[0].unbound_conf 2>/dev/null
uci set unbound.@unbound[0].validator='1'
uci set unbound.@unbound[0].port='5353'
uci add_list unbound.@unbound[0].unbound_conf='auto-trust-anchor-file: "/var/lib/unbound/root.key"'
uci add_list unbound.@unbound[0].unbound_conf='ntp-dot-allow: yes'
uci commit unbound

# 4. Привязка к Dnsmasq
echo "[4/4] Перенаправление Dnsmasq -> Unbound (5353)..."
while uci get dhcp.@dnsmasq[0].server >/dev/null 2>&1; do
    uci del_list dhcp.@dnsmasq[0].server=$(uci get dhcp.@dnsmasq[0].server | awk '{print $1}')
done
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].cachesize='1000'
uci commit dhcp

/etc/init.d/unbound restart
/etc/init.d/dnsmasq restart
echo "=== ГОТОВО! ==="
