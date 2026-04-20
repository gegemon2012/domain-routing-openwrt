#!/bin/sh

echo "=== RECURSIVE DNS & NTP FIX (OFFLINE-READY) ==="

# 1. Подготовка NTP (Запись в hosts для надежного старта)
sed -i '/time.cloudflare.com/d; /time.google.com/d; /ntp.yandex.ru/d' /etc/hosts
echo "162.159.200.1 time.cloudflare.com" >> /etc/hosts
echo "216.239.35.0 time.google.com" >> /etc/hosts
echo "213.180.193.1 ntp.yandex.ru" >> /etc/hosts

# Настройка системного NTP через UCI
uci del system.ntp.server 2>/dev/null
uci add_list system.ntp.server='ntp.yandex.ru'
uci add_list system.ntp.server='ntp1.vniiftri.ru'
uci add_list system.ntp.server='0.ru.pool.ntp.org'
uci add_list system.ntp.server='time.google.com'
uci add_list system.ntp.server='time.cloudflare.com'
uci set system.ntp.enabled='1'
uci commit system
/etc/init.d/sysntpd restart

# 2. Установка (с таймером 15 секунд)
echo "[?] Установить пакеты? Нажмите ЛЮБУЮ клавишу за 15 сек для ОТМЕНЫ."
if read -t 15 -n 1; then
    echo -e "\n[!] Шаг установки пропущен."
else
    echo -e "\n[2/4] Обновление и установка Unbound..."
    opkg update
    opkg install unbound-daemon luci-app-unbound bind-dig unbound-anchor
fi

# 3. Настройка Unbound без обязательного интернета
echo "[3/4] Локальная инициализация DNSSEC..."

# Устраняем конфликт с системными конфигами (причина crash loop на 53 порту)
[ -f /etc/unbound/unbound.conf ] && mv /etc/unbound/unbound.conf /etc/unbound/unbound.conf.bak

mkdir -p /var/lib/unbound

# Способ "без интернета": используем встроенный в утилиту ключ
# Если сети нет, она создаст файл на основе своих внутренних данных
unbound-anchor -a /var/lib/unbound/root.key || echo "Использован встроенный ключ"

# Принудительная установка прав
chown -R unbound:unbound /var/lib/unbound
chmod 644 /var/lib/unbound/root.key 2>/dev/null

# Настройка UCI
uci del unbound.@unbound[0] 2>/dev/null
uci add unbound unbound
uci set unbound.@unbound[0].validator='1'
uci set unbound.@unbound[0].port='5353'
uci set unbound.@unbound[0].listen_port='5353'
uci set unbound.@unbound[0].localservice='1'
uci add_list unbound.@unbound[0].unbound_conf='auto-trust-anchor-file: "/var/lib/unbound/root.key"'
uci commit unbound

/etc/init.d/unbound restart

# 4. Привязка к Dnsmasq (с приоритетом и Quad9)
echo "[4/4] Настройка приоритетов Dnsmasq..."

# Очистка текущих DNS
while uci get dhcp.@dnsmasq[0].server >/dev/null 2>&1; do
    uci del_list dhcp.@dnsmasq[0].server=$(uci get dhcp.@dnsmasq[0].server | head -n 1)
done

# Приоритет: 1. Unbound (локальный), 2. Quad9 (резерв)
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'
uci add_list dhcp.@dnsmasq[0].server='9.9.9.9' 

uci set dhcp.@dnsmasq[0].strictorder='1' # Опрос строго по порядку
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].cachesize='1000'
uci commit dhcp

/etc/init.d/unbound restart
/etc/init.d/dnsmasq restart

echo "=== ГОТОВО! Проверьте время (date) и DNS (nslookup google.com) ==="
