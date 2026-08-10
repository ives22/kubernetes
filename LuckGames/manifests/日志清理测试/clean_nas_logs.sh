#!/bin/bash

readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/${SCRIPT_NAME%.sh}_$(date +%Y%m%d).log"

# 颜色定义（可选）
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 日志记录函数
log() {
    local level="$1"
    local msg="$2"
    local timestamp=$(date '+%F %T')
    local color=""
    
    case "$level" in
        "INFO")    color="${GREEN}" ;;
        "WARN")    color="${YELLOW}" ;;
        "ERROR")   color="${RED}" ;;
        "DEBUG")   color="${BLUE}" ;;
        *)         color="${NC}" ;;
    esac
    
    local log_entry="$timestamp [$level] $msg"
    
    # 输出到控制台（带颜色）
    if [ "$level" = "ERROR" ] || [ "$VERBOSE" = true ] || [ "$level" != "DEBUG" ]; then
        echo -e "${color}${log_entry}${NC}"
    fi
    
    # 写入日志文件（不带颜色代码）
    echo "$log_entry" >> "$LOG_FILE"
}


# 解析脚本参数
parse_args() {
    if [ "$#" -lt 2 ]; then
        echo "用法: $0 <日志目录> [天数] [--dry-run]"
        exit 1
    fi

    LOG_DIR="${1%/}"  # 去掉末尾的斜杠
    DAYS="$2"

    # 解析 --dry-run
    if [ "$#" -ge 3 ] && [ "$3" = "--dry-run" ]; then
        DRY_RUN=true
    fi

    if [ ! -d "$LOG_DIR" ]; then
        log "ERROR" "目录不存在: $LOG_DIR"
        exit 1
    fi

    if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
        log "ERROR" "天数必须是正整数: $DAYS"
        exit 1
    fi
}


# 清理日志目录函数  
clean_log_directory() {
    local sub_dir="$1"
    local dir_path="$LOG_DIR/$sub_dir"
    local files_count=0
    local dirs_count=0

    log "INFO" "开始清理目录: $dir_path"

    if [ "$DRY_RUN" = true ]; then
        log "WARN" "[DRY-RUN] 模式：不会实际删除"
    fi

    # 清理日志文件
    while IFS= read -r file; do
        if [ "$DRY_RUN" = true ]; then
            log "WARN" "[DRY-RUN] 跳过删除文件: $file"
        else
            log "INFO" "删除文件: $file"
            rm -f "$file"
        fi
        ((files_count++))
    done < <(find "$dir_path" -mindepth 1 -maxdepth 4 -type f -name "*.log" -mtime +$DAYS -print)

    # 清理目录，只是清空 空目录
    while IFS= read -r dir; do
        if [ "$DRY_RUN" = true ]; then
            log "WARN" "[DRY-RUN] 跳过删除目录: $dir"
        else
            log "INFO" "删除目录: $dir"
            rmdir "$dir"
        fi
        ((dirs_count++))
    done < <(find "$dir_path" -mindepth 1 -maxdepth 4 -type d -empty -mtime +$DAYS -print)

    log "INFO" "清理完成: $dir_path，删除文件数: $files_count，删除目录数: $dirs_count"
}


# 主清理函数
main_clean() {
    log "INFO" "开始清理任务"
    log "INFO" "日志目录: $LOG_DIR"
    log "INFO" "保留天数: $DAYS"
    log "INFO" "日志文件: $LOG_FILE"

    # 遍历日志目录
    local total_processed=0

    for sub_dir in "$LOG_DIR"/*/; do
        [ -d "$sub_dir" ] || continue  # 确保是目录

        sub_dir_name=$(basename "$sub_dir")
        ((total_processed++))

        # 清理日志目录
        clean_log_directory "$sub_dir_name"
    done

    # 总结日志
    log "INFO" "清理任务完成"
    log "INFO" "处理目录总数: $total_processed"
}


# 主函数
main(){
    # 解析参数
    parse_args "$@"

    # 记录开始时间
    local start_time=$(date +%s)

    # 执行清理任务
    main_clean

    # 记录结束时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log "INFO" "清理任务耗时: ${duration}秒"
}


# 运行主函数
main "$@"