import json
import os

def generate_minimal_tproxy(input_file, output_file):
    if not os.path.exists(input_file):
        print(f"Ошибка: Файл {input_file} не найден.")
        return

    with open(input_file, 'r', encoding='utf-8') as f:
        config = json.load(f)

    # 1. Inbound: Только TPROXY (dokodemo-door) и SOCKS для тестов
    config['inbounds'] = [
        {
            "tag": "tproxy-in",
            "port": 1100,
            "protocol": "dokodemo-door",
            "settings": {
                "network": "tcp,udp",
                "followRedirect": True
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
            "settings": { "udp": True }
        }
    ]

    # 2. Outbounds: Прокси с меткой и прямой выход
    if 'outbounds' in config:
        for outbound in config['outbounds']:
            # Настраиваем основной прокси (VLESS/REALITY)
            if outbound.get('protocol') not in ['freedom', 'dns']:
                if 'streamSettings' not in outbound:
                    outbound['streamSettings'] = {}
                if 'sockopt' not in outbound['streamSettings']:
                    outbound['streamSettings']['sockopt'] = {}
                
                outbound['streamSettings']['sockopt']['mark'] = 255
                outbound['tag'] = "proxy"

    # Гарантируем наличие прямого выхода
    if not any(o.get('tag') == 'direct' for o in config.get('outbounds', [])):
        config.setdefault('outbounds', []).append({
            "protocol": "freedom",
            "tag": "direct"
        })

    # 3. Маршрутизация: Всё из TPROXY — в Прокси
    config['routing'] = {
        "rules": [
            {
                "type": "field",
                "inboundTag": ["tproxy-in"],
                "outboundTag": "proxy"
            }
        ]
    }

    # Удаляем секцию DNS, чтобы не мешать ruantiblock
    if 'dns' in config:
        del config['dns']

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    
    print(f"Минималистичный конфиг готов: {output_file}")

if __name__ == "__main__":
    generate_minimal_tproxy('config.json', 'config_tproxy.json')
