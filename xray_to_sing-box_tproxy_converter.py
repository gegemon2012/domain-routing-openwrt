import json
import os

def convert_xray_to_singbox_universal(xray_config):
    sb_outbounds = []
    
    # 1. Сначала добавляем прокси-выходы из Xray
    for x_out in xray_config.get('outbounds', []):
        protocol = x_out.get('protocol')
        tag = x_out.get('tag', 'proxy')
        
        if protocol == 'vless':
            try:
                vnext = x_out['settings']['vnext'][0]
                user = vnext['users'][0]
                stream = x_out.get('streamSettings', {})
                reality = stream.get('realitySettings', {})
                
                sb_out = {
                    "type": "vless",
                    "tag": tag,
                    "server": vnext['address'],
                    "server_port": vnext['port'],
                    "uuid": user['id'],
                    "flow": user.get('flow', ""),
                    "network": stream.get('network', 'tcp'),
                    "tls": {
                        "enabled": True,
                        "server_name": reality.get('serverName', ''),
                        "utls": {"enabled": True, "fingerprint": reality.get('fingerprint', 'chrome')},
                        "reality": {
                            "enabled": True,
                            "public_key": reality.get('publicKey', ''),
                            "short_id": reality.get('shortId', '')
                        }
                    }
                }
                sb_outbounds.append(sb_out)
            except KeyError:
                continue

    # 2. ДОБАВЛЯЕМ СТАНДАРТНЫЕ ВЫХОДЫ (Direct и DNS)
    # Эти блоки обязательны для работы правил маршрутизации и DNS
    standard_outbounds = [
        {
            "type": "direct",
            "tag": "direct"
        },
        {
            "type": "dns",
            "tag": "dns-out"
        }
    ]
    
    # Объединяем прокси с прямым выходом
    final_outbounds = sb_outbounds + standard_outbounds

    # Определяем тег основного прокси для DNS (берем первый из списка)
    proxy_tag = sb_outbounds[0]['tag'] if sb_outbounds else "direct"

    # 3. Собираем финальный конфиг
    return {
        "log": {"level": "info"},
        "dns": {
            "servers": [
                {"tag": "dns-remote", "address": "https://8.8.8.8/dns-query", "detour": proxy_tag},
                {"tag": "dns-direct", "address": "1.1.1.1", "detour": "direct"}
            ],
            "rules": [
                {"outbound": "any", "server": "dns-direct"},
                {"query_status": ["any"], "server": "dns-remote"}
            ],
            "strategy": "ipv4_only"
        },
        "inbounds": [
            {
                "type": "tproxy",
                "tag": "tproxy-in",
                "listen": "::",
                "listen_port": 12345,
                "sniff": True,
                "sniff_override_destination": True,
                "udp_fragment": True
            }
        ],
        "outbounds": final_outbounds,
        "route": {
            "auto_detect_interface": True,
            "rules": [
                {
                    "protocol": "dns",
                    "outbound": "dns-out"
                }
            ]
        }
    }

def main():
    in_file = "config.json"
    out_file = "config_singbox.json"

    if not os.path.exists(in_file):
        print(f"[-] Файл {in_file} не найден!")
        return

    try:
        with open(in_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        
        result = convert_xray_to_singbox_universal(data)
        
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=4, ensure_ascii=False)
        
        print(f"[+] Успех! Стандартный выход 'direct' добавлен.")
        print(f"[+] Файл сохранен: {out_file}")
        
    except Exception as e:
        print(f"[-] Ошибка: {e}")

if __name__ == "__main__":
    main()
