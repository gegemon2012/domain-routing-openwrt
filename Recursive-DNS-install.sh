#!/bin/sh

echo "========================================="
echo "   RECURSIVE DNS & NTP SYNC FIX (V2)"
echo "========================================="

# 1. Исправление петли времени (NTP + Hosts)
echo "[1/4] Настройка прямого доступа к NTP серверам..."
sed -i '/time.cloudflare.com/d' /etc/hosts
sed -i '/time.google.com/d' /etc/hosts
echo "162.159.200.1 time.cloudflare.com" >> /etc/hosts
echo "216.239.35.0 time.google.com" >> /etc/hosts
echo "   IP для Cloudflare и Google прописаны в /etc/hosts."

# 2. Обновление и установка пакетов
echo "[2/4] Обновление пакетов и установка Unbound..."
opkg update
# Добавляем unbound-anchor для управления ключами DNSSEC
opkg install unbound-daemon luci-app-unbound bind-dig unbound-anchor

# 3. Настройка Unbound и DNSSEC Trust Anchor
echo "[3/4] Настройка Unbound и генерация ключей..."

# Создаем директорию и генерируем корневой ключ (обязательно для DNSSEC)
mkdir -p /var/lib/unbound
unbound-anchor -a /var/lib/unbound/root.key
chown -R unbound:unbound /var/lib/unbound

# Настройка через UCI
uci del unbound.@unbound[0].unbound_conf 2>/dev/null

uci set unbound.@unbound[0].add_local_fqdn='1'
uci set unbound.@unbound[0].add_wan_fqdn='1'
uci set unbound.@unbound[0].validator='1'      # DNSSEC активен
uci set unbound.@unbound[0].rebind_protection='1'
uci set unbound.@unbound[0].port='5353'

# Привязываем файл ключа и разрешаем NTP исключение
uci add_list unbound.@unbound[0].unbound_conf='auto-trust-anchor-file: "/var/lib/unbound/root.key"'
uci add_list unbound.@unbound[0].unbound_conf='ntp-dot-allow: yes'
uci commit unbound

# 4. Привязка Dnsmasq к Unbound
echo "[4/4] Перенаправление Dnsmasq на порт 5353..."
# Очищаем старые DNS-серверы
while uci get dhcp.@dnsmasq[0].server >/dev/null 2>&1; do
    uci del_list dhcp.@dnsmasq[0].server=$(uci get dhcp.@dnsmasq[0].server | awk '{print $1}')
done

uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'
uci set dhcp.@dnsmasq[0].noresolv='1'
# Рекомендуется также включить локальный кэш в dnsmasq для скорости
uci set dhcp.@dnsmasq[0].cachesize='1000'
uci commit dhcp

# Перезапуск всех служб
echo "Применение настроек и перезапуск сервисов..."
/etc/init.d/sysntpd restart
/etc/init.d/unbound restart
/etc/init.d/dnsmasq restart

echo "========================================="
echo "   ГОТОВО: Рекурсивный DNS настроен"
echo "   DNSSEC: Ключи сгенерированы"
echo "   ПРИМЕЧАНИЕ: Проверьте дату командой 'date'!"
echo "========================================="
echo "   ГОТОВО: Рекурсивный DNS настроен"
echo "   NTP FIX: Применен (IP в hosts)"
echo "   DNSSEC: Работает на порту 5353"
echo "========================================="
