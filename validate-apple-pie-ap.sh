#!/bin/bash
# Apple Pie AP Verification Script
# Tests all functionality and handles session cleanup properly

PI_IP="192.168.86.62"
AP_IP="192.168.4.1"

echo "🍎 Apple Pie Access Point - Verification Script"
echo "================================================"

# Function to run SSH commands with proper cleanup
run_ssh_command() {
    local command="$1"
    local description="$2"
    
    echo "🔧 $description..."
    ssh -o ConnectTimeout=10 admin@$PI_IP "$command; exit" 2>/dev/null
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "✅ Success"
    else
        echo "❌ Failed (exit code: $exit_code)"
    fi
    return $exit_code
}

# Test 1: Check hostname
run_ssh_command "hostname" "Checking hostname"

# Test 2: Check WiFi AP status
run_ssh_command "sudo systemctl is-active hostapd" "Checking WiFi Access Point"

# Test 3: Check DHCP server
run_ssh_command "sudo systemctl is-active dnsmasq" "Checking DHCP server"

# Test 4: Check dashboard service
run_ssh_command "sudo systemctl is-active apple-pie-dashboard" "Checking dashboard service"

# Test 5: Check wlan0 configuration
run_ssh_command "ip addr show wlan0 | grep '192.168.4.1'" "Checking wlan0 IP configuration"

# Test 6: Test dashboard API (from within the Pi network)
echo "🌐 Testing dashboard API..."
if run_ssh_command "curl -s http://192.168.4.1/api/v1/status" "API test"; then
    echo "✅ Dashboard API is responding"
else
    echo "❌ Dashboard API not responding"
fi

echo ""
echo "🎯 Connection Information:"
echo "📶 Hidden WiFi Network: 'Apple'"
echo "🔐 Password: Pharos12345"
echo "🌐 Access Point IP: 192.168.4.1"
echo "🖥️  Dashboard: http://192.168.4.1/"
echo "🔧 UART API: http://192.168.4.1/api/v1/uart/"
echo ""
echo "📱 To connect:"
echo "1. Connect to hidden WiFi 'Apple' with password 'Pharos12345'"
echo "2. Open browser to http://192.168.4.1"
echo "3. You should see the Apple Pie dashboard!"
echo ""
echo "🔍 If you're already connected to the Apple network and still see issues:"
echo "- Clear your browser cache"
echo "- Try http://192.168.4.1/ directly"
echo "- Check that you got an IP in range 192.168.4.10-50"
