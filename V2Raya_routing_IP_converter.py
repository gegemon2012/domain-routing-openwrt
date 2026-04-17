import re
import sys
import ipaddress

def parse_and_fix_networks(input_text):
    # Извлекаем всё, что похоже на IP или CIDR
    raw_parts = re.findall(r"([0-9a-fA-F\.\:/]+)", input_text)
    networks = []
    
    for item in raw_parts:
        clean_item = item.strip("'\",")
        if not clean_item or clean_item == "/": continue
        try:
            # strict=False позволяет принимать адреса типа 192.168.1.5/24 и делать из них сеть .0
            net = ipaddress.ip_network(clean_item, strict=False)
            networks.append(str(net))
        except ValueError:
            continue
    
    # Сортировка: IPv4 сначала, затем IPv6, внутри по алфавиту
    def sort_key(net_str):
        net = ipaddress.ip_network(net_str)
        return (0 if net.version == 4 else 1, net)

    return sorted(list(set(networks)), key=sort_key)

def main():
    print("Введите IP-адреса или сети (или вставьте через Ctrl+V, потом Enter, потом Ctrl+D для завершения):")
    try:
        input_text = sys.stdin.read()
        if not input_text.strip():
            print("Ввод пуст.")
            return

        nets = parse_and_fix_networks(input_text)
        if not nets:
            print("Валидные IP-сети не найдены.")
            return

        # Формат: ip("1.1.1.1/32","8.8.8.8/32") ->proxy
        formatted = ",".join([f'"{n}"' for n in nets])
        print(f"\nРезультат:\nip({formatted}) ->proxy")
        
    except KeyboardInterrupt:
        print("\nПрервано.")

if __name__ == "__main__":
    main()
