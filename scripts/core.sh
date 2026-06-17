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
    local type=$(get_upstream_val "type")
    local host=$(get_upstream_val "host")
    local port=$(get_upstream_val "port")
    local user=$(get_upstream_val "username")
    local pass=$(get_upstream_val "password")
    local udp=$(get_upstream_val "udp")
    local tport=$(read_cfg "tproxy_port")

    mkdir -p "$MODDIR/config/generated"

    if [ "$type" = "socks5" ]; then
        # Generate hev-socks5-tproxy config (yaml)
        cat <<EOF > "$MODDIR/config/generated/hev-socks5-tproxy.yaml"
main:
  workers: 1
socks5:
  port: $port
  address: $host
  udp: '$( [ "$udp" = "true" ] && echo "udp" || echo "tcp" )'
  username: '$user'
  password: '$pass'
  mark: 255 # 0xff
tcp:
  port: $tport
  address: '::'
udp:
  port: $tport
  address: '::'
EOF
    elif [ "$type" = "http" ]; then
        # Generate redsocks2 config
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
    generate_config

    local type=$(get_upstream_val "type")
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
        # Use LD_PRELOAD or specific binary flags if needed to set mark for redsocks2
        # For redsocks2, it doesn't have a direct 'mark' option in config always,
        # but we can use 'man redsocks2' to check. Usually people use UID or CGROUP.
        # However, for this task, I'll assume mark works for the main SOCKS5 bridge.
        $bin $args > "$MODDIR/logs/bridge.log" 2>&1 &
        local pid=$!
        echo $pid > "$PID_FILE"
        stat -c %u "/proc/$pid" > "$UID_FILE" 2>/dev/null || echo "0" > "$UID_FILE"
        log "Bridge started with PID $pid (UID $(cat $UID_FILE))"
    else
        log "Error: Bridge binary not found at $bin"
        return 1
    fi

    # Start DNS forwarder if needed
    if [ "$(get_dns_val strategy)" = "hijack" ]; then
        local dns_bin=$(find_bin "dnsproxy")
        local dns_port=$(get_dns_val listen)
        local doh=$(get_dns_val doh)
        if [ -f "$dns_bin" ]; then
            chmod +x "$dns_bin"
            $dns_bin -l 0.0.0.0 -p $dns_port -u $doh --cache > "$MODDIR/logs/dns.log" 2>&1 &
            echo $! > "$MODDIR/logs/dns.pid"
            log "DNS forwarder started on port $dns_port"
        fi
    fi
}

stop_bridge() {
    log "Stopping bridge..."
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null
        rm "$PID_FILE"
    fi
    if [ -f "$MODDIR/logs/dns.pid" ]; then
        kill $(cat "$MODDIR/logs/dns.pid") 2>/dev/null
        rm "$MODDIR/logs/dns.pid"
    fi
    rm "$UID_FILE" 2>/dev/null
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
        start_bridge && apply_rules
        ;;
    stop)
        flush_rules
        stop_bridge
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    apply)
        flush_rules
        apply_rules
        ;;
    status)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "running"
        else
            echo "stopped"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|apply|status}"
        exit 1
        ;;
esac
