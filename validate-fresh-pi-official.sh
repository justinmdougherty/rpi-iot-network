#!/bin/bash
# Official Raspberry Pi Setup Validator
# Based on official Raspberry Pi documentation
# Validates fresh Pi setup files for headless deployment

echo "🔍 Official Raspberry Pi Setup Validator"
echo "========================================"
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
    exit 1
fi

echo "🎯 Validating: $BOOT_PARTITION"
echo ""

ERRORS=0
WARNINGS=0

# Check SSH enable file (official requirement)
echo "🔑 Checking SSH configuration..."
if [[ -f "$BOOT_PARTITION/ssh" ]]; then
    echo "✅ SSH enable file present"
else
    echo "❌ SSH enable file missing"
    echo "   Create with: touch $BOOT_PARTITION/ssh"
    ((ERRORS++))
fi

# Check userconf.txt (official user creation method)
echo ""
echo "👤 Checking user configuration..."
if [[ -f "$BOOT_PARTITION/userconf.txt" ]]; then
    echo "✅ userconf.txt present"
    
    # Validate format
    if grep -q "admin:" "$BOOT_PARTITION/userconf.txt"; then
        echo "✅ admin user configured"
    else
        echo "⚠️  admin user not found in userconf.txt"
        ((WARNINGS++))
    fi
    
    # Check if password is hashed
    if grep -q '\$6\$' "$BOOT_PARTITION/userconf.txt"; then
        echo "✅ Password properly hashed (SHA-512)"
    else
        echo "❌ Password not properly hashed"
        echo "   Use: openssl passwd -6"
        ((ERRORS++))
    fi
else
    echo "❌ userconf.txt missing"
    echo "   Create with hashed password for admin user"
    ((ERRORS++))
fi

# Check wpa_supplicant.conf (official WiFi method)
echo ""
echo "📡 Checking WiFi configuration..."
if [[ -f "$BOOT_PARTITION/wpa_supplicant.conf" ]]; then
    echo "✅ wpa_supplicant.conf present"
    
    # Check required fields
    if grep -q "ctrl_interface=" "$BOOT_PARTITION/wpa_supplicant.conf"; then
        echo "✅ Control interface configured"
    else
        echo "❌ Missing ctrl_interface"
        ((ERRORS++))
    fi
    
    if grep -q "country=" "$BOOT_PARTITION/wpa_supplicant.conf"; then
        echo "✅ Country code set"
    else
        echo "⚠️  Country code not set"
        ((WARNINGS++))
    fi
    
    # Check networks
    HOME_NETWORKS=$(grep -c "ssid=" "$BOOT_PARTITION/wpa_supplicant.conf" | grep -v "Apple")
    APPLE_NETWORK=$(grep -c "ssid=\"Apple\"" "$BOOT_PARTITION/wpa_supplicant.conf")
    
    if [[ $HOME_NETWORKS -gt 0 ]]; then
        echo "✅ Home WiFi network configured"
    else
        echo "❌ No home WiFi network found"
        echo "   Add your home network for initial access"
        ((ERRORS++))
    fi
    
    if [[ $APPLE_NETWORK -eq 1 ]]; then
        echo "✅ Apple IoT network configured"
        
        # Check if Apple network is hidden
        if grep -A5 "ssid=\"Apple\"" "$BOOT_PARTITION/wpa_supplicant.conf" | grep -q "scan_ssid=1"; then
            echo "✅ Apple network correctly set as hidden"
        else
            echo "⚠️  Apple network should be marked as hidden (scan_ssid=1)"
            ((WARNINGS++))
        fi
    else
        echo "❌ Apple IoT network not configured"
        ((ERRORS++))
    fi
    
    # Check for default passwords
    if grep -q "YourHomeSSID\|YourHomePassword" "$BOOT_PARTITION/wpa_supplicant.conf"; then
        echo "❌ Default WiFi credentials still present"
        echo "   Edit with your actual home WiFi details"
        ((ERRORS++))
    fi
    
else
    echo "❌ wpa_supplicant.conf missing"
    echo "   Required for WiFi connection"
    ((ERRORS++))
fi

# Check config.txt for IoT optimizations
echo ""
echo "⚙️ Checking hardware configuration..."
if [[ -f "$BOOT_PARTITION/config.txt" ]]; then
    echo "✅ config.txt present"
    
    # Check for UART (useful for debugging)
    if grep -q "enable_uart=1" "$BOOT_PARTITION/config.txt"; then
        echo "✅ UART enabled for debugging"
    else
        echo "ℹ️  UART not enabled (optional)"
    fi
    
    # Check for GPIO/I2C/SPI
    if grep -q "dtparam=i2c_arm=on" "$BOOT_PARTITION/config.txt"; then
        echo "✅ I2C enabled for sensors"
    else
        echo "ℹ️  I2C not enabled (may be needed for sensors)"
    fi
    
else
    echo "⚠️  config.txt not found (check boot partition)"
    ((WARNINGS++))
fi

# Check for kernel and bootloader files
echo ""
echo "🥧 Checking core boot files..."
CORE_FILES=("start*.elf" "kernel*.img" "bootcode.bin" "fixup*.dat")
for pattern in "${CORE_FILES[@]}"; do
    if ls "$BOOT_PARTITION"/$pattern >/dev/null 2>&1; then
        echo "✅ Boot files present ($pattern)"
    else
        echo "⚠️  Boot files missing ($pattern)"
        ((WARNINGS++))
    fi
done

# Summary
echo ""
echo "📊 Validation Summary"
echo "===================="

if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo "🎉 Perfect! All checks passed"
    echo ""
    echo "🚀 Ready for deployment:"
    echo "   1. Safely eject SD card"
    echo "   2. Insert into Raspberry Pi"
    echo "   3. Power on and wait 2-3 minutes"
    echo "   4. Find Pi IP in router or use network scan"
    echo "   5. Run: ./deploy-one-click.sh <pi-ip> <node-name>"
    
elif [[ $ERRORS -eq 0 ]]; then
    echo "✅ All critical checks passed"
    echo "⚠️  $WARNINGS warning(s) - deployment should work"
    echo ""
    echo "🚀 Proceed with deployment if warnings are acceptable"
    
else
    echo "❌ $ERRORS critical error(s) found"
    if [[ $WARNINGS -gt 0 ]]; then
        echo "⚠️  $WARNINGS warning(s) also found"
    fi
    echo ""
    echo "🔧 Fix errors before deployment:"
    echo "   - Review error messages above"
    echo "   - Use official setup script: ./setup-fresh-pi-official.sh"
    echo "   - Validate again after fixes"
fi

echo ""
echo "📋 Available deployment commands:"
echo "   ./deploy-one-click.sh <pi-ip> pumpkin"
echo "   ./deploy-one-click.sh <pi-ip> cherry"
echo "   ./deploy-one-click.sh <pi-ip> pecan"
echo "   ./deploy-one-click.sh <pi-ip> peach"
echo ""

exit $ERRORS
