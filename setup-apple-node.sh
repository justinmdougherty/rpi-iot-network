#!/bin/bash
# Apple Node (192.168.4.12) Configuration Script
# Run this script on a fresh Raspberry Pi OS installation

set -e  # Exit on any error

echo "======================================"
echo "Apple Node Configuration Starting..."
echo "======================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root. Run as pi user instead."
   exit 1
fi

log_info "Step 1: Creating admin user account..."
# Create admin user with standardized credentials
sudo useradd -m -s /bin/bash admin 2>/dev/null || log_warn "User admin already exists"
echo 'admin:001234' | sudo chpasswd

# Add admin to necessary groups
sudo usermod -a -G sudo,gpio,dialout,i2c,spi admin

# Setup SSH access for admin
sudo mkdir -p /home/admin/.ssh
sudo chown admin:admin /home/admin/.ssh
sudo chmod 700 /home/admin/.ssh

log_info "Step 2: Setting hostname to 'apple'..."
sudo hostnamectl set-hostname apple
echo "127.0.1.1    apple" | sudo tee -a /etc/hosts

log_info "Step 3: Updating system packages..."
sudo apt update && sudo apt upgrade -y

log_info "Step 4: Installing required packages..."
# Install Python libraries for web server, HTTP requests, and GPIO control
sudo apt install python3-flask python3-requests python3-gpiozero python3-pip -y

# Install network management tools
sudo apt install network-manager -y

# Install additional useful packages
sudo apt install git curl wget vim htop -y

log_info "Step 5: Configuring WiFi connection to hidden Apple network..."
# Remove any existing Apple connection
sudo nmcli connection delete Apple 2>/dev/null || true

# Add the hidden Apple network
sudo nmcli connection add type wifi con-name Apple ssid "Apple"

# Configure WiFi security
sudo nmcli connection modify Apple wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Pharos12345"

# Configure as hidden network
sudo nmcli connection modify Apple 802-11-wireless.hidden yes

# Configure static IP for Apple node (192.168.4.12)
sudo nmcli connection modify Apple ipv4.addresses 192.168.4.12/24 ipv4.gateway 192.168.4.1 ipv4.method manual

# Set DNS servers
sudo nmcli connection modify Apple ipv4.dns 8.8.8.8,8.8.4.4

# Set high priority for auto-connection
sudo nmcli connection modify Apple connection.autoconnect yes connection.autoconnect-priority 100

log_info "Step 6: Creating project directory structure..."
sudo mkdir -p /home/admin/client_project
sudo mkdir -p /home/admin/dashboard_project  # For failover AP mode
sudo chown -R admin:admin /home/admin/

log_info "Step 7: Creating Apple client application..."
cat > /home/admin/client_project/client_app.py << 'EOF'
#!/usr/bin/env python3
# Apple Node Client Application
# Node: apple (192.168.4.12)

import threading
import time
import datetime
import math
import random
import requests
import socket
import subprocess
from flask import Flask, request, jsonify
from gpiozero import LED, Button

# --- Configuration ---
NODE_NAME = "apple"
NODE_IP = "192.168.4.12"
LED_PINS = [17, 18, 19, 20]  # Try multiple pins in case one is busy

def get_ap_ip():
    """Discover AP IP via gateway"""
    try:
        result = subprocess.run(['ip', 'route', 'show', 'default'], 
                              capture_output=True, text=True)
        gateway_line = result.stdout.strip()
        if gateway_line:
            return gateway_line.split()[2]  # Extract gateway IP
        return "192.168.4.1"  # Fallback
    except:
        return "192.168.4.1"

AP_IP = get_ap_ip()
ALERT_ENDPOINT = f"http://{AP_IP}/api/alert"

# --- Flask API Server Setup ---
app = Flask(__name__)

# Initialize LED with fallback pins
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

@app.route(f'/{NODE_NAME}/api/v1/actuators/led', methods=['POST'])
def handle_led_command():
    """Controls the state of an LED."""
    if led is None:
        return jsonify({"error": "LED not available - GPIO initialization failed"}), 503
       
    request_data = request.get_json()
    state = request_data.get('state')
    brightness = request_data.get('brightness', 100)
   
    print(f"[{NODE_NAME}] Received LED command: state={state}, brightness={brightness}")
   
    if state == 'on':
        led.on()
        status_message = f"[{NODE_NAME}] LED turned on"
    elif state == 'off':
        led.off()
        status_message = f"[{NODE_NAME}] LED turned off"
    else:
        return jsonify({"error": "Invalid state. Use 'on' or 'off'."}), 400
    
    return jsonify({'status': status_message, 'node': NODE_NAME})

@app.route(f'/{NODE_NAME}/api/v1/actuators/led/status', methods=['GET'])
def get_led_status():
    """Returns the current state of the LED."""
    if led is None:
        return jsonify({"error": "LED not available - GPIO initialization failed"}), 503
       
    is_on = led.is_lit
    return jsonify({'state': 'on' if is_on else 'off', 'is_lit': is_on, 'node': NODE_NAME})

@app.route(f'/{NODE_NAME}/api/v1/status', methods=['GET'])
def get_node_status():
    """Return node health status."""
    return jsonify({
        'node': NODE_NAME,
        'ip': NODE_IP,
        'status': 'online',
        'timestamp': datetime.datetime.now().isoformat(),
        'led_available': led is not None
    })

def run_api_server():
    """Runs the Flask app."""
    app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)

# --- Alert Monitor Logic ---
def run_alert_monitor():
    """Simulates a sensor and pushes updates to the AP."""
    print(f"[{NODE_NAME}] Starting simulated sensor alert monitor...")
    counter = 0
    while True:
        try:
            # Simulate a temperature value cycling smoothly between 15.0 and 35.0
            # Apple node has a slightly different pattern for identification
            simulated_temp = 25.0 + 10.0 * math.sin(counter * 0.8)
            counter += 0.1
            print(f"[{NODE_NAME}] Simulated temp: {simulated_temp:.2f}°C. Sending update.")

            alert_payload = {
                "pi": NODE_NAME,
                "sensor": "temperature",
                "value": round(simulated_temp, 2),
                "unit": "celsius",
                "timestamp": datetime.datetime.now().isoformat()
            }

            response = requests.post(ALERT_ENDPOINT, json=alert_payload, timeout=5)
            print(f"[{NODE_NAME}] Response status: {response.status_code}")

        except Exception as e:
            print(f"[{NODE_NAME}] Alert monitor error: {e}")

        # Random sleep between 10 and 25 seconds
        sleep_time = random.randint(10, 25)
        time.sleep(sleep_time)

# --- Main Execution ---
if __name__ == '__main__':
    # Create a thread for the Flask API server
    api_thread = threading.Thread(target=run_api_server)
    api_thread.daemon = True
   
    # Create a thread for the alert monitor
    monitor_thread = threading.Thread(target=run_alert_monitor)
    monitor_thread.daemon = True
   
    print(f"[{NODE_NAME}] Starting API server thread...")
    api_thread.start()
   
    print(f"[{NODE_NAME}] Starting alert monitor thread...")
    monitor_thread.start()
   
    print(f"[{NODE_NAME}] Node ready - API on port 5000, monitoring active")
    
    # Keep the main thread alive
    while True:
        time.sleep(1)
EOF

log_info "Step 8: Creating systemd service file..."
cat > /home/admin/client_project/client_app.service << 'EOF'
[Unit]
Description=Apple Node Client Application (API and Alert Monitor)
After=network.target
Wants=network-online.target

[Service]
User=admin
WorkingDirectory=/home/admin/client_project
ExecStart=/usr/bin/python3 /home/admin/client_project/client_app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

log_info "Step 9: Setting up file permissions..."
chmod +x /home/admin/client_project/client_app.py
sudo chown -R admin:admin /home/admin/

log_info "Step 10: Installing and enabling the service..."
# Copy service file to systemd directory
sudo cp /home/admin/client_project/client_app.service /etc/systemd/system/

# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start automatically on boot
sudo systemctl enable client_app.service

log_info "Step 11: Creating validation script..."
cat > /home/admin/test_apple_node.sh << 'EOF'
#!/bin/bash
# Apple Node Test Script

echo "======================================"
echo "Testing Apple Node Configuration"
echo "======================================"

# Test network connectivity
echo "Testing network connectivity..."
ping -c 3 192.168.4.1 || echo "WARNING: Cannot reach AP"

# Test WiFi connection
echo "WiFi Status:"
nmcli connection show --active | grep Apple || echo "WARNING: Apple connection not active"

# Test IP assignment
echo "IP Address:"
ip addr show wlan0 | grep "192.168.4.12" || echo "WARNING: Expected IP not assigned"

# Test API endpoints (when service is running)
echo "Testing API endpoints..."
sleep 2
curl -s http://localhost:5000/apple/api/v1/status || echo "WARNING: API not responding"

echo "Test completed!"
EOF

chmod +x /home/admin/test_apple_node.sh

log_info "Step 12: Creating failover AP configuration (for dual-mode support)..."
mkdir -p /home/admin/failover_configs

cat > /home/admin/failover_configs/hostapd_apple.conf << 'EOF'
# Apple Node Failover AP Configuration
interface=wlan0
driver=nl80211
ssid=Apple-Backup
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

log_info "Configuration completed successfully!"
echo ""
echo "======================================"
echo "Apple Node Setup Summary"
echo "======================================"
echo "Node Name: apple"
echo "Static IP: 192.168.4.12"
echo "Network: Apple (hidden)"
echo "Password: Pharos12345"
echo "User: admin / Password: 001234"
echo ""
echo "Next Steps:"
echo "1. Connect to the Apple network: sudo nmcli connection up Apple"
echo "2. Start the service: sudo systemctl start client_app.service"
echo "3. Check status: sudo systemctl status client_app.service"
echo "4. Run tests: /home/admin/test_apple_node.sh"
echo "5. SSH to this node: ssh admin@192.168.4.12"
echo ""
echo "Service endpoints:"
echo "- LED Control: POST http://192.168.4.12:5000/apple/api/v1/actuators/led"
echo "- LED Status: GET http://192.168.4.12:5000/apple/api/v1/actuators/led/status"
echo "- Node Status: GET http://192.168.4.12:5000/apple/api/v1/status"
echo "======================================"
