#!/system/bin/sh

# Set MODDIR to the module root
if [ -z "$MODDIR" ] || [ "$MODDIR" = "-bash" ]; then
    CORE_SH_DIR="$(cd "$(dirname "$0")" && pwd)"
    MODDIR="$(dirname "$CORE_SH_DIR")"
fi

# Magisk specific path fallback
if echo "$MODDIR" | grep -q "^/system/bin"; then
    MODDIR="/data/adb/modules/tproxy_bridge"
fi

. "$MODDIR/scripts/lib.sh"
. "$MODDIR/scripts/rules-iptables.sh"
. "$MODDIR/scripts/rules-nftables.sh"

PID_FILE="$MODDIR/logs/bridge.pid"
UID_FILE="$MODDIR/logs/bridge.uid"

use_nft() {
    command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1
}

generate_config() {
    local type
    type=$(get_upstream_val "type")
    local host
    host=$(sanitize_yaml "$(get_upstream_val "host")")
    local port
    port=$(get_upstream_val "port")
    local user
    user=$(sanitize_yaml "$(get_upstream_val "username")")
    local pass
    pass=$(sanitize_yaml "$(get_upstream_val "password")")
    local udp
    udp=$(get_upstream_val "udp")
    local tport
    tport=$(read_cfg "tproxy_port")

    # Validate required fields
    [ -z "$host" ] && { log "Error: upstream host is empty"; return 1; }
    validate_port "$port" || { log "Error: invalid upstream port '$port'"; return 1; }
    validate_port "$tport" || { log "Error: invalid tproxy port '$tport'"; return 1; }

    mkdir -p "$MODDIR/config/generated"

    if [ "$type" = "socks5" ]; then
        cat <<EOF > "$MODDIR/config/generated/hev-socks5-tproxy.yaml"
main:
  workers: 1
socks5:
  port: $port
  address: '$host'
  udp: '$( [ "$udp" = "true" ] && echo "udp" || echo "tcp" )'
  username: '$user'
  password: '$pass'
  mark: 255
tcp:
  port: $tport
  address: '::'
udp:
  port: $tport
  address: '::'
EOF
    elif [ "$type" = "http" ]; then
        cat <<EOF > "$MODDIR/config/generated/redsocks2.conf"
base {
    log_debug = off;
    log_info = on;
    log = "file:$MODDIR/logs/redsocks2.log";
    daemon = on;
    redirector = tproxy;
}
redsocks {
    local_ip = 0.0.0.0;
    local_port = $tport;
    ip = $host;
    port = $port;
    type = http-connect;
    login = "$user";
    password = "$pass";
}
EOF
    fi
}

start_bridge() {
    log "Starting bridge..."
    generate_config || return 1

    local type
    type=$(get_upstream_val "type")
    local bin=""
    local args=""

    if [ "$type" = "socks5" ]; then
        bin=$(find_bin "hev-socks5-tproxy")
        args="$MODDIR/config/generated/hev-socks5-tproxy.yaml"
    elif [ "$type" = "http" ]; then
        bin=$(find_bin "redsocks2")
        args="-c $MODDIR/config/generated/redsocks2.conf"
    fi

    if [ -f "$bin" ]; then
        chmod +x "$bin"
        "$bin" $args > "$MODDIR/logs/bridge.log" 2>&1 &
        local pid=$!
        echo "$pid" > "$PID_FILE"
        # Wait for process to appear and read its UID reliably
        local uid=""
        local attempts=0
        while [ $attempts -lt 5 ] && [ -z "$uid" ]; do
            uid=$(awk '/^Uid:/{print $2}' "/proc/$pid/status" 2>/dev/null)
            [ -z "$uid" ] && sleep 1 && attempts=$((attempts + 1))
        done
        if [ -n "$uid" ]; then
            echo "$uid" > "$UID_FILE"
        else
            log "Warning: could not determine bridge UID, using fallback 1000"
            echo "1000" > "$UID_FILE"
        fi
        log "Bridge started with PID $pid (UID $(cat "$UID_FILE"))"
    else
        log "Error: Bridge binary not found at $bin"
        return 1
    fi

    # Start DNS forwarder if needed
    if [ "$(get_dns_val strategy)" = "hijack" ]; then
        local dns_bin
        dns_bin=$(find_bin "dnsproxy")
        local dns_port
        dns_port=$(get_dns_val listen)
        local doh
        doh=$(get_dns_val doh)
        validate_port "$dns_port" || { log "Error: invalid DNS port '$dns_port'"; return 1; }
        if [ -f "$dns_bin" ]; then
            chmod +x "$dns_bin"
            "$dns_bin" -l 0.0.0.0 -p "$dns_port" -u "$doh" --cache > "$MODDIR/logs/dns.log" 2>&1 &
            echo $! > "$MODDIR/logs/dns.pid"
            log "DNS forwarder started on port $dns_port"
        fi
    fi
}

_stop_pid() {
    local pid_file="$1"
    local name="$2"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            local i=0
            while [ $i -lt 3 ] && kill -0 "$pid" 2>/dev/null; do
                sleep 1
                i=$((i + 1))
            done
            kill -9 "$pid" 2>/dev/null
            log "$name (PID $pid) stopped"
        fi
        rm -f "$pid_file"
    fi
}

stop_bridge() {
    log "Stopping bridge..."
    _stop_pid "$PID_FILE" "Bridge"
    _stop_pid "$MODDIR/logs/dns.pid" "DNS forwarder"
    rm -f "$UID_FILE"
}

apply_rules() {
    log "Applying rules..."
    if use_nft; then
        apply_nftables
    else
        apply_iptables
    fi
}

flush_rules() {
    log "Flushing rules..."
    flush_iptables
    flush_nftables
}

case "$1" in
    start)
        stop_bridge
        flush_rules
        # Snapshot config to prevent inconsistent reads during rule application
        CONFIG_SNAPSHOT="$MODDIR/config/.config.snapshot"
        cp "$MODDIR/config/config.json" "$CONFIG_SNAPSHOT" 2>/dev/null
        start_bridge && apply_rules
        rm -f "$CONFIG_SNAPSHOT"
        ;;
    stop)
        flush_rules
        stop_bridge
        ;;
    restart)
        "$0" stop
        "$0" start
        ;;
    apply)
        CONFIG_SNAPSHOT="$MODDIR/config/.config.snapshot"
        cp "$MODDIR/config/config.json" "$CONFIG_SNAPSHOT" 2>/dev/null
        flush_rules
        apply_rules
        rm -f "$CONFIG_SNAPSHOT"
        ;;
    status)
        if [ -f "$PID_FILE" ]; then
            local pid
            pid=$(cat "$PID_FILE" 2>/dev/null)
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                # Verify it's actually our process by checking the executable name
                local exe
                exe=$(readlink "/proc/$pid/exe" 2>/dev/null)
                case "$exe" in
                    *hev-socks5-tproxy*|*redsocks2*)
                        echo "running"
                        ;;
                    *)
                        echo "stopped"
                        ;;
                esac
            else
                echo "stopped"
            fi
        else
            echo "stopped"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|apply|status}"
        exit 1
        ;;
esac
