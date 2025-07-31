#!/bin/bash
# Automated deployment with SSH key setup to avoid password prompts

PI_IP="192.168.86.62"
PI_USER="admin"
PI_PASS="001234"

echo "🍎 Apple Pie AP - Automated Deployment with SSH Key Setup"
echo "============================================================"

# Step 1: Set up SSH key authentication to avoid password prompts
echo "🔑 Setting up SSH key authentication..."

# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
fi

# Copy SSH key to Pi (this will be the last time we need the password)
echo "Copying SSH key to Pi (you'll need to enter password one last time)..."
sshpass -p "$PI_PASS" ssh-copy-id -o StrictHostKeyChecking=no "$PI_USER@$PI_IP"

if [ $? -eq 0 ]; then
    echo "✅ SSH key authentication set up successfully!"
    echo "🎉 No more password prompts needed!"
else
    echo "❌ SSH key setup failed. Falling back to password authentication..."
    USE_PASSWORD=true
fi

# Step 2: Upload and execute the fix script
echo ""
echo "📤 Uploading Apple Pie AP configuration script..."

if [ "$USE_PASSWORD" = true ]; then
    sshpass -p "$PI_PASS" scp fix-apple-pie-ap.sh "$PI_USER@$PI_IP:/home/admin/"
else
    scp fix-apple-pie-ap.sh "$PI_USER@$PI_IP:/home/admin/"
fi

echo "🚀 Executing Apple Pie AP configuration..."
echo "This will:"
echo "  - Fix WiFi blocking issues"
echo "  - Configure hidden 'Apple' WiFi network"
echo "  - Set up DHCP server (192.168.4.10-50)"
echo "  - Install Flask dashboard with UART control"
echo "  - Start all AP services"
echo ""

if [ "$USE_PASSWORD" = true ]; then
    sshpass -p "$PI_PASS" ssh "$PI_USER@$PI_IP" "chmod +x fix-apple-pie-ap.sh && sudo ./fix-apple-pie-ap.sh"
else
    ssh "$PI_USER@$PI_IP" "chmod +x fix-apple-pie-ap.sh && sudo ./fix-apple-pie-ap.sh"
fi

echo ""
echo "🎯 Deployment Complete!"
echo ""
echo "📱 Connect to Apple Pie AP:"
echo "  📶 Network: Apple (Hidden SSID)"
echo "  🔐 Password: Pharos12345"
echo "  🌐 Gateway: 192.168.4.1"
echo ""
echo "🖥️  Access Dashboard:"
echo "  🍎 Main: http://192.168.4.1:5000"
echo "  🔧 UART API: http://192.168.4.1:5000/api/v1/uart/"
echo ""
echo "🔧 Next Steps:"
echo "  1. Connect your device to 'Apple' WiFi network"
echo "  2. Open http://192.168.4.1:5000 in browser"
echo "  3. Connect UART devices for control"
echo "  4. Deploy other Pi nodes (Cherry, Pecan, Peach) as clients"
