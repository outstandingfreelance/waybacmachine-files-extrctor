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

# Функция поиска общего префикса по буквам
find_common_prefix() {
    local folders=("$@")
    
    # Если меньше 2 папок - нет префикса
    [[ ${#folders[@]} -lt 2 ]] && return 1
    
    local first_folder="${folders[0]}"
    local prefix=""
    
    # Идем по символам первой папки
    for ((i=0; i<${#first_folder}; i++)); do
        local char="${first_folder:$i:1}"
        local all_match=true
        
        # Проверяем этот символ во всех папках
        for folder in "${folders[@]:1}"; do
            [[ "${folder:$i:1}" == "$char" ]] || {
                all_match=false
                break
            }
        done
        
        # Если все совпали - добавляем символ к префиксу
        [[ "$all_match" == true ]] && prefix+="$char" || break
    done
    
    # Префикс должен быть хотя бы из 2 символов
    [[ ${#prefix} -ge 2 ]] && echo "$prefix" || return 1
}

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
    recursive_merge_subfolders "$target_folder"
}

# Рекурсивно объединяем подпапки по общим префиксам (глубина 4 уровня)
recursive_merge_subfolders() {
    local current_folder="$1"
    local current_depth="${2:-1}"
    
    # Ограничиваем глубину 4 уровнями
    [[ $current_depth -gt 4 ]] && return
    
    log_info "Проверка уровня $current_depth в '$(basename "$current_folder")'..."
    
    # Ищем подпапки в текущей папке
    local temp_file="/tmp/subfolders_recursive_$$"
    find "$current_folder" -maxdepth 1 -type d -not -path "$current_folder" > "$temp_file"
    
    # Получаем все подпапки
    local all_subfolders=()
    while IFS= read -r folder; do
        [[ -d "$folder" ]] && all_subfolders+=("$(basename "$folder")")
    done < "$temp_file"
    
    [[ ${#all_subfolders[@]} -lt 2 ]] && {
        rm -f "$temp_file"
        return
    }
    
    log_info "Найдено подпапок: ${#all_subfolders[@]}"
    
    local processed_folders=""
    local merged_any=false
    
    # Ищем группы с общими префиксами
    for ((i=0; i<${#all_subfolders[@]}; i++)); do
        local current_subfolder="${all_subfolders[i]}"
        [[ "$processed_folders" == *"$current_subfolder"* ]] && continue
        
        # Ищем подпапки с общим префиксом
        local matching_folders=("$current_subfolder")
        processed_folders+="$current_subfolder|"
        
        for ((j=i+1; j<${#all_subfolders[@]}; j++)); do
            local other_subfolder="${all_subfolders[j]}"
            [[ "$processed_folders" == *"$other_subfolder"* ]] && continue
            
            # Проверяем есть ли общий префикс
            local test_folders=("$current_subfolder" "$other_subfolder")
            local common_prefix=$(find_common_prefix "${test_folders[@]}")
            
            [[ -n "$common_prefix" ]] && {
                # Ищем все подпапки с этим префиксом
                for ((k=0; k<${#all_subfolders[@]}; k++)); do
                    [[ $k -eq $i ]] && continue
                    local check_subfolder="${all_subfolders[k]}"
                    [[ "$processed_folders" == *"$check_subfolder"* ]] && continue
                    
                    if [[ "$check_subfolder" == "$common_prefix"* ]]; then
                        matching_folders+=("$check_subfolder")
                        processed_folders+="$check_subfolder|"
                    fi
                done
                
                break
            }
        done
        
        # Если нашли группу с общим префиксом - объединяем
        if [[ ${#matching_folders[@]} -gt 1 ]]; then
            local common_prefix=$(find_common_prefix "${matching_folders[@]}")
            [[ -n "$common_prefix" ]] && {
                log_info "Найден общий префикс '$common_prefix': ${#matching_folders[@]} подпапок"
                
                # Показываем найденные подпапки
                for folder in "${matching_folders[@]}"; do
                    echo "  - $folder"
                done
                
                # Спрашиваем подтверждение
                echo
                echo -n "Объединить эти подпапки? (y/n): "
                read confirm
                log_info "Пользователь ввел: '$confirm'"
                
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    log_info "Начинаю процесс объединения..."
                    
                    # Создаем массив только с папками которые нужно объединить
                    local folders_to_merge=()
                    for folder in "${matching_folders[@]}"; do
                        [[ "$folder" != "$common_prefix" ]] && folders_to_merge+=("$folder")
                    done
                    
                    log_info "Папок для объединения: ${#folders_to_merge[@]}"
                    [[ ${#folders_to_merge[@]} -eq 0 ]] && {
                        log_warning "Нет папок для объединения (пропускаем)"
                        continue
                    }
                    
                    # Объединяем в папку с общим префиксом
                    log_info "Вызываю merge_subfolders_by_prefix..."
                    merge_subfolders_by_prefix "$current_folder" "$common_prefix" "${folders_to_merge[@]}"
                    merged_any=true
                    log_info "Завершил merge_subfolders_by_prefix"
                else
                    log_info "Пользователь отказался от объединения"
                fi
            }
        fi
    done
    
    rm -f "$temp_file"
    
    # Рекурсивно проверяем следующий уровень
    if [[ "$merged_any" == true ]]; then
        log_info "Переход на уровень $((current_depth + 1))..."
        recursive_merge_subfolders "$current_folder" $((current_depth + 1))
    fi
}

# Объединение подпапок по найденному префиксу
merge_subfolders_by_prefix() {
    local parent_folder="$1"
    local prefix="$2"
    shift 2
    local folders=("$@")
    local target_folder="${parent_folder}/${prefix}"
    
    log_info "Начинаю объединение: parent=$parent_folder, prefix=$prefix, folders=${#folders[@]}"
    
    # Если целевая папка не существует, создаем ее
    if [[ ! -d "$target_folder" ]]; then
        mkdir -p "$target_folder"
        log_info "Создана папка: $(basename "$target_folder")"
    fi
    
    log_info "Объединяю подпапки в '$(basename "$target_folder")'"
    
    # Перемещаем содержимое
    for folder in "${folders[@]}"; do
        local full_path="${parent_folder}/${folder}"
        log_info "Проверяю папку: $full_path"
        
        [[ "$full_path" == "$target_folder" ]] && continue
        [[ ! -d "$full_path" ]] && {
            log_warning "Папка не существует: $full_path"
            continue
        }
        
        local folder_name=$(basename "$full_path")
        log_info "Перемещаю из подпапки: $folder_name"
        
        # Перемещаем все файлы и подпапки
        local items_moved=0
        for item in "$full_path"/*; do
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
            items_moved=$((items_moved + 1))
        done
        
        log_info "Перемещено $items_moved элементов из $folder_name"
        
        # Удаляем пустую папку
        rmdir "$full_path" 2>/dev/null || true
    done
    
    log_success "Подпапки с префиксом '$prefix' объединены"
}

# Главная функция
main() {
    get_prefix
    echo
    
    # Шаг 1: Объединяем родительские папки
    find_parent_folders
    echo
    
    log_success "Все операции завершены!"
}

# Запускаем
main "$@"
