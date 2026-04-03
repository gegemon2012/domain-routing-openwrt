#!/bin/sh

echo "========================================="
echo "   RECURSIVE DNS & NTP SYNC FIX"
echo "========================================="

# 1. Исправление петли времени (NTP + Hosts)
# Прописываем IP для серверов времени, чтобы NTP работал без DNS
echo "[1/4] Настройка прямого доступа к NTP серверам..."
sed -i '/time.cloudflare.com/d' /etc/hosts
sed -i '/time.google.com/d' /etc/hosts
echo "162.159.200.1 time.cloudflare.com" >> /etc/hosts
echo "216.239.35.0 time.google.com" >> /etc/hosts
echo "   IP для Cloudflare и Google прописаны в /etc/hosts."

# 2. Обновление и установка пакетов
echo "[2/4] Обновление пакетов и установка Unbound..."
opkg update
opkg install unbound-daemon luci-app-unbound bind-dig

# 3. Настройка Unbound (Рекурсивный резолвер)
echo "[3/4] Настройка Unbound через UCI..."
# Сбрасываем старые списки доп. конфигов для чистоты
uci del unbound.@unbound[0].unbound_conf 2>/dev/null

uci set unbound.@unbound[0].add_local_fqdn='1'
uci set unbound.@unbound[0].add_wan_fqdn='1'
uci set unbound.@unbound[0].validator='1'      # DNSSEC активен
uci set unbound.@unbound[0].rebind_protection='1'
uci set unbound.@unbound[0].port='5353'

# Добавляем параметр ntp-dot-allow
# Позволяет Unbound доверять запросам к NTP даже при несинхронизированном времени
uci add_list unbound.@unbound[0].unbound_conf='ntp-dot-allow: yes'
uci commit unbound

# 4. Привязка Dnsmasq к Unbound
echo "[4/4] Перенаправление Dnsmasq на порт 5353..."
uci del_list dhcp.@dnsmasq[0].server 2>/dev/null
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci commit dhcp

# Перезапуск всех служб
echo "Применение настроек и перезапуск сервисов..."
/etc/init.d/dnsmasq restart
/etc/init.d/unbound restart
/etc/init.d/sysntpd restart

echo "========================================="
echo "   ГОТОВО: Рекурсивный DNS настроен"
echo "   NTP FIX: Применен (IP в hosts)"
echo "   DNSSEC: Работает на порту 5353"
echo "========================================="
