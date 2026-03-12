import json
import os

def convert_xray_to_singbox(xray_config):
    try:
        # Ищем первый подходящий outbound с VLESS
        x_out = next((o for o in xray_config.get('outbounds', []) if o.get('protocol') == 'vless'), None)
        
        if not x_out:
            raise ValueError("В исходном конфиге не найден блок 'vless'")

        vnext = x_out['settings']['vnext'][0]
        user = vnext['users'][0]
        stream = x_out.get('streamSettings', {})
        reality = stream.get('realitySettings', {})

        # Собираем outbound для sing-box
        sb_outbound = {
            "type": "vless",
            "tag": "proxy-out",
            "server": vnext['address'],
            "server_port": vnext['port'],
            "uuid": user['id'],
            "flow": user.get('flow', ""),
            "network": stream.get('network', 'tcp'),
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
        }

        # Формируем структуру sing-box
        return {
            "log": {"level": "debug"},
            "dns": {
                "servers": [
                    {"tag": "dns-remote", "address": "https://8.8.8.8/dns-query", "detour": "proxy-out"},
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
                    "type": "tun",
                    "tag": "tun-in",
                    "interface_name": "tun0",
                    "domain_strategy": "ipv4_only",
                    "address": ["172.16.250.1/30"],
                    "auto_route": False,
                    "strict_route": False,
                    "sniff": True,
                    "sniff_override_destination": True
                }
            ],
            "outbounds": [
                sb_outbound,
                {"type": "direct", "tag": "direct"},
                {"type": "dns", "tag": "dns-out"}
            ],
            "route": {
                "auto_detect_interface": True,
                "rules": [
                    {"protocol": "dns", "outbound": "dns-out"},
                    {"network": "udp", "port": 53, "outbound": "dns-out"}
                ]
            }
        }
    except Exception as e:
        return {"error": str(e)}

def main():
    in_file = "config.json"
    out_file = "config_for_sing-box.json"

    if not os.path.exists(in_file):
        print(f"[-] Файл {in_file} не найден!")
        return

    try:
        with open(in_file, "r", encoding="utf-8") as f:
            data = json.load(f)
        
        result = convert_xray_to_singbox(data)
        
        if "error" in result:
            print(f"[-] Ошибка: {result['error']}")
            return

        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=4, ensure_ascii=False)
        
        print(f"[+] Готово! Результат в файле: {out_file}")
        
    except Exception as e:
        print(f"[-] Произошла ошибка: {e}")

if __name__ == "__main__":
    main()
