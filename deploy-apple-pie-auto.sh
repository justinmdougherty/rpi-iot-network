#!/bin/bash
# Automated Apple Pie Access Point Deployment
# Includes all fixes and handles session management properly

PI_IP="${1:-192.168.86.62}"

echo "� Pumpkin Access Point - Automated Deployment"
echo "==============================================="
echo "Target Pi: $PI_IP"
echo "Deploying comprehensive AP setup with all fixes included..."
echo ""

# Check if setup script exists
if [[ ! -f "setup-apple-pie-complete.sh" ]]; then
    echo "❌ setup-apple-pie-complete.sh not found!"
    exit 1
fi

# Single command deployment to avoid password prompts
echo "🚀 Deploying Pumpkin Access Point..."
echo "This will configure:"
echo "  ✅ Hidden 'Apple' WiFi network"
echo "  ✅ DHCP server (192.168.4.10-50)"
echo "  ✅ Flask dashboard on port 80"
echo "  ✅ UART device management"
echo "  ✅ All service configurations"
echo "  ✅ Network fixes and optimizations"
echo ""

# Execute deployment
if cat setup-apple-pie-complete.sh | ssh admin@$PI_IP "cat > /tmp/setup.sh && chmod +x /tmp/setup.sh && sudo /tmp/setup.sh; exit_code=\$?; rm -f /tmp/setup.sh; exit \$exit_code"; then
    echo ""
    echo "🎉 Pumpkin Access Point Deployment Complete!"
    echo ""
    echo "📱 Connection Information:"
    echo "  📶 Network Name: Apple (Hidden SSID)"
    echo "  🔐 Password: Pharos12345"
    echo "  🌐 Access Point IP: 192.168.4.1"
    echo "  📱 Client IP Range: 192.168.4.10-50"
    echo ""
    echo "🖥️  Dashboard Access:"
    echo "  🍎 Main Dashboard: http://192.168.4.1/"
    echo "  🔧 UART API: http://192.168.4.1/api/v1/uart/"
    echo "  📊 Status API: http://192.168.4.1/api/v1/status"
    echo ""
    echo "🔧 Next Steps:"
    echo "  1. Connect your device to 'Apple' WiFi network"
    echo "  2. Open http://192.168.4.1/ in your browser"
    echo "  3. Test UART device connections"
    echo "  4. Deploy client nodes using:"
    echo "     ./deploy-client.sh <client-pi-ip> cherry"
    echo "     ./deploy-client.sh <client-pi-ip> pecan"
    echo "     ./deploy-client.sh <client-pi-ip> peach"
    
    # Quick verification
    echo ""
    echo "🔍 Quick Verification:"
    echo "Testing AP services..."
    
    if ssh admin@$PI_IP "ping -c 1 192.168.4.1 >/dev/null 2>&1; exit" 2>/dev/null; then
        echo "✅ Access Point IP reachable"
    else
        echo "⚠️  Access Point IP test inconclusive"
    fi
    
else
    echo ""
    echo "❌ Deployment Failed!"
    echo "Check the error messages above for details."
    echo ""
    echo "🔧 Troubleshooting:"
    echo "  1. Verify Pi is accessible: ping $PI_IP"
    echo "  2. Check SSH access: ssh admin@$PI_IP"
    echo "  3. Ensure credentials are admin/001234"
    echo "  4. Check Pi has internet connection for package downloads"
    exit 1
fi
