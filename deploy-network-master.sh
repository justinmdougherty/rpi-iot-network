#!/becho "🍎 Apple I# Configuration
declare -A NODES
NODES[apple]=""
NODE# Deployment functions
deploy_apple() {
    local ip="$1"
    echo ""
    echo "🍎 Deploying Applecho "📱 Node Access Points:"
if [[ -n "${NODES[apple]}" ]]; then
    echo "  🍎 Apple AP: http://192.168.4.1/"
fi
if [[ -n "${NODES[pumpkin]}" ]]; then
    echo "  🎃 Pumpkin API: http://192.168.4.10:5000/pumpkin/api/v1/status"
fi
if [[ -n "${NODES[cherry]}" ]]; then
    echo "  🍒 Cherry API: http://192.168.4.11:5000/cherry/api/v1/status"
fi
if [[ -n "${NODES[pecan]}" ]]; then
    echo "  🥜 Pecan API: http://192.168.4.12:5000/pecan/api/v1/status"
fi
if [[ -n "${NODES[peach]}" ]]; then
    echo "  🍑 Peach API: http://192.168.4.13:5000/peach/api/v1/status"
fio $ip..."
    echo "============================================="
    
    if ./deploy-apple-pie-auto.sh "$ip"; then
        echo "✅ Apple AP deployment successful!"
        return 0
    else
        echo "❌ Apple AP deployment failed!"
        return 1
    fi
}ODES[cherry]=""
NODES[pecan]=""
NODES[peach]=""

# Interactive configuration
echo "📝 Node IP Configuration:"
echo "Enter the current IP addresses for each Pi (leave blank to skip)"
echo ""

read -p "🍎 Apple AP IP address: " NODES[apple]
read -p "🎃 Pumpkin client IP address: " NODES[pumpkin]
read -p "🍒 Cherry client IP address: " NODES[cherry]
read -p "🥜 Pecan client IP address: " NODES[pecan]
read -p "🍑 Peach client IP address: " NODES[peach]r Deployment"
echo "==========================================="
echo "This script will deploy the complete IoT network:"
echo "  🍎 Apple - Access Point (192.168.4.1)"
echo "  🎃 Pumpkin - Client Node (192.168.4.10)"
echo "  🍒 Cherry - Client Node (192.168.4.11)"
echo "  🥜 Pecan - Client Node (192.168.4.12)"
echo "  🍑 Peach - Client Node (192.168.4.13)"# Master IoT Network Deployment Script
# Deploys complete Apple Pie IoT network with all nodes

echo "� Pumpkin IoT Network - Master Deployment"
echo "==========================================="
echo "This script will deploy the complete IoT network:"
echo "  � Pumpkin - Access Point (192.168.4.1)"
echo "  🍒 Cherry - Client Node (192.168.4.10)"
echo "  🥜 Pecan - Client Node (192.168.4.11)"
echo "  🍎 Apple - Client Node (192.168.4.12)"
echo "  🍑 Peach - Client Node (192.168.4.13)"
echo ""

# Configuration
declare -A NODES
NODES[pumpkin]=""
NODES[cherry]=""
NODES[pecan]=""
NODES[apple]=""
NODES[peach]=""

# Interactive configuration
echo "📝 Node IP Configuration:"
echo "Enter the current IP addresses for each Pi (leave blank to skip)"
echo ""

read -p "� Pumpkin AP IP address: " NODES[pumpkin]
read -p "🍒 Cherry client IP address: " NODES[cherry]
read -p "🥜 Pecan client IP address: " NODES[pecan]
read -p "🍎 Apple client IP address: " NODES[apple]
read -p "🍑 Peach client IP address: " NODES[peach]

echo ""
echo "📋 Deployment Plan:"
for node in "${!NODES[@]}"; do
    if [[ -n "${NODES[$node]}" ]]; then
        echo "✅ $node: ${NODES[$node]}"
    else
        echo "⏭️  $node: Skipped"
    fi
done

echo ""
read -p "Proceed with deployment? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Deployment functions
deploy_pumpkin() {
    local ip="$1"
    echo ""
    echo "� Deploying Pumpkin Access Point to $ip..."
    echo "============================================="
    
    if ./deploy-apple-pie-auto.sh "$ip"; then
        echo "✅ Pumpkin AP deployment successful!"
        return 0
    else
        echo "❌ Pumpkin AP deployment failed!"
        return 1
    fi
}

deploy_client() {
    local ip="$1"
    local name="$2"
    echo ""
    echo "🍒 Deploying $name client node to $ip..."
    echo "========================================="
    
    if ./deploy-client-auto.sh "$ip" "$name"; then
        echo "✅ $name client deployment successful!"
        return 0
    else
        echo "❌ $name client deployment failed!"
        return 1
    fi
}

# Start deployments
echo ""
echo "🚀 Starting Network Deployment..."
echo "=================================="

deployment_success=true

# Deploy Apple AP first (required for clients)
if [[ -n "${NODES[apple]}" ]]; then
    if ! deploy_apple "${NODES[apple]}"; then
        deployment_success=false
        echo "⚠️  Apple AP deployment failed - clients may not connect properly"
    else
        echo ""
        echo "⏳ Waiting 30 seconds for Apple AP to stabilize..."
        sleep 30
    fi
fi

# Deploy client nodes
for node in pumpkin cherry pecan peach; do
    if [[ -n "${NODES[$node]}" ]]; then
        if ! deploy_client "${NODES[$node]}" "$node"; then
            deployment_success=false
            echo "⚠️  $node deployment failed"
        fi
        
        # Brief pause between client deployments
        echo ""
        echo "⏳ Waiting 10 seconds before next deployment..."
        sleep 10
    fi
done

# Final status report
echo ""
echo "📊 Deployment Summary"
echo "===================="

if $deployment_success; then
    echo "🎉 All deployments completed successfully!"
else
    echo "⚠️  Some deployments had issues - check logs above"
fi

echo ""
echo "🌐 Network Access Information:"
echo "  📶 WiFi Network: Apple (Hidden)"
echo "  🔐 Password: Pharos12345"
echo "  🍎 Main Dashboard: http://192.168.4.1/"
echo ""

echo "📱 Node Access Points:"
if [[ -n "${NODES[pumpkin]}" ]]; then
    echo "  � Pumpkin AP: http://192.168.4.1/"
fi
if [[ -n "${NODES[cherry]}" ]]; then
    echo "  🍒 Cherry API: http://192.168.4.10:5000/cherry/api/v1/status"
fi
if [[ -n "${NODES[pecan]}" ]]; then
    echo "  🥜 Pecan API: http://192.168.4.11:5000/pecan/api/v1/status"
fi
if [[ -n "${NODES[apple]}" ]]; then
    echo "  🍎 Apple API: http://192.168.4.12:5000/apple/api/v1/status"
fi
if [[ -n "${NODES[peach]}" ]]; then
    echo "  🍑 Peach API: http://192.168.4.13:5000/peach/api/v1/status"
fi

echo ""
echo "🔧 Next Steps:"
echo "1. Connect to 'Apple' WiFi network with password 'Pharos12345'"
echo "2. Open http://192.168.4.1/ to access the main dashboard"
echo "3. Test UART device connections on Apple Pie AP"
echo "4. Test client node LED controls and sensor readings"
echo "5. Monitor network health and node communications"

echo ""
echo "📚 Quick Test Commands:"
echo "# Test Apple AP"
echo "curl http://192.168.4.1/api/v1/status"
echo ""
echo "# Test client nodes (after connecting to Apple network)"
if [[ -n "${NODES[pumpkin]}" ]]; then
    echo "curl http://192.168.4.10:5000/pumpkin/api/v1/status"
    echo "curl -X POST http://192.168.4.10:5000/pumpkin/api/v1/actuators/led -d '{\"state\":\"on\"}' -H 'Content-Type: application/json'"
fi
if [[ -n "${NODES[cherry]}" ]]; then
    echo "curl http://192.168.4.11:5000/cherry/api/v1/status"
    echo "curl -X POST http://192.168.4.11:5000/cherry/api/v1/actuators/led -d '{\"state\":\"on\"}' -H 'Content-Type: application/json'"
fi

echo ""
if $deployment_success; then
    echo "🎊 Apple IoT Network deployment complete!"
    exit 0
else
    echo "⚠️  Deployment completed with some issues. Check individual node logs."
    exit 1
fi
