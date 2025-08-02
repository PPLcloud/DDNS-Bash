#!/bin/bash

# ---------------- 配置区 ----------------

DYNV6_TOKEN=""        # 必填：dynv6 API Token
DYNV6_HOSTNAME=""     # 必填：要更新的主机名

ENABLE_IPV4_UPDATE=1  # 是否启用 IPv4 更新（1=启用，0=禁用）
ENABLE_IPV6_UPDATE=1  # 是否启用 IPv6 更新（1=启用，0=禁用）

TELEGRAM_BOT_TOKEN=""  # 可选：Telegram Bot Token
TELEGRAM_CHAT_ID=""    # 可选：Telegram Chat ID

LOG_FILE="/tmp/last_dns_update.log"

# ---------------------------------------

SCRIPT_PATH="$(realpath "$0")"

send_telegram() {
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return
    fi
    local text="$1"
    local encoded_message
    encoded_message=$(echo -e "$text" | jq -s -R -r @uri)
    curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage?chat_id=${TELEGRAM_CHAT_ID}&text=${encoded_message}" >/dev/null
}

check_ip_env() {
    local timeout=3

    if [[ "$ENABLE_IPV4_UPDATE" == "1" ]]; then
        if curl -4 --max-time $timeout -s ip.sb >/dev/null 2>&1; then
            HAS_IPV4=1
            ipv4_addr=$(curl -4 -s ip.sb)
        else
            HAS_IPV4=0
            ipv4_addr=""
        fi
    fi

    if [[ "$ENABLE_IPV6_UPDATE" == "1" ]]; then
        if curl -6 --max-time $timeout -s ip.sb >/dev/null 2>&1; then
            HAS_IPV6=1
            ipv6_addr=$(curl -6 -s ip.sb)
        else
            HAS_IPV6=0
            ipv6_addr=""
        fi
    fi
}

check_crontab() {
    if crontab -l 2>/dev/null | grep -q "CRONTAB_MANAGED_BY_MY_SCRIPT"; then
        return
    fi

    if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH"; then
        echo "检测到 crontab 中没有本脚本的定时任务。"
        read -p "请输入希望几分钟运行一次本脚本 (1-60)，或输入 'no' 表示不再提示: " interval

        if [[ "$interval" == "no" ]]; then 
            (crontab -l 2>/dev/null; echo "# CRONTAB_MANAGED_BY_MY_SCRIPT") | crontab -
            echo "用户选择跳过 crontab 设置提示，今后将不再提示。"
            return
        fi
    
        if ! [[ "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]] || [[ "$interval" -gt 60 ]]; then
            echo "用户输入的定时任务间隔无效：$interval"
            exit 1
        fi

        (crontab -l 2>/dev/null; echo "*/$interval * * * * $SCRIPT_PATH >> $LOG_FILE 2>&1") | crontab -
        echo "已添加 crontab 定时任务，每 $interval 分钟运行一次本脚本。"
    fi
}   

update_dns() {
    local record_type=$1
    local ip_addr=$2
    local hostname=$3

    if [ -n "$ip_addr" ]; then
        local query_type=$([ "$record_type" = "ipv4" ] && echo "A" || echo "AAAA")
        local last_log_ip=$(grep "$hostname $record_type" "$LOG_FILE" | tail -n 1 | awk '{print $6}')

        if [ "$last_log_ip" = "$ip_addr" ]; then
            echo "[$record_type] IP 未变化，无需更新。"
            return
        fi

        local current_dns_ip=$(dig +short "$hostname" "$query_type" @ns1.dynv6.com)
        echo "[$record_type] 当前DNS记录: $current_dns_ip | 当前IP: $ip_addr"

        if [ "$current_dns_ip" = "$ip_addr" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - $hostname $record_type $ip_addr" >> "$LOG_FILE"
            echo "DNS记录已匹配，无需更新"
        else
            local url="https://${record_type}.dynv6.com/api/update?hostname=${hostname}&${record_type}=${ip_addr}&token=${DYNV6_TOKEN}"
            local response=$(curl -s "$url")

            echo "$(date '+%Y-%m-%d %H:%M:%S') - $hostname $record_type $ip_addr" >> "$LOG_FILE"
            echo "$response"

            send_telegram "✅ DNS更新成功: $hostname [$record_type] -> $ip_addr"
        fi
    fi
}

# 主逻辑
[ -f "$LOG_FILE" ] || touch "$LOG_FILE"

check_ip_env

[ "$ENABLE_IPV4_UPDATE" = "1" ] && [ "$HAS_IPV4" = "1" ] && [ -n "$ipv4_addr" ] && update_dns "ipv4" "$ipv4_addr" "$DYNV6_HOSTNAME"
[ "$ENABLE_IPV6_UPDATE" = "1" ] && [ "$HAS_IPV6" = "1" ] && [ -n "$ipv6_addr" ] && update_dns "ipv6" "$ipv6_addr" "$DYNV6_HOSTNAME"

check_crontab

