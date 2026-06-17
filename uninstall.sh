#!/system/bin/sh

MODDIR="${0%/*}"

# Cleanup rules and processes
if [ -f "$MODDIR/scripts/core.sh" ]; then
    sh "$MODDIR/scripts/core.sh" stop
fi

# Remove generated files and logs
rm -rf "$MODDIR/config/generated"
rm -rf "$MODDIR/logs"
