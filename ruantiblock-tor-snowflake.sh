# 1. Установка клиента
opkg install snowflake-client

# 2. Настройка конфигурации Tor
# Вставляем настройки Snowflake в конец /etc/tor/torrc
# Мы используем sed, чтобы гарантированно удалить старые мосты перед добавлением
sed -i '/Bridge /d' /etc/tor/torrc
sed -i '/ClientTransportPlugin/d' /etc/tor/torrc
sed -i '/UseBridges/d' /etc/tor/torrc

cat <<EOF >> /etc/tor/torrc
UseBridges 1
ClientTransportPlugin snowflake exec /usr/bin/snowflake-client -url https://snowflake-broker.torproject.net.global.prod.fastly.net/ -front cdn.sstatic.net -ice stun:stun.l.google.com:19302,stun:stun.voip.blackberry.com:3478
Bridge snowflake 192.0.2.3:1 2B280B23E1107F24836209A3206656D32CC97D06
EOF

# 3. Перезапуск
/etc/init.d/tor restart
