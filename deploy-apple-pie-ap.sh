#!/bin/bash
# Apple Pie AP Deployment Script
# Deploys the Apple Pi as an Access Point with UART device control

# Function to find Raspberry Pi on network
find_raspberry_pi() {
    echo "🔍 Scanning for Raspberry Pi devices on local network..."
    
    # Try common hostnames first
    for hostname in raspberrypi raspberrypi.local apple apple.local; do
        if ping -c 1 "$hostname" &>/dev/null; then
            echo "✅ Found Pi at: $hostname"
            return 0
        fi
    done
    
    echo "❌ No Pi found with common hostnames"
    echo ""
    echo "💡 Manual discovery options:"
    echo "1. Check your router's admin page for connected devices"
    echo "2. Use: nmap -sn 192.168.1.0/24 | grep -i raspberry"
    echo "3. Use: arp -a | grep -i b8:27:eb"
    echo "4. Connect monitor/keyboard to Pi to see IP with: hostname -I"
    return 1
}

# Check command line arguments
if [ "$1" = "--find" ]; then
    if find_raspberry_pi; then
        read -p "Enter the Pi IP address found above: " PI_IP
    else
        exit 1
    fi
elif [ -n "$1" ]; then
    PI_IP="$1"
else
    echo "Usage: $0 <pi-ip-address>"
    echo "   or: $0 --find"
    echo ""
    echo "💡 To find your Pi's IP address:"
    echo "1. Check router admin page for 'raspberrypi' device"
    echo "2. Run: nmap -sn 192.168.1.0/24 | grep -i raspberry"
    echo "3. Connect monitor to Pi and run: hostname -I"
    exit 1
fi

echo "======================================"
echo "🍎🥧 Apple Pie AP Deployment"
echo "======================================"
echo "Target Pi: $PI_IP"
echo "Configuration: Access Point + UART Control"
echo "Network: Hidden 'Apple' SSID"
echo "Dashboard: http://192.168.4.1:5000"
echo ""

echo "Uploading Apple Pie AP setup script..."
echo "Using credentials: admin/001234"
scp setup-apple-pie-ap.sh admin@$PI_IP:/home/admin/

echo "Connecting to Pi and running Apple Pie AP setup..."
echo "Password: 001234"
ssh admin@$PI_IP << 'ENDSSH'
chmod +x setup-apple-pie-ap.sh
sudo ./setup-apple-pie-ap.sh
ENDSSH

echo ""
echo "======================================"
echo "🍎🥧 Apple Pie AP Deployment Complete!"
echo "======================================"
echo "AP Configuration:"
echo "- Name: Apple (hidden network)"
echo "- IP: 192.168.4.1"
echo "- Password: Pharos12345"
echo "- DHCP: 192.168.4.10-50"
echo ""
echo "Services Configured:"
echo "- WiFi Access Point (hostapd)"
echo "- DHCP Server (dnsmasq)"
echo "- Flask API Server (port 5000)"
echo "- UART Device Management"
echo ""
echo "Next Steps:"
echo "1. Reboot the Pi: ssh admin@$PI_IP 'sudo reboot'"
echo "2. Connect to 'Apple' WiFi network (password: Pharos12345)"
echo "3. Access dashboard: http://192.168.4.1:5000"
echo "4. Connect UART devices and test via API"
echo ""
echo "API Endpoints Available:"
echo "- GET  /api/v1/status - AP status"
echo "- GET  /api/v1/uart/discover - Find UART devices"
echo "- POST /api/v1/uart/connect - Connect to device"
echo "- POST /api/v1/uart/<device>/command - Send commands"
echo "- PUT  /api/v1/uart/<device>/config - Update config"
echo "======================================"
