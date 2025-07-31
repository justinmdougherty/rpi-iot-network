#!/bin/bash
# Test script to check if Pumpkin client node is responding

echo "🎃 Testing Pumpkin Client Node"
echo "==============================="
echo "Expected IP: 192.168.4.10"
echo "Expected to be connected to Apple WiFi network"
echo ""

# Test if we can reach the Pumpkin node
echo "🔍 Testing connectivity to Pumpkin..."
if ping -c 3 192.168.4.10 >/dev/null 2>&1; then
    echo "✅ Pumpkin is reachable at 192.168.4.10"
    
    echo ""
    echo "🔧 Testing API endpoints..."
    
    # Test status endpoint
    echo "📊 Status: curl http://192.168.4.10:5000/pumpkin/api/v1/status"
    curl -s http://192.168.4.10:5000/pumpkin/api/v1/status 2>/dev/null | head -5 || echo "❌ Status API not responding"
    
    echo ""
    echo "💡 LED Control Test: curl -X POST http://192.168.4.10:5000/pumpkin/api/v1/actuators/led -d '{\"state\":\"on\"}'"
    curl -s -X POST http://192.168.4.10:5000/pumpkin/api/v1/actuators/led \
         -H 'Content-Type: application/json' \
         -d '{"state":"on"}' 2>/dev/null || echo "❌ LED API not responding"
    
    echo ""
    echo "🎉 Pumpkin appears to be configured correctly!"
else
    echo "❌ Cannot reach Pumpkin at 192.168.4.10"
    echo ""
    echo "💡 Possible reasons:"
    echo "  1. Pumpkin is still booting/configuring (wait 2-3 minutes)"
    echo "  2. Apple AP is not running"
    echo "  3. You're not connected to the Apple WiFi network"
    echo "  4. WiFi configuration failed during deployment"
    echo ""
    echo "🔧 Troubleshooting steps:"
    echo "  1. Make sure Apple AP is running at 192.168.4.1"
    echo "  2. Connect to 'Apple' WiFi (password: Pharos12345)"
    echo "  3. Check if Pumpkin shows up in Apple dashboard"
    echo "  4. If needed, manually SSH to Pumpkin on Ethernet to debug"
fi
