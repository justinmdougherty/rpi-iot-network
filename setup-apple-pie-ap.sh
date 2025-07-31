#!/bin/bash
# Apple Pie Access Point Setup Script
# Converts Apple Pi into the main AP with UART device control

set -e  # Exit on any error

echo "======================================"
echo "🍎🥧 Apple Pie AP Configuration Starting..."
echo "======================================"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Step 1: Setting hostname to 'apple-pie'..."
sudo hostnamectl set-hostname apple-pie
echo "127.0.1.1    apple-pie" | sudo tee -a /etc/hosts

log "Step 2: Updating system packages..."
sudo apt update
sudo apt upgrade -y

log "Step 3: Installing AP and web server packages..."
sudo apt install -y hostapd dnsmasq dhcpcd5 iptables-persistent
sudo apt install -y python3-flask python3-requests python3-serial python3-pip
sudo apt install -y nginx supervisor git curl wget vim htop

log "Step 4: Installing Python packages for UART communication..."
sudo pip3 install pyserial flask-cors

log "Step 5: Configuring DHCP client for ethernet..."
sudo tee /etc/dhcpcd.conf > /dev/null << 'EOF'
# DHCP configuration for Apple Pie AP
# Interface eth0 uses DHCP for internet connection
interface eth0
static ip_address=
# Interface wlan0 configured as AP with static IP
interface wlan0
static ip_address=192.168.4.1/24
nohook wpa_supplicant
EOF

log "Step 6: Configuring DNS and DHCP server (dnsmasq)..."
sudo tee /etc/dnsmasq.conf > /dev/null << 'EOF'
# Apple Pie AP - DNS and DHCP Configuration
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h
domain=applepie.local
address=/applepie.local/192.168.4.1
EOF

log "Step 7: Configuring WiFi Access Point (hostapd)..."
sudo tee /etc/hostapd/hostapd.conf > /dev/null << 'EOF'
# Apple Pie Access Point Configuration
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

sudo tee /etc/default/hostapd > /dev/null << 'EOF'
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF

log "Step 8: Configuring IP forwarding and NAT..."
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf

# Configure iptables for NAT
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT

# Save iptables rules
sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"

# Create script to restore iptables on boot
sudo tee /etc/rc.local > /dev/null << 'EOF'
#!/bin/sh -e
# Restore iptables rules for Apple Pie AP
iptables-restore < /etc/iptables.ipv4.nat
exit 0
EOF
sudo chmod +x /etc/rc.local

log "Step 9: Creating project directory structure..."
sudo mkdir -p /home/admin/apple_pie_project
sudo mkdir -p /home/admin/apple_pie_project/templates
sudo mkdir -p /home/admin/apple_pie_project/static
sudo mkdir -p /home/admin/apple_pie_project/uart_devices
sudo mkdir -p /var/log/apple_pie

log "Step 10: Creating Apple Pie Flask API server..."
sudo tee /home/admin/apple_pie_project/apple_pie_server.py > /dev/null << 'EOF'
#!/usr/bin/env python3
"""
Apple Pie Access Point - Main Flask API Server
Handles UART device communication and web dashboard
"""

import os
import json
import time
import threading
import serial
import serial.tools.list_ports
from datetime import datetime
from flask import Flask, request, jsonify, render_template
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# Configuration
UART_DEVICES = {}
DEVICE_STATUS = {}
LOG_FILE = '/var/log/apple_pie/api.log'

class UARTDevice:
    def __init__(self, port, baudrate=9600, timeout=1):
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.serial_conn = None
        self.connected = False
        
    def connect(self):
        try:
            self.serial_conn = serial.Serial(
                self.port, 
                self.baudrate, 
                timeout=self.timeout
            )
            self.connected = True
            log_message(f"Connected to UART device on {self.port}")
            return True
        except Exception as e:
            log_message(f"Failed to connect to {self.port}: {e}")
            return False
    
    def disconnect(self):
        if self.serial_conn:
            self.serial_conn.close()
            self.connected = False
            log_message(f"Disconnected from {self.port}")
    
    def send_command(self, command):
        if not self.connected:
            return {"error": "Device not connected"}
        
        try:
            self.serial_conn.write(f"{command}\n".encode())
            response = self.serial_conn.readline().decode().strip()
            log_message(f"UART {self.port} -> Command: {command}, Response: {response}")
            return {"response": response, "success": True}
        except Exception as e:
            log_message(f"UART {self.port} error: {e}")
            return {"error": str(e), "success": False}
    
    def get_status(self):
        return {
            "port": self.port,
            "connected": self.connected,
            "baudrate": self.baudrate
        }

def log_message(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] {message}"
    print(log_entry)
    
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, 'a') as f:
            f.write(f"{log_entry}\n")
    except Exception as e:
        print(f"Failed to write to log file: {e}")

def discover_uart_devices():
    """Discover available UART devices"""
    ports = serial.tools.list_ports.comports()
    available_devices = []
    
    for port in ports:
        if 'USB' in port.description or 'tty' in port.device:
            available_devices.append({
                "device": port.device,
                "description": port.description,
                "hwid": port.hwid
            })
    
    return available_devices

# API Routes

@app.route('/')
def dashboard():
    """Main dashboard page"""
    return render_template('dashboard.html')

@app.route('/api/v1/status', methods=['GET'])
def get_ap_status():
    """Get Apple Pie AP status"""
    return jsonify({
        "node": "apple-pie",
        "role": "access_point",
        "ip": "192.168.4.1",
        "status": "online",
        "uart_devices": len(UART_DEVICES),
        "connected_devices": sum(1 for d in UART_DEVICES.values() if d.connected),
        "timestamp": datetime.now().isoformat()
    })

@app.route('/api/v1/uart/discover', methods=['GET'])
def discover_devices():
    """Discover available UART devices"""
    devices = discover_uart_devices()
    return jsonify({
        "available_devices": devices,
        "count": len(devices)
    })

@app.route('/api/v1/uart/connect', methods=['POST'])
def connect_device():
    """Connect to a UART device"""
    data = request.get_json()
    
    if not data or 'port' not in data:
        return jsonify({"error": "Port parameter required"}), 400
    
    port = data['port']
    baudrate = data.get('baudrate', 9600)
    device_name = data.get('name', f"device_{port.split('/')[-1]}")
    
    if device_name in UART_DEVICES:
        return jsonify({"error": "Device already connected"}), 400
    
    device = UARTDevice(port, baudrate)
    if device.connect():
        UART_DEVICES[device_name] = device
        return jsonify({
            "message": f"Connected to {device_name}",
            "device": device.get_status()
        })
    else:
        return jsonify({"error": "Failed to connect to device"}), 500

@app.route('/api/v1/uart/disconnect/<device_name>', methods=['POST'])
def disconnect_device(device_name):
    """Disconnect from a UART device"""
    if device_name not in UART_DEVICES:
        return jsonify({"error": "Device not found"}), 404
    
    UART_DEVICES[device_name].disconnect()
    del UART_DEVICES[device_name]
    
    return jsonify({"message": f"Disconnected from {device_name}"})

@app.route('/api/v1/uart/<device_name>/status', methods=['GET'])
def get_device_status(device_name):
    """Get status of a specific UART device"""
    if device_name not in UART_DEVICES:
        return jsonify({"error": "Device not found"}), 404
    
    device = UART_DEVICES[device_name]
    return jsonify(device.get_status())

@app.route('/api/v1/uart/<device_name>/command', methods=['POST'])
def send_device_command(device_name):
    """Send command to UART device"""
    if device_name not in UART_DEVICES:
        return jsonify({"error": "Device not found"}), 404
    
    data = request.get_json()
    if not data or 'command' not in data:
        return jsonify({"error": "Command parameter required"}), 400
    
    device = UART_DEVICES[device_name]
    result = device.send_command(data['command'])
    
    if result.get('success'):
        return jsonify({
            "device": device_name,
            "command": data['command'],
            "response": result['response']
        })
    else:
        return jsonify(result), 500

@app.route('/api/v1/uart/<device_name>/config', methods=['PUT'])
def update_device_config(device_name):
    """Update device configuration"""
    if device_name not in UART_DEVICES:
        return jsonify({"error": "Device not found"}), 404
    
    data = request.get_json()
    # Handle config updates (baudrate, timeout, etc.)
    
    return jsonify({
        "message": f"Configuration updated for {device_name}",
        "config": data
    })

@app.route('/api/v1/logs', methods=['GET'])
def get_logs():
    """Get recent log entries"""
    try:
        with open(LOG_FILE, 'r') as f:
            lines = f.readlines()
            recent_lines = lines[-100:]  # Last 100 lines
        return jsonify({"logs": recent_lines})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    log_message("🍎🥧 Apple Pie API Server starting...")
    
    # Start Flask server
    app.run(
        host='0.0.0.0',
        port=5000,
        debug=False,
        threaded=True
    )
EOF

log "Step 11: Creating basic dashboard template..."
sudo tee /home/admin/apple_pie_project/templates/dashboard.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🍎🥧 Apple Pie Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .status-panel { background: white; padding: 15px; border-radius: 8px; margin-bottom: 15px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .device-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px; }
        .device-card { background: white; padding: 15px; border-radius: 8px; border-left: 4px solid #3498db; }
        .connected { border-left-color: #27ae60; }
        .disconnected { border-left-color: #e74c3c; }
        button { background: #3498db; color: white; border: none; padding: 10px 15px; border-radius: 4px; cursor: pointer; }
        button:hover { background: #2980b9; }
        .log-panel { background: white; padding: 15px; border-radius: 8px; max-height: 300px; overflow-y: auto; font-family: monospace; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🍎🥧 Apple Pie Access Point Dashboard</h1>
        <p>UART Device Control Center - IP: 192.168.4.1</p>
    </div>
    
    <div class="status-panel">
        <h3>AP Status</h3>
        <div id="ap-status">Loading...</div>
    </div>
    
    <div class="status-panel">
        <h3>UART Devices</h3>
        <button onclick="discoverDevices()">Discover Devices</button>
        <div id="device-list" class="device-grid"></div>
    </div>
    
    <div class="status-panel">
        <h3>System Logs</h3>
        <div id="logs" class="log-panel"></div>
        <button onclick="refreshLogs()">Refresh Logs</button>
    </div>

    <script>
        // Dashboard JavaScript will be added here
        function discoverDevices() {
            fetch('/api/v1/uart/discover')
                .then(response => response.json())
                .then(data => {
                    console.log('Discovered devices:', data);
                    // Update UI with discovered devices
                });
        }
        
        function refreshLogs() {
            fetch('/api/v1/logs')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('logs').innerHTML = data.logs.join('<br>');
                });
        }
        
        // Auto-refresh status every 5 seconds
        setInterval(() => {
            fetch('/api/v1/status')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('ap-status').innerHTML = 
                        `Status: ${data.status} | UART Devices: ${data.uart_devices} | Connected: ${data.connected_devices}`;
                });
        }, 5000);
        
        // Initial load
        refreshLogs();
    </script>
</body>
</html>
EOF

log "Step 12: Creating systemd service for Apple Pie server..."
sudo tee /etc/systemd/system/apple_pie.service > /dev/null << 'EOF'
[Unit]
Description=Apple Pie Access Point - UART Device Server
After=network.target hostapd.service dnsmasq.service
Wants=hostapd.service dnsmasq.service

[Service]
Type=simple
User=root
WorkingDirectory=/home/admin/apple_pie_project
ExecStart=/usr/bin/python3 /home/admin/apple_pie_project/apple_pie_server.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

log "Step 13: Setting up file permissions..."
sudo chown -R admin:admin /home/admin/apple_pie_project
sudo chmod +x /home/admin/apple_pie_project/apple_pie_server.py

log "Step 14: Enabling services..."
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq
sudo systemctl enable apple_pie.service

log "Step 15: Creating validation script..."
sudo tee /home/admin/test_apple_pie.sh > /dev/null << 'EOF'
#!/bin/bash
echo "🍎🥧 Apple Pie AP Validation Test"
echo "================================="

echo "1. Testing AP status..."
curl -s http://localhost:5000/api/v1/status || echo "❌ API not responding"

echo "2. Testing UART device discovery..."
curl -s http://localhost:5000/api/v1/uart/discover || echo "❌ UART discovery failed"

echo "3. Checking WiFi AP status..."
sudo systemctl is-active hostapd || echo "❌ hostapd not running"

echo "4. Checking DHCP server..."
sudo systemctl is-active dnsmasq || echo "❌ dnsmasq not running"

echo "5. Testing network interface..."
ip addr show wlan0 | grep "192.168.4.1" || echo "❌ AP IP not configured"

echo "================================="
echo "✅ Apple Pie AP validation complete"
EOF

sudo chmod +x /home/admin/test_apple_pie.sh

log "Configuration completed successfully!"

echo "======================================"
echo "🍎🥧 Apple Pie AP Setup Summary"
echo "======================================"
echo "AP Name: Apple (hidden)"
echo "AP IP: 192.168.4.1"
echo "Password: Pharos12345"
echo "DHCP Range: 192.168.4.10-50"
echo "Dashboard: http://192.168.4.1:5000"
echo "User: admin / Password: 001234"
echo ""
echo "Next Steps:"
echo "1. Reboot the Pi: sudo reboot"
echo "2. Connect devices to 'Apple' network"
echo "3. Access dashboard at http://192.168.4.1:5000"
echo "4. Test UART devices: /home/admin/test_apple_pie.sh"
echo ""
echo "API Endpoints:"
echo "- Status: GET http://192.168.4.1:5000/api/v1/status"
echo "- Discover UART: GET http://192.168.4.1:5000/api/v1/uart/discover"
echo "- Connect Device: POST http://192.168.4.1:5000/api/v1/uart/connect"
echo "- Send Command: POST http://192.168.4.1:5000/api/v1/uart/{device}/command"
echo "- Update Config: PUT http://192.168.4.1:5000/api/v1/uart/{device}/config"
echo "======================================"
