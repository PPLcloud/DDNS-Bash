#!/bin/bash

# Cloudflare DDNS 更新脚本
# 功能：自动检测 IP 变化并更新 Cloudflare DNS 记录，并在关键日志时通过 Telegram 通知

# ==============================
# 配置部分
# ==============================
API_KEY=""                                          # 替换为你的 Cloudflare API 密钥
ZONE_ID=""                                          # 替换为你的 Zone ID
HOST_NAME=""                                        # 要更新的域名
LOG_FILE="/tmp/cloudflare_ddns.log"                 # 日志文件路径
SCRIPT_PATH="$(realpath "$0")"                      # 获取脚本完整路径

# Telegram Bot 配置（用于关键日志通知）
BOT_TOKEN=""                                        # 替换为你的 Bot Token
CHAT_ID=""                                          # 替换为你的 Chat ID

# ==============================
# 内部函数
# ==============================

# 在日志里写一行，并在必要时发送 Telegram 通知
# 参数：$1 = 日志级别 ("INFO"、"ERROR" 等)
# 参数：$2 = 日志内容
log_and_notify() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    # 将日志写入文件
    echo "$timestamp [$level] $message" >> "$LOG_FILE"

    if [[ "$BOT_TOKEN" != "" && "$CHAT_ID" != "" ]]; then
        return
    fi

    # 如果是 ERROR 或 CRITICAL，则发送 Telegram 通知
    if [[ "$level" == "ERROR" || "$level" == "CRITICAL" || "$level" == "SUC" ]]; then
        send_telegram "$timestamp [$level] $message"
    fi
}

# 通过 Telegram Bot 发送消息
# 参数：$1 = 要发送的文本
send_telegram() {
    local text="$1"
    # 使用 curl 调用 Telegram Bot API
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d text="$text" >/dev/null 2>&1
}

# 检查并安装必要软件：curl、jq
check_dependencies() {
    # 检查基础变量是否设置完成
    if [[ -z "$API_KEY" || -z "$ZONE_ID" || -z "$HOST_NAME" ]]; then
        log_and_notify "ERROR" "API_KEY、ZONE_ID 或 HOST_NAME 未设置，请检查脚本配置。"
        exit 1
    fi

    # 检查 curl
    if ! command -v curl &>/dev/null; then
        log_and_notify "INFO" "curl 未安装，尝试自动安装..."
        if [[ -f /etc/redhat-release ]]; then
            sudo yum install -y curl >> "$LOG_FILE" 2>&1 \
                && log_and_notify "INFO" "curl 安装成功" \
                || { log_and_notify "ERROR" "curl 安装失败，请手动安装"; exit 1; }
        elif [[ -f /etc/debian_version ]]; then
            sudo apt-get update >> "$LOG_FILE" 2>&1 && sudo apt-get install -y curl >> "$LOG_FILE" 2>&1 \
                && log_and_notify "INFO" "curl 安装成功" \
                || { log_and_notify "ERROR" "curl 安装失败，请手动安装"; exit 1; }
        else
            log_and_notify "ERROR" "无法自动安装 curl，请手动安装后重试。"
            exit 1
        fi
    fi

    # 检查 jq
    if ! command -v jq &>/dev/null; then
        log_and_notify "INFO" "jq 未安装，尝试自动安装..."
        if [[ -f /etc/redhat-release ]]; then
            sudo yum install -y epel-release >> "$LOG_FILE" 2>&1 && sudo yum install -y jq >> "$LOG_FILE" 2>&1 \
                && log_and_notify "INFO" "jq 安装成功" \
                || { log_and_notify "ERROR" "jq 安装失败，请手动安装"; exit 1; }
        elif [[ -f /etc/debian_version ]]; then
            sudo apt-get update >> "$LOG_FILE" 2>&1 && sudo apt-get install -y jq >> "$LOG_FILE" 2>&1 \
                && log_and_notify "INFO" "jq 安装成功" \
                || { log_and_notify "ERROR" "jq 安装失败，请手动安装"; exit 1; }
        else
            log_and_notify "ERROR" "无法自动安装 jq，请手动安装后重试。"
            exit 1
        fi
    fi
}

# 查找特定记录类型和名称对应的记录 ID 和内容（使用 jq）
# 返回值：输出 "record_id content"，调入端可用 read 读取
find_dns_record() {
    local json="$1"
    local record_type="$2"
    local name="$3"

    local output
    output=$(echo "$json" | jq -r --arg type "$record_type" --arg name "$name" '
        .result[]
        | select(.type == $type and .name == $name)
        | "\(.id) \(.content)"
    ')
    if [[ -n "$output" ]]; then
        echo "$output"
        return 0
    else
        echo "null null"
        return 1
    fi
}

# -------------------------------
# 1. 检测本机是否有 IPv4/IPv6 联通性
# -------------------------------
# 尝试用 curl -4/6 去访问 ip.sb（或 ifconfig.me），
# 成功则说明对应协议可用，否则不可用。
check_ip_env() {
    local timeout=1

    # 检测 IPv4
    if curl -4 --max-time $timeout -s ip.sb >/dev/null 2>&1 \
       || curl -4 --max-time $timeout -s ifconfig.me >/dev/null 2>&1; then
        HAS_IPV4=1
    else
        HAS_IPV4=0
    fi

    # 检测 IPv6
    if curl -6 --max-time $timeout -s ip.sb >/dev/null 2>&1 \
       || curl -6 --max-time $timeout -s ifconfig.me >/dev/null 2>&1; then
        HAS_IPV6=1
    else
        HAS_IPV6=0
    fi

    log_and_notify "INFO" "检测结果：HAS_IPV4=$HAS_IPV4，HAS_IPV6=$HAS_IPV6"
}

# -------------------------------
# 2. 根据协议类型尝试获取公网 IP
# -------------------------------
# 如果本机没有相应协议环境，就直接返回空串
get_current_ip() {
    local record_type="$1"
    if [[ "$record_type" == "A" ]]; then
        if [[ "$HAS_IPV4" -eq 1 ]]; then
            curl -4 -s ip.sb || curl -4 -s ifconfig.me
        else
            echo ""
        fi
    else
        if [[ "$HAS_IPV6" -eq 1 ]]; then
            curl -6 -s ip.sb || curl -6 -s ifconfig.me
        else
            echo ""
        fi
    fi
}

# 获取 DNS 记录信息
get_dns_record() {
    local response
    response=$(curl -s "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json")

    if [[ $(echo "$response" | jq -r '.success') != "true" ]]; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "未知错误"')
        log_and_notify "ERROR" "获取 DNS 记录失败: ${error_msg}"
        echo "null"
        return 1
    fi

    echo "$response"
}

# 更新 DNS 记录
update_dns_record() {
    local record_type="$1"
    local record_id="$2"
    local ip_addr="$3"

    local payload
    payload=$(jq -n --arg type "$record_type" --arg name "$HOST_NAME" --arg content "$ip_addr" '{
        type: $type,
        name: $name,
        content: $content,
        ttl: 1,
        proxied: false
    }')

    local response
    response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${record_id}" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        --data "$payload")

    echo "$response"
}

check_crontab() {
    # 检查用户是否输入过no
    if crontab -l 2>/dev/null | grep -q "CRONTAB_MANAGED_BY_MY_SCRIPT"; then
        return
    fi

    if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
        log_and_notify "INFO" "检测到 crontab 中没有本脚本的定时任务。"
        read -p "请输入希望几分钟运行一次本脚本 (1-60)，或输入 'no' 表示不再提示: " interval

        if [[ "$interval" == "no" ]]; then
            (crontab -l 2>/dev/null; echo "# CRONTAB_MANAGED_BY_MY_SCRIPT") | crontab -
            log_and_notify "INFO" "用户选择跳过 crontab 设置提示，今后将不再提示。"
            return
        fi

        if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]] || [[ "$interval" -gt 60 ]]; then
            log_and_notify "ERROR" "用户输入的定时任务间隔无效：$interval"
            exit 1
        fi

        (crontab -l 2>/dev/null; echo "*/$interval * * * * $SCRIPT_PATH >> $LOG_FILE 2>&1") | crontab -
        log_and_notify "INFO" "已添加 crontab 定时任务，每 $interval 分钟运行一次本脚本。"
    fi
}

# ==============================
# 主函数
# ==============================
main() {
    # 检查并安装依赖：curl 和 jq
    check_dependencies

    # 创建日志目录并确保日志文件存在
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    # 检测本机 IPv4/IPv6 环境
    check_ip_env

    # 获取所有 DNS 记录
    local dns_records
    dns_records=$(get_dns_record)
    if [[ "$dns_records" == "null" ]]; then
        log_and_notify "CRITICAL" "无法获取 DNS 记录，退出脚本。"
        exit 1
    fi

    # -------------------------------
    # 处理 IPv4 (A 记录)
    # -------------------------------
    if [[ "$HAS_IPV4" -eq 1 ]]; then
        local ipv4
        ipv4=$(get_current_ip "A")
        if [[ -n "$ipv4" ]]; then
            read -r record_id current_dns_ip <<< "$(find_dns_record "$dns_records" "A" "$HOST_NAME")"

            if [[ "$record_id" != "null" && -n "$record_id" ]]; then
                if [[ "$current_dns_ip" != "$ipv4" ]]; then
                    log_and_notify "INFO" "检测到 IPv4 变化: $current_dns_ip -> $ipv4"
                    local update_result
                    update_result=$(update_dns_record "A" "$record_id" "$ipv4")
                    if [[ $(echo "$update_result" | jq -r '.success') == "true" ]]; then
                        log_and_notify "SUC" "成功更新 A 记录: $HOST_NAME -> $ipv4"
                    else
                        local error_msg
                        error_msg=$(echo "$update_result" | jq -r '.errors[0].message // "未知错误"')
                        log_and_notify "ERROR" "A 记录更新失败: ${error_msg}"
                    fi
                else
                    log_and_notify "INFO" "IPv4 地址未变化: $ipv4"
                fi
            else
                log_and_notify "ERROR" "未找到 A 记录: $HOST_NAME"
            fi
        else
            log_and_notify "ERROR" "无法获取当前 IPv4 地址"
        fi
    else
        log_and_notify "INFO" "IPv4 环境不可用，跳过 A 记录更新"
    fi

    # -------------------------------
    # 处理 IPv6 (AAAA 记录)
    # -------------------------------
    if [[ "$HAS_IPV6" -eq 1 ]]; then
        local ipv6
        ipv6=$(get_current_ip "AAAA")
        if [[ -n "$ipv6" ]]; then
            read -r record_id current_dns_ip <<< "$(find_dns_record "$dns_records" "AAAA" "$HOST_NAME")"

            if [[ "$record_id" != "null" && -n "$record_id" ]]; then
                if [[ "$current_dns_ip" != "$ipv6" ]]; then
                    log_and_notify "INFO" "检测到 IPv6 变化: $current_dns_ip -> $ipv6"
                    local update_result
                    update_result=$(update_dns_record "AAAA" "$record_id" "$ipv6")
                    if [[ $(echo "$update_result" | jq -r '.success') == "true" ]]; then
                        log_and_notify "SUC" "成功更新 AAAA 记录: $HOST_NAME -> $ipv6"
                    else
                        local error_msg
                        error_msg=$(echo "$update_result" | jq -r '.errors[0].message // "未知错误"')
                        log_and_notify "ERROR" "AAAA 记录更新失败: ${error_msg}"
                    fi
                else
                    log_and_notify "INFO" "IPv6 地址未变化: $ipv6"
                fi
            else
                log_and_notify "ERROR" "未找到 AAAA 记录: $HOST_NAME"
            fi
        else
            log_and_notify "ERROR" "无法获取当前 IPv6 地址"
        fi
    else
        log_and_notify "INFO" "IPv6 环境不可用，跳过 AAAA 记录更新"
    fi

    # 检查是否是root运行，如果是，则确保 crontab 定时任务
    if [[ "$EUID" -eq 0 ]]; then
        check_crontab
    fi
}

# 执行主函数
main
