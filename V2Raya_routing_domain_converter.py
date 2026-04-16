import re
import sys

def parse_domains(input_text):
    """
    Извлекает домены из различных форматов ввода.
    Поддерживает:
    - youtube.com googlevideo.com
    - 'youtube.com' 'googlevideo.com'
    - youtube.com\n googlevideo.com
    - 'youtube.com'\n'googlevideo.com'
    - смешанные форматы
    """
    # Регулярное выражение для поиска доменов (с учётом кавычек)
    # Находит слова, содержащие буквы, цифры, точки и дефисы
    pattern = r"['\"]?([a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,})['\"]?"
    domains = re.findall(pattern, input_text)
    return domains

def convert_to_proxy_format(domains):
    """
    Преобразует список доменов в формат domain(domain: домен) ->proxy
    """
    result = []
    for domain in domains:
        result.append(f"domain(domain: {domain}) ->proxy")
    return result

def main():
    # Чтение входных данных
    print("Введите домены (для завершения ввода нажмите Ctrl+D или Ctrl+Z):")
    
    try:
        # Читаем весь ввод
        input_text = sys.stdin.read()
        
        if not input_text.strip():
            # Альтернативный вариант: чтение из аргумента командной строки
            if len(sys.argv) > 1:
                input_text = ' '.join(sys.argv[1:])
            else:
                print("Ошибка: нет входных данных")
                return
        
        # Извлекаем домены
        domains = parse_domains(input_text)
        
        if not domains:
            print("Ошибка: домены не найдены")
            return
        
        # Преобразуем в нужный формат
        output_lines = convert_to_proxy_format(domains)
        
        # Выводим результат
        print("\nРезультат:")
        for line in output_lines:
            print(line)
            
    except KeyboardInterrupt:
        print("\nПрерывание ввода")
    except Exception as e:
        print(f"Ошибка: {e}")

def process_string(input_string):
    """
    Функция для обработки строки напрямую (можно использовать как модуль)
    """
    domains = parse_domains(input_string)
    return convert_to_proxy_format(domains)

if __name__ == "__main__":
    main()