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

# Find all folders recursively
find_all_folders() {
    local folders=()
    while IFS= read -r -d '' folder; do
        [[ -d "$folder" ]] && folders+=("$folder")
    done < <(find "$WORK_DIR" -type d -print0 2>/dev/null)
    echo "${folders[@]}"
}

# Main merge function
merge_similar_folders() {
    log_info "Поиск папок с похожими названиями..."
    
    local folders=($(find_all_folders))
    local merged_any=false
    
    for ((i=0; i<${#folders[@]}; i++)); do
        for ((j=i+1; j<${#folders[@]}; j++)); do
            local folder1="${folders[i]}"
            local folder2="${folders[j]}"
            
            [[ ! -d "$folder1" || ! -d "$folder2" ]] && continue
            
            local name1=$(basename "$folder1")
            local name2=$(basename "$folder2")
            local prefix=$(find_longest_prefix "$name1" "$name2")
            
            # Check if prefix is meaningful (at least 3 chars)
            if [[ ${#prefix} -ge 3 && "$prefix" != "$name1" && "$prefix" != "$name2" ]]; then
                log_info "Найдено совпадение: '$prefix'"
                echo "  - $name1 ($folder1)"
                echo "  - $name2 ($folder2)"
                
                read -p "Объединить? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    merge_content "$folder1" "$folder2" "$prefix"
                    merged_any=true
                fi
            fi
        done
    done
    
    if [[ "$merged_any" == false ]]; then
        log_info "Подходящих папок для объединения не найдено"
    fi
}

# Merge content from child folders to parent
merge_content() {
    local folder1="$1"
    local folder2="$2"
    local prefix="$3"
    
    # Find parent folder that contains the prefix
    local parent_folder=$(find "$WORK_DIR" -type d -name "*${prefix}*" | head -1)
    
    if [[ -z "$parent_folder" ]]; then
        parent_folder="${WORK_DIR}/${prefix}"
        mkdir -p "$parent_folder"
        log_info "Создана родительская папка: $parent_folder"
    fi
    
    # Move content from both folders
    for folder in "$folder1" "$folder2"; do
        log_info "Перемещение содержимого из $(basename "$folder") в $parent_folder"
        
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
        
        # Remove empty folder
        rmdir "$folder" 2>/dev/null || true
    done
    
    log_success "Объединение завершено"
}

# Main
main() {
    echo -e "${BLUE}Merge Similar Folders${NC}"
    echo "======================="
    echo
    
    [[ ! -d "$WORK_DIR" ]] && { log_error "Рабочая директория не найдена"; exit 1; }
    
    log_info "Рабочая директория: $WORK_DIR"
    merge_similar_folders
}

main "$@"
