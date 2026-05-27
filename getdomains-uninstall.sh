#!/bin/ash

echo "Выпиливаем скрипты"
/etc/init.d/getdomains disable
rm -rf /etc/init.d/getdomains

rm -f /etc/hotplug.d/iface/30-vpnroute /etc/hotplug.d/net/30-vpnroute

echo "Выпиливаем из crontab"
sed -i '/getdomains start/d' /etc/crontabs/root

echo "Выпиливаем домены"
rm -f /tmp/dnsmasq.d/domains.lst

echo "Чистим firewall (ipset)"
ipset_id=$(uci show firewall | grep -E '@ipset.*name=.vpn_domains.' | awk -F '[][{}]' '{print $2}' | head -n 1)
if [ ! -z "$ipset_id" ]; then
    while uci -q delete firewall.@ipset[$ipset_id]; do :; done
fi

rule_id=$(uci show firewall | grep -E '@rule.*name=.mark_domains.' | awk -F '[][{}]' '{print $2}' | head -n 1)
if [ ! -z "$rule_id" ]; then
    while uci -q delete firewall.@rule[$rule_id]; do :; done
fi

ipset_id=$(uci show firewall | grep -E '@ipset.*name=.vpn_domains_internal.' | awk -F '[][{}]' '{print $2}' | head -n 1)
if [ ! -z "$ipset_id" ]; then
    while uci -q delete firewall.@ipset[$ipset_id]; do :; done
fi

rule_id=$(uci show firewall | grep -E '@rule.*name=.mark_domains_intenal.' | awk -F '[][{}]' '{print $2}' | head -n 1)
if [ ! -z "$rule_id" ]; then
    while uci -q delete firewall.@rule[$rule_id]; do :; done
fi

ipset_id=$(uci show firewall | grep -E '@ipset.*name=.vpn_subnet.' | awk -F '[][{}]' '{print $2}' | head -n 1)
if [ ! -z "$ipset_id" ]; then
    while uci -q delete firewall.@ipset[$ipset_id]; do :; done
fi

rule_id=$(uci show firewall | grep -E '@rule.*name=.mark_subnet.' | awk -F '[][{}]' '{print $2}' | head -n 1)
if [ ! -z "$rule_id" ]; then
    while uci -q delete firewall.@rule[$rule_id]; do :; done
fi

uci commit firewall
/etc/init.d/firewall restart

echo "Чистим nftables (nftset) — если используется"
if command -v nft &> /dev/null; then
    for setname in vpn_domains vpn_domains_internal vpn_subnet; do
        if nft list sets 2>/dev/null | grep -q "$setname"; then
            echo "Удаляем nftset: $setname"
            nft delete set inet fw4 "$setname" 2>/dev/null
            nft delete set filter "$setname" 2>/dev/null
            nft delete set ip fw4 "$setname" 2>/dev/null
        fi
    done

    # Удаляем правила, помеченные комментарием mark_domains / mark_subnet
    nft -a list ruleset 2>/dev/null | grep -E 'comment "(mark_domains|mark_subnet)"' | while read -r line; do
        handle=$(echo "$line" | grep -o 'handle [0-9]\+' | awk '{print $2}')
        chain=$(echo "$line" | grep -oP 'chain \K\w+')
        if [ -n "$handle" ] && [ -n "$chain" ]; then
            echo "Удаляем правило nftables: chain $chain, handle $handle"
            nft delete rule inet fw4 "$chain" handle "$handle" 2>/dev/null
        fi
    done
else
    echo "nftables не найден, пропускаем"
fi

echo "Чистим сеть"
sed -i '/99 vpn/d' /etc/iproute2/rt_tables

rule_id=$(uci show network | grep -E '@rule.*name=.mark0x1.' | awk -F '[][{}]' '{print $2}' | head -n 1)
if [ ! -z "$rule_id" ]; then
    while uci -q delete network.@rule[$rule_id]; do :; done
fi

rule_id=$(uci show network | grep -E '@rule.*name=.mark0x2.' | awk -F '[][{}]' '{print $2}' | head -n 1)
if [ ! -z "$rule_id" ]; then
    while uci -q delete network.@rule[$rule_id]; do :; done
fi

while uci -q delete network.vpn_route_internal; do :; done

uci commit network
/etc/init.d/network restart

echo "Проверяем Dnsmasq"
if uci show dhcp | grep -q ipset; then
    echo "В dnsmasq (/etc/config/dhcp) заданы домены. Нужные из них сохраните, остальные удалите вместе с ipset/nftset"
fi

echo "Все туннели, прокси, зоны и forwarding к ним оставляем на месте, они вам не помешают и скорее пригодятся"
echo "Dnscrypt, stubby тоже не трогаем"

echo "  ______  _____        _____   _____  ______  _     _  _____   _____"
echo " |  ____ |     |      |_____] |     | |     \ |____/  |     | |_____]"
echo " |_____| |_____|      |       |_____| |_____/ |    \_ |_____| |     "
