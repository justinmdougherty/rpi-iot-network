#!/bin/bash
# One-Click Client Deployment with embedded credentials

PI_IP="$1"
NODE_NAME="$2"
PASSWORD="001234"

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

echo "🍒 ONE-CLICK Client Deployment - $NODE_NAME"
echo "============================================="
echo "Target Pi: $PI_IP"
echo "Node Name: $NODE_NAME"
echo "🔐 Using embedded credentials (no prompts)"
echo ""

# Check if setup script exists
if [[ ! -f "setup-client-complete.sh" ]]; then
    echo "❌ setup-client-complete.sh not found!"
    exit 1
fi

echo "🚀 Deploying $NODE_NAME client node..."
echo ""

# Create a temporary script that handles the deployment
TEMP_SCRIPT="/tmp/one_click_deploy_$$"
cat > "$TEMP_SCRIPT" << 'SCRIPT_END'
#!/bin/bash
PI_IP="$1"
NODE_NAME="$2"
PASSWORD="$3"

# Function to execute SSH commands with password
ssh_with_pass() {
    local cmd="$1"
    expect -c "
        set timeout 60
        spawn ssh -o StrictHostKeyChecking=no admin@$PI_IP \"$cmd\"
        expect {
            \"password:\" { send \"$PASSWORD\r\"; exp_continue }
            \"Password:\" { send \"$PASSWORD\r\"; exp_continue }
            eof
        }
    "
}

# Upload and execute the setup script
echo "📤 Uploading setup script..."
cat setup-client-complete.sh | ssh_with_pass "cat > /tmp/client-setup.sh && chmod +x /tmp/client-setup.sh"

echo "⚙️ Executing setup script..."
ssh_with_pass "echo '$PASSWORD' | sudo -S /tmp/client-setup.sh $NODE_NAME && rm -f /tmp/client-setup.sh"

SCRIPT_END

chmod +x "$TEMP_SCRIPT"

# Check if expect is available
if ! command -v expect >/dev/null 2>&1; then
    echo "⚠️  expect not found, trying alternative method..."
    
    # Alternative: use here-doc with SSH
    echo "📤 Uploading and executing (alternative method)..."
    
    # Upload script first, then execute
    cat setup-client-complete.sh | ssh -o StrictHostKeyChecking=no admin@$PI_IP "cat > /tmp/client-setup.sh && chmod +x /tmp/client-setup.sh"
    
    # Execute with password
    ssh -o StrictHostKeyChecking=no admin@$PI_IP "echo '$PASSWORD' | sudo -S /tmp/client-setup.sh $NODE_NAME && rm -f /tmp/client-setup.sh"
    
    deployment_result=$?
else
    # Use expect-based deployment
    echo "📤 Using expect for automated deployment..."
    "$TEMP_SCRIPT" "$PI_IP" "$NODE_NAME" "$PASSWORD"
    deployment_result=$?
fi

# Clean up
rm -f "$TEMP_SCRIPT"

if [ $deployment_result -eq 0 ]; then
    # Map node names to IPs
    case $NODE_NAME in
        "pumpkin") NODE_IP="192.168.4.10"; NODE_EMOJI="🎃" ;;
        "cherry") NODE_IP="192.168.4.11"; NODE_EMOJI="🍒" ;;
        "pecan") NODE_IP="192.168.4.12"; NODE_EMOJI="🥜" ;;
        "peach") NODE_IP="192.168.4.13"; NODE_EMOJI="🍑" ;;
    esac
    
    echo ""
    echo "🎉 $NODE_EMOJI $NODE_NAME Client Node Deployment Complete!"
    echo ""
    echo "📊 Configuration:"
    echo "  🏷️  Hostname: $NODE_NAME"
    echo "  🌐 Target IP: $NODE_IP"
    echo "  📡 Connects to: Apple AP (192.168.4.1)"
    echo ""
    echo "⚠️  IMPORTANT: Pi may reboot during WiFi configuration"
    echo "   Wait 2-3 minutes, then connect to Apple WiFi to test"
    echo ""
    echo "🔍 Test when ready:"
    echo "   curl http://$NODE_IP:5000/$NODE_NAME/api/v1/status"
    
else
    echo ""
    echo "❌ Deployment failed or connection dropped during WiFi setup"
    echo "This might be normal if Pi is switching to WiFi"
    echo ""
    echo "🔧 Next steps:"
    echo "  1. Wait 2-3 minutes for Pi to complete setup"
    echo "  2. Connect to Apple WiFi network"
    echo "  3. Test node at IP $NODE_IP"
    echo "  4. If still not working, check Pi directly"
fi
