#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}"

log_info() { echo -e "${BLUE}[ИНФО]${NC} $1"; }
log_success() { echo -e "${GREEN}[УСПЕХ]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1"; }
log_error() { echo -e "${RED}[ОШИБКА]${NC} $1"; }
log_progress() { echo -e "${CYAN}[ПРОГРЕСС]${NC} $1"; }

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r["
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d/%d (%d%%)" $current $total $percentage
}

# Get user input
get_user_input() {
    echo -e "${BLUE}Custom Merge Tool${NC}"
    echo "=================="
    echo
    
    read -p "Введите префикс для поиска папок (например: 'project'): " prefix
    [[ -z "$prefix" ]] && { log_error "Префикс не может быть пустым"; exit 1; }
    
    read -p "Введите название для папки объединения: " merge_folder_name
    [[ -z "$merge_folder_name" ]] && { log_error "Название папки не может быть пустым"; exit 1; }
    
    log_info "Префикс поиска: '$prefix'"
    log_info "Папка объединения: '$merge_folder_name'"
    echo
}

# Find parent folders by prefix
find_parent_folders() {
    log_info "Поиск родительских папок с префиксом '$prefix'..."
    
    local temp_file="/tmp/parent_folders_$$"
    find "$WORK_DIR" -maxdepth 1 -type d -not -path "$WORK_DIR" -printf "%f|%p\n" 2>/dev/null | sort > "$temp_file"
    
    local parent_folders=()
    local total=$(wc -l < "$temp_file")
    local processed=0
    
    while IFS='|' read -r name path; do
        processed=$((processed + 1))
        show_progress $processed $total
        
        if [[ "$name" == "$prefix"* ]]; then
            parent_folders+=("$path")
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    echo # New line after progress bar
    
    if [[ ${#parent_folders[@]} -eq 0 ]]; then
        log_warning "Родительских папок с префиксом '$prefix' не найдено"
        return 0
    fi
    
    log_info "Найдено родительских папок: ${#parent_folders[@]}"
    for folder in "${parent_folders[@]}"; do
        echo "  - $(basename "$folder")"
    done
    
    merge_parent_folders "${parent_folders[@]}"
}

# Merge parent folders
merge_parent_folders() {
    local folders=("$@")
    
    if [[ ${#folders[@]} -lt 2 ]]; then
        log_info "Недостаточно папок для объединения (${#folders[@]})"
        return 0
    fi
    
    echo
    read -p "Объединить ${#folders[@]} папок в '$merge_folder_name'? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return 0
    
    local target_folder="${WORK_DIR}/${merge_folder_name}"
    if [[ -d "$target_folder" ]]; then
        local counter=1
        while [[ -d "${WORK_DIR}/${merge_folder_name}_${counter}" ]]; do
            counter=$((counter + 1))
        done
        target_folder="${WORK_DIR}/${merge_folder_name}_${counter}"
    fi
    
    mkdir -p "$target_folder"
    log_info "Создана папка: $(basename "$target_folder")"
    
    local total_items=0
    for folder in "${folders[@]}"; do
        [[ ! -d "$folder" ]] && continue
        total_items=$((total_items + $(find "$folder" -maxdepth 1 | wc -l) - 1))
    done
    
    local processed_items=0
    echo "Перемещение $total_items элементов..."
    
    for folder in "${folders[@]}"; do
        [[ ! -d "$folder" ]] && continue
        
        log_progress "Перемещение из $(basename "$folder")"
        
        for item in "$folder"/*; do
            [[ -e "$item" ]] || continue
            processed_items=$((processed_items + 1))
            show_progress $processed_items $total_items
            
            local item_name=$(basename "$item")
            local dest_path="${target_folder}/${item_name}"
            
            # Handle conflicts
            local counter=1
            while [[ -e "$dest_path" ]]; do
                if [[ -d "$item" ]]; then
                    dest_path="${target_folder}/${item_name}_${counter}"
                else
                    local name_without_ext="${item_name%.*}"
                    local extension="${item_name##*.}"
                    [[ "$name_without_ext" == "$extension" ]] && dest_path="${target_folder}/${item_name}_${counter}" || dest_path="${target_folder}/${name_without_ext}_${counter}.${extension}"
                fi
                counter=$((counter + 1))
            done
            
            mv "$item" "$dest_path"
        done
        
        rmdir "$folder" 2>/dev/null || true
    done
    
    echo # New line after progress bar
    log_success "Родительские папки объединены"
}

# Find subfolders with exact matches
find_subfolders() {
    log_info "Поиск подпапок с точными совпадениями..."
    
    local temp_file="/tmp/subfolders_$$"
    find "$WORK_DIR" -mindepth 2 -maxdepth 4 -type d -printf "%f|%p\n" 2>/dev/null | sort > "$temp_file"
    
    local total=$(wc -l < "$temp_file")
    [[ $total -eq 0 ]] && { rm -f "$temp_file"; return; }
    
    log_info "Всего подпапок: $total"
    
    # Create hash for exact matches
    declare -A exact_matches
    local processed=0
    
    while IFS='|' read -r name path; do
        processed=$((processed + 1))
        show_progress $processed $total
        
        exact_matches["$name"]+="$path|"
    done < "$temp_file"
    
    rm -f "$temp_file"
    echo # New line after progress bar
    
    local merged_any=false
    local total_groups=${#exact_matches[@]}
    local current_group=0
    
    for name in "${!exact_matches[@]}"; do
        current_group=$((current_group + 1))
        echo
        log_progress "Обработка группы $current_group/$total_groups"
        
        local paths="${exact_matches[$name]}"
        local path_array=(${paths//|/ })
        
        if [[ ${#path_array[@]} -gt 1 ]]; then
            log_info "Найдено точное совпадение: '$name' (${#path_array[@]} папок)"
            for p in "${path_array[@]}"; do
                echo "  - $(dirname "$p")/$(basename "$p")"
            done
            
            read -p "Объединить? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                merge_exact_subfolders "${path_array[@]}" "$name"
                merged_any=true
            fi
        fi
    done
    
    if [[ "$merged_any" == false ]]; then
        log_info "Подпапок с точными совпадениями не найдено"
    fi
}

# Merge exact subfolders
merge_exact_subfolders() {
    local folders=("$@")
    local last_idx=$((${#folders[@]} - 1))
    local folder_name="${folders[$last_idx]}"
    unset "folders[$last_idx]"
    
    local target_folder="${WORK_DIR}/${folder_name}"
    if [[ -d "$target_folder" ]]; then
        local counter=1
        while [[ -d "${WORK_DIR}/${folder_name}_${counter}" ]]; do
            counter=$((counter + 1))
        done
        target_folder="${WORK_DIR}/${folder_name}_${counter}"
    fi
    
    mkdir -p "$target_folder"
    log_info "Создана папка: $(basename "$target_folder")"
    
    local total_items=0
    for folder in "${folders[@]}"; do
        [[ ! -d "$folder" ]] && continue
        total_items=$((total_items + $(find "$folder" -maxdepth 1 | wc -l) - 1))
    done
    
    local processed_items=0
    echo "Перемещение $total_items элементов..."
    
    for folder in "${folders[@]}"; do
        [[ ! -d "$folder" ]] && continue
        
        for item in "$folder"/*; do
            [[ -e "$item" ]] || continue
            processed_items=$((processed_items + 1))
            show_progress $processed_items $total_items
            
            local item_name=$(basename "$item")
            local dest_path="${target_folder}/${item_name}"
            
            # Handle conflicts
            local counter=1
            while [[ -e "$dest_path" ]]; do
                if [[ -d "$item" ]]; then
                    dest_path="${target_folder}/${item_name}_${counter}"
                else
                    local name_without_ext="${item_name%.*}"
                    local extension="${item_name##*.}"
                    [[ "$name_without_ext" == "$extension" ]] && dest_path="${target_folder}/${item_name}_${counter}" || dest_path="${target_folder}/${name_without_ext}_${counter}.${extension}"
                fi
                counter=$((counter + 1))
            done
            
            mv "$item" "$dest_path"
        done
        
        rmdir "$folder" 2>/dev/null || true
    done
    
    echo # New line after progress bar
    log_success "Подпапки объединены"
}

# Main function
main() {
    get_user_input
    
    echo
    log_info "Начало объединения..."
    echo
    
    find_parent_folders
    echo
    find_subfolders
    echo
    
    log_success "Объединение завершено!"
}

main "$@"
