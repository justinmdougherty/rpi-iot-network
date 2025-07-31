#!/bin/bash
# Make Apple SSID Visible - Quick Fix Script
# Run this on the Apple Pi to make the "Apple" network visible

echo "🍎 Making Apple SSID Visible..."
echo "Current date: $(date)"
echo ""

# Check if we're on the Apple Pi
hostname_check=$(hostname)
if [[ "$hostname_check" != "apple-pie" ]]; then
    echo "⚠️  Warning: This script should be run on the Apple Pi (apple-pie)"
    echo "Current hostname: $hostname_check"
    echo "Continue anyway? (y/N)"
    read -r continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
        echo "Exiting..."
        exit 1
    fi
fi

echo "📝 Backing up current hostapd configuration..."
sudo cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.backup.$(date +%Y%m%d-%H%M%S)

echo "🔧 Modifying hostapd configuration to make SSID visible..."
sudo sed -i 's/ignore_broadcast_ssid=1/ignore_broadcast_ssid=0/' /etc/hostapd/hostapd.conf

echo "📋 Verifying configuration change..."
echo "Current hostapd.conf content:"
echo "================================"
cat /etc/hostapd/hostapd.conf
echo "================================"

echo ""
echo "🔄 Restarting hostapd service to apply changes..."
sudo systemctl restart hostapd

echo "⏳ Waiting for service to restart..."
sleep 5

echo "📊 Checking hostapd service status..."
if sudo systemctl is-active --quiet hostapd; then
    echo "✅ hostapd service is running"
else
    echo "❌ hostapd service failed to start"
    echo "Service status:"
    sudo systemctl status hostapd
    exit 1
fi

echo ""
echo "🎉 Apple SSID should now be VISIBLE!"
echo ""
echo "📡 To verify the change worked:"
echo "   1. Check from another device's WiFi scan"
echo "   2. Look for 'Apple' network in available networks"
echo "   3. It should now appear in the list (not hidden)"
echo ""
echo "🔄 If you want to make it hidden again later, run:"
echo "   sudo sed -i 's/ignore_broadcast_ssid=0/ignore_broadcast_ssid=1/' /etc/hostapd/hostapd.conf"
echo "   sudo systemctl restart hostapd"
echo ""
echo "✅ Done! The Apple network should now be visible."
