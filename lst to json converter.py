import json
import os

def convert_lst_to_json(input_file, output_file):
    """
    Конвертирует список IP-сетей из формата .lst в .json массив.
    """
    if not os.path.exists(input_file):
        print(f"Ошибка: Файл {input_file} не найден.")
        return

    ip_list = []
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            for line in f:
                # Очистка строки от пробелов и символов переноса
                clean_line = line.strip()
                
                # Пропускаем пустые строки и комментарии
                if not clean_line or clean_line.startswith('#'):
                    continue
                
                # Базовая проверка: строка должна содержать точку (для IP)
                if '.' in clean_line:
                    ip_list.append(clean_line)
        
        # Сохранение в формате JSON
        with open(output_file, 'w', encoding='utf-8') as jf:
            json.dump(ip_list, jf, indent=4, ensure_ascii=False)
            
        print(f"Успешно! {len(ip_list)} записей сохранено в {output_file}")

    except Exception as e:
        print(f"Произошла ошибка при обработке: {e}")

# Настройки имен файлов
input_filename = 'ipsum.lst'  # Ваш входной файл
output_filename = 'ipsum.json' # Результат

if __name__ == "__main__":
    convert_lst_to_json(input_filename, output_filename)
