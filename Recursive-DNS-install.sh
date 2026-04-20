#!/bin/sh

echo "=== RECURSIVE DNS & NTP FIX (RU OPTIMIZED) ==="

# 1. NTP Fix (Запись в hosts для старта при "холодном" DNS)
sed -i '/time.cloudflare.com/d; /time.google.com/d; /ntp.yandex.ru/d' /etc/hosts
echo "162.159.200.1 time.cloudflare.com" >> /etc/hosts
echo "216.239.35.0 time.google.com" >> /etc/hosts
echo "213.180.193.1 ntp.yandex.ru" >> /etc/hosts
echo "[1/4] IP адреса NTP добавлены в /etc/hosts для надежности."

# Настройка системного NTP через UCI (для РФ)
echo "Конфигурация NTP серверов..."
uci del system.ntp.server
uci add_list system.ntp.server='ntp.yandex.ru'
uci add_list system.ntp.server='0.ru.pool.ntp.org'
uci add_list system.ntp.server='1.ru.pool.ntp.org'
uci add_list system.ntp.server='ntp1.vniiftri.ru' # Эталонное время РФ (НИИР)
uci add_list system.ntp.server='time.cloudflare.com'
uci add_list system.ntp.server='time.google.com'
uci set system.ntp.enabled='1'
uci set system.ntp.enable_server='0'
uci commit system
/etc/init.d/sysntpd restart

# 2. Установка Unbound
DO_OPKG=1
echo "[?] Установить Unbound? Нажмите ЛЮБУЮ клавишу за 15 сек для ОТМЕНЫ."
if read -t 15 -n 1; then
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

# Сброс и чистая настройка UCI
uci del unbound.@unbound[0] 2>/dev/null
uci add unbound unbound
uci set unbound.@unbound[0].validator='1'
uci set unbound.@unbound[0].port='5353'
uci set unbound.@unbound[0].localservice='1'
uci add_list unbound.@unbound[0].unbound_conf='auto-trust-anchor-file: "/var/lib/unbound/root.key"'
uci commit unbound

# 4. Привязка к Dnsmasq
echo "[4/4] Перенаправление Dnsmasq -> Unbound (5353)..."

# Удаляем все старые серверы из dnsmasq
while uci get dhcp.@dnsmasq[0].server | grep -q "."; do
    uci del_list dhcp.@dnsmasq[0].server=$(uci get dhcp.@dnsmasq[0].server | head -n 1)
done

uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].cachesize='1000'
uci commit dhcp

/etc/init.d/unbound restart
/etc/init.d/dnsmasq restart
echo "=== ГОТОВО! Проверьте время командой 'date' ==="
