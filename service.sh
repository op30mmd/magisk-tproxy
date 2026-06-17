#!/system/bin/sh

MODDIR="${0%/*}"

# Wait for boot completion
until [ "$(getprop sys.boot_completed)" = 1 ]; do
    sleep 3
done

# Wait for network connectivity (optional but recommended)
# until ping -c 1 8.8.8.8 >/dev/null 2>&1; do sleep 2; done

. "$MODDIR/scripts/lib.sh"

if [ "$(read_cfg enabled)" = "true" ]; then
    sh "$MODDIR/scripts/core.sh" start
    log "Boot: TProxy Bridge started"
else
    log "Boot: TProxy Bridge disabled"
fi

# Simple watchdog
while true; do
    if [ "$(read_cfg enabled)" = "true" ]; then
        if [ "$(sh "$MODDIR/scripts/core.sh" status)" != "running" ]; then
            log "Watchdog: Bridge not running, restarting..."
            sh "$MODDIR/scripts/core.sh" start
        fi
    fi
    sleep 60
done
