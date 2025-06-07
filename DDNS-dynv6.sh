#!/bin/bash

LOG_FILE="/tmp/last_dns_update.log"

# 获取公网 IPv4 / IPv6（分别测试是否可获取）
ipv4_addr=$(curl -4 -s ip.sb)
ipv6_addr=$(curl -6 -s ip.sb)

# Telegram Bot 配置（你需要设置以下变量）
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

send_telegram() {
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return
    fi

    local message=$1
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="$message" > /dev/null
}

check_crontab() {
    # 检查用户是否输入过no
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
    local token=""  # 🔁请输入真实 token

    if [ -n "$ip_addr" ]; then
        local last_update=$(grep "$hostname $record_type" "$LOG_FILE" | tail -n 1 | awk '{print $6}')
        if [ "$last_update" = "$ip_addr" ]; then
            echo "The $record_type address for $hostname is already up to date."
        else
            local query_type=$([ "$record_type" = "ipv4" ] && echo "A" || echo "AAAA")
            local query_ip=$(dig +short "$hostname" "$query_type" @ns1.dynv6.com)

            echo "Current DNS: $query_ip | Actual: $ip_addr"

            if [ "$query_ip" = "$ip_addr" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - $hostname $record_type $ip_addr" >> "$LOG_FILE"
            else
                local url="https://${record_type}.dynv6.com/api/update?hostname=${hostname}&${record_type}=${ip_addr}&token=${token}"
                local response=$(curl -s "$url")

                echo "$(date '+%Y-%m-%d %H:%M:%S') - Updated $record_type for $hostname to $ip_addr" >> "$LOG_FILE"
                echo "$response"

                # 发送 Telegram 通知
                send_telegram "✅ DNS更新成功: $hostname [$record_type] -> $ip_addr"
            fi
        fi
    fi

    check_crontab
}

# 创建日志文件（如不存在）
[ -f "$LOG_FILE" ] || touch "$LOG_FILE"

# 自动检测并更新
[ -n "$ipv4_addr" ] && update_dns "ipv4" "$ipv4_addr" "xxx.dns.army"
[ -n "$ipv6_addr" ] && update_dns "ipv6" "$ipv6_addr" "xxx.v6.army"

