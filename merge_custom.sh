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
    
    # Рекурсивно применяем ту же функцию к подпапкам в созданной папке
    log_info "Проверяю подпапки в созданной папке..."
    recursive_merge_subfolders "$target_folder" "$prefix"
}

# Рекурсивно объединяем подпапки с префиксом
recursive_merge_subfolders() {
    local current_folder="$1"
    local search_prefix="$2"  # Добавляем передачу префикса
    
    # Ищем подпапки в текущей папке
    local temp_file="/tmp/subfolders_recursive_$$"
    find "$current_folder" -maxdepth 1 -type d -not -path "$current_folder" > "$temp_file"
    
    # Группируем папки по префиксу (как у родителей)
    local merged_any=false
    local processed_folders=""
    
    while IFS= read -r folder; do
        [[ ! -d "$folder" ]] && continue
        [[ "$processed_folders" == *"$folder"* ]] && continue
        
        local folder_name=$(basename "$folder")
        
        # Ищем папки содержащие префикс
        if [[ "$folder_name" == *"$search_prefix"* ]]; then
            # Ищем другие папки с таким же префиксом
            local matching_folders=("$folder")
            processed_folders+="$folder|"
            
            while IFS= read -r other_folder; do
                [[ "$other_folder" == "$folder" ]] && continue
                [[ "$processed_folders" == *"$other_folder"* ]] && continue
                [[ ! -d "$other_folder" ]] && continue
                
                local other_name=$(basename "$other_folder")
                if [[ "$other_name" == *"$search_prefix"* ]]; then
                    matching_folders+=("$other_folder")
                    processed_folders+="$other_folder|"
                fi
            done < "$temp_file"
            
            # Если нашли больше 1 папки с префиксом - объединяем
            if [[ ${#matching_folders[@]} -gt 1 ]]; then
                log_info "Найдены папки с префиксом '$search_prefix' в '$(basename "$current_folder")': ${#matching_folders[@]} шт"
                
                # Объединяем подпапки
                merge_subfolder_group_recursive "${matching_folders[@]}" "$current_folder" "$search_prefix"
                merged_any=true
                
                # Выходим из цикла чтобы не обрабатывать повторно
                break
            fi
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    # Рекурсивно проверяем подпапки следующего уровня
    if [[ "$merged_any" == true ]]; then
        log_info "Повторная проверка подпапок в '$(basename "$current_folder")'..."
        recursive_merge_subfolders "$current_folder" "$search_prefix"
    fi
}

# Объединяем группу подпапок рекурсивно
merge_subfolder_group_recursive() {
    local folders=("$@")
    local last_idx=$((${#folders[@]} - 2))
    local last_idx=$((${#folders[@]} - 1))
    local parent_folder="${folders[$last_idx]}"
    unset "folders[$last_idx]"
    
    # Создаем целевую папку с префиксом
    local search_prefix="$2"
    local target_folder="${parent_folder}/${search_prefix}"
    
    # Создаем целевую папку если нет
    [[ ! -d "$target_folder" ]] && mkdir -p "$target_folder"
    
    log_info "Объединяю подпапки с префиксом '$search_prefix' в '$(basename "$parent_folder")'"
    
    # Перемещаем содержимое
    for source_folder in "${folders[@]}"; do
        [[ "$source_folder" == "$target_folder" ]] && continue
        
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
        
        rmdir "$source_folder" 2>/dev/null || true
    done
}

# Ищем дубликаты подпапок по префиксу
find_and_merge_subfolders() {
    local search_prefix="$1"  # Принимаем префикс как параметр
    log_info "Поиск подпапок с префиксом '$search_prefix'..."
    
    # Создаем временный файл со всеми подпапками
    local temp_file="/tmp/subfolders_$$"
    find "$WORK_DIR" -mindepth 2 -type d > "$temp_file"
    
    # Группируем папки по префиксу
    local merged_any=false
    local processed_folders=""
    
    while IFS= read -r folder; do
        [[ ! -d "$folder" ]] && continue
        [[ "$processed_folders" == *"$folder"* ]] && continue
        
        local folder_name=$(basename "$folder")
        
        # Ищем папки содержащие префикс
        if [[ "$folder_name" == *"$search_prefix"* ]]; then
            # Ищем другие папки с таким же префиксом
            local matching_folders=("$folder")
            processed_folders+="$folder|"
            
            while IFS= read -r other_folder; do
                [[ "$other_folder" == "$folder" ]] && continue
                [[ "$processed_folders" == *"$other_folder"* ]] && continue
                [[ ! -d "$other_folder" ]] && continue
                
                local other_name=$(basename "$other_folder")
                if [[ "$other_name" == *"$search_prefix"* ]]; then
                    matching_folders+=("$other_folder")
                    processed_folders+="$other_folder|"
                fi
            done < "$temp_file"
            
            # Если нашли больше 1 папки с префиксом - объединяем
            if [[ ${#matching_folders[@]} -gt 1 ]]; then
                log_info "Найдены подпапки с префиксом '$search_prefix': ${#matching_folders[@]} шт"
                
                # Объединяем подпапки
                merge_subfolder_group "${matching_folders[@]}"
                merged_any=true
            fi
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    [[ "$merged_any" == false ]] && log_info "Подпапок с префиксом '$search_prefix' не найдено"
}

# Объединяем группу подпапок
merge_subfolder_group() {
    local folders=("$@")
    
    # Создаем целевую папку с префиксом
    local target_folder="${WORK_DIR}/${prefix}"
    
    # Создаем целевую папку если нет
    [[ ! -d "$target_folder" ]] && mkdir -p "$target_folder"
    
    log_info "Объединяю подпапки с префиксом '$prefix'"
    
    # Перемещаем содержимое
    for source_folder in "${folders[@]}"; do
        [[ "$source_folder" == "$target_folder" ]] && continue
        
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
    find_and_merge_subfolders "$prefix"
    echo
    
    log_success "Все операции завершены!"
}

# Запускаем
main "$@"
