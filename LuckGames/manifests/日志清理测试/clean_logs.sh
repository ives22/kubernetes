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

    if [ ! -d "$LOG_DIR" ]; then
        log "ERROR" "目录不存在: $LOG_DIR"
        exit 1
    fi

    if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
        log "ERROR" "天数必须是正整数: $DAYS"
        exit 1
    fi
}


# 获取Kubernetes Pod列表
get_kubernetes_pods() {
    local token ca_cert api_server
    local deployment_name="clean-log-demo"
    local namespaces="default"

    # 检查是否在Kubernetes环境中
    if [ ! -f "/var/run/secrets/kubernetes.io/serviceaccount/token" ]; then
        log "WARN" "不在Kubernetes环境中，跳过Pod检测"
        return 1
    fi

    token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null || echo "")
    ca_cert="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    api_server="https://kubernetes.default.svc"

    if [ -z "$token" ]; then
        log "WARN" "无法获取Kubernetes Token"
        return 1
    fi

    # 使用curl获取Pod列表
    local response
    response=$(curl -s --cacert "$ca_cert" \
        -H "Authorization: Bearer $token" \
        "${api_server}/api/v1/namespaces/${namespaces}/pods" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        log "WARN" "无法从Kubernetes API获取Pod列表"
        return 1
    fi

    # 使用jq解析，如果没有jq则使用grep
    if command -v jq >/dev/null 2>&1; then
        PODS=$(echo "$response" | jq -r --arg dep "$deployment_name" '
            .items[] | 
            select(.metadata.labels.app == $dep) | 
            .metadata.name' 2>/dev/null)
    else
        # 使用grep作为替代
        log "WARN" "系统中未安装jq，使用grep解析Pod列表"
        PODS=$(echo "$response" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | \
            grep -i "$deployment_name" || true)
    fi

    if [ -n "$PODS" ]; then
        log "INFO" "找到 $(echo "$PODS" | wc -w) 个Pod需要跳过"
    else
        log "WARN" "未找到匹配的Pod"
    fi
}


# 检查是否应该跳过目录
should_skip_directory() {
    local dir_name="$1"
    
    for pod in $PODS; do
        if [ "$dir_name" = "$pod" ]; then
            log "INFO" "目录 $dir_name 匹配 Pod $pod，跳过"
            return 0  # 应该跳过
        fi
    done
    
    return 1  # 不应该跳过
}


# 清理日志目录函数  
clean_log_directory() {
    local sub_dir="$1"
    local dir_path="$LOG_DIR/$sub_dir"
    local files_count=0
    local dirs_count=0

    log "INFO" "开始清理目录: $dir_path"

    # 清理日志文件
    while IFS= read -r file; do
        log "INFO" "删除文件: $file"
        rm -f "$file"
        ((files_count++))
    done < <(find "$dir_path" -mindepth 0 -maxdepth 4 -type f -name "*.log" -mtime +$DAYS -print)

    # 清理目录
    while IFS= read -r dir; do
        log "INFO" "删除目录: $dir"
        rm -rf "$dir"
        ((dirs_count++))
    done < <(find "$dir_path" -mindepth 0 -maxdepth 4 -type d -mtime +$DAYS -print)

    log "INFO" "清理完成: $dir_path，删除文件数: $files_count，删除目录数: $dirs_count"
}


# 主清理函数
main_clean() {
    log "INFO" "开始清理任务"
    log "INFO" "日志目录: $LOG_DIR"
    log "INFO" "保留天数: $DAYS"
    log "INFO" "日志文件: $LOG_FILE"

    # 获取Kubernetes Pod列表    
    get_kubernetes_pods || PODS=""

    # 遍历日志目录
    local total_processed=0
    local total_skipped=0

    for sub_dir in "$LOG_DIR"/*/; do
        [ -d "$sub_dir" ] || continue  # 确保是目录

        sub_dir_name=$(basename "$sub_dir")
        ((total_processed++))

        # 检查是否应该跳过
        if should_skip_directory "$sub_dir_name"; then
            log "WARN" "跳过当前运行的Pod目录: $sub_dir_name"
            ((total_skipped++))
            continue
        fi

        # 清理日志目录
        clean_log_directory "$sub_dir_name"
    done

    # 总结日志
    log "INFO" "清理任务完成"
    log "INFO" "处理目录总数: $total_processed"
    log "INFO" "跳过目录总数: $total_skipped, 目录列表: $(for i in ${PODS}; do echo -n "$i "; done)"
    log "INFO" "实际处理目录: $((total_processed - total_skipped))"
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