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

# Fast folder grouping using hash table by first 1-3 chars
find_similar_fast() {
    log_info "Поиск папок (быстрый алгоритм)..."
    
    # Get all folder names and paths
    local temp_file="/tmp/folders_$$"
    find "$WORK_DIR" -type d -not -path "$WORK_DIR" -printf "%f|%p\n" 2>/dev/null | sort > "$temp_file"
    
    local total=$(wc -l < "$temp_file")
    log_info "Найдено папок: $total"
    
    # Create hash table: prefix -> folder paths
    declare -A hash_1  # first char
    declare -A hash_2  # first 2 chars  
    declare -A hash_3  # first 3 chars
    
    # Build hash tables
    while IFS='|' read -r name path; do
        [[ ${#name} -lt 3 ]] && continue
        
        local prefix1="${name:0:1}"
        local prefix2="${name:0:2}"  
        local prefix3="${name:0:3}"
        
        hash_1["$prefix1"]+="$path|"
        hash_2["$prefix2"]+="$path|"
        hash_3["$prefix3"]+="$path|"
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    local merged_any=false
    
    # Check hash tables for potential matches
    for prefix in "${!hash_3[@]}"; do
        local paths="${hash_3[$prefix]}"
        local path_array=(${paths//|/ })
        
        if [[ ${#path_array[@]} -gt 1 ]]; then
            check_and_merge_group "${path_array[@]}" "$merged_any"
        fi
    done
    
    for prefix in "${!hash_2[@]}"; do
        local paths="${hash_2[$prefix]}"
        local path_array=(${paths//|/ })
        
        if [[ ${#path_array[@]} -gt 1 ]]; then
            check_and_merge_group "${path_array[@]}" "$merged_any"
        fi
    done
    
    for prefix in "${!hash_1[@]}"; do
        local paths="${hash_1[$prefix]}"
        local path_array=(${paths//|/ })
        
        if [[ ${#path_array[@]} -gt 1 ]]; then
            check_and_merge_group "${path_array[@]}" "$merged_any"
        fi
    done
    
    if [[ "$merged_any" == false ]]; then
        log_info "Подходящих папок для объединения не найдено"
    fi
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
