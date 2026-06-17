#!/system/bin/sh

# MODDIR is expected to be the module root
[ -z "$MODDIR" ] && MODDIR="$(cd "$(dirname "$0")/.." && pwd)"

LOG_FILE="$MODDIR/logs/tproxy.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

read_cfg() {
    local key="$1"
    grep "\"$key\":" "$MODDIR/config/config.json" | head -n 1 | sed -E 's/.*"'$key'":\s*([^,]*),?/\1/' | sed 's/\"//g' | sed 's/ //g'
}

get_upstream_val() {
    local key="$1"
    sed -n '/"upstream": {/,/}/p' "$MODDIR/config/config.json" | grep "\"$key\":" | head -n 1 | sed -E 's/.*"'$key'":\s*([^,]*),?/\1/' | sed 's/\"//g' | sed 's/ //g'
}

get_dns_val() {
    local key="$1"
    sed -n '/"dns": {/,/}/p' "$MODDIR/config/config.json" | grep "\"$key\":" | head -n 1 | sed -E 's/.*"'$key'":\s*([^,]*),?/\1/' | sed 's/\"//g' | sed 's/ //g'
}

get_ipv6_val() {
    local key="$1"
    sed -n '/"ipv6": {/,/}/p' "$MODDIR/config/config.json" | grep "\"$key\":" | head -n 1 | sed -E 's/.*"'$key'":\s*([^,]*),?/\1/' | sed 's/\"//g' | sed 's/ //g'
}

get_bypass_cidrs() {
    sed -n '/"bypass_cidr": \[/,/\]/p' "$MODDIR/config/config.json" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+'
}

get_app_uids() {
    local type="$1"
    sed -n "/\"$type\": \[/,/\]/p" "$MODDIR/config/config.json" | grep -oE '[0-9]+'
}

find_bin() {
    local name="$1"
    local arch=$(getprop ro.product.cpu.abi)
    [ -z "$arch" ] && arch="arm64-v8a"
    local bin_path="$MODDIR/bin/$arch/$name"
    if [ -f "$bin_path" ]; then
        echo "$bin_path"
    else
        echo "$MODDIR/bin/$name"
    fi
}
