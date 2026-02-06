#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}"

log_info() { echo -e "${BLUE}[ИНФО]${NC} $1"; }
log_success() { echo -e "${GREEN}[УСПЕХ]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1"; }
log_error() { echo -e "${RED}[ОШИБКА]${NC} $1"; }

# Find longest common prefix
find_longest_prefix() {
    local str1="$1"
    local str2="$2"
    local common=""
    local min_len=${#str1}
    [[ ${#str2} -lt $min_len ]] && min_len=${#str2}
    
    for ((i=0; i<min_len; i++)); do
        [[ "${str1:$i:1}" == "${str2:$i:1}" ]] && common+="${str1:$i:1}" || break
    done
    echo "$common"
}

# Fast folder grouping with two-level logic
find_similar_fast() {
    log_info "Поиск папок (двухуровневый алгоритм)..."
    
    # Level 1: Parent folders (longest matches)
    log_info "Проверка родительских папок (1 уровень)..."
    find_parent_matches
    
    # Level 2+: Subfolders (exact matches only)
    log_info "Проверка подпапок (точные совпадения)..."
    find_subfolder_matches
}

# Find matches in parent folders (level 1)
find_parent_matches() {
    local temp_file="/tmp/parent_folders_$$"
    find "$WORK_DIR" -maxdepth 1 -type d -not -path "$WORK_DIR" -printf "%f|%p\n" 2>/dev/null | sort > "$temp_file"
    
    local total=$(wc -l < "$temp_file")
    [[ $total -eq 0 ]] && { rm -f "$temp_file"; return; }
    
    log_info "Родительских папок: $total"
    
    # Show found folders for debugging
    echo "Найденные папки:"
    while IFS='|' read -r name path; do
        echo "  - $name"
    done < "$temp_file"
    
    # Hash table for parent folders
    declare -A hash_1 hash_2 hash_3
    
    while IFS='|' read -r name path; do
        [[ ${#name} -lt 3 ]] && continue
        
        hash_1["${name:0:1}"]+="$path|"
        hash_2["${name:0:2}"]+="$path|"
        hash_3["${name:0:3}"]+="$path|"
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    local merged_any=false
    
    # Debug hash tables
    echo "Группы по 3 символам:"
    for prefix in "${!hash_3[@]}"; do
        local paths="${hash_3[$prefix]}"
        local path_array=(${paths//|/ })
        if [[ ${#path_array[@]} -gt 1 ]]; then
            echo "  Префикс '$prefix': ${#path_array[@]} папок"
            merge_parent_group "${path_array[@]}" "$merged_any"
        fi
    done
    
    for prefix in "${!hash_2[@]}"; do
        local paths="${hash_2[$prefix]}"
        local path_array=(${paths//|/ })
        if [[ ${#path_array[@]} -gt 1 ]]; then
            echo "  Префикс '$prefix': ${#path_array[@]} папок"
            merge_parent_group "${path_array[@]}" "$merged_any"
        fi
    done
    
    for prefix in "${!hash_1[@]}"; do
        local paths="${hash_1[$prefix]}"
        local path_array=(${paths//|/ })
        if [[ ${#path_array[@]} -gt 1 ]]; then
            echo "  Префикс '$prefix': ${#path_array[@]} папок"
            merge_parent_group "${path_array[@]}" "$merged_any"
        fi
    done
    
    if [[ "$merged_any" == false ]]; then
        log_info "Подходящих папок для объединения не найдено"
    fi
}

# Merge parent folders to common folder
merge_parent_group() {
    local folders=("$@")
    local last_idx=$((${#folders[@]} - 1))
    local merged_any_ref="${folders[$last_idx]}"
    unset "folders[$last_idx]"
    
    echo "DEBUG: Получено папок для обработки: ${#folders[@]}"
    for folder in "${folders[@]}"; do
        echo "DEBUG: - $(basename "$folder")"
    done
    
    # Find longest common prefix among all folder names
    local common_prefix=""
    if [[ ${#folders[@]} -gt 0 ]]; then
        common_prefix=$(basename "${folders[0]}")
        echo "DEBUG: Начальный префикс: '$common_prefix'"
        for ((i=1; i<${#folders[@]}; i++)); do
            local next_name=$(basename "${folders[i]}")
            echo "DEBUG: Сравниваем '$common_prefix' с '$next_name'"
            common_prefix=$(find_longest_prefix "$common_prefix" "$next_name")
            echo "DEBUG: Новый префикс: '$common_prefix'"
        done
    fi
    
    echo "DEBUG: Итоговый префикс: '$common_prefix' (длина: ${#common_prefix})"
    
    # Only merge if we have a meaningful common prefix
    if [[ ${#common_prefix} -lt 3 ]]; then
        echo "DEBUG: Префикс слишком короткий, пропускаем"
        return 0
    fi
    
    log_info "Найдена группа родителей: '$common_prefix'"
    for folder in "${folders[@]}"; do
        echo "  - $(basename "$folder")"
    done
    
    read -p "Объединить в папку '$common_prefix'? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Create target folder with common prefix name
        local target_folder="${WORK_DIR}/${common_prefix}"
        if [[ -d "$target_folder" ]]; then
            local counter=1
            while [[ -d "${WORK_DIR}/${common_prefix}_${counter}" ]]; do
                counter=$((counter + 1))
            done
            target_folder="${WORK_DIR}/${common_prefix}_${counter}"
        fi
        
        mkdir -p "$target_folder"
        log_info "Создана папка: $(basename "$target_folder")"
        
        # Move content from all parent folders
        for folder in "${folders[@]}"; do
            [[ ! -d "$folder" ]] && continue
            
            log_info "Перемещение содержимого из $(basename "$folder")"
            
            for item in "$folder"/*; do
                [[ -e "$item" ]] || continue
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
        
        log_success "Объединение завершено"
        merged_any_ref=true
    fi
}

# Find exact matches in subfolders (level 2+)
find_subfolder_matches() {
    local temp_file="/tmp/subfolders_$$"
    find "$WORK_DIR" -mindepth 2 -type d -printf "%f|%p\n" 2>/dev/null | sort > "$temp_file"
    
    local total=$(wc -l < "$temp_file")
    [[ $total -eq 0 ]] && { rm -f "$temp_file"; return; }
    
    log_info "Подпапок: $total"
    
    # Hash table for exact matches only
    declare -A exact_matches
    
    while IFS='|' read -r name path; do
        exact_matches["$name"]+="$path|"
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    local merged_any=false
    
    # Check only exact matches
    for name in "${!exact_matches[@]}"; do
        local paths="${exact_matches[$name]}"
        local path_array=(${paths//|/ })
        
        if [[ ${#path_array[@]} -gt 1 ]]; then
            log_info "Найдено точное совпадение: '$name'"
            for p in "${path_array[@]}"; do
                echo "  - $(basename "$p")"
            done
            
            read -p "Объединить? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                merge_exact_matches "${path_array[@]}" "$name"
                merged_any=true
            fi
        fi
    done
}

# Check and merge group of folders
check_and_merge_group() {
    local folders=("$@")
    local last_idx=$((${#folders[@]} - 1))
    local merged_any_ref="${folders[$last_idx]}"
    unset "folders[$last_idx]"
    
    for ((i=0; i<${#folders[@]}; i++)); do
        for ((j=i+1; j<${#folders[@]}; j++)); do
            local folder1="${folders[i]}"
            local folder2="${folders[j]}"
            
            [[ ! -d "$folder1" || ! -d "$folder2" ]] && continue
            
            local name1=$(basename "$folder1")
            local name2=$(basename "$folder2")
            local prefix=$(find_longest_prefix "$name1" "$name2")
            
            if [[ ${#prefix} -ge 3 && "$prefix" != "$name1" && "$prefix" != "$name2" ]]; then
                log_info "Найдено совпадение: '$prefix'"
                echo "  - $name1"
                echo "  - $name2"
                
                read -p "Объединить? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    merge_content "$folder1" "$folder2" "$prefix"
                    merged_any_ref=true
                fi
            fi
        done
    done
}

# Merge exact matches (for subfolders)
merge_exact_matches() {
    local folders=("$@")
    local last_idx=$((${#folders[@]} - 1))
    local folder_name="${folders[$last_idx]}"
    unset "folders[$last_idx]"
    
    # Create parent folder with exact name
    local parent_folder="${WORK_DIR}/${folder_name}"
    if [[ ! -d "$parent_folder" ]]; then
        mkdir -p "$parent_folder"
        log_info "Создана папка: $(basename "$parent_folder")"
    fi
    
    # Move content from all folders
    for folder in "${folders[@]}"; do
        [[ ! -d "$folder" ]] && continue
        
        log_info "Перемещение содержимого из $(basename "$folder")"
        
        for item in "$folder"/*; do
            [[ -e "$item" ]] || continue
            local item_name=$(basename "$item")
            local dest_path="${parent_folder}/${item_name}"
            
            # Handle conflicts
            local counter=1
            while [[ -e "$dest_path" ]]; do
                if [[ -d "$item" ]]; then
                    dest_path="${parent_folder}/${item_name}_${counter}"
                else
                    local name_without_ext="${item_name%.*}"
                    local extension="${item_name##*.}"
                    [[ "$name_without_ext" == "$extension" ]] && dest_path="${parent_folder}/${item_name}_${counter}" || dest_path="${parent_folder}/${name_without_ext}_${counter}.${extension}"
                fi
                counter=$((counter + 1))
            done
            
            mv "$item" "$dest_path"
        done
        
        rmdir "$folder" 2>/dev/null || true
    done
    
    log_success "Объединение завершено"
}

# Merge content from child folders to parent
merge_content() {
    local folder1="$1"
    local folder2="$2"
    local prefix="$3"
    
    # Find or create parent folder
    local parent_folder="${WORK_DIR}/${prefix}"
    if [[ ! -d "$parent_folder" ]]; then
        mkdir -p "$parent_folder"
        log_info "Создана родительская папка: $(basename "$parent_folder")"
    fi
    
    # Move content from both folders
    for folder in "$folder1" "$folder2"; do
        log_info "Перемещение содержимого из $(basename "$folder")"
        
        for item in "$folder"/*; do
            [[ -e "$item" ]] || continue
            local item_name=$(basename "$item")
            local dest_path="${parent_folder}/${item_name}"
            
            # Handle conflicts
            local counter=1
            while [[ -e "$dest_path" ]]; do
                if [[ -d "$item" ]]; then
                    dest_path="${parent_folder}/${item_name}_${counter}"
                else
                    local name_without_ext="${item_name%.*}"
                    local extension="${item_name##*.}"
                    [[ "$name_without_ext" == "$extension" ]] && dest_path="${parent_folder}/${item_name}_${counter}" || dest_path="${parent_folder}/${name_without_ext}_${counter}.${extension}"
                fi
                counter=$((counter + 1))
            done
            
            mv "$item" "$dest_path"
        done
        
        rmdir "$folder" 2>/dev/null || true
    done
    
    log_success "Объединение завершено"
}

# Main
main() {
    echo -e "${BLUE}Merge Similar Folders (FAST)${NC}"
    echo "==============================="
    echo
    
    [[ ! -d "$WORK_DIR" ]] && { log_error "Рабочая директория не найдена"; exit 1; }
    
    log_info "Рабочая директория: $WORK_DIR"
    find_similar_fast
}

main "$@"
