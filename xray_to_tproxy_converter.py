import json
import os

def convert_to_tproxy(input_file, output_file):
    if not os.path.exists(input_file):
        print(f"Ошибка: Файл {input_file} не найден.")
        return

    with open(input_file, 'r', encoding='utf-8') as f:
        config = json.load(f)

    # 1. Настройка Inbounds (Входящие соединения)
    # Очищаем старые инбаунды или модифицируем их
    new_inbounds = [
        {
            "tag": "transparent",
            "port": 1100,
            "protocol": "vless",
            "settings": {
                "decryption": "none",
                "network": "tcp,udp"
            },
            "streamSettings": {
                "sockopt": {
                    "tproxy": "tproxy",
                    "mark": 255
                }
            }
        },
        {
            "listen": "127.0.0.1",
            "port": 10880,
            "protocol": "socks",
            "settings": {
                "udp": True
            }
        }
    ]
    config['inbounds'] = new_inbounds

    # 2. Настройка Outbounds (Исходящие соединения)
    # Нам нужно добавить "mark": 255 во все прокси-аутбаунды
    if 'outbounds' in config:
        for outbound in config['outbounds']:
            # Пропускаем freedom (direct) и dns, если они есть
            if outbound.get('protocol') not in ['freedom', 'dns']:
                if 'streamSettings' not in outbound:
                    outbound['streamSettings'] = {}
                if 'sockopt' not in outbound['streamSettings']:
                    outbound['streamSettings']['sockopt'] = {}
                
                outbound['streamSettings']['sockopt']['mark'] = 255
                outbound['tag'] = "proxy" # Даем тег для маршрутизации

    # 3. Настройка маршрутизации (Routing)
    config['routing'] = {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "inboundTag": ["transparent"],
                "outboundTag": "proxy"
            }
        ]
    }

    # Сохраняем обновленный конфиг
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    
    print(f"Конвертация завершена! Файл сохранен как: {output_file}")

if __name__ == "__main__":
    convert_to_tproxy('config.json', 'config_tproxy.json')
