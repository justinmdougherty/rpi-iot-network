#!/bin/bash
# Completely Automated Client Node Deployment - NO PASSWORD PROMPTS

PI_IP="$1"
NODE_NAME="$2"

if [[ -z "$PI_IP" || -z "$NODE_NAME" ]]; then
    echo "Usage: $0 <pi-ip-address> <node-name>"
    echo ""
    echo "Available node names:"
    echo "  🎃 pumpkin - IP: 192.168.4.10"
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

echo "🍒 Client Node Deployment - $NODE_NAME (AUTOMATED)"
echo "=================================================="
echo "Target Pi: $PI_IP"
echo "Node Name: $NODE_NAME"
echo "🔐 Using automated authentication"
echo ""

# Check if setup script exists
if [[ ! -f "setup-client-complete.sh" ]]; then
    echo "❌ setup-client-complete.sh not found!"
    exit 1
fi

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

# Create temporary expect script for automation
cat > /tmp/deploy_expect.sh << 'EOF'
#!/bin/bash
PI_IP="$1"
NODE_NAME="$2"

# Upload script and execute with embedded password
cat setup-client-complete.sh | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR admin@$PI_IP "
# Provide password for sudo
echo '001234' | sudo -S bash -c '
    cat > /tmp/client-setup.sh
    chmod +x /tmp/client-setup.sh
    /tmp/client-setup.sh $NODE_NAME
    exit_code=\$?
    rm -f /tmp/client-setup.sh
    exit \$exit_code
'
"
EOF

chmod +x /tmp/deploy_expect.sh

# Execute the deployment
echo "📤 Executing automated deployment..."
if bash -c "echo '001234' | /tmp/deploy_expect.sh $PI_IP $NODE_NAME"; then
    deployment_success=true
else
    deployment_success=false
fi

# Clean up
rm -f /tmp/deploy_expect.sh

if $deployment_success; then
    # Map node names to IPs
    case $NODE_NAME in
        "pumpkin")
            NODE_IP="192.168.4.10"
            NODE_EMOJI="🎃"
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
    
    # Note about connection drop
    echo "⚠️  NOTE: SSH connection may drop when Pi switches to WiFi"
    echo "   This is NORMAL behavior. Wait 2-3 minutes for setup to complete."
    echo "   Then connect to Apple WiFi and test the node."
    
else
    echo ""
    echo "❌ Deployment Failed!"
    echo "Check the error messages above for details."
    echo ""
    echo "🔧 Troubleshooting:"
    echo "  1. Verify Pi is accessible: ping $PI_IP"
    echo "  2. Check SSH access works manually"
    echo "  3. Ensure credentials are admin/001234"
    echo "  4. Verify Apple AP is running and accessible"
    echo "  5. Check Pi has internet connection for package downloads"
    exit 1
fi
