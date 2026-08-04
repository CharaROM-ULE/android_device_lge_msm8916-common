#!/system/bin/sh
# Fix corrupted Bluetooth MAC address in /persist/.bt_nv.bin
# For LG devices where the persist file got partially wiped

BT_NV_FILE="/persist/.bt_nv.bin"
LOG_TAG="bt_mac_fix"

log_info() {
    /system/bin/log -t $LOG_TAG -p i "$1"
}

log_error() {
    /system/bin/log -t $LOG_TAG -p e "$1"
}

# Check if file exists
if [ ! -f "$BT_NV_FILE" ]; then
    log_info "BT NV file does not exist, skipping"
    exit 0
fi

# Read the file and check for corruption (last 3 bytes are 00 00 00)
# File format: 01 00 06 XX XX XX XX XX XX (header + 6 byte MAC)
HEXDUMP=$(cat "$BT_NV_FILE" | od -A n -t x1 | tr -d ' \n')

# Check if last 6 chars are 000000 (corrupted)
LAST_SIX="${HEXDUMP: -6}"
if [ "$LAST_SIX" = "000000" ]; then
    log_error "Detected corrupted BT MAC (half-zeroed), attempting fix"
    
    # Try to get MAC from WiFi and derive BT MAC (same OUI, different NIC)
    WIFI_MAC=$(cat /sys/class/net/wlan0/address 2>/dev/null | tr -d ':')
    
    if [ -n "$WIFI_MAC" ] && [ "$WIFI_MAC" != "000000000000" ]; then
        # Use WiFi OUI
        OUI="${WIFI_MAC:0:6}"
        # Generate a BT NIC based on device serial
        BT_NIC=$(getprop ro.serialno | md5sum | cut -c1-6)
        
        if [ -z "$BT_NIC" ]; then
            BT_NIC="1a5ab2"  # fallback
        fi
        
        log_info "Generating BT MAC from OUI $OUI + NIC $BT_NIC"
        
        # Write new bt_nv.bin: 01 00 06 + 6 byte MAC
        printf "\x01\x00\x06" > "$BT_NV_FILE.tmp"
        printf "\x${OUI:0:2}\x${OUI:2:2}\x${OUI:4:2}" >> "$BT_NV_FILE.tmp"
        printf "\x${BT_NIC:0:2}\x${BT_NIC:2:2}\x${BT_NIC:4:2}" >> "$BT_NV_FILE.tmp"
        
        # Verify and move
        if [ -s "$BT_NV_FILE.tmp" ]; then
            mv "$BT_NV_FILE.tmp" "$BT_NV_FILE"
            chmod 600 "$BT_NV_FILE"
            chown bluetooth:bluetooth "$BT_NV_FILE"
            log_info "BT MAC fixed successfully"
        else
            log_error "Failed to write new BT NV file"
            rm -f "$BT_NV_FILE.tmp"
        fi
    else
        log_error "Could not get WiFi MAC to derive BT MAC"
    fi
else
    log_info "BT MAC appears valid, no fix needed"
fi

exit 0
