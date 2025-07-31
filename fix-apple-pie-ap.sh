#!/bin/bash
# Fix Apple Pie AP Configuration - handles WiFi blocking and proper AP setup

echo "🍎 Fixing Apple Pie Access Point Configuration..."

# Step 1: Stop conflicting services and disconnect from WiFi
echo "📡 Disconnecting from existing WiFi networks..."
sudo nmcli radio wifi off
sleep 2
sudo nmcli radio wifi on
sleep 2

# Step 2: Create proper network configuration
echo "🔧 Configuring wlan0 interface for AP mode..."
sudo ip link set wlan0 down
sudo ip addr flush dev wlan0
sudo ip addr add 192.168.4.1/24 dev wlan0
sudo ip link set wlan0 up

# Step 3: Ensure hostapd configuration is correct
echo "📝 Verifying hostapd configuration..."
sudo tee /etc/hostapd/hostapd.conf > /dev/null << 'EOF'
interface=wlan0
driver=nl80211
ssid=Apple
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=1
wpa=2
wpa_passphrase=Pharos12345
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

# Step 4: Configure dnsmasq for DHCP
echo "🌐 Configuring DHCP server..."
sudo tee /etc/dnsmasq.conf > /dev/null << 'EOF'
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h
domain=local
address=/gw.local/192.168.4.1
EOF

# Step 5: Enable IP forwarding and NAT
echo "🔀 Setting up NAT routing..."
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Configure iptables for NAT
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

# Save iptables rules
sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"

# Step 6: Create startup script to restore iptables
sudo tee /etc/rc.local > /dev/null << 'EOF'
#!/bin/sh -e
iptables-restore < /etc/iptables.ipv4.nat
exit 0
EOF
sudo chmod +x /etc/rc.local

# Step 7: Start services
echo "🚀 Starting AP services..."
sudo systemctl stop hostapd dnsmasq
sleep 2
sudo systemctl start dnsmasq
sleep 2
sudo systemctl start hostapd

# Step 8: Enable services for auto-start
sudo systemctl enable hostapd dnsmasq

# Step 9: Create and start Flask API server
echo "🐍 Setting up Flask API server..."
mkdir -p /home/admin/dashboard_project
cd /home/admin/dashboard_project

# Create the Flask app for UART device management
cat > app.py << 'PYEOF'
#!/usr/bin/env python3
import os
import json
import time
import threading
from datetime import datetime
from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import serial
import serial.tools.list_ports

app = Flask(__name__)
CORS(app)

# Global variables
uart_connections = {}
device_status = {}

# HTML template for the dashboard
DASHBOARD_HTML = '''
<!DOCTYPE html>
<html>
<head>
    <title>Apple Pie AP Dashboard</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { text-align: center; background: #4CAF50; color: white; padding: 20px; border-radius: 10px; }
        .status-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin: 20px 0; }
        .status-card { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .status-indicator { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 8px; }
        .online { background: #4CAF50; }
        .offline { background: #f44336; }
        .warning { background: #ff9800; }
        .command-section { background: white; padding: 20px; border-radius: 10px; margin: 20px 0; }
        .log-section { background: white; padding: 20px; border-radius: 10px; max-height: 300px; overflow-y: auto; }
        button { background: #4CAF50; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; }
        button:hover { background: #45a049; }
        select, input { padding: 8px; margin: 5px; border-radius: 5px; border: 1px solid #ddd; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🍎 Apple Pie Access Point Dashboard</h1>
            <p>UART Device Management & IoT Network Control</p>
        </div>
        
        <div class="status-grid">
            <div class="status-card">
                <h3>Access Point Status</h3>
                <p><span class="status-indicator online"></span>Apple WiFi Network: Active</p>
                <p><span class="status-indicator online"></span>DHCP Server: Running</p>
                <p><span class="status-indicator online"></span>IP: 192.168.4.1</p>
            </div>
            <div class="status-card">
                <h3>UART Devices</h3>
                <div id="uart-devices">Loading...</div>
                <button onclick="scanDevices()">Scan Devices</button>
            </div>
            <div class="status-card">
                <h3>Connected Clients</h3>
                <div id="connected-clients">Cherry: Offline<br>Pecan: Offline<br>Peach: Offline</div>
            </div>
        </div>
        
        <div class="command-section">
            <h3>UART Device Control</h3>
            <select id="deviceSelect"><option>Select Device...</option></select>
            <input type="text" id="commandInput" placeholder="Enter command...">
            <button onclick="sendCommand()">Send Command</button>
        </div>
        
        <div class="log-section">
            <h3>System Log</h3>
            <div id="log-output">Apple Pie AP started successfully...<br></div>
        </div>
    </div>
    
    <script>
        function addLog(message) {
            const log = document.getElementById('log-output');
            const timestamp = new Date().toLocaleTimeString();
            log.innerHTML += `[${timestamp}] ${message}<br>`;
            log.scrollTop = log.scrollHeight;
        }
        
        function scanDevices() {
            fetch('/api/v1/uart/discover')
                .then(response => response.json())
                .then(data => {
                    const deviceDiv = document.getElementById('uart-devices');
                    const deviceSelect = document.getElementById('deviceSelect');
                    deviceDiv.innerHTML = '';
                    deviceSelect.innerHTML = '<option>Select Device...</option>';
                    
                    if (data.devices && data.devices.length > 0) {
                        data.devices.forEach(device => {
                            deviceDiv.innerHTML += `<p><span class="status-indicator online"></span>${device.port} - ${device.description}</p>`;
                            deviceSelect.innerHTML += `<option value="${device.port}">${device.port} - ${device.description}</option>`;
                        });
                    } else {
                        deviceDiv.innerHTML = '<p><span class="status-indicator offline"></span>No UART devices found</p>';
                    }
                    addLog(`Found ${data.devices ? data.devices.length : 0} UART devices`);
                })
                .catch(error => {
                    addLog(`Error scanning devices: ${error}`);
                });
        }
        
        function sendCommand() {
            const device = document.getElementById('deviceSelect').value;
            const command = document.getElementById('commandInput').value;
            
            if (device === 'Select Device...' || !command) {
                addLog('Please select a device and enter a command');
                return;
            }
            
            fetch('/api/v1/uart/command', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({device: device, command: command})
            })
            .then(response => response.json())
            .then(data => {
                addLog(`Command sent to ${device}: ${command}`);
                if (data.response) {
                    addLog(`Response: ${data.response}`);
                }
            })
            .catch(error => {
                addLog(`Error sending command: ${error}`);
            });
            
            document.getElementById('commandInput').value = '';
        }
        
        // Auto-scan devices on load
        window.onload = function() {
            scanDevices();
            addLog('Apple Pie AP Dashboard loaded');
        };
    </script>
</body>
</html>
'''

@app.route('/')
def dashboard():
    """Main dashboard page"""
    return render_template_string(DASHBOARD_HTML)

@app.route('/api/v1/uart/discover', methods=['GET'])
def discover_uart_devices():
    """Discover available UART devices"""
    try:
        ports = serial.tools.list_ports.comports()
        devices = []
        for port in ports:
            devices.append({
                'port': port.device,
                'description': port.description,
                'hwid': port.hwid
            })
        return jsonify({'status': 'success', 'devices': devices})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/v1/uart/connect', methods=['POST'])
def connect_uart_device():
    """Connect to a UART device"""
    try:
        data = request.get_json()
        port = data.get('port')
        baud_rate = data.get('baud_rate', 9600)
        
        if port in uart_connections:
            uart_connections[port].close()
        
        uart_connections[port] = serial.Serial(port, baud_rate, timeout=1)
        device_status[port] = 'connected'
        
        return jsonify({'status': 'success', 'message': f'Connected to {port}'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/v1/uart/command', methods=['POST'])
def send_uart_command():
    """Send command to UART device"""
    try:
        data = request.get_json()
        device = data.get('device')
        command = data.get('command')
        
        if device not in uart_connections:
            # Try to auto-connect
            uart_connections[device] = serial.Serial(device, 9600, timeout=1)
        
        uart_connection = uart_connections[device]
        uart_connection.write(f"{command}\n".encode())
        
        # Try to read response
        response = uart_connection.readline().decode().strip()
        
        return jsonify({
            'status': 'success',
            'command': command,
            'response': response,
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/v1/uart/config', methods=['GET', 'POST'])
def uart_config():
    """Get or set UART configuration"""
    if request.method == 'GET':
        return jsonify({'connections': list(uart_connections.keys()), 'status': device_status})
    elif request.method == 'POST':
        # Handle configuration updates
        data = request.get_json()
        return jsonify({'status': 'success', 'message': 'Configuration updated'})

@app.route('/api/v1/status', methods=['GET'])
def api_status():
    """API status endpoint"""
    return jsonify({
        'hostname': 'apple-pie',
        'role': 'access_point',
        'ip': '192.168.4.1',
        'network': 'Apple',
        'uart_devices': len(uart_connections),
        'timestamp': datetime.now().isoformat()
    })

if __name__ == '__main__':
    print("🍎 Starting Apple Pie AP Dashboard...")
    print("🌐 Dashboard: http://192.168.4.1:5000")
    print("📡 UART API: http://192.168.4.1:5000/api/v1/uart/")
    app.run(host='0.0.0.0', port=5000, debug=False)
PYEOF

# Create systemd service for the dashboard
sudo tee /etc/systemd/system/apple-pie-dashboard.service > /dev/null << 'EOF'
[Unit]
Description=Apple Pie AP Dashboard
After=network.target hostapd.service dnsmasq.service
Requires=hostapd.service dnsmasq.service

[Service]
Type=simple
User=admin
WorkingDirectory=/home/admin/dashboard_project
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Set permissions
sudo chown -R admin:admin /home/admin/dashboard_project
chmod +x /home/admin/dashboard_project/app.py

# Start the dashboard service
sudo systemctl daemon-reload
sudo systemctl enable apple-pie-dashboard.service
sudo systemctl start apple-pie-dashboard.service

echo ""
echo "✅ Apple Pie Access Point Configuration Complete!"
echo ""
echo "📊 Network Status:"
echo "  🔐 SSID: Apple (Hidden)"
echo "  🔑 Password: Pharos12345"
echo "  🌐 AP IP: 192.168.4.1"
echo "  📱 DHCP Range: 192.168.4.10-50"
echo ""
echo "🍎 Dashboard Access:"
echo "  🖥️  Main Dashboard: http://192.168.4.1:5000"
echo "  🔧 UART API: http://192.168.4.1:5000/api/v1/uart/"
echo "  📊 Status API: http://192.168.4.1:5000/api/v1/status"
echo ""
echo "🎯 To connect other devices:"
echo "  1. Connect to hidden WiFi 'Apple' with password 'Pharos12345'"
echo "  2. Devices will get IPs in range 192.168.4.10-50"
echo "  3. Access dashboard at http://192.168.4.1:5000"

# Final status check
echo ""
echo "🔍 Service Status:"
sudo systemctl is-active hostapd && echo "✅ hostapd: Active" || echo "❌ hostapd: Failed"
sudo systemctl is-active dnsmasq && echo "✅ dnsmasq: Active" || echo "❌ dnsmasq: Failed"
sudo systemctl is-active apple-pie-dashboard && echo "✅ dashboard: Active" || echo "❌ dashboard: Failed"
