#!/bin/bash
# Complete Client Node Setup Script
# Configures Pi as client connecting to Apple Pie AP with sensors and actuators

set -e  # Exit on any error

# Configuration variables - modify these per node
NODE_NAME="${1:-cherry}"  # Default to cherry, can be overridden
NODE_IP=""

case $NODE_NAME in
    "pumpkin")
        NODE_IP="192.168.4.10"
        ;;
    "cherry")
        NODE_IP="192.168.4.11"
        ;;
    "pecan")
        NODE_IP="192.168.4.12"
        ;;
    "peach")
        NODE_IP="192.168.4.13"
        ;;
    *)
        echo "❌ Invalid node name. Use: pumpkin, cherry, pecan, or peach"
        exit 1
        ;;
esac

echo "🍒 Client Node Setup - $NODE_NAME"
echo "================================="
echo "Configuring this Pi as: $NODE_NAME"
echo "Target IP: $NODE_IP"
echo "Will connect to: Apple AP (192.168.4.1)"
echo ""

# Set hostname
echo "🏷️  Setting hostname to $NODE_NAME..."
sudo hostnamectl set-hostname "$NODE_NAME"
echo "$NODE_NAME" | sudo tee /etc/hostname > /dev/null

# Update hosts file
sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$NODE_NAME/" /etc/hosts

# Update package list and install required packages
echo "📦 Installing required packages..."
sudo apt update -qq
sudo apt install -y python3-flask python3-requests python3-gpiozero python3-rpi.gpio python3-serial network-manager

# Install additional Python packages
echo "🐍 Installing Python packages..."
sudo pip3 install --break-system-packages flask requests gpiozero pyserial 2>/dev/null || true

# Stop conflicting services
echo "🛑 Stopping conflicting services..."
sudo systemctl stop hostapd 2>/dev/null || true
sudo systemctl disable hostapd 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true

# Ensure NetworkManager is active
sudo systemctl enable NetworkManager
sudo systemctl start NetworkManager

# Enable WiFi hardware
echo "📡 Enabling WiFi hardware..."
sudo rfkill unblock wifi
sleep 2

# Bring up WiFi interface
sudo ip link set wlan0 up 2>/dev/null || echo "wlan0 already up or not available"
sleep 2

# Restart NetworkManager to detect WiFi
sudo systemctl restart NetworkManager
sleep 3

# Remove existing Apple connection if it exists
echo "📡 Configuring WiFi connection..."
sudo nmcli connection delete "Apple" 2>/dev/null || true
sudo nmcli connection delete "Apple-Connection" 2>/dev/null || true

# Create connection to Apple AP
sudo nmcli connection add type wifi con-name "Apple-Connection" ssid "Apple"
sudo nmcli connection modify "Apple-Connection" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Pharos12345"
sudo nmcli connection modify "Apple-Connection" 802-11-wireless.hidden yes
sudo nmcli connection modify "Apple-Connection" ipv4.addresses "$NODE_IP/24"
sudo nmcli connection modify "Apple-Connection" ipv4.gateway "192.168.4.1"
sudo nmcli connection modify "Apple-Connection" ipv4.dns "192.168.4.1,8.8.8.8"
sudo nmcli connection modify "Apple-Connection" ipv4.method manual
sudo nmcli connection modify "Apple-Connection" connection.autoconnect yes

# Connect to Apple network
echo "🔗 Connecting to Apple AP..."
sudo nmcli connection up "Apple-Connection"

# Create client application directory
echo "🛠️  Setting up client application..."
mkdir -p /home/admin/client_project
cd /home/admin/client_project

# Create comprehensive client application
cat > client_app.py << 'PYEOF'
#!/usr/bin/env python3
import os
import json
import time
import threading
import requests
import subprocess
from datetime import datetime
from flask import Flask, request, jsonify
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Node configuration - will be set during setup
NODE_NAME = os.environ.get('NODE_NAME', 'unknown')
NODE_IP = os.environ.get('NODE_IP', '192.168.4.10')
AP_IP = "192.168.4.1"

# Global variables
sensor_data = {}
device_status = {}
last_heartbeat = None

# Try to import GPIO libraries with fallback
try:
    from gpiozero import LED, Button, MCP3008
    from gpiozero.pins.pigpio import PiGPIOFactory
    from gpiozero import Device
    
    # Try to use pigpio for better performance, fallback to default
    try:
        Device.pin_factory = PiGPIOFactory()
        logger.info("Using pigpio pin factory")
    except Exception:
        logger.info("Using default pin factory")
        
    GPIO_AVAILABLE = True
except ImportError:
    logger.warning("GPIO libraries not available")
    GPIO_AVAILABLE = False

# Device management with fallback pins
class DeviceManager:
    def __init__(self):
        self.devices = {}
        self.led_pins = [17, 18, 19, 20, 21]  # Fallback pin strategy
        self.button_pins = [2, 3, 4, 14, 15]
        self.init_devices()
    
    def init_devices(self):
        """Initialize GPIO devices with fallback strategy"""
        if not GPIO_AVAILABLE:
            logger.warning("GPIO not available, running in simulation mode")
            return
            
        # Try to initialize LED with fallback pins
        for pin in self.led_pins:
            try:
                self.devices['led'] = LED(pin)
                logger.info(f"LED initialized on pin {pin}")
                break
            except Exception as e:
                logger.warning(f"Failed to initialize LED on pin {pin}: {e}")
        
        # Try to initialize button with fallback pins
        for pin in self.button_pins:
            try:
                self.devices['button'] = Button(pin)
                logger.info(f"Button initialized on pin {pin}")
                break
            except Exception as e:
                logger.warning(f"Failed to initialize button on pin {pin}: {e}")
    
    def control_led(self, state):
        """Control LED state"""
        if 'led' in self.devices:
            try:
                if state.lower() in ['on', 'true', '1']:
                    self.devices['led'].on()
                    return True
                else:
                    self.devices['led'].off()
                    return True
            except Exception as e:
                logger.error(f"LED control error: {e}")
                return False
        else:
            logger.warning("LED not available")
            return False
    
    def read_button(self):
        """Read button state"""
        if 'button' in self.devices:
            try:
                return self.devices['button'].is_pressed
            except Exception as e:
                logger.error(f"Button read error: {e}")
                return False
        else:
            return False

# Initialize device manager
device_manager = DeviceManager()

def get_ap_ip():
    """Discover AP IP address"""
    try:
        result = subprocess.run(['ip', 'route', 'show', 'default'], 
                              capture_output=True, text=True, timeout=5)
        if result.stdout:
            return result.stdout.split()[2]
    except Exception:
        pass
    return "192.168.4.1"

def send_heartbeat():
    """Send periodic heartbeat to AP"""
    global last_heartbeat
    while True:
        try:
            ap_ip = get_ap_ip()
            heartbeat_data = {
                'node': NODE_NAME,
                'ip': NODE_IP,
                'timestamp': datetime.now().isoformat(),
                'status': 'online',
                'devices': list(device_manager.devices.keys()),
                'sensor_data': sensor_data
            }
            
            response = requests.post(
                f"http://{ap_ip}/api/heartbeat",
                json=heartbeat_data,
                timeout=5
            )
            
            if response.status_code == 200:
                last_heartbeat = datetime.now()
                logger.info(f"Heartbeat sent to {ap_ip}")
            else:
                logger.warning(f"Heartbeat failed: {response.status_code}")
                
        except Exception as e:
            logger.error(f"Heartbeat error: {e}")
        
        time.sleep(30)  # Send heartbeat every 30 seconds

def sensor_monitor():
    """Monitor sensors and update data"""
    while True:
        try:
            # Read button state if available
            if device_manager.read_button():
                sensor_data['button'] = {
                    'state': 'pressed',
                    'timestamp': datetime.now().isoformat()
                }
            
            # Simulate temperature sensor (replace with real sensor)
            import random
            sensor_data['temperature'] = {
                'value': round(20 + random.random() * 10, 1),
                'unit': 'celsius',
                'timestamp': datetime.now().isoformat()
            }
            
            time.sleep(5)  # Monitor every 5 seconds
            
        except Exception as e:
            logger.error(f"Sensor monitoring error: {e}")
            time.sleep(10)

# Flask API Routes
@app.route(f'/{NODE_NAME}/api/v1/status', methods=['GET'])
def node_status():
    """Return node status"""
    return jsonify({
        'node': NODE_NAME,
        'ip': NODE_IP,
        'status': 'online',
        'timestamp': datetime.now().isoformat(),
        'devices': list(device_manager.devices.keys()),
        'last_heartbeat': last_heartbeat.isoformat() if last_heartbeat else None,
        'sensor_data': sensor_data
    })

@app.route(f'/{NODE_NAME}/api/v1/actuators/led', methods=['GET', 'POST'])
def led_control():
    """Control LED actuator"""
    if request.method == 'GET':
        return jsonify({
            'device': 'led',
            'available': 'led' in device_manager.devices,
            'state': 'unknown'
        })
    
    elif request.method == 'POST':
        try:
            data = request.get_json() or {}
            state = data.get('state', 'off')
            
            success = device_manager.control_led(state)
            
            return jsonify({
                'device': 'led',
                'state': state,
                'success': success,
                'timestamp': datetime.now().isoformat()
            })
        except Exception as e:
            return jsonify({'error': str(e)}), 500

@app.route(f'/{NODE_NAME}/api/v1/sensors/<sensor_type>', methods=['GET'])
def read_sensor(sensor_type):
    """Read sensor data"""
    if sensor_type in sensor_data:
        return jsonify({
            'sensor': sensor_type,
            'data': sensor_data[sensor_type]
        })
    else:
        return jsonify({'error': f'Sensor {sensor_type} not available'}), 404

@app.route(f'/{NODE_NAME}/api/v1/sensors', methods=['GET'])
def list_sensors():
    """List all available sensors"""
    return jsonify({
        'sensors': list(sensor_data.keys()),
        'data': sensor_data
    })

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'node': NODE_NAME})

def run_flask_server():
    """Run Flask server in a thread"""
    logger.info(f"Starting Flask server for {NODE_NAME} on {NODE_IP}:5000")
    app.run(host='0.0.0.0', port=5000, debug=False)

if __name__ == '__main__':
    logger.info(f"Starting {NODE_NAME} client application")
    
    # Start background threads
    heartbeat_thread = threading.Thread(target=send_heartbeat, daemon=True)
    heartbeat_thread.start()
    
    sensor_thread = threading.Thread(target=sensor_monitor, daemon=True)
    sensor_thread.start()
    
    # Start Flask server
    try:
        run_flask_server()
    except KeyboardInterrupt:
        logger.info(f"{NODE_NAME} client application stopping")
PYEOF

# Create environment file for the service
cat > .env << EOF
NODE_NAME=$NODE_NAME
NODE_IP=$NODE_IP
EOF

# Set proper permissions
sudo chown -R admin:admin /home/admin/client_project
chmod +x /home/admin/client_project/client_app.py

# Create systemd service
echo "🔧 Creating client application service..."
sudo tee /etc/systemd/system/client-app.service > /dev/null << EOF
[Unit]
Description=$NODE_NAME Client Application
After=network.target NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=simple
User=admin
Group=gpio
WorkingDirectory=/home/admin/client_project
Environment=NODE_NAME=$NODE_NAME
Environment=NODE_IP=$NODE_IP
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 client_app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Ensure admin user is in gpio group
sudo usermod -a -G gpio admin

# Create network monitor script
echo "📡 Creating network monitor..."
cat > /home/admin/network_monitor.sh << 'EOF'
#!/bin/bash
# Network monitoring and auto-reconnection script

NODE_NAME="${NODE_NAME}"
AP_IP="192.168.4.1"

while true; do
    # Check if we can reach the AP
    if ! ping -c 1 "$AP_IP" &>/dev/null; then
        echo "$(date): Lost connection to AP, attempting reconnection..."
        
        # Try to reconnect
        sudo nmcli connection down "Apple-Connection" 2>/dev/null || true
        sleep 2
        sudo nmcli connection up "Apple-Connection" 2>/dev/null || true
        sleep 5
        
        # Check if reconnection worked
        if ping -c 1 "$AP_IP" &>/dev/null; then
            echo "$(date): Reconnection successful"
        else
            echo "$(date): Reconnection failed, will retry"
        fi
    fi
    
    sleep 30
done
EOF

chmod +x /home/admin/network_monitor.sh

# Create network monitor service
sudo tee /etc/systemd/system/network-monitor.service > /dev/null << 'EOF'
[Unit]
Description=Network Monitor and Auto-reconnect
After=network.target NetworkManager.service

[Service]
Type=simple
User=admin
Environment=NODE_NAME=$NODE_NAME
ExecStart=/home/admin/network_monitor.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
echo "🚀 Enabling and starting services..."
sudo systemctl daemon-reload
sudo systemctl enable NetworkManager
sudo systemctl enable client-app.service
sudo systemctl enable network-monitor.service

# Start services
sudo systemctl start client-app.service
sudo systemctl start network-monitor.service

# Wait a moment for services to start
sleep 3

echo ""
echo "✅ Client Node Setup Complete!"
echo ""
echo "📊 Node Configuration:"
echo "  🏷️  Hostname: $NODE_NAME"
echo "  🌐 IP Address: $NODE_IP"
echo "  📡 Connected to: Apple AP (192.168.4.1)"
echo "  🔌 API Port: 5000"
echo ""
echo "🔧 API Endpoints:"
echo "  📊 Status: http://$NODE_IP:5000/$NODE_NAME/api/v1/status"
echo "  💡 LED Control: http://$NODE_IP:5000/$NODE_NAME/api/v1/actuators/led"
echo "  📡 Sensors: http://$NODE_IP:5000/$NODE_NAME/api/v1/sensors"
echo "  ❤️  Health: http://$NODE_IP:5000/health"
echo ""
echo "🎯 From Apple AP Dashboard:"
echo "  🌐 Access via: http://192.168.4.1/"
echo "  🔧 Control this node remotely"
echo "  📊 Monitor sensor data"
echo ""

# Final status check
echo "🔍 Service Status:"
services=("NetworkManager" "client-app" "network-monitor")
for service in "${services[@]}"; do
    if sudo systemctl is-active "$service" >/dev/null 2>&1; then
        echo "✅ $service: Active"
    else
        echo "❌ $service: Failed"
        echo "   Check logs: sudo journalctl -u $service --no-pager -n 5"
    fi
done

# Test connection to AP
echo ""
echo "🔍 Testing connection to Apple AP..."
if ping -c 3 192.168.4.1 >/dev/null 2>&1; then
    echo "✅ Successfully connected to Apple AP"
    
    # Test API endpoint
    if curl -s "http://$NODE_IP:5000/health" >/dev/null 2>&1; then
        echo "✅ Client API is responding"
    else
        echo "⚠️  Client API not yet ready (may need a moment to start)"
    fi
else
    echo "❌ Cannot reach Apple AP"
    echo "   Check WiFi connection: sudo nmcli connection show"
fi

echo ""
echo "🎉 Setup complete! $NODE_NAME is ready to operate as a client node."
