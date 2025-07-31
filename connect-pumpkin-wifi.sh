#!/bin/bash
# Completely automated WiFi connection script - NO PASSWORD PROMPTS

PI_IP="192.168.86.26"

echo "🎃 Connecting Pumpkin to Apple WiFi - AUTOMATED"
echo "==============================================="
echo "Target Pi: $PI_IP"
echo "🔐 Using embedded credentials"
echo ""

# Create a script that handles WiFi connection with embedded password
cat > /tmp/wifi_connect.sh << 'EOF'
#!/bin/bash
PI_IP="$1"

# Use here-doc to provide password automatically
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR admin@$PI_IP << 'REMOTE_COMMANDS'
001234

# Enable WiFi if needed
sudo rfkill unblock wifi
sudo ip link set wlan0 up

# Check device status
echo "📊 Device Status:"
sudo nmcli device status

echo ""
echo "📡 Available WiFi Networks:"
sudo nmcli device wifi list

echo ""
echo "🔗 Attempting to connect to Apple network..."
sudo nmcli connection up Apple-Connection

echo ""
echo "📊 Connection Status:"
sudo nmcli connection show --active

echo ""
echo "🌐 IP Address:"
hostname -I

exit
REMOTE_COMMANDS
EOF

chmod +x /tmp/wifi_connect.sh

echo "📡 Executing WiFi connection..."
bash /tmp/wifi_connect.sh "$PI_IP"

echo ""
echo "🔍 Testing connectivity..."
sleep 5

# Test if Pumpkin is now accessible on the Apple network
if ping -c 2 192.168.4.10 >/dev/null 2>&1; then
    echo "✅ SUCCESS! Pumpkin is now accessible at 192.168.4.10"
    echo ""
    echo "🎉 Pumpkin Client Node is connected to Apple WiFi!"
    echo "📊 Test the API: curl http://192.168.4.10:5000/pumpkin/api/v1/status"
else
    echo "⚠️  Pumpkin may still be connecting or check your Apple WiFi connection"
    echo "💡 Connect to Apple WiFi network and try: curl http://192.168.4.10:5000/pumpkin/api/v1/status"
fi

# Clean up
rm -f /tmp/wifi_connect.sh
