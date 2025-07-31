#!/bin/bash
# Verify Apple SSID Visibility
# Run this to check if the Apple network is now visible

echo "🔍 Checking Apple SSID Visibility..."
echo "Date: $(date)"
echo ""

echo "📡 Testing from Apple Pi (192.168.86.62):"
ssh admin@192.168.86.62 << 'EOF'
echo "🔧 hostapd configuration:"
sudo grep "ignore_broadcast_ssid" /etc/hostapd/hostapd.conf

echo ""
echo "📊 hostapd service status:"
sudo systemctl is-active hostapd

echo ""
echo "🌐 WiFi interface status:"
iwconfig wlan0 | grep -E "ESSID|Mode"

echo ""
echo "📋 Current hostapd process:"
ps aux | grep hostapd | grep -v grep
EOF

echo ""
echo "✅ Apple SSID Status Summary:"
echo "   - ignore_broadcast_ssid should be set to 0 (visible)"
echo "   - hostapd service should be active"
echo "   - WiFi should be in Master mode"
echo ""
echo "📱 To connect from another device:"
echo "   1. Scan for WiFi networks"
echo "   2. Look for 'Apple' in the list"
echo "   3. Connect with password: Pharos12345"
echo ""
echo "🔄 If Apple network still not visible, try:"
echo "   - Wait 30-60 seconds for changes to take effect"
echo "   - Refresh WiFi scan on your device"
echo "   - Restart WiFi on your connecting device"
