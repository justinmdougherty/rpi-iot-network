#!/bin/bash
# Raspberry Pi IP Discovery Helper
# Various methods to find your Pi's IP address on the network

echo "======================================"
echo "Raspberry Pi IP Discovery Helper"
echo "======================================"

echo "🔍 Method 1: Checking common hostnames..."
for hostname in raspberrypi raspberrypi.local; do
    echo -n "Trying $hostname... "
    if ping -c 1 -W 2 "$hostname" &>/dev/null; then
        ip=$(ping -c 1 "$hostname" | grep -oP '(\d+\.){3}\d+' | head -1)
        echo "✅ FOUND: $hostname ($ip)"
        FOUND_IP="$ip"
    else
        echo "❌ Not found"
    fi
done

echo ""
echo "🔍 Method 2: Scanning local network for Pi MAC addresses..."
echo "Looking for Raspberry Pi Foundation MAC addresses (b8:27:eb, dc:a6:32, e4:5f:01)..."

# Get local network
local_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+' 2>/dev/null || hostname -I | awk '{print $1}')
if [ -n "$local_ip" ]; then
    network=$(echo "$local_ip" | cut -d. -f1-3)
    echo "Scanning network: ${network}.0/24"
    
    # Use nmap if available
    if command -v nmap &>/dev/null; then
        echo "Using nmap scan..."
        nmap -sn "${network}.0/24" &>/dev/null
        arp -a | grep -E "(b8:27:eb|dc:a6:32|e4:5f:01)" | while read line; do
            ip=$(echo "$line" | grep -oP '(\d+\.){3}\d+')
            mac=$(echo "$line" | grep -oP '([0-9a-f]{2}:){5}[0-9a-f]{2}')
            echo "✅ FOUND Pi: $ip ($mac)"
        done
    else
        echo "nmap not available, checking ARP table..."
        arp -a | grep -E "(b8:27:eb|dc:a6:32|e4:5f:01)" | while read line; do
            ip=$(echo "$line" | grep -oP '(\d+\.){3}\d+')
            mac=$(echo "$line" | grep -oP '([0-9a-f]{2}:){5}[0-9a-f]{2}')
            echo "✅ FOUND Pi: $ip ($mac)"
        done
    fi
fi

echo ""
echo "🔍 Method 3: Manual discovery options..."
echo "If automatic discovery didn't work, try these:"
echo ""
echo "Router Admin Page:"
echo "  1. Open your router's web interface (usually http://192.168.1.1 or http://192.168.0.1)"
echo "  2. Look for connected devices or DHCP client list"
echo "  3. Find device named 'raspberrypi' or with Pi MAC address"
echo ""
echo "Command Line Options:"
echo "  • arp -a | grep -E \"(b8:27:eb|dc:a6:32|e4:5f:01)\""
echo "  • nmap -sn 192.168.1.0/24 (adjust network range)"
echo "  • avahi-browse -rt _ssh._tcp (if avahi installed)"
echo ""
echo "Direct Pi Access:"
echo "  • Connect monitor and keyboard to Pi"
echo "  • Run: hostname -I"
echo "  • Or check: ip addr show"

echo ""
echo "======================================"
if [ -n "$FOUND_IP" ]; then
    echo "✅ Pi likely found at: $FOUND_IP"
    echo ""
    echo "To deploy Apple node configuration:"
    echo "  ./deploy-apple.sh $FOUND_IP"
    echo "  or"
    echo "  ./Deploy-AppleNode.ps1 -PiIP $FOUND_IP"
else
    echo "❌ No Pi automatically discovered"
    echo "Try the manual methods listed above"
fi
echo "======================================"
