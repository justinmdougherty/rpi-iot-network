#!/bin/bash
# Official One-Click Deployment Script
# Based on official Raspberry Pi documentation and Context7 guidance
# Eliminates SSH password prompts and syntax errors

PI_IP="$1"
NODE_NAME="$2"
PASSWORD="001234"

if [[ -z "$PI_IP" || -z "$NODE_NAME" ]]; then
    echo "🍎 Official One-Click IoT Node Deployment"
    echo "========================================"
    echo "Usage: $0 <pi-ip-address> <node-name>"
    echo ""
    echo "Available node names:"
    echo "  🎃 pumpkin - Target IP: 192.168.4.10"
    echo "  🍒 cherry  - Target IP: 192.168.4.11"
    echo "  🥜 pecan   - Target IP: 192.168.4.12"
    echo "  🍑 peach   - Target IP: 192.168.4.13"
    echo ""
    echo "Example: $0 192.168.1.100 pumpkin"
    echo ""
    echo "Prerequisites:"
    echo "  1. Fresh Pi set up with setup-fresh-pi-official.sh"
    echo "  2. Pi connected to home WiFi and accessible"
    echo "  3. SSH enabled and admin user created"
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

echo "🍎 Official One-Click IoT Node Deployment"
echo "========================================"
echo "Target Pi: $PI_IP"
echo "Node Name: $NODE_NAME"
echo "Based on official Raspberry Pi documentation"
echo ""

# Check if setup script exists
if [[ ! -f "setup-client-complete.sh" ]]; then
    echo "❌ setup-client-complete.sh not found!"
    echo "This script is required for deployment"
    exit 1
fi

# Map node names to target IPs and emojis
case $NODE_NAME in
    "pumpkin") NODE_IP="192.168.4.10"; NODE_EMOJI="🎃" ;;
    "cherry") NODE_IP="192.168.4.11"; NODE_EMOJI="🍒" ;;
    "pecan") NODE_IP="192.168.4.12"; NODE_EMOJI="🥜" ;;
    "peach") NODE_IP="192.168.4.13"; NODE_EMOJI="🍑" ;;
esac

echo "🚀 Deploying $NODE_EMOJI $NODE_NAME client node..."
echo "📍 Target IoT IP: $NODE_IP"
echo ""

# Test SSH connectivity first
echo "🔗 Testing SSH connectivity..."
if ! timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes admin@$PI_IP "echo 'SSH test successful'" 2>/dev/null; then
    echo "❌ SSH connection failed or requires password"
    echo ""
    echo "🔧 SSH troubleshooting:"
    echo "   1. Verify Pi IP: ping $PI_IP"
    echo "   2. Check SSH service: telnet $PI_IP 22"
    echo "   3. Verify admin user exists on Pi"
    echo "   4. Set up SSH key: ssh-copy-id admin@$PI_IP"
    echo ""
    echo "💡 For password-based deployment, use sshpass:"
    echo "   sudo apt install sshpass"
    echo "   sshpass -p '$PASSWORD' ssh admin@$PI_IP"
    exit 1
fi

echo "✅ SSH connectivity verified"
echo ""

# Create temporary deployment directory
TEMP_DIR="/tmp/iot_deployment_$$"
echo "📦 Creating deployment package..."

# Upload setup script
echo "📤 Uploading client setup script..."
if ! scp -o StrictHostKeyChecking=no setup-client-complete.sh admin@$PI_IP:/tmp/client-setup.sh; then
    echo "❌ Failed to upload setup script"
    exit 1
fi

echo "✅ Setup script uploaded"

# Make script executable and run deployment
echo "⚙️ Executing deployment on $NODE_NAME..."

# Official deployment command - no here-docs to avoid syntax issues
DEPLOY_CMD="chmod +x /tmp/client-setup.sh && echo '$PASSWORD' | sudo -S /tmp/client-setup.sh $NODE_NAME"

if ssh -o StrictHostKeyChecking=no admin@$PI_IP "$DEPLOY_CMD"; then
    deployment_result=0
else
    deployment_result=$?
fi

# Clean up
echo "🧹 Cleaning up temporary files..."
ssh -o StrictHostKeyChecking=no admin@$PI_IP "rm -f /tmp/client-setup.sh" 2>/dev/null

# Report results
echo ""
if [ $deployment_result -eq 0 ]; then
    echo "🎉 $NODE_EMOJI $NODE_NAME Client Node Deployment Complete!"
    echo ""
    echo "📊 Configuration Summary:"
    echo "  🏷️  Hostname: $NODE_NAME"
    echo "  🌐 Current IP: $PI_IP (home WiFi)"
    echo "  🎯 Target IP: $NODE_IP (Apple IoT)"
    echo "  📡 Will connect to: Apple AP (192.168.4.1)"
    echo ""
    echo "⚠️  IMPORTANT: Pi will reboot to apply WiFi changes"
    echo "   📱 Connection may drop during WiFi reconfiguration"
    echo "   ⏱️  Wait 3-5 minutes for complete setup"
    echo ""
    echo "🔄 After reboot process:"
    echo "   1. Pi switches from home WiFi to Apple network"
    echo "   2. Gets new IP address: $NODE_IP"
    echo "   3. Starts IoT client services"
    echo ""
    echo "🧪 Testing when ready:"
    echo "   curl http://$NODE_IP:5000/$NODE_NAME/api/v1/status"
    echo "   curl http://$NODE_IP:5000/$NODE_NAME/api/v1/actuators/led"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Wait for Pi to complete reboot cycle"
    echo "   2. Connect your device to Apple WiFi network"
    echo "   3. Test node APIs at $NODE_IP"
    echo "   4. Deploy additional nodes if needed"
    
else
    echo "❌ Deployment encountered issues (exit code: $deployment_result)"
    echo ""
    echo "🔍 Common causes:"
    echo "   • Pi lost connection during WiFi reconfiguration (normal)"
    echo "   • Sudo password authentication failed"
    echo "   • NetworkManager conflicts"
    echo "   • Insufficient permissions"
    echo ""
    echo "🔧 Troubleshooting steps:"
    echo "   1. Wait 5 minutes for Pi to complete any reboots"
    echo "   2. Check if Pi appears on Apple WiFi at $NODE_IP"
    echo "   3. If not, SSH back to home IP and check logs:"
    echo "      ssh admin@$PI_IP 'journalctl -u NetworkManager -n 50'"
    echo "   4. Verify WiFi configuration:"
    echo "      ssh admin@$PI_IP 'nmcli connection show'"
    echo ""
    echo "🔄 To retry deployment:"
    echo "   $0 $PI_IP $NODE_NAME"
fi

echo ""
echo "📚 Official documentation used:"
echo "   • Raspberry Pi headless setup"
echo "   • NetworkManager WiFi configuration"
echo "   • SSH key-based authentication"
echo "   • Systemd service management"
echo ""
