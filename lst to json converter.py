import json
import os
import glob

def convert_all_lst_to_json():
    # Поиск всех файлов с расширением .lst в текущей директории
    lst_files = glob.glob("*.lst")
    
    if not lst_files:
        print("Файлы .lst не найдены в текущей папке.")
        return

    print(f"Найдено файлов для обработки: {len(lst_files)}")

    for input_file in lst_files:
        # Формируем имя выходного файла (заменяем .lst на .json)
        output_file = os.path.splitext(input_file)[0] + ".json"
        
        ip_list = []
        try:
            with open(input_file, 'r', encoding='utf-8') as f:
                # Используем set для автоматического удаления дубликатов внутри файла
                unique_ips = set()
                for line in f:
                    clean_line = line.strip()
                    # Пропускаем пустые строки, комментарии и мусор
                    if clean_line and not clean_line.startswith('#') and '.' in clean_line:
                        unique_ips.add(clean_line)
                
                # Сортируем список для порядка
                ip_list = sorted(list(unique_ips))

            # Записываем результат в JSON
            with open(output_file, 'w', encoding='utf-8') as jf:
                json.dump(ip_list, jf, indent=4, ensure_ascii=False)
                
            print(f"✓ Обработан: {input_file} -> {output_file} ({len(ip_list)} записей)")

        except Exception as e:
            print(f"✗ Ошибка при обработке файла {input_file}: {e}")

if __name__ == "__main__":
    convert_all_lst_to_json()
    print("\nРабота завершена.")
