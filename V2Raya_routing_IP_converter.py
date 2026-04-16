import re
import sys
import ipaddress

def parse_ip_networks_advanced(input_text):
    """
    Расширенная версия с валидацией IP-сетей
    """
    # Более точное регулярное выражение для IPv4 CIDR
    ipv4_pattern = r"'?(\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}/\d{1,2})\b'?"
    
    # Для IPv6 CIDR
    ipv6_pattern = r"'?(\b(?:[0-9a-fA-F]{1,4}:){1,7}[0-9a-fA-F]{1,4}/\d{1,3})\b'?"
    
    networks = []
    
    # Поиск IPv4
    for match in re.finditer(ipv4_pattern, input_text):
        network = match.group(1)
        try:
            # Валидация IPv4 сети
            ipaddress.ip_network(network, strict=False)
            networks.append(network)
        except ValueError:
            continue
    
    # Поиск IPv6
    for match in re.finditer(ipv6_pattern, input_text):
        network = match.group(1)
        try:
            # Валидация IPv6 сети
            ipaddress.ip_network(network, strict=False)
            networks.append(network)
        except ValueError:
            continue
    
    # Удаляем дубликаты, сохраняя порядок
    seen = set()
    unique_networks = []
    for net in networks:
        if net not in seen:
            seen.add(net)
            unique_networks.append(net)
    
    return unique_networks

def convert_to_ip_format_advanced(networks):
    """
    Преобразует список IP-сетей в формат ip("сеть1","сеть2",...) ->proxy
    """
    if not networks:
        return ""
    
    # Сортируем сети (IPv4 сначала, затем IPv6)
    def sort_key(network):
        try:
            net = ipaddress.ip_network(network, strict=False)
            # IPv4 возвращают 0, IPv6 возвращают 1 для сортировки
            return (0 if net.version == 4 else 1, network)
        except:
            return (2, network)
    
    sorted_networks = sorted(networks, key=sort_key)
    
    # Объединяем сети в кавычках через запятую
    networks_quoted = ','.join([f'"{net}"' for net in sorted_networks])
    
    return f"ip({networks_quoted}) ->proxy"

def process_input(input_text):
    """
    Основная функция обработки
    """
    networks = parse_ip_networks_advanced(input_text)
    return convert_to_ip_format_advanced(networks)

# Простой интерфейс командной строки
if __name__ == "__main__":
    if len(sys.argv) > 1:
        # Если аргументы переданы как параметры
        input_text = ' '.join(sys.argv[1:])
        result = process_input(input_text)
        print(result)
    else:
        # Интерактивный режим
        print("Введите IP-сети (поддерживаются форматы с пробелами, переносами строк и кавычками):")
        print("Пример: 91.105.192.0/23 91.108.4.0/22 или '91.105.192.0/23' '91.108.4.0/22'")
        print("Нажмите Ctrl+D (Linux/Mac) или Ctrl+Z (Windows) для завершения ввода\n")
        
        try:
            input_text = sys.stdin.read()
            if input_text.strip():
                result = process_input(input_text)
                print("\nРезультат:")
                print(result)
            else:
                print("Ошибка: нет входных данных")
        except KeyboardInterrupt:
            print("\nПрерывание ввода")