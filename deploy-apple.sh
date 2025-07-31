#!/bin/bash
# Quick deployment script - copy and run this on the Apple Pi (Access Point)

# Function to find Raspberry Pi on network
find_raspberry_pi() {
    echo "🔍 Scanning for Raspberry Pi devices on local network..."
    
    # Try common hostnames first
    for hostname in raspberrypi raspberrypi.local; do
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
# Determine deployment type
if [[ -f "setup-apple-pie-complete.sh" ]]; then
    SETUP_SCRIPT="setup-apple-pie-complete.sh"
    DEPLOYMENT_TYPE="Apple Pie Access Point"
    TARGET_ROLE="Access Point"
elif [[ -f "setup-client-complete.sh" ]]; then
    SETUP_SCRIPT="setup-client-complete.sh"
    DEPLOYMENT_TYPE="Client Node"
    TARGET_ROLE="Client"
else
    echo "❌ No setup script found! Expected setup-apple-pie-complete.sh or setup-client-complete.sh"
    exit 1
fi

echo "🚀 Deploying $DEPLOYMENT_TYPE to $PI_IP..."
echo "📋 Setup script: $SETUP_SCRIPT"
echo "🎯 Target role: $TARGET_ROLE"
echo ""

# Upload and execute in one command to avoid password prompts
echo "📤 Uploading and executing setup script..."
cat "$SETUP_SCRIPT" | ssh admin@$PI_IP "cat > /tmp/complete-setup.sh && chmod +x /tmp/complete-setup.sh && sudo /tmp/complete-setup.sh && rm /tmp/complete-setup.sh"

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Deployment successful!"
    echo ""
    if [[ "$DEPLOYMENT_TYPE" == "Apple Pie Access Point" ]]; then
        echo "✅ Apple Pie Access Point Configuration:"
        echo "  📶 Hidden WiFi: 'Apple' (password: Pharos12345)"
        echo "  🌐 AP IP: 192.168.4.1"
        echo "  🖥️  Dashboard: http://192.168.4.1/"
        echo "  🔧 UART API: http://192.168.4.1/api/v1/uart/"
        echo ""
        echo "📱 Next steps:"
        echo "  1. Connect to 'Apple' WiFi network"
        echo "  2. Open http://192.168.4.1/ in browser"
        echo "  3. Deploy client nodes (Pumpkin, Cherry, Pecan, Peach)"
    else
        echo "✅ Client Node Configuration:"
        echo "  🏷️  Hostname: Configured during setup"
        echo "  📡 Connected to: Apple AP"
        echo "  🔌 API Port: 5000"
        echo ""
        echo "📱 Access from Apple dashboard at http://192.168.4.1/"
    fi
else
    echo "❌ Deployment failed! Check the error messages above."
    exit 1
fi
