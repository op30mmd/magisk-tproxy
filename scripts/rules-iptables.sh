#!/system/bin/sh

# Expects MODDIR and other variables to be set or helpers to be available
. "$MODDIR/scripts/lib.sh"

IPTABLES="iptables"
IP6TABLES="ip6tables"

apply_iptables() {
    local TPORT=$(read_cfg "tproxy_port")
    local MARK=$(read_cfg "mark")
    local TABLE=$(read_cfg "table")
    local MODE=$(read_cfg "mode")
    local BRIDGE_UID=$(cat "$MODDIR/logs/bridge.uid" 2>/dev/null || echo "0")
    local IPV6_ENABLED=$(get_ipv6_val enabled)

    # 1. Routing Policy
    ip rule add fwmark $MARK/$MARK lookup $TABLE
    ip route add local default dev lo table $TABLE

    # IPv6 Routing
    if [ "$IPV6_ENABLED" = "true" ]; then
        ip -6 rule add fwmark $MARK/$MARK lookup $TABLE
        ip -6 route add local default dev lo table $TABLE
    fi

    # 2. Mangle Table - PREROUTING
    # IPv4
    $IPTABLES -t mangle -N PROXY_PRE
    $IPTABLES -t mangle -A PROXY_PRE -p tcp -m socket -j DIVERT
    $IPTABLES -t mangle -A PROXY_PRE -p udp -m socket -j DIVERT

    for n in $(get_bypass_cidrs); do
        $IPTABLES -t mangle -A PROXY_PRE -d "$n" -j RETURN
    done

    $IPTABLES -t mangle -A PROXY_PRE -p tcp -j TPROXY --on-port "$TPORT" --tproxy-mark "$MARK/$MARK"
    $IPTABLES -t mangle -A PROXY_PRE -p udp -j TPROXY --on-port "$TPORT" --tproxy-mark "$MARK/$MARK"
    $IPTABLES -t mangle -A PREROUTING -j PROXY_PRE

    # IPv6 Mangle
    if [ "$IPV6_ENABLED" = "true" ]; then
        $IP6TABLES -t mangle -N PROXY_PRE
        $IP6TABLES -t mangle -A PROXY_PRE -p tcp -m socket -j DIVERT
        $IP6TABLES -t mangle -A PROXY_PRE -p udp -m socket -j DIVERT
        # Add IPv6 reserved ranges
        for n in ::1/128 fc00::/7 fe80::/10 ff00::/8; do
            $IP6TABLES -t mangle -A PROXY_PRE -d "$n" -j RETURN
        done
        $IP6TABLES -t mangle -A PROXY_PRE -p tcp -j TPROXY --on-port "$TPORT" --tproxy-mark "$MARK/$MARK"
        $IP6TABLES -t mangle -A PROXY_PRE -p udp -j TPROXY --on-port "$TPORT" --tproxy-mark "$MARK/$MARK"
        $IP6TABLES -t mangle -A PREROUTING -j PROXY_PRE
    fi

    # DIVERT helper (IPv4 & IPv6)
    $IPTABLES -t mangle -N DIVERT
    $IPTABLES -t mangle -A DIVERT -j MARK --set-mark "$MARK"
    $IPTABLES -t mangle -A DIVERT -j ACCEPT

    if [ "$IPV6_ENABLED" = "true" ]; then
        $IP6TABLES -t mangle -N DIVERT
        $IP6TABLES -t mangle -A DIVERT -j MARK --set-mark "$MARK"
        $IP6TABLES -t mangle -A DIVERT -j ACCEPT
    fi

    # 3. Mangle Table - OUTPUT
    $IPTABLES -t mangle -N PROXY_OUT
    $IPTABLES -t mangle -A PROXY_OUT -m mark --mark 0xff -j RETURN # LOOP_MARK
    # If not using mark, fallback to UID if bridge is not root,
    # but here we emphasize mark 0xff for the bridge.
    $IPTABLES -t mangle -A PROXY_OUT -o lo -j RETURN

    for n in $(get_bypass_cidrs); do
        $IPTABLES -t mangle -A PROXY_OUT -d "$n" -j RETURN
    done

    if [ "$MODE" = "allowlist" ]; then
        for uid in $(get_app_uids "allow"); do
            $IPTABLES -t mangle -A PROXY_OUT -m owner --uid-owner "$uid" -j MARK --set-mark "$MARK"
        done
    elif [ "$MODE" = "blocklist" ]; then
        for uid in $(get_app_uids "block"); do
            $IPTABLES -t mangle -A PROXY_OUT -m owner --uid-owner "$uid" -j RETURN
        done
        $IPTABLES -t mangle -A PROXY_OUT -p tcp -j MARK --set-mark "$MARK"
        $IPTABLES -t mangle -A PROXY_OUT -p udp -j MARK --set-mark "$MARK"
    else # global
        $IPTABLES -t mangle -A PROXY_OUT -p tcp -j MARK --set-mark "$MARK"
        $IPTABLES -t mangle -A PROXY_OUT -p udp -j MARK --set-mark "$MARK"
    fi

    $IPTABLES -t mangle -A OUTPUT -j PROXY_OUT

    # IPv6 Output
    if [ "$IPV6_ENABLED" = "true" ]; then
        $IP6TABLES -t mangle -N PROXY_OUT
        $IP6TABLES -t mangle -A PROXY_OUT -m mark --mark 0xff -j RETURN
        $IP6TABLES -t mangle -A PROXY_OUT -o lo -j RETURN
        for n in ::1/128 fc00::/7 fe80::/10 ff00::/8; do
            $IP6TABLES -t mangle -A PROXY_OUT -d "$n" -j RETURN
        done
        # ... Mode logic mirrored for IPv6
        if [ "$MODE" = "allowlist" ]; then
            for uid in $(get_app_uids "allow"); do
                $IP6TABLES -t mangle -A PROXY_OUT -m owner --uid-owner "$uid" -j MARK --set-mark "$MARK"
            done
        elif [ "$MODE" = "blocklist" ]; then
            for uid in $(get_app_uids "block"); do
                $IP6TABLES -t mangle -A PROXY_OUT -m owner --uid-owner "$uid" -j RETURN
            done
            $IP6TABLES -t mangle -A PROXY_OUT -p tcp -j MARK --set-mark "$MARK"
            $IP6TABLES -t mangle -A PROXY_OUT -p udp -j MARK --set-mark "$MARK"
        else
            $IP6TABLES -t mangle -A PROXY_OUT -p tcp -j MARK --set-mark "$MARK"
            $IP6TABLES -t mangle -A PROXY_OUT -p udp -j MARK --set-mark "$MARK"
        fi
        $IP6TABLES -t mangle -A OUTPUT -j PROXY_OUT
    fi

    # 4. DNS Hijack (NAT Table)
    if [ "$(get_dns_val strategy)" = "hijack" ]; then
        local DNS_PORT=$(get_dns_val listen)
        $IPTABLES -t nat -N PROXY_DNS
        $IPTABLES -t nat -A PROXY_DNS -p udp --dport 53 -m owner ! --uid-owner "$BRIDGE_UID" -j REDIRECT --to-ports "$DNS_PORT"
        $IPTABLES -t nat -A PROXY_DNS -p tcp --dport 53 -m owner ! --uid-owner "$BRIDGE_UID" -j REDIRECT --to-ports "$DNS_PORT"
        $IPTABLES -t nat -A OUTPUT -j PROXY_DNS
    fi
}

flush_iptables() {
    local MARK=$(read_cfg "mark")
    local TABLE=$(read_cfg "table")

    # Routing Policy
    ip rule del fwmark $MARK/$MARK lookup $TABLE 2>/dev/null
    ip route flush table $TABLE 2>/dev/null
    ip -6 rule del fwmark $MARK/$MARK lookup $TABLE 2>/dev/null
    ip -6 route flush table $TABLE 2>/dev/null

    # Mangle Table
    for ipt in $IPTABLES $IP6TABLES; do
        $ipt -t mangle -D PREROUTING -j PROXY_PRE 2>/dev/null
        $ipt -t mangle -F PROXY_PRE 2>/dev/null
        $ipt -t mangle -X PROXY_PRE 2>/dev/null

        $ipt -t mangle -F DIVERT 2>/dev/null
        $ipt -t mangle -X DIVERT 2>/dev/null

        $ipt -t mangle -D OUTPUT -j PROXY_OUT 2>/dev/null
        $ipt -t mangle -F PROXY_OUT 2>/dev/null
        $ipt -t mangle -X PROXY_OUT 2>/dev/null
    done

    # NAT Table
    $IPTABLES -t nat -D OUTPUT -j PROXY_DNS 2>/dev/null
    $IPTABLES -t nat -F PROXY_DNS 2>/dev/null
    $IPTABLES -t nat -X PROXY_DNS 2>/dev/null
}
