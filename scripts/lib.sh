#!/system/bin/sh

# MODDIR is expected to be the module root
[ -z "$MODDIR" ] && MODDIR="$(cd "$(dirname "$0")/.." && pwd)"

LOG_FILE="$MODDIR/logs/tproxy.log"
CONFIG_SNAPSHOT=""

log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# --- Input validation helpers ---

validate_port() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) [ "$1" -ge 1 ] && [ "$1" -le 65535 ] ;;
    esac
}

validate_mark() {
    case "$1" in
        0x[0-9a-fA-F]*) [ ${#1} -le 10 ] ;;
        [0-9]*) [ "$1" -ge 0 ] && [ "$1" -le 4294967295 ] ;;
        *) return 1 ;;
    esac
}

validate_numeric() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# --- Sanitization helpers ---

sanitize_yaml() {
    printf '%s' "$1" | tr -d '\n\r\0' | sed "s/'/''/g"
}

sanitize_conf() {
    printf '%s' "$1" | tr -d '\n\r\0";`$\\'
}

# --- Config reading (supports snapshot for consistency) ---

_cfg_file() {
    if [ -n "$CONFIG_SNAPSHOT" ] && [ -f "$CONFIG_SNAPSHOT" ]; then
        echo "$CONFIG_SNAPSHOT"
    else
        echo "$MODDIR/config/config.json"
    fi
}

read_cfg() {
    local key="$1"
    local cfg_file
    cfg_file="$(_cfg_file)"
    grep "\"$key\":" "$cfg_file" 2>/dev/null | head -n 1 | sed -E 's/.*"'$key'":\s*([^,]*),?/\1/' | sed 's/\"//g' | sed 's/ //g'
}

get_upstream_val() {
    local key="$1"
    local cfg_file
    cfg_file="$(_cfg_file)"
    sed -n '/"upstream": {/,/}/p' "$cfg_file" 2>/dev/null | grep "\"$key\":" | head -n 1 | sed -E 's/.*"'$key'":\s*([^,]*),?/\1/' | sed 's/\"//g' | sed 's/ //g'
}

get_dns_val() {
    local key="$1"
    local cfg_file
    cfg_file="$(_cfg_file)"
    sed -n '/"dns": {/,/}/p' "$cfg_file" 2>/dev/null | grep "\"$key\":" | head -n 1 | sed -E 's/.*"'$key'":\s*([^,]*),?/\1/' | sed 's/\"//g' | sed 's/ //g'
}

get_ipv6_val() {
    local key="$1"
    local cfg_file
    cfg_file="$(_cfg_file)"
    sed -n '/"ipv6": {/,/}/p' "$cfg_file" 2>/dev/null | grep "\"$key\":" | head -n 1 | sed -E 's/.*"'$key'":\s*([^,]*),?/\1/' | sed 's/\"//g' | sed 's/ //g'
}

get_bypass_cidrs() {
    local cfg_file
    cfg_file="$(_cfg_file)"
    sed -n '/"bypass_cidr": \[/,/\]/p' "$cfg_file" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+'
}

get_app_uids() {
    local type="$1"
    local cfg_file
    cfg_file="$(_cfg_file)"
    sed -n "/\"$type\": \[/,/\]/p" "$cfg_file" 2>/dev/null | grep -oE '[0-9]+'
}

find_bin() {
    local name="$1"
    local arch
    arch=$(getprop ro.product.cpu.abi)
    [ -z "$arch" ] && arch="arm64-v8a"
    local bin_path="$MODDIR/bin/$arch/$name"
    if [ -f "$bin_path" ]; then
        echo "$bin_path"
    else
        echo "$MODDIR/bin/$name"
    fi
}
