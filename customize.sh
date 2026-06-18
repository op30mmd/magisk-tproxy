#!/system/bin/sh

SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

# Detected ARCH is provided by Magisk
ui_print "- Detecting ABI: $ARCH"

# Set permissions
set_perm_recursive $MODPATH/bin 0 0 0755 0755
set_perm_recursive $MODPATH/scripts 0 0 0755 0755
set_perm_recursive $MODPATH/webroot 0 0 0755 0644
set_perm_recursive $MODPATH/config 0 0 0755 0600
set_perm_recursive $MODPATH/logs 0 0 0755 0700

# Keep only the matching ABI dir to save space
ui_print "- Cleaning up unused binaries"
for abi in arm64-v8a armeabi-v7a x86_64; do
    if [ "$abi" != "$ARCH" ]; then
        rm -rf "$MODPATH/bin/$abi"
    fi
done

ui_print "- TProxy Bridge installed"
