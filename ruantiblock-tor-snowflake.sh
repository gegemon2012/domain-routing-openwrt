#!/bin/sh

# Установка необходимого модуля
opkg update
opkg install snowflake-client

TORRC="/etc/tor/torrc"
SNOWFLAKE_BIN=$(which snowflake-client)

if [ -z "$SNOWFLAKE_BIN" ]; then
    echo "Ошибка: snowflake-client не установлен!"
    exit 1
fi

# Делаем копию конфига, как в основном скрипте ruantiblock
cp $TORRC "${TORRC}.bak.$(date +%s)"

# Очищаем старые настройки мостов и транспортов, чтобы не дублировать
sed -i '/UseBridges/d' $TORRC
sed -i '/ClientTransportPlugin snowflake/d' $TORRC
sed -i '/Bridge snowflake/d' $TORRC

# Добавляем конфигурацию Snowflake
# Мы используем публичные STUN-серверы и брокер Tor Project
cat <<EOF >> $TORRC

# Автоматическая настройка Snowflake
UseBridges 1
ClientTransportPlugin snowflake exec $SNOWFLAKE_BIN -url https://snowflake-broker.torproject.net.global.prod.fastly.net/ -front cdn.sstatic.net -ice stun:stun.l.google.com:19302,stun:stun.voip.blackberry.com:3478
Bridge snowflake 192.0.2.3:1 2B280B23E1107F24836209A3206656D32CC97D06
EOF

# Перезагружаем Tor
/etc/init.d/tor restart

echo "Snowflake успешно интегрирован в Tor."