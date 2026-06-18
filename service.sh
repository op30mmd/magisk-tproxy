#!/system/bin/sh

MODDIR="${0%/*}"

# Wait for boot completion
until [ "$(getprop sys.boot_completed)" = 1 ]; do
    sleep 3
done

. "$MODDIR/scripts/lib.sh"

if [ "$(read_cfg enabled)" = "true" ]; then
    sh "$MODDIR/scripts/core.sh" start
    log "Boot: TProxy Bridge started"
else
    log "Boot: TProxy Bridge disabled"
fi

# Watchdog with mkdir-based lock to prevent concurrent restarts
LOCK_DIR="$MODDIR/logs/.watchdog_lock"
while true; do
    if [ "$(read_cfg enabled)" = "true" ]; then
        if [ "$(sh "$MODDIR/scripts/core.sh" status)" != "running" ]; then
            if mkdir "$LOCK_DIR" 2>/dev/null; then
                # Double-check status after acquiring lock
                if [ "$(sh "$MODDIR/scripts/core.sh" status)" != "running" ]; then
                    log "Watchdog: Bridge not running, restarting..."
                    sh "$MODDIR/scripts/core.sh" start
                fi
                rmdir "$LOCK_DIR" 2>/dev/null
            fi
        fi
    fi
    sleep 60
done
