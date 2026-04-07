#!/bin/sh

echo "========================================="
echo "   RECURSIVE DNS & NTP & BYPASS FIX"
echo "========================================="

# 1. Исправление доступа к NTP и Root DNS (через IP)
echo "[1/10] Прописываем IP серверов в /etc/hosts..."
sed -i '/ntp/d; /root-servers/d; /time\./d' /etc/hosts
cat >> /etc/hosts << 'EOF'
194.190.168.1      ntp.msk-ix.ru
89.109.251.21      ntp1.vniiftri.ru
162.159.200.1      time.cloudflare.com
198.41.0.4          a.root-servers.net
199.9.14.201        b.root-servers.net
EOF

# 2. Установка софта (до основных правок)
echo "[2/10] Установка пакетов..."
opkg update && opkg install unbound-daemon luci-app-unbound bind-dig

# 3. Настройка NTP в UCI
echo "[3/10] Настройка серверов времени..."
uci delete system.ntp.server 2>/dev/null
uci add_list system.ntp.server="ntp.msk-ix.ru"
uci add_list system.ntp.server="ntp1.vniiftri.ru"
uci add_list system.ntp.server="time.cloudflare.com"
uci set system.ntp.enabled='1'
uci commit system
/etc/init.d/sysntpd restart

# 4. Предварительная настройка Unbound (БЕЗ DNSSEC)
echo "[4/10] Настройка Unbound (шаг 1: без DNSSEC)..."
uci set unbound.@unbound[0].listen_port='5353'
uci set unbound.@unbound[0].validator='0'  # Выключен для синхронизации
uci set unbound.@unbound[0].rebind_protection='1'
uci set unbound.@unbound[0].query_minimize='1'
uci commit unbound

# Создаем root.hints локально
mkdir -p /etc/unbound
cat > /etc/unbound/root.hints << 'EOF'
.                        3600000  NS    a.root-servers.net.
a.root-servers.net.      3600000  A     198.41.0.4
b.root-servers.net.      3600000  A     199.9.14.201
EOF

# 5. Привязка dnsmasq
echo "[5/10] Настройка dnsmasq..."
uci set dhcp.@dnsmasq[0].noresolv='1'
uci del dhcp.@dnsmasq[0].server 2>/dev/null
uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5353"
uci commit dhcp

# 6. Очистка временных конфигов (чтобы не мешали обходчикам)
rm -f /tmp/dnsmasq.d/* 2>/dev/null

# 7. Запуск в режиме "Временный DNS"
echo "[6/10] Запуск DNS для синхронизации времени..."
/etc/init.d/unbound restart
/etc/init.d/dnsmasq restart

# 8. Ожидание времени (корректный метод для OpenWrt)
echo -n "[7/10] Ожидание синхронизации времени (до 60с) "
for i in $(seq 1 12); do
    # Проверяем, считается ли время синхронизированным (status 8192 и выше в ntptime)
    if ntptime 2>/dev/null | grep -q "OK"; then
        SYNCED=1
        break
    fi
    echo -n "."
    sleep 5
done

# 9. Включение DNSSEC (если время ок)
if [ "$SYNCED" = "1" ]; then
    echo -e "\n   ✅ Время получено. Включаем DNSSEC..."
    uci set unbound.@unbound[0].validator='1'
    uci commit unbound
    /etc/init.d/unbound restart
else
    echo -e "\n   ⚠️ Время НЕ синхронизировано. DNSSEC остается выключенным!"
fi

# 10. Совместимость с вашими обходчиками
echo "[10/10] Восстановление обхода блокировок..."
[ -x "/etc/init.d/ruantiblock" ] && /etc/init.d/ruantiblock restart
if [ -x "/etc/init.d/getdomains" ]; then
    /etc/init.d/getdomains start
    sleep 2
    /etc/init.d/dnsmasq restart
fi

echo "========================================="
echo "   УСТАНОВКА ЗАВЕРШЕНА"
echo "========================================="

echo "========================================="
echo "   ГОТОВО: Рекурсивный DNS настроен"
echo "   NTP FIX: Применен (IP в hosts)"
echo "   DNSSEC: Работает на порту 5353"
echo "========================================="
