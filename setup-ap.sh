#!/bin/bash
# Raspberry Pi Access Point Automated Setup Script
# Version: 1.0
# Usage: ./setup-ap.sh [ssid] [password]

set -e

# Configuration defaults
DEFAULT_SSID="RPiAP"
DEFAULT_PASSWORD="Pharos1234"
DEFAULT_CHANNEL="7"
DEFAULT_IP="192.168.4.1"
DEFAULT_DHCP_START="192.168.4.10"
DEFAULT_DHCP_END="192.168.4.50"

# Parse arguments
SSID=${1:-$DEFAULT_SSID}
PASSWORD=${2:-$DEFAULT_PASSWORD}

echo "=== Raspberry Pi Access Point Setup ==="
echo "SSID: $SSID"
echo "Starting automated setup..."

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        log "✓ $1 completed successfully"
    else
        log "✗ $1 failed"
        exit 1
    fi
}

# Step 1: System Update
log "Updating system packages..."
sudo apt update && sudo apt upgrade -y
check_status "System update"

# Step 2: Install AP software
log "Installing access point software..."
sudo apt install -y hostapd dnsmasq python3-flask python3-socketio python3-requests python3-gpiozero iptables-persistent
check_status "Package installation"

# Step 3: Configure hostapd
log "Configuring hostapd..."
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq

cat << EOF | sudo tee /etc/hostapd/hostapd.conf
interface=wlan0
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$DEFAULT_CHANNEL
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd
check_status "hostapd configuration"

# Step 4: Configure dnsmasq
log "Configuring DHCP server..."
sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup

cat << EOF | sudo tee -a /etc/dnsmasq.conf

# RPiAP Configuration
interface=wlan0
dhcp-range=$DEFAULT_DHCP_START,$DEFAULT_DHCP_END,255.255.255.0,24h
dhcp-option=3,$DEFAULT_IP
dhcp-option=6,$DEFAULT_IP

# Static IP reservations for known clients
dhcp-host=*:*:*:*:*:*,pi2,$DEFAULT_DHCP_START
EOF

check_status "dnsmasq configuration"

# Step 5: Configure network interface
log "Configuring network interface..."
sudo cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup

cat << EOF | sudo tee -a /etc/dhcpcd.conf

# RPiAP Static IP Configuration
interface wlan0
static ip_address=$DEFAULT_IP/24
nohook wpa_supplicant
EOF

check_status "Network interface configuration"

# Step 6: Enable IP forwarding
log "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf

# Configure iptables for NAT (if eth0 available)
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
sudo sh -c "iptables-save > /etc/iptables/rules.v4"
check_status "IP forwarding and NAT configuration"

# Step 7: Create dashboard project
log "Creating dashboard application..."
mkdir -p /home/admin/dashboard_project
cd /home/admin/dashboard_project

# Create basic dashboard app
cat > app.py << 'EOF'
#!/usr/bin/env python3
# Auto-generated dashboard application
from flask import Flask, render_template, request, jsonify
import requests
import datetime
import json

app = Flask(__name__)

# Store connected nodes and their data
connected_nodes = {}
sensor_data = {}

@app.route('/')
def dashboard():
    return render_template('dashboard.html', nodes=connected_nodes, data=sensor_data)

@app.route('/api/alert', methods=['POST'])
def receive_alert():
    try:
        data = request.get_json()
        node_id = data.get('pi', 'unknown')
        sensor_type = data.get('sensor', 'unknown')
        value = data.get('value', 0)
        timestamp = data.get('timestamp', datetime.datetime.now().isoformat())
        
        # Update node status
        connected_nodes[node_id] = {
            'last_seen': timestamp,
            'status': 'online'
        }
        
        # Store sensor data
        if node_id not in sensor_data:
            sensor_data[node_id] = {}
        if sensor_type not in sensor_data[node_id]:
            sensor_data[node_id][sensor_type] = []
        
        sensor_data[node_id][sensor_type].append({
            'value': value,
            'timestamp': timestamp
        })
        
        # Keep only last 50 readings
        sensor_data[node_id][sensor_type] = sensor_data[node_id][sensor_type][-50:]
        
        print(f"Received data from {node_id}: {sensor_type}={value}")
        return jsonify({'status': 'success'}), 200
        
    except Exception as e:
        print(f"Error processing alert: {e}")
        return jsonify({'error': str(e)}), 400

@app.route('/api/nodes', methods=['GET'])
def get_nodes():
    return jsonify(connected_nodes)

@app.route('/api/control/<node_id>/led', methods=['POST'])
def control_led(node_id):
    try:
        command = request.get_json()
        node_ip = f"192.168.4.{10 + int(node_id.replace('pi', '')) - 2}"
        
        response = requests.post(
            f"http://{node_ip}:5000/api/v1/actuators/led",
            json=command,
            timeout=5
        )
        
        return jsonify(response.json()), response.status_code
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80, debug=False)
EOF

# Create basic dashboard template
mkdir -p templates
cat > templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>RPiAP Dashboard</title>
    <meta http-equiv="refresh" content="10">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .node { border: 1px solid #ccc; margin: 10px; padding: 15px; border-radius: 5px; }
        .online { border-color: green; }
        .offline { border-color: red; }
        button { padding: 10px; margin: 5px; }
        .sensor-data { margin-top: 10px; }
    </style>
</head>
<body>
    <h1>Raspberry Pi Network Dashboard</h1>
    <div id="nodes">
        {% for node_id, node_info in nodes.items() %}
        <div class="node {{ node_info.status }}">
            <h3>{{ node_id }}</h3>
            <p>Status: {{ node_info.status }}</p>
            <p>Last seen: {{ node_info.last_seen }}</p>
            <button onclick="controlLED('{{ node_id }}', 'on')">LED ON</button>
            <button onclick="controlLED('{{ node_id }}', 'off')">LED OFF</button>
            
            {% if node_id in data %}
            <div class="sensor-data">
                {% for sensor, readings in data[node_id].items() %}
                <h4>{{ sensor }}</h4>
                <p>Latest: {{ readings[-1].value if readings else 'No data' }}</p>
                {% endfor %}
            </div>
            {% endif %}
        </div>
        {% endfor %}
    </div>
    
    <script>
        function controlLED(nodeId, state) {
            fetch(`/api/control/${nodeId}/led`, {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({state: state, brightness: 100})
            })
            .then(response => response.json())
            .then(data => console.log(data))
            .catch(error => console.error('Error:', error));
        }
    </script>
</body>
</html>
EOF

chmod +x app.py
check_status "Dashboard application creation"

# Step 8: Create dashboard service
log "Creating dashboard service..."
cat > dashboard.service << EOF
[Unit]
Description=Dashboard Web Server for Pi Control
After=network.target

[Service]
User=root
WorkingDirectory=/home/admin/dashboard_project
ExecStart=/usr/bin/python3 /home/admin/dashboard_project/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo cp dashboard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable dashboard.service
check_status "Dashboard service creation"

# Step 9: Enable services
log "Enabling services..."
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl enable dashboard.service
check_status "Service enablement"

log "=== Setup Complete ==="
echo ""
echo "Access Point '$SSID' has been configured!"
echo ""
echo "Network Configuration:"
echo "  - SSID: $SSID"
echo "  - Password: $PASSWORD"
echo "  - AP IP: $DEFAULT_IP"
echo "  - DHCP Range: $DEFAULT_DHCP_START - $DEFAULT_DHCP_END"
echo ""
echo "Services will start after reboot."
echo ""
echo "Next Steps:"
echo "  1. Reboot the system: sudo reboot"
echo "  2. Connect devices to '$SSID' network"
echo "  3. Access dashboard at: http://$DEFAULT_IP"
echo ""
echo "IMPORTANT: System will reboot in 10 seconds to apply changes..."
sleep 10
sudo reboot
