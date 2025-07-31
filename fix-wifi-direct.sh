#!/bin/bash
# Direct WiFi fix for Pumpkin - since it's worked before

echo "🔧 Direct WiFi Fix for Pumpkin"
echo "=============================="
echo "Since this Pi has worked on WiFi before, let's force it"
echo ""

# Exit raspi-config if you're still in it, then run this:

echo "Step 1: Bringing up WiFi interface manually..."
sudo ip link set wlan0 down
sudo ip link set wlan0 up

echo ""
echo "Step 2: Restarting WiFi services..."
sudo modprobe -r brcmfmac
sudo modprobe brcmfmac

echo ""
echo "Step 3: Restarting NetworkManager..."
sudo systemctl restart NetworkManager
sleep 5

echo ""
echo "Step 4: Checking status..."
sudo nmcli device status

echo ""
echo "Step 5: Scanning for networks..."
sudo nmcli device wifi rescan
sleep 3
sudo nmcli device wifi list

echo ""
echo "Step 6: Connecting to Apple network..."
sudo nmcli connection up Apple-Connection

echo ""
echo "Step 7: Final status..."
sudo nmcli connection show --active
ip addr show wlan0
