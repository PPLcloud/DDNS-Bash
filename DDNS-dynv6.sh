#!/bin/bash

# Define the log file path
LOG_FILE="/tmp/last_dns_update.log"

# Get IPv4 and IPv6 addresses
ipv4_addr=$(curl -4 -s ip.sb)
ipv6_addr=$(curl -6 -s ip.sb)

# Function to update DNS records
update_dns() {
    local record_type=$1
    local ip_addr=$2
    local hostname=$3
    local token=""

    if [ ! -z "$ip_addr" ]; then
        local last_update=$(grep "$hostname $record_type" "$LOG_FILE" | tail -n 1 | awk '{print $6}')
        if [ "$last_update" = "$ip_addr" ]; then
            echo "The $record_type address for $hostname is already updated. Exiting..."
        else
            # Determine the query type
            local query_type=$([ "$record_type" = "ipv4" ] && echo "A" || echo "AAAA")

            # Use dig to query the current DNS resolution
            local query_ip=$(dig +short "$hostname" "$query_type" @ns1.dynv6.com)
            echo “query_ip = $query_ip”
            if [[ "$query_ip" = "$ip_addr" ]]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - $hostname $record_type $ip_addr" >> "$LOG_FILE"
            else
                local url="https://${record_type}.dynv6.com/api/update?hostname=${hostname}&${record_type}=${ip_addr}&token=${token}"
                local response=$(curl -s "$url")
                echo "$url"
                echo "$response"
            fi
        fi
    fi
}

# Check if the log file exists, create if not
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
fi

# Execute updates
# update_dns "ipv4" "$ipv4_addr" "xxx.dns.army"
update_dns "ipv6" "$ipv6_addr" "yeyeye.v6.army"
