#!/bin/bash
# Raspberry Pi Client Node Automated Setup Script
# Version: 1.0
# Usage: ./setup-client.sh [node_id] [ap_ssid] [ap_password]

set -e

# Configuration defaults
DEFAULT_NODE_ID="pi2"
DEFAULT_AP_SSID="RPiAP"
DEFAULT_AP_PASSWORD="Pharos1234"
DEFAULT_CLIENT_IP="192.168.4.10"
DEFAULT_AP_IP="192.168.4.1"

# Parse command line arguments
NODE_ID=${1:-$DEFAULT_NODE_ID}
AP_SSID=${2:-$DEFAULT_AP_SSID}
AP_PASSWORD=${3:-$DEFAULT_AP_PASSWORD}

echo "=== Raspberry Pi Client Node Setup ==="
echo "Node ID: $NODE_ID"
echo "AP SSID: $AP_SSID"
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

# Step 2: Install required packages
log "Installing required packages..."
sudo apt install -y python3-flask python3-requests python3-gpiozero network-manager curl
check_status "Package installation"

# Step 3: WiFi Configuration
log "Configuring WiFi connection to $AP_SSID..."
sudo nmcli connection delete RPiAP 2>/dev/null || true
sudo nmcli connection add type wifi con-name RPiAP ssid "$AP_SSID"
sudo nmcli connection modify RPiAP wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$AP_PASSWORD"
sudo nmcli connection modify RPiAP ipv4.addresses $DEFAULT_CLIENT_IP/24 ipv4.gateway $DEFAULT_AP_IP ipv4.method manual
sudo nmcli connection modify RPiAP connection.autoconnect yes connection.autoconnect-priority 100
check_status "WiFi configuration"

# Step 4: Create project directory
log "Creating project directory..."
mkdir -p /home/admin/client_project
cd /home/admin/client_project
check_status "Project directory creation"

# Step 5: Create client application
log "Creating client application..."
cat > client_app.py << 'EOF'
#!/usr/bin/env python3
# Auto-generated client application
import threading
import time
import datetime
import math
import random
import requests
import socket
import subprocess
from flask import Flask, request, jsonify
from gpiozero import LED

# Dynamic configuration
def get_ap_ip():
    try:
        result = subprocess.run(['ip', 'route', 'show', 'default'], 
                               capture_output=True, text=True)
        gateway_line = result.stdout.strip()
        if gateway_line:
            return gateway_line.split()[2]
        return "192.168.4.1"
    except:
        return "192.168.4.1"

def get_my_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "192.168.4.10"

# Configuration
AP_IP = get_ap_ip()
MY_IP = get_my_ip()
NODE_ID = "NODE_ID_PLACEHOLDER"
ALERT_ENDPOINT = f"http://{AP_IP}/api/alert"
LED_PINS = [17, 18, 19, 20]

# Flask app setup
app = Flask(__name__)

# Initialize LED with fallback
led = None
for pin in LED_PINS:
    try:
        led = LED(pin)
        print(f"Successfully initialized LED on GPIO pin {pin}")
        break
    except Exception as e:
        print(f"Failed to initialize LED on GPIO pin {pin}: {e}")
        continue

if led is None:
    print("Failed to initialize LED on any available pin")

@app.route('/api/v1/actuators/led', methods=['POST'])
def handle_led_command():
    if led is None:
        return jsonify({"error": "LED not available"}), 503
    
    request_data = request.get_json()
    state = request_data.get('state')
    brightness = request_data.get('brightness', 100)
    
    print(f"Received LED command: state={state}, brightness={brightness}")
    
    if state == 'on':
        led.on()
        return jsonify({'status': 'LED turned on'})
    elif state == 'off':
        led.off()
        return jsonify({'status': 'LED turned off'})
    else:
        return jsonify({"error": "Invalid state. Use 'on' or 'off'."}), 400

@app.route('/api/v1/actuators/led/status', methods=['GET'])
def get_led_status():
    if led is None:
        return jsonify({"error": "LED not available"}), 503
    
    is_on = led.is_lit
    return jsonify({'state': 'on' if is_on else 'off', 'is_lit': is_on})

@app.route('/api/v1/status', methods=['GET'])
def get_node_status():
    return jsonify({
        'node_id': NODE_ID,
        'ip_address': MY_IP,
        'ap_ip': AP_IP,
        'led_available': led is not None,
        'timestamp': datetime.datetime.now().isoformat()
    })

def run_api_server():
    app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)

def run_alert_monitor():
    print("Starting sensor alert monitor...")
    counter = 0
    while True:
        try:
            simulated_temp = 25.0 + 15.0 * math.sin(counter)
            counter += 0.1
            
            alert_payload = {
                "pi": NODE_ID,
                "sensor": "temperature",
                "value": simulated_temp,
                "unit": "celsius",
                "timestamp": datetime.datetime.now().isoformat()
            }
            
            response = requests.post(ALERT_ENDPOINT, json=alert_payload, timeout=5)
            print(f"Temp: {simulated_temp:.2f}°C - Status: {response.status_code}")
            
        except Exception as e:
            print(f"Alert monitor error: {e}")
        
        sleep_time = random.randint(5, 30)
        time.sleep(sleep_time)

if __name__ == '__main__':
    api_thread = threading.Thread(target=run_api_server)
    api_thread.daemon = True
    
    monitor_thread = threading.Thread(target=run_alert_monitor)
    monitor_thread.daemon = True
    
    print(f"Starting {NODE_ID} application...")
    print(f"Node IP: {MY_IP}, AP IP: {AP_IP}")
    
    api_thread.start()
    monitor_thread.start()
    
    while True:
        time.sleep(1)
EOF

# Replace placeholder with actual node ID
sed -i "s/NODE_ID_PLACEHOLDER/$NODE_ID/g" client_app.py
chmod +x client_app.py
check_status "Client application creation"

# Step 6: Create systemd service
log "Creating systemd service..."
cat > client_app.service << EOF
[Unit]
Description=Client Pi Application ($NODE_ID)
After=network.target

[Service]
User=admin
WorkingDirectory=/home/admin/client_project
ExecStart=/usr/bin/python3 /home/admin/client_project/client_app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo cp client_app.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable client_app.service
check_status "Service creation"

# Step 7: GPIO permissions
log "Setting up GPIO permissions..."
sudo usermod -a -G gpio admin
check_status "GPIO permissions"

# Step 8: Connect to WiFi and start service
log "Connecting to WiFi network..."
sudo nmcli connection up RPiAP
sleep 5
check_status "WiFi connection"

log "Starting client service..."
sudo systemctl start client_app.service
sleep 3
check_status "Service startup"

# Step 9: Verification
log "Performing verification tests..."
sleep 5

# Test network connectivity
ping -c 3 $DEFAULT_AP_IP > /dev/null 2>&1
check_status "AP connectivity test"

# Test service status
sudo systemctl is-active --quiet client_app.service
check_status "Service status check"

# Test API endpoint
curl -s http://localhost:5000/api/v1/status > /dev/null
check_status "API endpoint test"

log "=== Setup Complete ==="
echo ""
echo "Client Pi '$NODE_ID' has been successfully configured!"
echo ""
echo "Network Configuration:"
echo "  - Connected to: $AP_SSID"
echo "  - Client IP: $DEFAULT_CLIENT_IP"
echo "  - Gateway: $DEFAULT_AP_IP"
echo ""
echo "Services:"
echo "  - API Server: http://$DEFAULT_CLIENT_IP:5000"
echo "  - Service Status: $(sudo systemctl is-active client_app.service)"
echo ""
echo "Next Steps:"
echo "  1. Check service logs: journalctl -u client_app.service -f"
echo "  2. Test LED control from dashboard"
echo "  3. Verify temperature data transmission"
echo ""
echo "For troubleshooting, run: ./troubleshoot.py"
