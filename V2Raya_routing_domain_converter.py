import re
import sys

def parse_domains(input_text):
    # Очищаем текст от мусора, превращая всё в пробелы
    temp_text = re.sub(r"['\",\t\r\n]", " ", input_text)
    
    # Улучшенное регулярное выражение для доменов
    pattern = r"\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,12}\b"
    domains = re.findall(pattern, temp_text, re.IGNORECASE)
    
    # Удаляем дубликаты и приводим к нижнему регистру
    return sorted(list(set(d.lower() for d in domains)))

def main():
    print("Введите домены (Ctrl+V, потом Enter, потом Ctrl+D для завершения):")
    try:
        input_text = sys.stdin.read()
        if not input_text.strip():
            print("Ввод пуст.")
            return

        domains = parse_domains(input_text)
        if not domains:
            print("Домены не найдены.")
            return

        print("\nРезультат:")
        # Формат: по одной строке на домен для удобства вставки в Routing Rules
        for d in domains:
            print(f"domain(domain: {d}) ->proxy")
            
    except KeyboardInterrupt:
        print("\nПрервано.")

if __name__ == "__main__":
    main()
