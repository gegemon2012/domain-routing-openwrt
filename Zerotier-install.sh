#!/bin/sh

# 1. Установка (на случай, если пакет слетел)
opkg update
opkg install zerotier

# 2. Остановка сервиса перед правкой конфигов
/etc/init.d/zerotier stop

echo "Введите ваш ZeroTier Network ID:"
read ZT_ID

# 3. Полная перезапись конфига ZeroTier (прямая запись в файл)
cat <<EOF > /etc/config/zerotier
config zerotier 'ztnoname'
	option enabled '1'
	list join '$ZT_ID'
EOF

# 4. Настройка сети (Интерфейс)
# Удаляем старое, если есть, и пишем заново
sed -i '/config interface .zerotier./,/^$/d' /etc/config/network
cat <<EOF >> /etc/config/network

config interface 'zerotier'
	option proto 'none'
	option device 'zt+'
EOF

# 5. Настройка Firewall (Зона и Forwarding)
# Очищаем старые упоминания zerotier из firewall чтобы не было конфликтов
sed -i '/zerotier/d' /etc/config/firewall

cat <<EOF >> /etc/config/firewall

config zone
	option name 'zerotier'
	option input 'ACCEPT'
	option forward 'ACCEPT'
	option output 'ACCEPT'
	option network 'zerotier'
	option masq '1'
	option mtu_fix '1'

config forwarding
	option src 'lan'
	option dest 'zerotier'

config forwarding
	option src 'zerotier'
	option dest 'lan'
EOF

# 6. Запуск и инициализация ключей
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/zerotier enable
/etc/init.d/zerotier start

echo "Генерация ключей и запуск сервиса (ждем 10 секунд)..."
sleep 10

echo "------------------------------------------------------"
# Проверка статуса
NODE_ID=$(zerotier-cli status | awk '{print $3}')

if [ "$NODE_ID" = "" ] || [ "$NODE_ID" = "OFFLINE" ]; then
    echo "Сервис запускается медленно. Попробуйте 'zerotier-cli status' через минуту."
    echo "Если ошибка 'missing port' осталась - проверьте лог командой: logread | grep zerotier"
else
    echo "Успех! Ваш Node ID: $NODE_ID"
    echo "Теперь добавьте этот ID в панель управления ZeroTier."
fi
echo "------------------------------------------------------"
