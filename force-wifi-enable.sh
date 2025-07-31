#!/bin/bash
# Force enable WiFi hardware and connect - AUTOMATED

PI_IP="192.168.86.26"

echo "🎃 FORCE Enable WiFi and Connect Pumpkin"
echo "========================================"
echo "Target Pi: $PI_IP"
echo ""

# Create comprehensive WiFi enablement script
cat > /tmp/force_wifi.sh << 'EOF'
#!/bin/bash

# Function to execute commands on Pi with password
exec_on_pi() {
    local cmd="$1"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR admin@192.168.86.26 << REMOTE_EOF
001234
$cmd
exit
REMOTE_EOF
}

echo "🔧 Step 1: Checking current WiFi status..."
exec_on_pi "
echo '=== Current Device Status ==='
sudo nmcli device status
echo ''
echo '=== Current rfkill status ==='
sudo rfkill list all
"

echo ""
echo "🔧 Step 2: Force enable WiFi hardware..."
exec_on_pi "
echo '=== Unblocking WiFi ==='
sudo rfkill unblock all
sudo rfkill unblock wifi
echo ''
echo '=== After unblock ==='
sudo rfkill list all
"

echo ""
echo "🔧 Step 3: Restart networking services..."
exec_on_pi "
echo '=== Restarting services ==='
sudo systemctl restart NetworkManager
sleep 5
sudo systemctl status NetworkManager --no-pager
"

echo ""
echo "🔧 Step 4: Check if WiFi is now available..."
exec_on_pi "
echo '=== Device status after restart ==='
sudo nmcli device status
echo ''
echo '=== Available networks ==='
sudo nmcli device wifi list || echo 'WiFi scan failed'
"

echo ""
echo "🔧 Step 5: Attempt connection..."
exec_on_pi "
echo '=== Connecting to Apple ==='
sudo nmcli connection up Apple-Connection || echo 'Connection failed - this is expected if WiFi hardware is disabled'
echo ''
echo '=== Final status ==='
sudo nmcli connection show --active
hostname -I
"

EOF

chmod +x /tmp/force_wifi.sh
bash /tmp/force_wifi.sh

echo ""
echo "🔍 Final connectivity test..."
sleep 3

if ping -c 2 192.168.4.10 >/dev/null 2>&1; then
    echo "✅ SUCCESS! Pumpkin connected to Apple WiFi at 192.168.4.10"
else
    echo "⚠️  WiFi hardware may be permanently disabled on this Pi"
    echo ""
    echo "💡 Solutions:"
    echo "  1. This Pi might not have WiFi hardware"
    echo "  2. WiFi might be disabled in firmware/config"
    echo "  3. Try enabling WiFi in raspi-config"
    echo ""
    echo "🔧 Manual check: SSH to Pi and run 'sudo raspi-config' → Advanced → WiFi"
fi

rm -f /tmp/force_wifi.sh
