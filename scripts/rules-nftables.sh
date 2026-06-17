#!/system/bin/sh

. "$MODDIR/scripts/lib.sh"

NFT="nft"

apply_nftables() {
    local TPORT=$(read_cfg "tproxy_port")
    local MARK=$(read_cfg "mark")
    local TABLE=$(read_cfg "table")
    local MODE=$(read_cfg "mode")
    local BRIDGE_UID=$(cat "$MODDIR/logs/bridge.uid" 2>/dev/null || echo "0")

    # 1. Routing Policy (same as iptables)
    ip rule add fwmark $MARK/$MARK lookup $TABLE
    ip route add local default dev lo table $TABLE

    if [ "$(get_ipv6_val enabled)" = "true" ]; then
        ip -6 rule add fwmark $MARK/$MARK lookup $TABLE
        ip -6 route add local default dev lo table $TABLE
    fi

    # 2. nftables ruleset
    $NFT add table inet tproxy_bridge
    $NFT add chain inet tproxy_bridge prerouting { type filter hook prerouting priority mangle \; policy accept \; }
    $NFT add chain inet tproxy_bridge output { type filter hook output priority mangle \; policy accept \; }
    $NFT add chain inet tproxy_bridge divert { type filter hook prerouting priority mangle - 1 \; policy accept \; }

    # Divert for established sockets
    $NFT add rule inet tproxy_bridge divert meta l4proto { tcp, udp } socket transparent 1 meta mark set $MARK accept

    # Bypass CIDRs
    for n in $(get_bypass_cidrs); do
        $NFT add rule inet tproxy_bridge prerouting ip daddr "$n" return
        $NFT add rule inet tproxy_bridge output ip daddr "$n" return
    done

    # Output chain
    $NFT add rule inet tproxy_bridge output meta skuid "$BRIDGE_UID" return
    $NFT add rule inet tproxy_bridge output meta mark 0xff return
    $NFT add rule inet tproxy_bridge output oifname "lo" return

    if [ "$MODE" = "allowlist" ]; then
        for uid in $(get_app_uids "allow"); do
            $NFT add rule inet tproxy_bridge output meta skuid "$uid" meta mark set $MARK
        done
    elif [ "$MODE" = "blocklist" ]; then
        for uid in $(get_app_uids "block"); do
            $NFT add rule inet tproxy_bridge output meta skuid "$uid" return
        done
        $NFT add rule inet tproxy_bridge output meta l4proto { tcp, udp } meta mark set $MARK
    else # global
        $NFT add rule inet tproxy_bridge output meta l4proto { tcp, udp } meta mark set $MARK
    fi

    # Prerouting TPROXY
    $NFT add rule inet tproxy_bridge prerouting meta l4proto { tcp, udp } tproxy to :$TPORT meta mark set $MARK

    # 3. DNS Hijack
    if [ "$(get_dns_val strategy)" = "hijack" ]; then
        local DNS_PORT=$(get_dns_val listen)
        $NFT add table ip tproxy_dns
        $NFT add chain ip tproxy_dns output { type nat hook output priority dstnat \; policy accept \; }
        $NFT add rule ip tproxy_dns output meta skuid != "$BRIDGE_UID" udp dport 53 redirect to :$DNS_PORT
        $NFT add rule ip tproxy_dns output meta skuid != "$BRIDGE_UID" tcp dport 53 redirect to :$DNS_PORT
    fi
}

flush_nftables() {
    local MARK=$(read_cfg "mark")
    local TABLE=$(read_cfg "table")

    ip rule del fwmark $MARK/$MARK lookup $TABLE 2>/dev/null
    ip route flush table $TABLE 2>/dev/null
    ip -6 rule del fwmark $MARK/$MARK lookup $TABLE 2>/dev/null
    ip -6 route flush table $TABLE 2>/dev/null

    $NFT delete table inet tproxy_bridge 2>/dev/null
    $NFT delete table ip tproxy_dns 2>/dev/null
}
