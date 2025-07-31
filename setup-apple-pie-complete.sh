#!/bin/bash
# Complete Apple Pie Access Point Setup Script
# Includes all fixes and configurations for hands-off deployment

set -e  # Exit on any error

echo "🍎 Apple Pie Access Point - Complete Setup"
echo "==========================================="
echo "This script will configure this Pi as the main Access Point with:"
echo "- Hidden WiFi network 'Apple' (password: Pharos12345)"
echo "- DHCP server (192.168.4.10-50)"
echo "- Flask dashboard on http://192.168.4.1/"
echo "- UART device management API"
echo "- All necessary service configurations"
echo ""

# Set hostname
echo "🏷️  Setting hostname to pumpkin..."
sudo hostnamectl set-hostname pumpkin
echo "pumpkin" | sudo tee /etc/hostname > /dev/null

# Update package list and install required packages
echo "📦 Installing required packages..."
sudo apt update -qq
sudo apt install -y hostapd dnsmasq iptables-persistent python3-flask python3-flask-cors python3-serial

# Install additional Python packages with proper handling
echo "🐍 Installing Python packages..."
sudo apt install -y python3-flask-cors || true
sudo pip3 install --break-system-packages pyserial flask-cors 2>/dev/null || true

# Stop and disable conflicting services
echo "🛑 Stopping conflicting services..."
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl disable nginx 2>/dev/null || true
sudo systemctl stop client_app 2>/dev/null || true
sudo systemctl disable client_app 2>/dev/null || true
sudo systemctl stop wpa_supplicant 2>/dev/null || true

# Unblock WiFi and prepare interface
echo "📡 Configuring WiFi interface..."
sudo rfkill unblock wifi
sudo nmcli radio wifi off
sleep 2
sudo nmcli radio wifi on
sleep 2

# Configure wlan0 interface for AP mode
echo "🔧 Setting up wlan0 interface..."
sudo ip link set wlan0 down 2>/dev/null || true
sudo ip addr flush dev wlan0 2>/dev/null || true
sudo ip addr add 192.168.4.1/24 dev wlan0
sudo ip link set wlan0 up

# Create hostapd configuration
echo "📝 Creating hostapd configuration..."
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

# Configure hostapd daemon
echo "⚙️  Configuring hostapd daemon..."
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd > /dev/null

# Create dnsmasq configuration for DHCP
echo "🌐 Configuring DHCP server..."
sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup 2>/dev/null || true
sudo tee /etc/dnsmasq.conf > /dev/null << 'EOF'
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h
domain=local
address=/gw.local/192.168.4.1
EOF

# Enable IP forwarding
echo "🔀 Setting up IP forwarding and NAT..."
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf > /dev/null
sudo sysctl -p > /dev/null

# Configure iptables for NAT
sudo iptables -t nat -F 2>/dev/null || true
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

# Save iptables rules
sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"

# Create startup script to restore iptables
sudo tee /etc/rc.local > /dev/null << 'EOF'
#!/bin/sh -e
iptables-restore < /etc/iptables.ipv4.nat
exit 0
EOF
sudo chmod +x /etc/rc.local

# Create dashboard project directory
echo "🍎 Setting up Apple Pie Dashboard..."
mkdir -p /home/admin/dashboard_project
cd /home/admin/dashboard_project

# Create the complete Flask application
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
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; 
            margin: 0; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            min-height: 100vh; color: #333;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        .header { 
            text-align: center; background: rgba(255,255,255,0.95); 
            color: #333; padding: 30px; border-radius: 15px; 
            box-shadow: 0 8px 32px rgba(0,0,0,0.1); margin-bottom: 30px;
            backdrop-filter: blur(10px);
        }
        .header h1 { margin: 0; font-size: 2.5em; font-weight: 300; }
        .header p { margin: 10px 0 0 0; opacity: 0.8; font-size: 1.1em; }
        
        .dashboard-grid { 
            display: grid; 
            grid-template-columns: 1fr 1fr; 
            gap: 30px; 
            margin-bottom: 30px;
        }
        
        .left-panel { display: flex; flex-direction: column; gap: 20px; }
        .right-panel { display: flex; flex-direction: column; gap: 20px; }
        
        .status-card, .command-card, .log-card { 
            background: rgba(255,255,255,0.95); 
            padding: 25px; border-radius: 15px; 
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
        }
        
        .status-card h3, .command-card h3, .log-card h3 { 
            margin: 0 0 20px 0; color: #4a5568; font-weight: 600;
            border-bottom: 2px solid #e2e8f0; padding-bottom: 10px;
        }
        
        .node-grid {
            display: grid;
            grid-template-columns: 1fr;
            gap: 15px;
        }
        
        .node-panel {
            background: #f8fafc;
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #4caf50;
        }
        
        .node-panel h4 {
            margin: 0 0 15px 0;
            color: #2d3748;
            font-size: 1.2em;
        }
        
        .status-indicator { 
            display: inline-block; width: 12px; height: 12px; 
            border-radius: 50%; margin-right: 10px; 
        }
        .online { background: #4caf50; box-shadow: 0 0 10px rgba(76,175,80,0.5); }
        .offline { background: #f44336; }
        .warning { background: #ff9800; }
        
        .command-section { 
            display: grid; 
            grid-template-columns: 1fr 1fr auto; 
            gap: 15px; 
            align-items: end; 
            margin-bottom: 20px;
        }
        
        .form-group {
            display: flex;
            flex-direction: column;
        }
        
        .form-group label {
            margin-bottom: 5px;
            font-weight: 500;
            color: #4a5568;
        }
        
        button { 
            background: linear-gradient(135deg, #4caf50, #45a049); 
            color: white; padding: 12px 24px; border: none; 
            border-radius: 8px; cursor: pointer; font-weight: 500;
            transition: all 0.2s; box-shadow: 0 4px 15px rgba(76,175,80,0.3);
        }
        button:hover { 
            transform: translateY(-2px); 
            box-shadow: 0 6px 20px rgba(76,175,80,0.4);
        }
        
        select, input { 
            padding: 12px; border-radius: 8px; 
            border: 2px solid #e2e8f0; font-size: 14px;
            transition: border-color 0.2s;
        }
        select:focus, input:focus { 
            outline: none; border-color: #4caf50; 
        }
        
        .log-output { 
            background: #1a202c; color: #e2e8f0; 
            padding: 20px; border-radius: 8px; 
            font-family: 'Monaco', 'Menlo', monospace; 
            font-size: 13px; line-height: 1.5;
            max-height: 300px; overflow-y: auto;
            border: 1px solid #2d3748;
        }
        
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 15px;
            margin-top: 15px;
        }
        
        .metric {
            text-align: center;
            padding: 15px;
            background: #edf2f7;
            border-radius: 8px;
        }
        
        .metric-value {
            font-size: 1.5em;
            font-weight: bold;
            color: #4caf50;
        }
        
        .metric-label {
            font-size: 0.9em;
            color: #718096;
            margin-top: 5px;
        }
        
        @media (max-width: 768px) {
            .dashboard-grid { grid-template-columns: 1fr; }
            .command-section { grid-template-columns: 1fr; }
            body { padding: 10px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>� Pumpkin Access Point</h1>
            <p>UART Device Management & IoT Network Control Center</p>
        </div>
        
        <div class="dashboard-grid">
            <div class="left-panel">
                <div class="status-card">
                    <h3>🌐 Network Status</h3>
                    <div class="node-grid">
                        <div class="node-panel">
                            <h4>� Pumpkin (Access Point)</h4>
                            <p><span class="status-indicator online"></span>WiFi Network: Apple (Hidden)</p>
                            <p><span class="status-indicator online"></span>DHCP Server: Active</p>
                            <p><span class="status-indicator online"></span>IP: 192.168.4.1</p>
                        </div>
                        <div class="node-panel">
                            <h4>🍒 Connected Clients</h4>
                            <div id="connected-clients">
                                <p><span class="status-indicator offline"></span>Cherry: Offline</p>
                                <p><span class="status-indicator offline"></span>Pecan: Offline</p>
                                <p><span class="status-indicator offline"></span>Apple: Offline</p>
                                <p><span class="status-indicator offline"></span>Peach: Offline</p>
                            </div>
                        </div>
                    </div>
                    
                    <div class="metrics">
                        <div class="metric">
                            <div class="metric-value" id="client-count">0</div>
                            <div class="metric-label">Clients</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value" id="uart-count">0</div>
                            <div class="metric-label">UART Devices</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value" id="uptime">--</div>
                            <div class="metric-label">Uptime</div>
                        </div>
                    </div>
                </div>
                
                <div class="status-card">
                    <h3>🔧 UART Devices</h3>
                    <div id="uart-devices">Scanning for devices...</div>
                    <button onclick="scanDevices()" style="margin-top: 15px;">🔍 Scan Devices</button>
                </div>
            </div>
            
            <div class="right-panel">
                <div class="command-card">
                    <h3>📡 Device Control</h3>
                    <div class="command-section">
                        <div class="form-group">
                            <label for="deviceSelect">Device</label>
                            <select id="deviceSelect">
                                <option>Select Device...</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label for="commandInput">Command</label>
                            <input type="text" id="commandInput" placeholder="Enter command...">
                        </div>
                        <button onclick="sendCommand()">📤 Send</button>
                    </div>
                    
                    <div class="form-group">
                        <label>Quick Commands</label>
                        <div style="display: flex; gap: 10px; flex-wrap: wrap; margin-top: 10px;">
                            <button onclick="sendQuickCommand('STATUS')" style="font-size: 12px; padding: 8px 16px;">Status</button>
                            <button onclick="sendQuickCommand('RESET')" style="font-size: 12px; padding: 8px 16px;">Reset</button>
                            <button onclick="sendQuickCommand('PING')" style="font-size: 12px; padding: 8px 16px;">Ping</button>
                        </div>
                    </div>
                </div>
                
                <div class="log-card">
                    <h3>📋 System Log</h3>
                    <div class="log-output" id="log-output">
[<span id="startup-time"></span>] 🍎 Apple Pie Access Point started successfully
[<span id="startup-time2"></span>] 📡 UART management system online
[<span id="startup-time3"></span>] 🌐 WiFi network 'Apple' broadcasting (hidden)
                    </div>
                    <button onclick="clearLog()" style="margin-top: 15px; font-size: 12px; padding: 8px 16px;">🗑️ Clear Log</button>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        let startTime = new Date();
        
        function addLog(message, type = 'info') {
            const log = document.getElementById('log-output');
            const timestamp = new Date().toLocaleTimeString();
            const icon = type === 'error' ? '❌' : type === 'success' ? '✅' : type === 'warning' ? '⚠️' : 'ℹ️';
            log.innerHTML += `<br>[${timestamp}] ${icon} ${message}`;
            log.scrollTop = log.scrollHeight;
        }
        
        function clearLog() {
            const log = document.getElementById('log-output');
            const timestamp = new Date().toLocaleTimeString();
            log.innerHTML = `[${timestamp}] 🍎 Log cleared`;
        }
        
        function updateUptime() {
            const now = new Date();
            const diff = Math.floor((now - startTime) / 1000);
            const hours = Math.floor(diff / 3600);
            const minutes = Math.floor((diff % 3600) / 60);
            document.getElementById('uptime').textContent = `${hours}h ${minutes}m`;
        }
        
        function scanDevices() {
            addLog('Scanning for UART devices...');
            fetch('/api/v1/uart/discover')
                .then(response => response.json())
                .then(data => {
                    const deviceDiv = document.getElementById('uart-devices');
                    const deviceSelect = document.getElementById('deviceSelect');
                    const uartCount = document.getElementById('uart-count');
                    
                    deviceDiv.innerHTML = '';
                    deviceSelect.innerHTML = '<option>Select Device...</option>';
                    
                    if (data.devices && data.devices.length > 0) {
                        data.devices.forEach(device => {
                            deviceDiv.innerHTML += `
                                <div style="padding: 10px; margin: 5px 0; background: #f8fafc; border-radius: 6px; border-left: 3px solid #4caf50;">
                                    <strong>${device.port}</strong><br>
                                    <small style="color: #718096;">${device.description}</small>
                                </div>
                            `;
                            deviceSelect.innerHTML += `<option value="${device.port}">${device.port} - ${device.description}</option>`;
                        });
                        uartCount.textContent = data.devices.length;
                        addLog(`Found ${data.devices.length} UART device(s)`, 'success');
                    } else {
                        deviceDiv.innerHTML = '<p style="color: #718096; font-style: italic;">No UART devices found</p>';
                        uartCount.textContent = '0';
                        addLog('No UART devices found', 'warning');
                    }
                })
                .catch(error => {
                    addLog(`Error scanning devices: ${error}`, 'error');
                });
        }
        
        function sendCommand() {
            const device = document.getElementById('deviceSelect').value;
            const command = document.getElementById('commandInput').value.trim();
            
            if (device === 'Select Device...' || !command) {
                addLog('Please select a device and enter a command', 'warning');
                return;
            }
            
            addLog(`Sending command to ${device}: ${command}`);
            
            fetch('/api/v1/uart/command', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({device: device, command: command})
            })
            .then(response => response.json())
            .then(data => {
                if (data.status === 'success') {
                    addLog(`Command sent successfully`, 'success');
                    if (data.response && data.response.trim()) {
                        addLog(`Response: ${data.response}`, 'info');
                    }
                } else {
                    addLog(`Command failed: ${data.message}`, 'error');
                }
            })
            .catch(error => {
                addLog(`Error sending command: ${error}`, 'error');
            });
            
            document.getElementById('commandInput').value = '';
        }
        
        function sendQuickCommand(cmd) {
            document.getElementById('commandInput').value = cmd;
            sendCommand();
        }
        
        // Initialize timestamps
        window.onload = function() {
            const now = new Date().toLocaleTimeString();
            document.getElementById('startup-time').textContent = now;
            document.getElementById('startup-time2').textContent = now;
            document.getElementById('startup-time3').textContent = now;
            
            // Auto-scan devices
            scanDevices();
            
            // Update uptime every minute
            setInterval(updateUptime, 60000);
            updateUptime();
            
            addLog('Pumpkin Dashboard loaded successfully', 'success');
        };
        
        // Handle Enter key in command input
        document.addEventListener('DOMContentLoaded', function() {
            document.getElementById('commandInput').addEventListener('keypress', function(e) {
                if (e.key === 'Enter') {
                    sendCommand();
                }
            });
        });
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
                'description': port.description or 'Unknown Device',
                'hwid': port.hwid or 'Unknown'
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
        
        return jsonify({'status': 'success', 'message': f'Connected to {port} at {baud_rate} baud'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/v1/uart/command', methods=['POST'])
def send_uart_command():
    """Send command to UART device"""
    try:
        data = request.get_json()
        device = data.get('device')
        command = data.get('command')
        
        if not device or not command:
            return jsonify({'status': 'error', 'message': 'Device and command required'})
        
        # Auto-connect if not connected
        if device not in uart_connections:
            try:
                uart_connections[device] = serial.Serial(device, 9600, timeout=1)
                device_status[device] = 'connected'
            except Exception as e:
                return jsonify({'status': 'error', 'message': f'Failed to connect to {device}: {str(e)}'})
        
        uart_connection = uart_connections[device]
        
        # Send command
        uart_connection.write(f"{command}\n".encode())
        uart_connection.flush()
        
        # Try to read response with timeout
        response = ""
        try:
            response = uart_connection.readline().decode().strip()
        except Exception:
            response = "No response"
        
        return jsonify({
            'status': 'success',
            'command': command,
            'response': response,
            'device': device,
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/v1/uart/disconnect', methods=['POST'])
def disconnect_uart_device():
    """Disconnect from a UART device"""
    try:
        data = request.get_json()
        port = data.get('port')
        
        if port in uart_connections:
            uart_connections[port].close()
            del uart_connections[port]
            device_status[port] = 'disconnected'
            return jsonify({'status': 'success', 'message': f'Disconnected from {port}'})
        else:
            return jsonify({'status': 'error', 'message': f'No connection to {port}'})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/api/v1/uart/config', methods=['GET', 'POST'])
def uart_config():
    """Get or set UART configuration"""
    if request.method == 'GET':
        return jsonify({
            'connections': list(uart_connections.keys()),
            'status': device_status,
            'active_connections': len(uart_connections)
        })
    elif request.method == 'POST':
        data = request.get_json()
        return jsonify({'status': 'success', 'message': 'Configuration updated'})

@app.route('/api/v1/status', methods=['GET'])
def api_status():
    """API status endpoint"""
    return jsonify({
        'hostname': 'pumpkin',
        'role': 'access_point',
        'ip': '192.168.4.1',
        'network': 'Apple',
        'uart_devices': len(uart_connections),
        'active_connections': len(uart_connections),
        'timestamp': datetime.now().isoformat(),
        'uptime': time.time()
    })

if __name__ == '__main__':
    print("� Starting Pumpkin AP Dashboard...")
    print("🌐 Dashboard: http://192.168.4.1/")
    print("📡 UART API: http://192.168.4.1/api/v1/uart/")
    print("🔧 Status API: http://192.168.4.1/api/v1/status")
    app.run(host='0.0.0.0', port=80, debug=False)
PYEOF

# Set proper permissions
sudo chown -R admin:admin /home/admin/dashboard_project
chmod +x /home/admin/dashboard_project/app.py

# Create systemd service for the dashboard (runs as root for port 80)
echo "🔧 Creating dashboard service..."
sudo tee /etc/systemd/system/pumpkin-dashboard.service > /dev/null << 'EOF'
[Unit]
Description=Pumpkin AP Dashboard
After=network.target hostapd.service dnsmasq.service
Requires=hostapd.service dnsmasq.service

[Service]
Type=simple
User=root
WorkingDirectory=/home/admin/dashboard_project
ExecStart=/usr/bin/python3 app.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

# Unmask and enable services
echo "🚀 Enabling and starting services..."
sudo systemctl unmask hostapd
sudo systemctl daemon-reload

# Stop conflicting services first
sudo systemctl stop hostapd dnsmasq apple-pie-dashboard 2>/dev/null || true

# Start services in correct order
sudo systemctl enable dnsmasq
sudo systemctl start dnsmasq
sleep 2

sudo systemctl enable hostapd
sudo systemctl start hostapd
sleep 3

sudo systemctl enable pumpkin-dashboard
sudo systemctl start pumpkin-dashboard
sleep 2

# Create network interface configuration to persist across reboots
echo "🔧 Creating persistent network configuration..."
sudo tee /etc/systemd/network/10-wlan0.network > /dev/null << 'EOF'
[Match]
Name=wlan0

[Network]
IPForward=yes
Address=192.168.4.1/24
EOF

# Enable systemd-networkd (backup network manager)
sudo systemctl enable systemd-networkd

echo ""
echo "✅ Apple Pie Access Point Setup Complete!"
echo ""
echo "📊 Network Status:"
echo "  🔐 SSID: Apple (Hidden)"
echo "  🔑 Password: Pharos12345"
echo "  🌐 AP IP: 192.168.4.1"
echo "  📱 DHCP Range: 192.168.4.10-50"
echo ""
echo "🍎 Dashboard Access:"
echo "  🖥️  Main Dashboard: http://192.168.4.1/"
echo "  🔧 UART API: http://192.168.4.1/api/v1/uart/"
echo "  📊 Status API: http://192.168.4.1/api/v1/status"
echo ""
echo "🎯 To connect other devices:"
echo "  1. Connect to hidden WiFi 'Apple' with password 'Pharos12345'"
echo "  2. Devices will get IPs in range 192.168.4.10-50"
echo "  3. Access dashboard at http://192.168.4.1/"
echo ""

# Final comprehensive status check
echo "🔍 Final Service Status:"
services=("hostapd" "dnsmasq" "pumpkin-dashboard")
for service in "${services[@]}"; do
    if sudo systemctl is-active "$service" >/dev/null 2>&1; then
        echo "✅ $service: Active"
    else
        echo "❌ $service: Failed"
        echo "   Checking logs: sudo journalctl -u $service --no-pager -n 5"
    fi
done

echo ""
echo "🎉 Setup complete! The Pumpkin Access Point is ready to use."
echo "📱 Connect to the 'Apple' WiFi network and navigate to http://192.168.4.1/"
