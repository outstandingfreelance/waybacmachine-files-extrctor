#!/bin/bash

# File Organizer Script for macOS
# Extracts files from first-level folders, merges duplicates, and handles hash conflicts

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}"
OUTPUT_DIR="${SCRIPT_DIR}/organized_files"
TEMP_DIR="${SCRIPT_DIR}/.temp_organizer"
DUPLICATE_FILES_FILE="${TEMP_DIR}/duplicate_files.txt"
HASH_MAP_FILE="${TEMP_DIR}/hash_map.txt"

# Cleanup function
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Trap for cleanup
trap cleanup EXIT

# Create temp directory
mkdir -p "$TEMP_DIR"

# Logging functions
log_info() {
    echo -e "${BLUE}[ИНФО]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[УСПЕХ]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1"
}

log_error() {
    echo -e "${RED}[ОШИБКА]${NC} $1"
}

# Calculate file hash
calculate_hash() {
    local file="$1"
    if command -v md5 >/dev/null 2>&1; then
        md5 -q "$file"
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | cut -d' ' -f1
    else
        shasum -a 256 "$file" | cut -d' ' -f1
    fi
}

# Step 1: Extract files and folders from first-level folders
extract_files_and_folders() {
    log_info "Шаг 1: Извлечение файлов и папок из папок первого уровня..."
    
    # Create output directory
    if [[ -d "$OUTPUT_DIR" ]]; then
        log_warning "Папка $OUTPUT_DIR уже существует. Её содержимое будет очищено."
        rm -rf "$OUTPUT_DIR"
    fi
    mkdir -p "$OUTPUT_DIR"
    log_info "Создана папка для результата: $OUTPUT_DIR"
    
    local extracted_count=0
    local folder_count=0
    
    # Find all first-level directories (excluding output and temp dirs)
    for folder in "$WORK_DIR"/*; do
        if [[ -d "$folder" && "$(basename "$folder")" != ".temp_organizer" && "$(basename "$folder")" != "organized_files" ]]; then
            folder_count=$((folder_count + 1))
            local folder_name=$(basename "$folder")
            log_info "Обработка папки: $folder_name"
            
            # Extract all items (files and folders) from this folder
            for item in "$folder"/*; do
                if [[ -e "$item" ]]; then
                    local item_name=$(basename "$item")
                    local new_path="${OUTPUT_DIR}/${item_name}"
                    
                    # Handle name conflicts
                    local counter=1
                    while [[ -e "$new_path" ]]; do
                        if [[ -d "$item" ]]; then
                            new_path="${OUTPUT_DIR}/${item_name}_${counter}"
                        else
                            local name_without_ext="${item_name%.*}"
                            local extension="${item_name##*.}"
                            if [[ "$name_without_ext" == "$extension" ]]; then
                                new_path="${OUTPUT_DIR}/${item_name}_${counter}"
                            else
                                new_path="${OUTPUT_DIR}/${name_without_ext}_${counter}.${extension}"
                            fi
                        fi
                        counter=$((counter + 1))
                    done
                    
                    # Move item to output directory
                    if [[ -d "$item" ]]; then
                        mv "$item" "$new_path"
                        log_info "  Извлечена папка: $(basename "$item")"
                    else
                        mv "$item" "$new_path"
                        log_info "  Извлечен файл: $(basename "$item")"
                    fi
                    extracted_count=$((extracted_count + 1))
                fi
            done
            
            # Remove empty folder
            rmdir "$folder" 2>/dev/null || true
        fi
    done
    
    log_success "Извлечено $extracted_count элементов из $folder_count папок"
}

# Function to find base name without suffix
get_base_name() {
    local name="$1"
    # Remove suffix pattern like _1, _2, _01, etc.
    echo "$name" | sed 's/_[0-9]\+$//'
}

# Function to find common prefix between two strings
find_common_prefix() {
    local str1="$1"
    local str2="$2"
    local common=""
    local min_len=${#str1}
    if [[ ${#str2} -lt $min_len ]]; then
        min_len=${#str2}
    fi
    
    for ((i=0; i<min_len; i++)); do
        if [[ "${str1:$i:1}" == "${str2:$i:1}" ]]; then
            common+="${str1:$i:1}"
        else
            break
        fi
    done
    
    echo "$common"
}

# Step 2: Find and merge folders with similar names
find_similar_folders() {
    log_info "Шаг 2: Поиск папок с похожими названиями..."
    
    # Check if output directory exists
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_warning "Папка $OUTPUT_DIR не найдена. Сначала выполните шаг 1."
        return 1
    fi
    
    # Get all folder names in output directory
    local folder_names=()
    local folder_paths=()
    for folder in "$OUTPUT_DIR"/*; do
        if [[ -d "$folder" ]]; then
            folder_names+=("$(basename "$folder")")
            folder_paths+=("$folder")
        fi
    done
    
    if [[ ${#folder_names[@]} -eq 0 ]]; then
        log_info "Папок для обработки не найдено"
        return 0
    fi
    
    # Find groups of similar folders
    local groups_found=false
    
    for ((i=0; i<${#folder_names[@]}; i++)); do
        local current_name="${folder_names[i]}"
        local current_base=$(get_base_name "$current_name")
        local similar_indices=($i)
        
        # Find folders with similar base names
        for ((j=i+1; j<${#folder_names[@]}; j++)); do
            local compare_name="${folder_names[j]}"
            local compare_base=$(get_base_name "$compare_name")
            
            # Check if base names match
            if [[ "$current_base" == "$compare_base" ]]; then
                similar_indices+=($j)
            fi
        done
        
        # If we found similar folders, merge them
        if [[ ${#similar_indices[@]} -gt 1 ]]; then
            groups_found=true
            log_info "Найдена группа похожих папок: '$current_base'"
            
            # Show found folders
            for idx in "${similar_indices[@]}"; do
                echo "  - ${folder_names[idx]}"
            done
            
            # Ask for confirmation
            echo
            read -p "Объединить эти папки? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                merge_similar_folders "$current_base" "${similar_indices[@]}" "${folder_paths[@]}"
            fi
        fi
    done
    
    if [[ "$groups_found" == false ]]; then
        log_info "Папок с похожими названиями не найдено"
    fi
}

# Merge similar folders into one
merge_similar_folders() {
    local base_name="$1"
    shift
    local similar_indices=("${@:1:$((${#@}/2))}")
    local folder_paths=("${@:$((${#@}/2+1))}")
    
    # Create merged folder
    local merged_folder="${OUTPUT_DIR}/${base_name}"
    if [[ -d "$merged_folder" ]]; then
        local counter=1
        while [[ -d "${OUTPUT_DIR}/${base_name}_${counter}" ]]; do
            counter=$((counter + 1))
        done
        merged_folder="${OUTPUT_DIR}/${base_name}_${counter}"
    fi
    
    mkdir -p "$merged_folder"
    log_info "Создана объединенная папка: $(basename "$merged_folder")"
    
    # Move content from all similar folders to merged folder
    for ((i=0; i<${#similar_indices[@]}; i++)); do
        local idx=${similar_indices[i]}
        local source_folder="${folder_paths[idx]}"
        
        log_info "  Перемещение содержимого из: $(basename "$source_folder")"
        
        # Move all items from source to merged folder
        for item in "$source_folder"/*; do
            if [[ -e "$item" ]]; then
                local item_name=$(basename "$item")
                local dest_path="${merged_folder}/${item_name}"
                
                # Handle conflicts
                local counter=1
                while [[ -e "$dest_path" ]]; do
                    if [[ -d "$item" ]]; then
                        dest_path="${merged_folder}/${item_name}_${counter}"
                    else
                        local name_without_ext="${item_name%.*}"
                        local extension="${item_name##*.}"
                        if [[ "$name_without_ext" == "$extension" ]]; then
                            dest_path="${merged_folder}/${item_name}_${counter}"
                        else
                            dest_path="${merged_folder}/${name_without_ext}_${counter}.${extension}"
                        fi
                    fi
                    counter=$((counter + 1))
                done
                
                mv "$item" "$dest_path"
            fi
        done
        
        # Remove empty source folder
        rmdir "$source_folder" 2>/dev/null || true
    done
    
    log_success "Объединено ${#similar_indices[@]} папок в $(basename "$merged_folder")"
}

# Step 3: Check for duplicate files by hash in output directory
check_duplicate_files() {
    log_info "Шаг 3: Проверка дубликатов файлов по хэшу..."
    
    # Check if output directory exists
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_warning "Папка $OUTPUT_DIR не найдена. Сначала выполните шаг 1."
        return 1
    fi
    
    # Build hash map for files in output directory
    > "$HASH_MAP_FILE"
    > "$DUPLICATE_FILES_FILE"
    
    local file_count=0
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]]; then
            local hash=$(calculate_hash "$file")
            echo "${hash}|${file}" >> "$HASH_MAP_FILE"
            file_count=$((file_count + 1))
        fi
    done < <(find "$OUTPUT_DIR" -type f -print0 2>/dev/null)
    
    log_info "Прохэшировано $file_count файлов"
    
    # Find duplicates
    local duplicates_found=false
    while IFS='|' read -r hash file_path; do
        local count=$(grep -c "^${hash}|" "$HASH_MAP_FILE" || true)
        if [[ $count -gt 1 ]]; then
            if ! grep -q "^${hash}|" "$DUPLICATE_FILES_FILE"; then
                echo "${hash}|${count}" >> "$DUPLICATE_FILES_FILE"
                duplicates_found=true
            fi
        fi
    done < "$HASH_MAP_FILE"
    
    if [[ "$duplicates_found" == false ]]; then
        log_success "Дубликаты файлов по хэшу не найдены"
        return 0
    fi
    
    log_warning "Найдены дубликаты файлов по хэшу:"
    while IFS='|' read -r hash count; do
        echo "  Хэш: $hash ($count копий)"
        grep "^${hash}|" "$HASH_MAP_FILE" | cut -d'|' -f2 | while read -r file; do
            echo "    - $(basename "$file") ($(du -h "$file" | cut -f1))"
        done
        echo
    done < "$DUPLICATE_FILES_FILE"
    
    # Ask user what to do with duplicates
    handle_duplicate_files
}

# Handle duplicate files interactively
handle_duplicate_files() {
    echo
    echo -e "${YELLOW}Найдены дубликаты файлов! Выберите опцию:${NC}"
    echo "1) Удалить все дубликаты (оставить первое вхождение)"
    echo "2) Просмотреть дубликаты один за другим"
    echo "3) Пропустить удаление"
    echo "4) Показать детальную информацию о файлах"
    echo
    
    read -p "Введите ваш выбор (1-4): " choice
    
    case $choice in
        1)
            delete_all_duplicates
            ;;
        2)
            review_duplicates_one_by_one
            ;;
        3)
            log_info "Пропуск удаления дубликатов"
            ;;
        4)
            show_detailed_info
            handle_duplicate_files
            ;;
        *)
            log_error "Неверный выбор. Пропуск удаления."
            ;;
    esac
}

# Delete all duplicates (keep first occurrence)
delete_all_duplicates() {
    log_info "Удаление всех дубликатов (сохранение первого вхождения)..."
    
    local deleted_count=0
    while IFS='|' read -r hash count; do
        local files=()
        while IFS='|' read -r h file_path; do
            if [[ "$h" == "$hash" ]]; then
                files+=("$file_path")
            fi
        done < "$HASH_MAP_FILE"
        
        # Keep first file, delete rest
        for ((i=1; i<${#files[@]}; i++)); do
            log_info "  Удаление: $(basename "${files[i]}")"
            rm "${files[i]}"
            deleted_count=$((deleted_count + 1))
        done
    done < "$DUPLICATE_FILES_FILE"
    
    log_success "Удалено $deleted_count дубликатов файлов"
}

# Review duplicates one by one
review_duplicates_one_by_one() {
    while IFS='|' read -r hash count; do
        echo
        echo -e "${BLUE}Группа дубликатов (хэш: $hash)${NC}"
        
        local files=()
        local index=0
        while IFS='|' read -r h file_path; do
            if [[ "$h" == "$hash" ]]; then
                files+=("$file_path")
                echo "  $((index + 1))) $(basename "$file_path") ($(du -h "$file_path" | cut -f1)) - $file_path"
                index=$((index + 1))
            fi
        done < "$HASH_MAP_FILE"
        
        echo
        echo "Выберите действие для этой группы:"
        echo "1) Сохранить файл #1, удалить остальные"
        echo "2) Сохранить файл #2, удалить остальные"
        echo "3) Сохранить файл #3, удалить остальные"
        echo "4) Пропустить эту группу"
        echo "5) Удалить все в этой группе"
        
        read -p "Введите выбор: " group_choice
        
        case $group_choice in
            1|2|3)
                local keep_index=$((group_choice - 1))
                for ((i=0; i<${#files[@]}; i++)); do
                    if [[ $i -ne $keep_index ]]; then
                        log_info "  Удаление: $(basename "${files[i]}")"
                        rm "${files[i]}"
                    fi
                done
                ;;
            4)
                log_info "Пропуск этой группы"
                ;;
            5)
                for file in "${files[@]}"; do
                    log_info "  Удаление: $(basename "$file")"
                    rm "$file"
                done
                ;;
            *)
                log_warning "Неверный выбор. Пропуск этой группы."
                ;;
        esac
    done < "$DUPLICATE_FILES_FILE"
}

# Show detailed information about duplicates
show_detailed_info() {
    echo
    echo -e "${BLUE}Детальная информация о дубликатах:${NC}"
    echo
    
    while IFS='|' read -r hash count; do
        echo -e "${YELLOW}Хэш: $hash ($count файлов)${NC}"
        
        local total_size=0
        while IFS='|' read -r h file_path; do
            if [[ "$h" == "$hash" ]]; then
                local size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "0")
                total_size=$((total_size + size))
                echo "  📄 $(basename "$file_path")"
                echo "     Path: $file_path"
                echo "     Size: $(du -h "$file_path" | cut -f1)"
                echo "     Modified: $(stat -f%Sm "$file_path" 2>/dev/null || stat -c%y "$file_path" 2>/dev/null)"
                echo
            fi
        done < "$HASH_MAP_FILE"
        
        local wasted_size=$((total_size * (count - 1)))
        echo -e "${RED}Занято место: $(echo "$wasted_size" | awk '{printf "%.1f MB", $1/1024/1024}')${NC}"
        echo "----------------------------------------"
        echo
    done < "$DUPLICATE_FILES_FILE"
}

# Function to show main menu and get user choice
show_main_menu() {
    echo
    echo -e "${BLUE}File Organizer для macOS - Главное меню${NC}"
    echo "=================================="
    echo "Выберите действие:"
    echo "1) Извлечь файлы и папки из папок первого уровня"
    echo "2) Объединить папки с похожими названиями"
    echo "3) Проверить дубликаты файлов по хэшу"
    echo "4) Выполнить все шаги последовательно"
    echo "5) Выход"
    echo
    
    read -p "Введите ваш выбор (1-5): " choice
    
    case $choice in
        1)
            extract_files_and_folders
            echo
            show_final_statistics
            echo
            read -p "Нажмите Enter для возврата в меню..."
            show_main_menu
            ;;
        2)
            find_similar_folders
            echo
            show_final_statistics
            echo
            read -p "Нажмите Enter для возврата в меню..."
            show_main_menu
            ;;
        3)
            check_duplicate_files
            echo
            show_final_statistics
            echo
            read -p "Нажмите Enter для возврата в меню..."
            show_main_menu
            ;;
        4)
            run_all_steps
            echo
            read -p "Нажмите Enter для возврата в меню..."
            show_main_menu
            ;;
        5)
            log_info "Завершение работы скрипта"
            exit 0
            ;;
        *)
            log_error "Неверный выбор. Попробуйте снова."
            show_main_menu
            ;;
    esac
}

# Function to run all steps sequentially
run_all_steps() {
    extract_files_and_folders
    echo
    find_similar_folders
    echo
    check_duplicate_files
    echo
    log_success "Все шаги выполнены!"
    echo
    
    # Show final statistics
    show_final_statistics
}

# Function to show final statistics
show_final_statistics() {
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        log_warning "Папка с результатами $OUTPUT_DIR не найдена. Сначала выполните шаг 1."
        return 1
    fi
    
    local total_files=$(find "$OUTPUT_DIR" -type f 2>/dev/null | wc -l)
    local total_dirs=$(find "$OUTPUT_DIR" -type d 2>/dev/null | wc -l)
    local total_size=""
    
    if [[ -d "$OUTPUT_DIR" ]]; then
        total_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
    else
        total_size="0B"
    fi
    
    echo -e "${BLUE}Итоговая статистика:${NC}"
    echo "  Файлов: $total_files"
    echo "  Папок: $total_dirs"
    echo "  Общий размер: $total_size"
    echo "  Результат в: $OUTPUT_DIR"
}

# Main function
main() {
    echo -e "${BLUE}File Organizer для macOS${NC}"
    echo "=================================="
    echo
    
    # Check if we're in the right directory
    if [[ ! -d "$WORK_DIR" ]]; then
        log_error "Рабочая директория не существует: $WORK_DIR"
        exit 1
    fi
    
    log_info "Рабочая директория: $WORK_DIR"
    log_info "Папка для результата: $OUTPUT_DIR"
    echo
    
    # Show main menu
    show_main_menu
}

# Run main function
main "$@"
