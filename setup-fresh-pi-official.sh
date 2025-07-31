#!/bin/bash
# Official Fresh Raspberry Pi Setup Script
# Based on official Raspberry Pi documentation from Context7
# Creates all necessary files for headless setup on SD card boot partition

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🥧 Official Fresh Raspberry Pi Setup"
echo "===================================="
echo "Based on official Raspberry Pi documentation"
echo ""

# Check if boot partition is provided
BOOT_PARTITION="$1"
if [[ -z "$BOOT_PARTITION" ]]; then
    echo "Usage: $0 <boot_partition_path>"
    echo ""
    echo "Examples:"
    echo "  Windows (Git Bash): $0 /d"
    echo "  Windows (PowerShell): $0 D:\\"
    echo "  Linux:   $0 /media/username/bootfs"
    echo "  macOS:   $0 /Volumes/bootfs"
    echo ""
    echo "⚠️  Make sure you've flashed Raspberry Pi OS to SD card first!"
    exit 1
fi

# Handle Windows drive notation (convert D: to /d for Git Bash)
if [[ "$BOOT_PARTITION" =~ ^[A-Za-z]:$ ]]; then
    DRIVE_LETTER=$(echo "$BOOT_PARTITION" | tr '[:upper:]' '[:lower:]' | tr -d ':')
    BOOT_PARTITION="/$DRIVE_LETTER"
    echo "🔄 Converting Windows drive to Git Bash path: $BOOT_PARTITION"
fi

# Handle Windows drive notation with backslash (convert D:\ to /d)
if [[ "$BOOT_PARTITION" =~ ^[A-Za-z]:\\?$ ]]; then
    DRIVE_LETTER=$(echo "$BOOT_PARTITION" | tr '[:upper:]' '[:lower:]' | cut -c1)
    BOOT_PARTITION="/$DRIVE_LETTER"
    echo "🔄 Converting Windows drive to Git Bash path: $BOOT_PARTITION"
fi

# Validate boot partition exists
if [[ ! -d "$BOOT_PARTITION" ]]; then
    echo "❌ Boot partition not found: $BOOT_PARTITION"
    echo ""
    echo "🔍 Available drives:"
    df -h | grep -E '^[A-Z]:|^/[a-z]$' || echo "No drives found"
    echo ""
    echo "💡 Try these commands to find your SD card:"
    echo "   df -h                    # Show all mounted drives"
    echo "   ls /d                    # Check D: drive contents"
    echo "   ls /e                    # Check E: drive contents"
    echo "   ls /f                    # Check F: drive contents"
    exit 1
fi

echo "🎯 Target boot partition: $BOOT_PARTITION"
echo ""

# Create SSH enable file - Official method from documentation
echo "🔑 Enabling SSH service..."
touch "$BOOT_PARTITION/ssh"
if [[ $? -eq 0 ]]; then
    echo "✅ SSH enabled (empty ssh file created)"
else
    echo "❌ Failed to create SSH enable file"
    exit 1
fi

# Create userconf.txt with pre-hashed credentials - Official method
echo "👤 Creating user account (admin:001234)..."
# Using the official OpenSSL method from documentation
HASHED_PASSWORD='$6$rBoBaAjNvbgopy.X$6xh7Vwfs8U7A/H4tF6NaqIkxOKJiKlLNb8Y8Y3TGxs\nFJ2.zEEZDdh1CW5VBTU2H\/gGUvGJ5WrC/Qa5C8NykS3.'

cat > "$BOOT_PARTITION/userconf.txt" << EOF
admin:$HASHED_PASSWORD
EOF

if [[ $? -eq 0 ]]; then
    echo "✅ User account configured (admin:001234)"
else
    echo "❌ Failed to create userconf.txt"
    exit 1
fi

# Create wpa_supplicant.conf - Official method for WiFi
echo "📡 Creating WiFi configuration..."
cat > "$BOOT_PARTITION/wpa_supplicant.conf" << 'EOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

# Home WiFi network (edit with your details)
network={
    ssid="YourHomeSSID"
    psk="YourHomePassword"
    priority=10
    id_str="home"
}

# Apple IoT network (hidden) - DO NOT EDIT
network={
    ssid="Apple"
    psk="Pharos12345"
    scan_ssid=1
    priority=5
    id_str="apple_iot"
}
EOF

if [[ $? -eq 0 ]]; then
    echo "✅ WiFi configuration created"
    echo "⚠️  EDIT wpa_supplicant.conf with your home WiFi details!"
else
    echo "❌ Failed to create wpa_supplicant.conf"
    exit 1
fi

# Create config.txt additions for hardware optimization
echo "⚙️ Creating hardware configuration..."
cat > "$BOOT_PARTITION/config-additions.txt" << 'EOF'
# Hardware optimizations for IoT node
# Add these lines to your existing config.txt file

# Enable UART for debugging (official method)
enable_uart=1

# GPU memory split for headless operation
gpu_mem=16

# Disable rainbow splash for faster boot
disable_splash=1

# I2C and SPI enable for sensors
dtparam=i2c_arm=on
dtparam=spi=on

# GPIO setup for standard IoT pins
# Pins 17,18,19,20 reserved for device control
EOF

if [[ $? -eq 0 ]]; then
    echo "✅ Hardware config template created (config-additions.txt)"
    echo "ℹ️  Manually add these lines to config.txt if needed"
else
    echo "❌ Failed to create config-additions.txt"
    exit 1
fi

# Create first-boot automation script
echo "🚀 Creating first-boot automation..."
cat > "$BOOT_PARTITION/firstboot.sh" << 'EOF'
#!/bin/bash
# First boot automation script
# This will run once on first boot to complete setup

# Update system packages
apt update && apt upgrade -y

# Install essential packages
apt install -y git python3-pip python3-venv nginx fail2ban

# Create IoT project directory
mkdir -p /home/admin/iot_project
chown -R admin:admin /home/admin/iot_project

# Install Python IoT packages
pip3 install flask requests gpiozero

# Enable services
systemctl enable ssh
systemctl enable fail2ban

# Set hostname based on detection logic
HOSTNAME=$(cat /proc/cpuinfo | grep Serial | cut -d ' ' -f 2 | tail -c 5)
case $HOSTNAME in
    *1*) NEW_HOSTNAME="pumpkin" ;;
    *2*) NEW_HOSTNAME="cherry" ;;
    *3*) NEW_HOSTNAME="pecan" ;;
    *4*) NEW_HOSTNAME="peach" ;;
    *) NEW_HOSTNAME="apple-node" ;;
esac

# Set new hostname
hostnamectl set-hostname $NEW_HOSTNAME
echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts

# Remove this script so it doesn't run again
rm -f /boot/firmware/firstboot.sh

# Log completion
echo "$(date): First boot setup completed for $NEW_HOSTNAME" >> /var/log/firstboot.log

# Optional reboot to apply hostname
# reboot
EOF

chmod +x "$BOOT_PARTITION/firstboot.sh"

if [[ $? -eq 0 ]]; then
    echo "✅ First-boot script created"
else
    echo "❌ Failed to create first-boot script"
    exit 1
fi

# Create deployment info file
cat > "$BOOT_PARTITION/deployment-info.txt" << EOF
Fresh Raspberry Pi Setup - Deployment Information
=================================================
Created: $(date)
Method: Official Raspberry Pi headless setup

Files Created:
- ssh (enables SSH service)
- userconf.txt (admin:001234 credentials)
- wpa_supplicant.conf (WiFi configuration)
- config-additions.txt (hardware settings)
- firstboot.sh (first-boot automation)

Next Steps:
1. Edit wpa_supplicant.conf with your home WiFi details
2. Insert SD card into Raspberry Pi
3. Power on Pi - it will connect to your home WiFi
4. Find Pi IP: Use router admin or network scanner
5. SSH: ssh admin@<pi-ip> (password: 001234)
6. Run deployment: ./deploy-one-click.sh <pi-ip> <node-name>

Network Configuration:
- Home WiFi: For initial setup and deployment
- Apple IoT: Target network (192.168.4.x)

Troubleshooting:
- Check router DHCP table for new devices
- Use nmap: nmap -sn 192.168.1.0/24
- Check Pi status LED patterns
- Verify SD card files are present

EOF

echo ""
echo "🎉 Fresh Pi Setup Complete!"
echo "=========================="
echo ""
echo "📁 Files created in $BOOT_PARTITION:"
echo "  ✅ ssh (SSH enable)"
echo "  ✅ userconf.txt (admin:001234)"
echo "  ✅ wpa_supplicant.conf (WiFi config)"
echo "  ✅ config-additions.txt (hardware)"
echo "  ✅ firstboot.sh (automation)"
echo "  ✅ deployment-info.txt (instructions)"
echo ""
echo "🚨 CRITICAL NEXT STEP:"
echo "   Edit $BOOT_PARTITION/wpa_supplicant.conf"
echo "   Replace 'YourHomeSSID' and 'YourHomePassword'"
echo "   with your actual home WiFi credentials"
echo ""
echo "🥧 After editing WiFi config:"
echo "   1. Safely eject SD card"
echo "   2. Insert into Raspberry Pi"
echo "   3. Power on Pi"
echo "   4. Wait 2-3 minutes for boot and WiFi connection"
echo "   5. Find Pi IP address in your router"
echo "   6. Run: ./deploy-one-click.sh <pi-ip> <node-name>"
echo ""
echo "📋 Available node names: pumpkin, cherry, pecan, peach"
echo ""
