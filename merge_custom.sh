#!/bin/bash
set -euo pipefail

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Директория где запускаем скрипт
WORK_DIR="$(pwd)"

# Функции для логов
log_info() { echo -e "${BLUE}[ИНФО]${NC} $1"; }
log_success() { echo -e "${GREEN}[УСПЕХ]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1"; }

# Получаем префикс от пользователя
get_prefix() {
    echo -e "${BLUE}Merge Tool${NC}"
    echo "============"
    echo
    
    read -p "Введите префикс для поиска папок: " prefix
    [[ -z "$prefix" ]] && { 
        echo "Ошибка: префикс не может быть пустым" 
        exit 1 
    }
    
    log_info "Ищу папки с префиксом: '$prefix'"
}

# Находим все родительские папки с префиксом
find_parent_folders() {
    log_info "Поиск родительских папок..."
    
    # Создаем временный файл со списком папок
    local temp_file="/tmp/parent_folders_$$"
    find "$WORK_DIR" -maxdepth 1 -type d -not -path "$WORK_DIR" > "$temp_file"
    
    # Фильтруем папки по префиксу
    local parent_folders=()
    while IFS= read -r folder; do
        local folder_name=$(basename "$folder")
        # Ищем папки содержащие префикс
        if [[ "$folder_name" == *"$prefix"* ]]; then
            parent_folders+=("$folder")
            echo "Найдена: $folder_name"
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    if [[ ${#parent_folders[@]} -lt 2 ]]; then
        log_warning "Нужно минимум 2 папки для объединения"
        return 1
    fi
    
    log_info "Найдено папок: ${#parent_folders[@]}"
    
    # Объединяем папки
    merge_parent_folders "${parent_folders[@]}"
}

# Объединяем содержимое родительских папок
merge_parent_folders() {
    local folders=("$@")
    local target_folder="${WORK_DIR}/${prefix}"
    
    # Создаем целевую папку если нет
    [[ ! -d "$target_folder" ]] && mkdir -p "$target_folder"
    
    log_info "Объединяю в папку: $(basename "$target_folder")"
    
    # Перемещаем содержимое из каждой папки
    for source_folder in "${folders[@]}"; do
        [[ "$source_folder" == "$target_folder" ]] && continue
        
        local folder_name=$(basename "$source_folder")
        log_info "Перемещаю из: $folder_name"
        
        # Перемещаем все файлы и подпапки
        for item in "$source_folder"/*; do
            [[ -e "$item" ]] || continue
            local item_name=$(basename "$item")
            local dest_path="${target_folder}/${item_name}"
            
            # Решаем конфликты имен
            local counter=1
            while [[ -e "$dest_path" ]]; do
                if [[ -d "$item" ]]; then
                    dest_path="${target_folder}/${item_name}_${counter}"
                else
                    local name="${item_name%.*}"
                    local ext="${item_name##*.}"
                    [[ "$name" == "$ext" ]] && dest_path="${target_folder}/${item_name}_${counter}" || dest_path="${target_folder}/${name}_${counter}.${ext}"
                fi
                counter=$((counter + 1))
            done
            
            mv "$item" "$dest_path"
        done
        
        # Удаляем пустую папку
        rmdir "$source_folder" 2>/dev/null || true
    done
    
    log_success "Родительские папки объединены"
}

# Ищем дубликаты подпапок по точному совпадению
find_and_merge_subfolders() {
    log_info "Поиск дубликатов подпапок..."
    
    # Создаем временный файл со всеми подпапками
    local temp_file="/tmp/subfolders_$$"
    find "$WORK_DIR" -mindepth 2 -type d > "$temp_file"
    
    # Создаем хеш-таблицу для группировки
    declare -A folder_groups
    
    while IFS= read -r folder; do
        local folder_name=$(basename "$folder")
        folder_groups["$folder_name"]+="$folder|"
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    # Объединяем группы с одинаковыми именами
    local merged_any=false
    for folder_name in "${!folder_groups[@]}"; do
        local folders="${folder_groups[$folder_name]}"
        local folder_array=(${folders//|/ })
        
        # Если в группе больше 1 папки - объединяем
        if [[ ${#folder_array[@]} -gt 1 ]]; then
            log_info "Найдены дубликаты: '$folder_name' (${#folder_array[@]} шт)"
            
            # Объединяем подпапки
            merge_subfolder_group "${folder_array[@]}" "$folder_name"
            merged_any=true
        fi
    done
    
    [[ "$merged_any" == false ]] && log_info "Дубликатов подпапок не найдено"
}

# Объединяем группу подпапок
merge_subfolder_group() {
    local folders=("$@")
    local last_idx=$((${#folders[@]} - 1))
    local folder_name="${folders[$last_idx]}"
    unset "folders[$last_idx]"
    
    local target_folder="${WORK_DIR}/${folder_name}"
    
    # Создаем целевую папку если нет
    [[ ! -d "$target_folder" ]] && mkdir -p "$target_folder"
    
    log_info "Объединяю подпапки '$folder_name'"
    
    # Перемещаем содержимое
    for source_folder in "${folders[@]}"; do
        [[ "$source_folder" == "$target_folder" ]] && continue
        
        for item in "$source_folder"/*; do
            [[ -e "$item" ]] || continue
            mv "$item" "$target_folder/"
        done
        
        rmdir "$source_folder" 2>/dev/null || true
    done
}

# Главная функция
main() {
    get_prefix
    echo
    
    # Шаг 1: Объединяем родительские папки
    find_parent_folders
    echo
    
    # Шаг 2: Объединяем подпапки с одинаковыми именами
    find_and_merge_subfolders
    echo
    
    log_success "Все операции завершены!"
}

# Запускаем
main "$@"
