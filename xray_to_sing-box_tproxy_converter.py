import json

def convert_to_minimal_singbox(x_cfg):
    # Извлекаем основные параметры из первого outbound Xray
    x_out = x_cfg['outbounds'][0]
    vnext = x_out['settings']['vnext'][0]
    user = vnext['users'][0]
    reality = x_out['streamSettings']['realitySettings']

    # Формируем структуру без DNS-секции
    sb_config = {
        "log": {
            "level": "error"
        },
        "inbounds": [
            {
                "type": "tproxy",
                "tag": "tproxy-in",
                "listen": "::",
                "listen_port": 12345,
                "sniff": True,
                "sniff_override_destination": True
            }
        ],
        "outbounds": [
            {
                "type": "vless",
                "tag": "proxy",
                "server": vnext['address'],
                "server_port": vnext['port'],
                "uuid": user['id'],
                "flow": user.get('flow', ""),
                "network": "tcp",
                "tls": {
                    "enabled": True,
                    "server_name": reality.get('serverName', ''),
                    "utls": {
                        "enabled": True,
                        "fingerprint": reality.get('fingerprint', 'chrome')
                    },
                    "reality": {
                        "enabled": True,
                        "public_key": reality.get('publicKey', ''),
                        "short_id": reality.get('shortId', '')
                    }
                }
            },
            {
                "type": "direct",
                "tag": "direct"
            }
        ],
        "route": {
            "auto_detect_interface": True
        }
    }
    return sb_config

# Основной цикл работы
try:
    with open("amnezia_for_xray.json", "r", encoding="utf-8") as f:
        data = json.load(f)
    
    result = convert_to_minimal_singbox(data)
    
    with open("config_singbox.json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=4, ensure_ascii=False)
    
    print("[+] Конфиг без DNS успешно создан: config_singbox.json")

except Exception as e:
    print(f"[-] Ошибка: {e}")
