#!/bin/bash
# Automated Client Node Deployment
# Configures Pi as Pumpkin, Cherry, Pecan, or Peach client connecting to Apple AP

PI_IP="$1"
NODE_NAME="$2"

if [[ -z "$PI_IP" || -z "$NODE_NAME" ]]; then
    echo "Usage: $0 <pi-ip-address> <node-name>"
    echo ""
    echo "Available node names:"
    echo "  � pumpkin - IP: 192.168.4.10"
    echo "  🍒 cherry  - IP: 192.168.4.11"
    echo "  🥜 pecan   - IP: 192.168.4.12"
    echo "  🍑 peach   - IP: 192.168.4.13"
    echo ""
    echo "Example: $0 192.168.1.100 pumpkin"
    exit 1
fi

# Validate node name
case $NODE_NAME in
    "pumpkin"|"cherry"|"pecan"|"peach")
        ;;
    *)
        echo "❌ Invalid node name: $NODE_NAME"
        echo "Valid options: pumpkin, cherry, pecan, peach"
        exit 1
        ;;
esac

echo "🍒 Client Node Deployment - $NODE_NAME"
echo "======================================"
echo "Target Pi: $PI_IP"
echo "Node Name: $NODE_NAME"
echo "Deploying comprehensive client setup..."
echo ""

# Check if setup script exists
if [[ ! -f "setup-client-complete.sh" ]]; then
    echo "❌ setup-client-complete.sh not found!"
    exit 1
fi

# Deploy client node
echo "🚀 Deploying $NODE_NAME client node..."
echo "This will configure:"
echo "  ✅ Hostname: $NODE_NAME"
echo "  ✅ WiFi connection to Apple AP"
echo "  ✅ Static IP assignment"
echo "  ✅ Flask API server with GPIO control"
echo "  ✅ Sensor monitoring"
echo "  ✅ Heartbeat communication with AP"
echo "  ✅ Network monitoring and auto-reconnect"
echo ""

# Execute deployment with node name parameter
echo "📤 Uploading and executing setup script (one-time password prompt)..."

# Use sshpass if available, otherwise use expect-style approach
if command -v sshpass >/dev/null 2>&1; then
    # Use sshpass for password automation
    if echo "cat > /tmp/client-setup.sh && chmod +x /tmp/client-setup.sh && sudo /tmp/client-setup.sh $NODE_NAME; exit_code=\$?; rm -f /tmp/client-setup.sh; exit \$exit_code" | sshpass -p "001234" ssh -o StrictHostKeyChecking=no admin@$PI_IP; then
        deployment_success=true
    else
        deployment_success=false
    fi
else
    # Fall back to piped authentication
    {
        echo "001234"
        echo "001234" 
        echo "001234"
    } | ssh -o StrictHostKeyChecking=no admin@$PI_IP "cat > /tmp/client-setup.sh && chmod +x /tmp/client-setup.sh && sudo -S /tmp/client-setup.sh $NODE_NAME; exit_code=\$?; rm -f /tmp/client-setup.sh; exit \$exit_code" < /dev/stdin
    
    if [ $? -eq 0 ]; then
        deployment_success=true
    else
        deployment_success=false
    fi
fi

if $deployment_success; then
    
    # Map node names to IPs
    case $NODE_NAME in
        "pumpkin")
            NODE_IP="192.168.4.10"
            NODE_EMOJI="�"
            ;;
        "cherry")
            NODE_IP="192.168.4.11"
            NODE_EMOJI="🍒"
            ;;
        "pecan")
            NODE_IP="192.168.4.12"
            NODE_EMOJI="🥜"
            ;;
        "peach")
            NODE_IP="192.168.4.13"
            NODE_EMOJI="🍑"
            ;;
    esac
    
    echo ""
    echo "🎉 $NODE_EMOJI $NODE_NAME Client Node Deployment Complete!"
    echo ""
    echo "📊 Node Configuration:"
    echo "  🏷️  Hostname: $NODE_NAME"
    echo "  🌐 IP Address: $NODE_IP"
    echo "  📡 Connected to: Apple AP (192.168.4.1)"
    echo "  🔌 API Port: 5000"
    echo ""
    echo "🔧 API Endpoints:"
    echo "  📊 Status: http://$NODE_IP:5000/$NODE_NAME/api/v1/status"
    echo "  💡 LED Control: http://$NODE_IP:5000/$NODE_NAME/api/v1/actuators/led"
    echo "  📡 Sensors: http://$NODE_IP:5000/$NODE_NAME/api/v1/sensors"
    echo ""
    echo "🎯 Access from Apple Dashboard:"
    echo "  🍎 Main Dashboard: http://192.168.4.1/"
    echo "  🔧 Control $NODE_NAME remotely"
    echo "  📊 Monitor sensor data"
    echo ""
    echo "🔍 Quick Test Commands:"
    echo "  💡 Turn on LED: curl -X POST http://$NODE_IP:5000/$NODE_NAME/api/v1/actuators/led -d '{\"state\":\"on\"}' -H 'Content-Type: application/json'"
    echo "  📊 Check status: curl http://$NODE_IP:5000/$NODE_NAME/api/v1/status"
    echo ""
    
    # Verification
    echo "🔍 Quick Verification:"
    echo "Testing node connectivity..."
    
    # Give services a moment to start
    sleep 5
    
    if ssh admin@$PI_IP "ping -c 1 192.168.4.1 >/dev/null 2>&1; exit" 2>/dev/null; then
        echo "✅ Can reach Apple AP"
    else
        echo "⚠️  Apple AP connectivity test inconclusive"
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
    echo "  4. Verify Apple AP is running and accessible"
    echo "  5. Check Pi has internet connection for package downloads"
    exit 1
fi
