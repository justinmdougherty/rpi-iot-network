#!/bin/bash
# Find Apple Access Point Pi
# Scan for Raspberry Pi devices on the network

echo "🔍 Searching for Apple Access Point Pi..."
echo "==========================================="
echo ""

# Try common Pi IPs first
COMMON_IPS=("192.168.86.100" "192.168.86.101" "192.168.86.102" "192.168.86.50" "192.168.86.51" "192.168.86.52" "192.168.86.200" "192.168.86.201")

echo "📡 Testing common Pi IP addresses..."
for ip in "${COMMON_IPS[@]}"; do
    if timeout 2 ssh -o ConnectTimeout=2 -o BatchMode=yes admin@$ip "hostname" 2>/dev/null; then
        echo "✅ Found Pi at $ip: $(ssh admin@$ip 'hostname')"
        echo "   Testing for Apple AP services..."
        
        # Check if it's running hostapd (AP service)
        if ssh admin@$ip "systemctl is-active hostapd" 2>/dev/null | grep -q "active"; then
            echo "🍎 FOUND APPLE AP at $ip!"
            echo "   ✅ hostapd service is running"
            
            # Check if Apple network is being broadcast
            if ssh admin@$ip "iwconfig 2>/dev/null | grep -q Apple"; then
                echo "   ✅ Apple network is being broadcast"
            else
                echo "   ⚠️  Apple network might not be broadcasting"
            fi
            
            # Check network interfaces
            echo "   📊 Network interfaces:"
            ssh admin@$ip "ip addr show | grep -E 'inet.*192\.168\.4\.' || echo '   No 192.168.4.x interface found'"
            
            exit 0
        else
            echo "   ℹ️  Not an Access Point (hostapd not running)"
        fi
    fi
done

echo ""
echo "❌ Apple AP not found in common locations"
echo ""
echo "🔧 Manual troubleshooting steps:"
echo "1. Check your router's admin panel for connected devices"
echo "2. Look for device named 'apple' or with MAC starting with:"
echo "   b8:27:eb, dc:a6:32, e4:5f:01 (common Pi MAC prefixes)"
echo "3. Try these commands on your router or from another device:"
echo "   nmap -sn 192.168.86.0/24"
echo "   arp-scan --local | grep -i raspberry"
echo ""
echo "💡 If Apple AP is connected via Ethernet but not accessible:"
echo "   - Check Ethernet cable connection"
echo "   - Check Pi power and status LEDs"
echo "   - Connect monitor/keyboard to Pi directly"
echo "   - Check router DHCP reservations"
echo ""
