#!/bin/bash
# Fresh Pi Setup - Copy files to SD card boot partition after flashing

echo "🍎 Fresh Pi Auto-Setup Tool"
echo "=========================="
echo ""

# Check if SD card mount point is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <sd-card-mount-point>"
    echo ""
    echo "Examples:"
    echo "  Windows: $0 D:"
    echo "  Linux:   $0 /media/user/bootfs"
    echo "  macOS:   $0 /Volumes/bootfs"
    echo ""
    echo "💡 Flash Raspberry Pi OS first, then run this script"
    exit 1
fi

BOOT_PATH="$1"

# Verify boot partition
if [ ! -d "$BOOT_PATH" ]; then
    echo "❌ Boot partition not found at: $BOOT_PATH"
    echo "💡 Make sure SD card is mounted and path is correct"
    exit 1
fi

echo "📁 Boot partition found: $BOOT_PATH"
echo ""

# Copy configuration files
echo "📤 Copying configuration files..."

# Enable SSH
echo "  ✅ Enabling SSH..."
touch "$BOOT_PATH/ssh"

# Copy WiFi configuration (user needs to edit this)
echo "  📡 Setting up WiFi configuration..."
cp wpa_supplicant.conf "$BOOT_PATH/"
echo "     ⚠️  EDIT wpa_supplicant.conf with your home WiFi details!"

# Copy user configuration (admin:001234)
echo "  👤 Setting up user account (admin:001234)..."
cp userconf.txt "$BOOT_PATH/"

# Copy enhanced boot config
echo "  ⚙️  Copying boot configuration..."
if [ -f "$BOOT_PATH/config.txt" ]; then
    cp "$BOOT_PATH/config.txt" "$BOOT_PATH/config.txt.backup"
    cat boot-config.txt >> "$BOOT_PATH/config.txt"
else
    cp boot-config.txt "$BOOT_PATH/config.txt"
fi

echo ""
echo "🎉 SD Card Auto-Setup Complete!"
echo ""
echo "📋 Next Steps:"
echo "  1. Edit $BOOT_PATH/wpa_supplicant.conf with your WiFi details"
echo "  2. Safely eject SD card"
echo "  3. Boot Pi - it will auto-connect to your WiFi"
echo "  4. Find Pi IP and run deployment scripts"
echo ""
echo "🔧 Auto-configured:"
echo "  ✅ SSH enabled"
echo "  ✅ User: admin / Password: 001234"
echo "  ✅ WiFi enabled and configured"
echo "  ✅ Country code set to US"
echo ""
echo "💡 After Pi boots, use: ./deploy-one-click.sh <pi-ip> <node-name>"
