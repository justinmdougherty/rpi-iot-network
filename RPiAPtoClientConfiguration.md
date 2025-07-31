# Raspberry Pi Client Node Configuration Guide

This guide will walk you through setting up a Raspberry Pi as a client node that automatically connects to an RPiAP access point and runs sensor monitoring with GPIO control capabilities.

## Prerequisites
- Fresh Raspberry Pi OS installation (Bookworm or later recommended)
- SSH access to the Pi (either via Ethernet or temporary WiFi connection)
- RPiAP (Raspberry Pi Access Point) already configured and running
- Default user account: `admin` with password: `001234`

## Quick Start with Automation Tools

**New!** Use the comprehensive toolset in the `tools/` directory for automated setup:
- `setup-client.sh` - Automated client Pi configuration
- `setup-ap.sh` - Automated access point setup  
- `monitor.py` - Network and service monitoring
- `validate-config.py` - Configuration validation
- `troubleshoot.py` - Automated troubleshooting

See the **Project Toolset** section below for complete automation tools.

## Step 1: Initial System Setup

**What this provides:** Updates the operating system and installs essential Python libraries for web services, HTTP communication, and GPIO hardware control. This creates the foundation for running Flask web servers and controlling physical devices.

### Create standardized user account
```bash
# Create admin user with standard password
sudo useradd -m -s /bin/bash admin
echo 'admin:001234' | sudo chpasswd

# Add admin to necessary groups
sudo usermod -a -G sudo,gpio,dialout admin

# Enable SSH login for admin user
sudo mkdir -p /home/admin/.ssh
sudo chown admin:admin /home/admin/.ssh
sudo chmod 700 /home/admin/.ssh
```

### Update the system
```bash
sudo apt update && sudo apt upgrade -y
```

### Install required packages
```bash
# Install Python libraries for web server, HTTP requests, and GPIO control
sudo apt install python3-flask python3-requests python3-gpiozero -y

# Install network management tools (if not already installed)
sudo apt install network-manager -y
```

## Step 2: WiFi Configuration

**What this provides:** Configures automatic connection to the RPiAP with a static IP address. This ensures the client Pi always gets the same IP address (192.168.4.10) that the dashboard expects, and automatically reconnects to the access point on boot or after network interruptions.

### Connect to the RPiAP using NetworkManager
```bash
# Add the Apple network (hidden SSID)
sudo nmcli connection add type wifi con-name Apple ssid "Apple"

# Set the WiFi password
sudo nmcli connection modify Apple wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Pharos12345"

# Configure as hidden network
sudo nmcli connection modify Apple 802-11-wireless.hidden yes

# Configure static IP address as expected by the dashboard
sudo nmcli connection modify Apple ipv4.addresses 192.168.4.10/24 ipv4.gateway 192.168.4.1 ipv4.method manual

# Set high priority for auto-connection
sudo nmcli connection modify Apple connection.autoconnect yes connection.autoconnect-priority 100

# Connect to the network
sudo nmcli connection up Apple
```

### Verify connection
```bash
# Check IP address (should show 192.168.4.10)
ip addr show wlan0

# Test connectivity to AP
ping -c 3 192.168.4.1
```

## Step 3: Create Project Directory and Application

**What this provides:** Creates the main client application that runs two services simultaneously: (1) A REST API server that listens for LED control commands from the dashboard, and (2) A sensor monitor that continuously sends simulated temperature data to the access point. The application includes automatic GPIO pin fallback and robust error handling.

### Create project directory
```bash
mkdir -p /home/admin/client_project
cd /home/admin/client_project
```

### Create the main application file

Create `/home/admin/client_project/client_app.py`:
```python
#!/usr/bin/env python3
# client_app.py

import threading
import time
import datetime
import math
import random
import requests
from flask import Flask, request, jsonify
from gpiozero import LED

# --- Configuration ---
AP_IP = "192.168.4.1"
ALERT_ENDPOINT = f"http://{AP_IP}/api/alert"
LED_PINS = [17, 18, 19, 20]  # Try multiple pins in case one is busy

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

@app.route('/api/v1/actuators/led', methods=['POST'])
def handle_led_command():
    """Controls the state of an LED."""
    if led is None:
        return jsonify({"error": "LED not available - GPIO initialization failed"}), 503
       
    request_data = request.get_json()
    state = request_data.get('state')
    brightness = request_data.get('brightness', 100)  # Default to 100% if not specified
   
    print(f"Received LED command: state={state}, brightness={brightness}")
   
    if state == 'on':
        led.on()
        status_message = "LED turned on"
    elif state == 'off':
        led.off()
        status_message = "LED turned off"
    else:
        return jsonify({"error": "Invalid state. Use 'on' or 'off'."}), 400
    return jsonify({'status': status_message})

@app.route('/api/v1/actuators/led/status', methods=['GET'])
def get_led_status():
    """Returns the current state of the LED."""
    if led is None:
        return jsonify({"error": "LED not available - GPIO initialization failed"}), 503
       
    is_on = led.is_lit
    return jsonify({'state': 'on' if is_on else 'off', 'is_lit': is_on})

def run_api_server():
    """Runs the Flask app."""
    app.run(host='0.0.0.0', port=5000, debug=False, use_reloader=False)

# --- Alert Monitor Logic ---
def run_alert_monitor():
    """Simulates a sensor and pushes updates to the AP."""
    print("Starting simulated sensor alert monitor...")
    counter = 0
    while True:
        try:
            # Simulate a temperature value cycling smoothly between 10.0 and 40.0
            simulated_temp = 25.0 + 15.0 * math.sin(counter)
            counter += 0.1
            print(f"Simulated temp: {simulated_temp:.2f}°C. Sending update.")
           

            alert_payload = {
                "pi": "pi2",
                "sensor": "temperature",
                "value": simulated_temp,
                "unit": "celsius",
                "timestamp": datetime.datetime.now().isoformat()
            }
           

            response = requests.post(ALERT_ENDPOINT, json=alert_payload, timeout=5)
            print(f"Response status: {response.status_code}, Response: {response.text}")
           

        except Exception as e:
            print(f"Alert monitor error: {e}")
       

        # Random sleep between 5 and 30 seconds
        sleep_time = random.randint(5, 30)
        time.sleep(sleep_time)

# --- Main Execution ---
if __name__ == '__main__':
    # Create a thread for the Flask API server
    api_thread = threading.Thread(target=run_api_server)
    api_thread.daemon = True
   
    # Create a thread for the alert monitor
    monitor_thread = threading.Thread(target=run_alert_monitor)
    monitor_thread.daemon = True
   
    print("Starting API server thread...")
    api_thread.start()
   
    print("Starting alert monitor thread...")
    monitor_thread.start()
   
    # Keep the main thread alive
    while True:
        time.sleep(1)
```

### Make the script executable
```bash
chmod +x /home/admin/client_project/client_app.py
```

## Step 4: Create Systemd Service for Auto-Start

**What this provides:** Creates a system service that automatically starts the client application on boot and restarts it if it crashes. This ensures the Pi functions autonomously without manual intervention, making it truly "plug-and-play" for the IoT network.

### Create service file

Create `/home/admin/client_project/client_app.service`:
```ini
[Unit]
Description=Client Pi Application (API and Alert Monitor)
After=network.target

[Service]
User=admin
WorkingDirectory=/home/admin/client_project
ExecStart=/usr/bin/python3 /home/admin/client_project/client_app.py
Restart=always

[Install]
WantedBy=multi-user.target
```

### Install and enable the service
```bash
# Copy service file to systemd directory
sudo cp /home/admin/client_project/client_app.service /etc/systemd/system/

# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start automatically on boot
sudo systemctl enable client_app.service

# Start the service immediately
sudo systemctl start client_app.service
```

### Verify service is running
```bash
# Check service status
sudo systemctl status client_app.service

# Follow live logs
journalctl -u client_app.service -f
```

## Step 5: GPIO Permissions Setup

**What this provides:** Grants the user account proper permissions to control GPIO pins without requiring root privileges. This is essential for LED control, sensor reading, and other hardware interactions while maintaining system security.

### Add user to GPIO group
```bash
sudo usermod -a -G gpio admin
```

### Verify group membership
```bash
groups admin
```

## Step 6: Testing and Verification

**What this provides:** Comprehensive testing procedures to verify that all components work correctly: network connectivity, sensor data transmission, and LED control via REST API. These tests confirm the client Pi is fully functional before putting it into production use.

### Test network connectivity
```bash
# Verify IP address
ip addr show wlan0

# Test AP connectivity
ping -c 3 192.168.4.1

# Test HTTP endpoint
curl -X POST http://192.168.4.1/api/alert -H "Content-Type: application/json" -d '{"pi":"pi2","sensor":"temperature","value":25.5,"unit":"celsius","timestamp":"2025-07-19T11:30:00"}'
```

### Test LED control (from another device on the network)
```bash
# Turn LED on
curl -X POST http://192.168.4.10:5000/api/v1/actuators/led -H "Content-Type: application/json" -d '{"state":"on","brightness":100}'

# Turn LED off
curl -X POST http://192.168.4.10:5000/api/v1/actuators/led -H "Content-Type: application/json" -d '{"state":"off"}'

# Check LED status
curl http://192.168.4.10:5000/api/v1/actuators/led/status
```

## Step 7: Service Management Commands

**What this provides:** Essential commands for ongoing maintenance and troubleshooting of the client service. These commands allow you to start, stop, restart, and monitor the client application, as well as view logs for debugging issues.

### Useful commands for managing the service
```bash
# Check service status
sudo systemctl status client_app.service

# Start the service
sudo systemctl start client_app.service

# Stop the service
sudo systemctl stop client_app.service

# Restart the service
sudo systemctl restart client_app.service

# View recent logs
journalctl -u client_app.service -n 50

# Follow live logs
journalctl -u client_app.service -f

# Disable auto-start (if needed)
sudo systemctl disable client_app.service
```

## Step 8: Troubleshooting

**What this provides:** Solutions to common problems you may encounter during setup or operation, including GPIO conflicts, network connectivity issues, service startup failures, and port conflicts. This section helps you quickly diagnose and resolve issues without starting over.

### Common issues and solutions

#### GPIO "busy" error
- Try different GPIO pins (script automatically tries pins 17, 18, 19, 20)
- Reboot the Pi to clear any held GPIO resources
- Check for other processes using GPIO: `sudo lsof /dev/gpiomem`

#### Network connectivity issues
- Verify WiFi connection: `nmcli connection show --active`
- Check IP assignment: `ip addr show wlan0`
- Test AP connectivity: `ping 192.168.4.1`

#### Service fails to start
- Check service logs: `journalctl -u client_app.service`
- Verify Python dependencies: `python3 -c "import flask, requests, gpiozero"`
- Check file permissions: `ls -la /home/admin/client_project/`

#### Port conflicts
- Check what's using port 5000: `sudo lsof -i :5000`
- Kill conflicting processes: `sudo pkill -f client_app.py`

## Current Configuration Summary

**Network Configuration:**
- SSID: Apple (hidden network)
- Password: Pharos12345
- Static IP: 192.168.4.10/24 (Cherry), 192.168.4.11/24 (Pecan), 192.168.4.12/24 (Apple), 192.168.4.13/24 (Peach)
- Gateway: 192.168.4.1 (Pumpkin AP)
- User credentials: admin/001234

**Application Features:**
- Temperature sensor simulation (sends data every 5-30 seconds randomly)
- LED control via GPIO pin 17 (fallback to 18, 19, 20)
- REST API server on port 5000
- Auto-connects to Apple hidden network on boot
- Auto-starts application service on boot
- Automatic service restart on failure

**API Endpoints:**
- POST `/api/v1/actuators/led` - Control LED (expects: `{"state":"on/off","brightness":100}`)
- GET `/api/v1/actuators/led/status` - Get LED status

**Data Format Sent to AP:**
```json
{
  "pi": "pi2",
  "sensor": "temperature",
  "value": 25.5,
  "unit": "celsius",
  "timestamp": "2025-07-19T11:30:00.000000"
}
```

This configuration creates a fully autonomous client Pi that will automatically connect to the RPiAP and begin sending sensor data and accepting control commands as soon as it boots up.

## Step 9: RPiAP (Access Point) Setup Guide

**What this provides:** Complete instructions for setting up the central Raspberry Pi that acts as the WiFi access point and dashboard server. This creates the network hub that all client Pis connect to, including WiFi access point functionality, DHCP server for IP assignment, and the web dashboard for monitoring and controlling all connected nodes.

This section covers setting up the Raspberry Pi Access Point that manages the client nodes.

### RPiAP Prerequisites
- Raspberry Pi with WiFi capability (Pi 3B+ or newer recommended)
- Fresh Raspberry Pi OS installation
- Ethernet connection for internet access (optional but recommended)

### Install Access Point Software
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install hostapd and dnsmasq for AP functionality
sudo apt install hostapd dnsmasq -y

# Install Python packages for dashboard
sudo apt install python3-flask python3-socketio python3-requests python3-gpiozero -y
```

### Configure Access Point
```bash
# Configure hostapd
sudo nano /etc/hostapd/hostapd.conf
```

Add the following configuration:
```
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
```

### Configure DHCP Server
```bash
# Backup original dnsmasq config
sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup

# Configure dnsmasq
sudo nano /etc/dnsmasq.conf
```

Add these lines:
```
interface=wlan0
dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h
dhcp-option=3,192.168.4.1
dhcp-option=6,192.168.4.1
```

### Configure Network Interface
```bash
# Configure static IP for wlan0
sudo nano /etc/dhcpcd.conf
```

Add at the end:
```
interface wlan0
static ip_address=192.168.4.1/24
nohook wpa_supplicant
```

### Enable Services
```bash
# Enable and start services
sudo systemctl enable hostapd
sudo systemctl enable dnsmasq

# Configure hostapd daemon
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd

# Reboot to apply changes
sudo reboot
```

### Create Dashboard Application

Create `/home/admin/dashboard_project/app.py` with your dashboard code, then create the service:
```bash
# Create dashboard service
sudo nano /etc/systemd/system/dashboard.service
```

```ini
[Unit]
Description=Dashboard Web Server for Pi Control
After=network.target

[Service]
User=root
WorkingDirectory=/home/admin/dashboard_project
ExecStart=/usr/bin/python3 /home/admin/dashboard_project/app.py
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
# Enable dashboard service
sudo systemctl daemon-reload
sudo systemctl enable dashboard.service
sudo systemctl start dashboard.service
```

## Step 10: IP Address Management Enhancement

**What this provides:** Advanced networking configuration that eliminates hardcoded IP addresses. Implements dynamic IP discovery and DHCP reservations, making the system more flexible and easier to deploy. Client Pis can automatically find the access point and get appropriate IP addresses without manual configuration.

Instead of hardcoding IP addresses, implement dynamic IP discovery and configuration.

### Option 1: DHCP with Hostname Resolution

Modify the client application to use hostnames instead of fixed IPs:
```python
# In client_app.py, replace static IP configuration
import socket

def get_ap_ip():
    """Discover AP IP via gateway"""
    try:
        # Get default gateway (should be the AP)
        import subprocess
        result = subprocess.run(['ip', 'route', 'show', 'default'], 
                              capture_output=True, text=True)
        gateway_line = result.stdout.strip()
        if gateway_line:
            return gateway_line.split()[2]  # Extract gateway IP
        return "192.168.4.1"  # Fallback
    except:
        return "192.168.4.1"

def get_my_ip():
    """Get our current IP address"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "192.168.4.10"

# Use dynamic discovery
AP_IP = get_ap_ip()
MY_IP = get_my_ip()
```

### Option 2: Use DHCP Reservations on AP

Configure the AP to assign specific IPs based on MAC addresses:
```bash
# On the AP, edit dnsmasq configuration
sudo nano /etc/dnsmasq.conf
```

Add MAC-based reservations:
```
# DHCP reservations for specific clients
dhcp-host=aa:bb:cc:dd:ee:ff,pi2,192.168.4.10
dhcp-host=11:22:33:44:55:66,pi3,192.168.4.11
dhcp-host=77:88:99:aa:bb:cc,pi4,192.168.4.12
```

## Step 11: Multi-Pi Network Enhancements

**What this provides:** Advanced features for scaling beyond a simple client-server setup. Includes automatic node discovery, support for multiple sensor types (temperature, humidity, motion, door, light), hardware abstraction for easy device management, and data buffering for offline resilience. These enhancements transform the basic setup into a robust IoT network capable of supporting 3-5+ Pi nodes with diverse sensor and actuator capabilities.

### Client-Side Enhancements

#### 1. Node Auto-Discovery and Registration
```python
# Add to client_app.py
import uuid
import psutil

def register_with_ap():
    """Register this node with the AP"""
    node_info = {
        "node_id": f"pi{socket.gethostname().split('-')[-1]}",
        "mac_address": get_mac_address(),
        "ip_address": get_my_ip(),
        "hostname": socket.gethostname(),
        "capabilities": ["temperature", "led", "gpio"],
        "last_boot": psutil.boot_time()
    }
   

    try:
        response = requests.post(f"http://{AP_IP}/api/register", 
                              json=node_info, timeout=10)
        print(f"Registration response: {response.status_code}")
    except Exception as e:
        print(f"Registration failed: {e}")

def get_mac_address():
    """Get WiFi interface MAC address"""
    import netifaces
    try:
        return netifaces.ifaddresses('wlan0')[netifaces.AF_LINK][0]['addr']
    except:
        return "unknown"
```

#### 2. Multiple Sensor Support
```python
# Enhanced sensor system
class SensorManager:
    def __init__(self):
        self.sensors = {
            "temperature": self.read_temperature,
            "humidity": self.read_humidity,
            "motion": self.read_motion,
            "door": self.read_door_sensor,
            "light": self.read_light_level
        }
   

    def read_temperature(self):
        # Actual sensor reading or simulation
        return {"value": 25.0 + 15.0 * math.sin(time.time()), "unit": "celsius"}
   

    def read_humidity(self):
        return {"value": 45.0 + 10.0 * math.sin(time.time() * 0.7), "unit": "percent"}
   

    def read_motion(self):
        # PIR sensor reading
        return {"value": random.choice([True, False]), "unit": "boolean"}
   

    def read_door_sensor(self):
        # Magnetic door sensor
        return {"value": random.choice(["open", "closed"]), "unit": "state"}
   

    def read_light_level(self):
        # LDR or light sensor
        return {"value": random.randint(0, 1023), "unit": "lux"}
```

#### 3. Hardware Abstraction Layer
```python
# GPIO device manager
class DeviceManager:
    def __init__(self):
        self.devices = {}
        self.init_devices()
   

    def init_devices(self):
        """Initialize available GPIO devices"""
        device_configs = [
            {"type": "led", "pin": 17, "name": "status_led"},
            {"type": "led", "pin": 18, "name": "alert_led"},
            {"type": "servo", "pin": 19, "name": "door_servo"},
            {"type": "relay", "pin": 20, "name": "pump_relay"},
            {"type": "button", "pin": 21, "name": "reset_button"}
        ]
       

        for config in device_configs:
            try:
                if config["type"] == "led":
                    self.devices[config["name"]] = LED(config["pin"])
                elif config["type"] == "servo":
                    from gpiozero import Servo
                    self.devices[config["name"]] = Servo(config["pin"])
                elif config["type"] == "relay":
                    self.devices[config["name"]] = LED(config["pin"])  # Relay acts like LED
                # Add more device types as needed
                print(f"Initialized {config['name']} on pin {config['pin']}")
            except Exception as e:
                print(f"Failed to initialize {config['name']}: {e}")
```

#### 4. Advanced Communication Features
```python
# Mesh networking capabilities
def setup_peer_to_peer():
    """Enable direct communication between client nodes"""
    pass

# Data buffering for offline scenarios
class DataBuffer:
    def __init__(self, max_size=1000):
        self.buffer = []
        self.max_size = max_size
   

    def add_reading(self, data):
        self.buffer.append(data)
        if len(self.buffer) > self.max_size:
            self.buffer.pop(0)
   

    def flush_to_ap(self):
        """Send buffered data when connection restored"""
        for data in self.buffer:
            # Attempt to send each buffered reading
            pass
```

### AP-Side Enhancements

#### 1. Node Management Dashboard
```python
# Enhanced dashboard features
class NodeManager:
    def __init__(self):
        self.registered_nodes = {}
        self.node_status = {}
   

    def register_node(self, node_info):
        """Register a new client node"""
        node_id = node_info["node_id"]
        self.registered_nodes[node_id] = node_info
        self.node_status[node_id] = {
            "last_seen": time.time(),
            "status": "online",
            "alerts": []
        }
   

    def update_node_status(self, node_id, data):
        """Update node status from incoming data"""
        if node_id in self.node_status:
            self.node_status[node_id]["last_seen"] = time.time()
            self.node_status[node_id]["status"] = "online"
   

    def check_offline_nodes(self):
        """Mark nodes as offline if no recent communication"""
        current_time = time.time()
        for node_id, status in self.node_status.items():
            if current_time - status["last_seen"] > 60:  # 60 seconds timeout
                status["status"] = "offline"
```

#### 2. Advanced Alerting System
```python
# Smart alerting with rules engine
class AlertRuleEngine:
    def __init__(self):
        self.rules = [
            {"sensor": "temperature", "condition": ">", "threshold": 35, "action": "email"},
            {"sensor": "motion", "condition": "==", "threshold": True, "action": "sms"},
            {"sensor": "door", "condition": "==", "threshold": "open", "action": "notification"}
        ]
   

    def evaluate_alert(self, sensor_data):
        """Check if sensor data triggers any alert rules"""
        for rule in self.rules:
            if self.rule_matches(sensor_data, rule):
                self.trigger_action(rule["action"], sensor_data)
   

    def rule_matches(self, data, rule):
        """Evaluate if data matches rule condition"""
        # Implementation of rule matching logic
        pass
```

#### 3. Data Logging and Analytics
```python
# Database integration for historical data
import sqlite3
from datetime import datetime, timedelta

class DataLogger:
    def __init__(self, db_path="/home/admin/sensor_data.db"):
        self.db_path = db_path
        self.init_database()
   

    def init_database(self):
        """Create database tables"""
        conn = sqlite3.connect(self.db_path)
        conn.execute('''
            CREATE TABLE IF NOT EXISTS sensor_readings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                node_id TEXT,
                sensor_type TEXT,
                value REAL,
                unit TEXT,
                timestamp DATETIME,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        conn.commit()
        conn.close()
   

    def log_reading(self, node_id, sensor_type, value, unit, timestamp):
        """Store sensor reading in database"""
        conn = sqlite3.connect(self.db_path)
        conn.execute('''
            INSERT INTO sensor_readings (node_id, sensor_type, value, unit, timestamp)
            VALUES (?, ?, ?, ?, ?)
        ''', (node_id, sensor_type, value, unit, timestamp))
        conn.commit()
        conn.close()
```

#### 4. Web API for External Integration
```python
# RESTful API for external systems
@app.route('/api/nodes', methods=['GET'])
def get_all_nodes():
    """Return status of all registered nodes"""
    return jsonify(node_manager.node_status)

@app.route('/api/nodes/<node_id>/command', methods=['POST'])
def send_command_to_node(node_id):
    """Send command to specific node"""
    command_data = request.get_json()
    # Forward command to target node
    return jsonify({"status": "command_sent"})

@app.route('/api/data/export', methods=['GET'])
def export_sensor_data():
    """Export historical sensor data"""
    # Return CSV or JSON export of sensor data
    pass
```

## Step 12: Advanced Features and Integrations

**What this provides:** Enterprise-grade features for professional IoT deployments. Includes API key-based security, mobile app support via WebSocket, and scalability features for multiple access points. These integrations enable secure remote access and the ability to scale to larger installations with multiple access points.

### Security Enhancements
```python
# API key authentication
import hashlib
import secrets

class SecurityManager:
    def __init__(self):
        self.api_keys = {}
        self.generate_node_keys()
   

    def generate_node_keys(self):
        """Generate unique API keys for each node"""
        for node_id in ["pi2", "pi3", "pi4", "pi5"]:
            self.api_keys[node_id] = secrets.token_urlsafe(32)
   

    def validate_request(self, node_id, provided_key):
        """Validate API key for node authentication"""
        return self.api_keys.get(node_id) == provided_key
```

### Mobile App Support
```python
# WebSocket API for real-time mobile updates
from flask_socketio import SocketIO, emit

socketio = SocketIO(app, cors_allowed_origins="*")

@socketio.on('connect')
def handle_connect():
    emit('status', {'msg': 'Connected to Pi network'})

@socketio.on('get_node_status')
def handle_node_status_request():
    emit('node_status', node_manager.node_status)
```

### Scalability Features
```python
# Load balancing for multiple APs
class APCluster:
    def __init__(self):
        self.access_points = [
            {"ip": "192.168.4.1", "load": 0},
            {"ip": "192.168.5.1", "load": 0}
        ]
   

    def get_least_loaded_ap(self):
        """Return AP with lowest node count"""
        return min(self.access_points, key=lambda ap: ap["load"])
```

## Project Toolset

This project includes a comprehensive set of automation tools, scripts, and templates to simplify deployment and maintenance. All tools are located in the `tools/` directory.

### Available Tools:
- **Setup Scripts**: Automated installation for both client and AP configurations
- **Monitoring Tools**: Real-time network and service monitoring
- **Configuration Management**: Templates and validation tools
- **Troubleshooting**: Automated diagnostics and repair scripts
- **Documentation**: Auto-generated reports and checklists

Refer to the individual tool files in the `tools/` directory for detailed usage instructions.

\# Configure static IP for wlan0

sudo nano /etc/dhcpcd.conf

```



Add at the end:

```

interface wlan0

static ip\_address=192.168.4.1/24

nohook wpa\_supplicant

```



\### Enable Services

```bash

\# Enable and start services

sudo systemctl enable hostapd

sudo systemctl enable dnsmasq



\# Configure hostapd daemon

echo 'DAEMON\_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd



\# Reboot to apply changes

sudo reboot

```



\### Create Dashboard Application

Create `/home/admin/dashboard\_project/app.py` with your dashboard code, then create the service:



```bash

\# Create dashboard service

sudo nano /etc/systemd/system/dashboard.service

```



```ini

\[Unit]

Description=Dashboard Web Server for Pi Control

After=network.target



\[Service]

User=root

WorkingDirectory=/home/admin/dashboard\_project

ExecStart=/usr/bin/python3 /home/admin/dashboard\_project/app.py

Restart=always



\[Install]

WantedBy=multi-user.target

```



```bash

\# Enable dashboard service

sudo systemctl daemon-reload

sudo systemctl enable dashboard.service

sudo systemctl start dashboard.service

```



\## Step 10: IP Address Management Enhancement



\*\*What this provides:\*\* Advanced networking configuration that eliminates hardcoded IP addresses. Implements dynamic IP discovery and DHCP reservations, making the system more flexible and easier to deploy. Client Pis can automatically find the access point and get appropriate IP addresses without manual configuration.



Instead of hardcoding IP addresses, implement dynamic IP discovery and configuration.



\### Option 1: DHCP with Hostname Resolution

Modify the client application to use hostnames instead of fixed IPs:



```python

\# In client\_app.py, replace static IP configuration

import socket



def get\_ap\_ip():

&nbsp;   """Discover AP IP via gateway"""

&nbsp;   try:

&nbsp;       # Get default gateway (should be the AP)

&nbsp;       import subprocess

&nbsp;       result = subprocess.run(\['ip', 'route', 'show', 'default'], 

&nbsp;                             capture\_output=True, text=True)

&nbsp;       gateway\_line = result.stdout.strip()

&nbsp;       if gateway\_line:

&nbsp;           return gateway\_line.split()\[2]  # Extract gateway IP

&nbsp;       return "192.168.4.1"  # Fallback

&nbsp;   except:

&nbsp;       return "192.168.4.1"



def get\_my\_ip():

&nbsp;   """Get our current IP address"""

&nbsp;   try:

&nbsp;       s = socket.socket(socket.AF\_INET, socket.SOCK\_DGRAM)

&nbsp;       s.connect(("8.8.8.8", 80))

&nbsp;       ip = s.getsockname()\[0]

&nbsp;       s.close()

&nbsp;       return ip

&nbsp;   except:

&nbsp;       return "192.168.4.10"



\# Use dynamic discovery

AP\_IP = get\_ap\_ip()

MY\_IP = get\_my\_ip()

```



\### Option 2: Use DHCP Reservations on AP

Configure the AP to assign specific IPs based on MAC addresses:



```bash

\# On the AP, edit dnsmasq configuration

sudo nano /etc/dnsmasq.conf

```



Add MAC-based reservations:

```

\# DHCP reservations for specific clients

dhcp-host=aa:bb:cc:dd:ee:ff,pi2,192.168.4.10

dhcp-host=11:22:33:44:55:66,pi3,192.168.4.11

dhcp-host=77:88:99:aa:bb:cc,pi4,192.168.4.12

```



\## Step 11: Multi-Pi Network Enhancements



\*\*What this provides:\*\* Advanced features for scaling beyond a simple client-server setup. Includes automatic node discovery, support for multiple sensor types (temperature, humidity, motion, door, light), hardware abstraction for easy device management, and data buffering for offline resilience. These enhancements transform the basic setup into a robust IoT network capable of supporting 3-5+ Pi nodes with diverse sensor and actuator capabilities.



\### Client-Side Enhancements



\#### 1. Node Auto-Discovery and Registration

```python

\# Add to client\_app.py

import uuid

import psutil



def register\_with\_ap():

&nbsp;   """Register this node with the AP"""

&nbsp;   node\_info = {

&nbsp;       "node\_id": f"pi{socket.gethostname().split('-')\[-1]}",

&nbsp;       "mac\_address": get\_mac\_address(),

&nbsp;       "ip\_address": get\_my\_ip(),

&nbsp;       "hostname": socket.gethostname(),

&nbsp;       "capabilities": \["temperature", "led", "gpio"],

&nbsp;       "last\_boot": psutil.boot\_time()

&nbsp;   }

&nbsp;   

&nbsp;   try:

&nbsp;       response = requests.post(f"http://{AP\_IP}/api/register", 

&nbsp;                              json=node\_info, timeout=10)

&nbsp;       print(f"Registration response: {response.status\_code}")

&nbsp;   except Exception as e:

&nbsp;       print(f"Registration failed: {e}")



def get\_mac\_address():

&nbsp;   """Get WiFi interface MAC address"""

&nbsp;   import netifaces

&nbsp;   try:

&nbsp;       return netifaces.ifaddresses('wlan0')\[netifaces.AF\_LINK]\[0]\['addr']

&nbsp;   except:

&nbsp;       return "unknown"

```



\#### 2. Multiple Sensor Support

```python

\# Enhanced sensor system

class SensorManager:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.sensors = {

&nbsp;           "temperature": self.read\_temperature,

&nbsp;           "humidity": self.read\_humidity,

&nbsp;           "motion": self.read\_motion,

&nbsp;           "door": self.read\_door\_sensor,

&nbsp;           "light": self.read\_light\_level

&nbsp;       }

&nbsp;   

&nbsp;   def read\_temperature(self):

&nbsp;       # Actual sensor reading or simulation

&nbsp;       return {"value": 25.0 + 15.0 \* math.sin(time.time()), "unit": "celsius"}

&nbsp;   

&nbsp;   def read\_humidity(self):

&nbsp;       return {"value": 45.0 + 10.0 \* math.sin(time.time() \* 0.7), "unit": "percent"}

&nbsp;   

&nbsp;   def read\_motion(self):

&nbsp;       # PIR sensor reading

&nbsp;       return {"value": random.choice(\[True, False]), "unit": "boolean"}

&nbsp;   

&nbsp;   def read\_door\_sensor(self):

&nbsp;       # Magnetic door sensor

&nbsp;       return {"value": random.choice(\["open", "closed"]), "unit": "state"}

&nbsp;   

&nbsp;   def read\_light\_level(self):

&nbsp;       # LDR or light sensor

&nbsp;       return {"value": random.randint(0, 1023), "unit": "lux"}

```



\#### 3. Hardware Abstraction Layer

```python

\# GPIO device manager

class DeviceManager:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.devices = {}

&nbsp;       self.init\_devices()

&nbsp;   

&nbsp;   def init\_devices(self):

&nbsp;       """Initialize available GPIO devices"""

&nbsp;       device\_configs = \[

&nbsp;           {"type": "led", "pin": 17, "name": "status\_led"},

&nbsp;           {"type": "led", "pin": 18, "name": "alert\_led"},

&nbsp;           {"type": "servo", "pin": 19, "name": "door\_servo"},

&nbsp;           {"type": "relay", "pin": 20, "name": "pump\_relay"},

&nbsp;           {"type": "button", "pin": 21, "name": "reset\_button"}

&nbsp;       ]

&nbsp;       

&nbsp;       for config in device\_configs:

&nbsp;           try:

&nbsp;               if config\["type"] == "led":

&nbsp;                   self.devices\[config\["name"]] = LED(config\["pin"])

&nbsp;               elif config\["type"] == "servo":

&nbsp;                   from gpiozero import Servo

&nbsp;                   self.devices\[config\["name"]] = Servo(config\["pin"])

&nbsp;               elif config\["type"] == "relay":

&nbsp;                   self.devices\[config\["name"]] = LED(config\["pin"])  # Relay acts like LED

&nbsp;               # Add more device types as needed

&nbsp;               print(f"Initialized {config\['name']} on pin {config\['pin']}")

&nbsp;           except Exception as e:

&nbsp;               print(f"Failed to initialize {config\['name']}: {e}")

```



\#### 4. Advanced Communication Features

```python

\# Mesh networking capabilities

def setup\_peer\_to\_peer():

&nbsp;   """Enable direct communication between client nodes"""

&nbsp;   pass



\# Data buffering for offline scenarios

class DataBuffer:

&nbsp;   def \_\_init\_\_(self, max\_size=1000):

&nbsp;       self.buffer = \[]

&nbsp;       self.max\_size = max\_size

&nbsp;   

&nbsp;   def add\_reading(self, data):

&nbsp;       self.buffer.append(data)

&nbsp;       if len(self.buffer) > self.max\_size:

&nbsp;           self.buffer.pop(0)

&nbsp;   

&nbsp;   def flush\_to\_ap(self):

&nbsp;       """Send buffered data when connection restored"""

&nbsp;       for data in self.buffer:

&nbsp;           # Attempt to send each buffered reading

&nbsp;           pass

```



\### AP-Side Enhancements



\#### 1. Node Management Dashboard

```python

\# Enhanced dashboard features

class NodeManager:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.registered\_nodes = {}

&nbsp;       self.node\_status = {}

&nbsp;   

&nbsp;   def register\_node(self, node\_info):

&nbsp;       """Register a new client node"""

&nbsp;       node\_id = node\_info\["node\_id"]

&nbsp;       self.registered\_nodes\[node\_id] = node\_info

&nbsp;       self.node\_status\[node\_id] = {

&nbsp;           "last\_seen": time.time(),

&nbsp;           "status": "online",

&nbsp;           "alerts": \[]

&nbsp;       }

&nbsp;   

&nbsp;   def update\_node\_status(self, node\_id, data):

&nbsp;       """Update node status from incoming data"""

&nbsp;       if node\_id in self.node\_status:

&nbsp;           self.node\_status\[node\_id]\["last\_seen"] = time.time()

&nbsp;           self.node\_status\[node\_id]\["status"] = "online"

&nbsp;   

&nbsp;   def check\_offline\_nodes(self):

&nbsp;       """Mark nodes as offline if no recent communication"""

&nbsp;       current\_time = time.time()

&nbsp;       for node\_id, status in self.node\_status.items():

&nbsp;           if current\_time - status\["last\_seen"] > 60:  # 60 seconds timeout

&nbsp;               status\["status"] = "offline"

```



\#### 2. Advanced Alerting System

```python

\# Smart alerting with rules engine

class AlertRuleEngine:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.rules = \[

&nbsp;           {"sensor": "temperature", "condition": ">", "threshold": 35, "action": "email"},

&nbsp;           {"sensor": "motion", "condition": "==", "threshold": True, "action": "sms"},

&nbsp;           {"sensor": "door", "condition": "==", "threshold": "open", "action": "notification"}

&nbsp;       ]

&nbsp;   

&nbsp;   def evaluate\_alert(self, sensor\_data):

&nbsp;       """Check if sensor data triggers any alert rules"""

&nbsp;       for rule in self.rules:

&nbsp;           if self.rule\_matches(sensor\_data, rule):

&nbsp;               self.trigger\_action(rule\["action"], sensor\_data)

&nbsp;   

&nbsp;   def rule\_matches(self, data, rule):

&nbsp;       """Evaluate if data matches rule condition"""

&nbsp;       # Implementation of rule matching logic

&nbsp;       pass

```



\#### 3. Data Logging and Analytics

```python

\# Database integration for historical data

import sqlite3

from datetime import datetime, timedelta



class DataLogger:

&nbsp;   def \_\_init\_\_(self, db\_path="/home/admin/sensor\_data.db"):

&nbsp;       self.db\_path = db\_path

&nbsp;       self.init\_database()

&nbsp;   

&nbsp;   def init\_database(self):

&nbsp;       """Create database tables"""

&nbsp;       conn = sqlite3.connect(self.db\_path)

&nbsp;       conn.execute('''

&nbsp;           CREATE TABLE IF NOT EXISTS sensor\_readings (

&nbsp;               id INTEGER PRIMARY KEY AUTOINCREMENT,

&nbsp;               node\_id TEXT,

&nbsp;               sensor\_type TEXT,

&nbsp;               value REAL,

&nbsp;               unit TEXT,

&nbsp;               timestamp DATETIME,

&nbsp;               created\_at DATETIME DEFAULT CURRENT\_TIMESTAMP

&nbsp;           )

&nbsp;       ''')

&nbsp;       conn.commit()

&nbsp;       conn.close()

&nbsp;   

&nbsp;   def log\_reading(self, node\_id, sensor\_type, value, unit, timestamp):

&nbsp;       """Store sensor reading in database"""

&nbsp;       conn = sqlite3.connect(self.db\_path)

&nbsp;       conn.execute('''

&nbsp;           INSERT INTO sensor\_readings (node\_id, sensor\_type, value, unit, timestamp)

&nbsp;           VALUES (?, ?, ?, ?, ?)

&nbsp;       ''', (node\_id, sensor\_type, value, unit, timestamp))

&nbsp;       conn.commit()

&nbsp;       conn.close()

```



\#### 4. Web API for External Integration

```python

\# RESTful API for external systems

@app.route('/api/nodes', methods=\['GET'])

def get\_all\_nodes():

&nbsp;   """Return status of all registered nodes"""

&nbsp;   return jsonify(node\_manager.node\_status)



@app.route('/api/nodes/<node\_id>/command', methods=\['POST'])

def send\_command\_to\_node(node\_id):

&nbsp;   """Send command to specific node"""

&nbsp;   command\_data = request.get\_json()

&nbsp;   # Forward command to target node

&nbsp;   return jsonify({"status": "command\_sent"})



@app.route('/api/data/export', methods=\['GET'])

def export\_sensor\_data():

&nbsp;   """Export historical sensor data"""

&nbsp;   # Return CSV or JSON export of sensor data

&nbsp;   pass

```



\## Step 12: Advanced Features and Integrations



\*\*What this provides:\*\* Enterprise-grade features for professional IoT deployments. Includes API key-based security, mobile app support via WebSocket, and scalability features for multiple access points. These integrations enable secure remote access and the ability to scale to larger installations with multiple access points.



\### Security Enhancements

```python

\# API key authentication

import hashlib

import secrets



class SecurityManager:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.api\_keys = {}

&nbsp;       self.generate\_node\_keys()

&nbsp;   

&nbsp;   def generate\_node\_keys(self):

&nbsp;       """Generate unique API keys for each node"""

&nbsp;       for node\_id in \["pi2", "pi3", "pi4", "pi5"]:

&nbsp;           self.api\_keys\[node\_id] = secrets.token\_urlsafe(32)

&nbsp;   

&nbsp;   def validate\_request(self, node\_id, provided\_key):

&nbsp;       """Validate API key for node authentication"""

&nbsp;       return self.api\_keys.get(node\_id) == provided\_key

```



\### Mobile App Support

```python

\# WebSocket API for real-time mobile updates

from flask\_socketio import SocketIO, emit



socketio = SocketIO(app, cors\_allowed\_origins="\*")



@socketio.on('connect')

def handle\_connect():

&nbsp;   emit('status', {'msg': 'Connected to Pi network'})



@socketio.on('get\_node\_status')

def handle\_node\_status\_request():

&nbsp;   emit('node\_status', node\_manager.node\_status)

```



\### Scalability Features

```python

\# Load balancing for multiple APs

class APCluster:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.access\_points = \[

&nbsp;           {"ip": "192.168.4.1", "load": 0},

&nbsp;           {"ip": "192.168.5.1", "load": 0}

&nbsp;       ]

&nbsp;   

&nbsp;   def get\_least\_loaded\_ap(self):

&nbsp;       """Return AP with lowest node count"""

&nbsp;       return min(self.access\_points, key=lambda ap: ap\["load"])

```



This enhanced configuration provides a robust foundation for a scalable IoT network with multiple Raspberry Pi nodes, comprehensive monitoring, advanced alerting, and integration capabilities for larger automation systems.

y

```



\### Install required packages

```bash

\# Install Python libraries for web server, HTTP requests, and GPIO control

sudo apt install python3-flask python3-requests python3-gpiozero -y



\# Install network management tools (if not already installed)

sudo apt install network-manager -y

```



\## Step 2: WiFi Configuration



\*\*What this provides:\*\* Configures automatic connection to the RPiAP with a static IP address. This ensures the client Pi always gets the same IP address (192.168.4.10) that the dashboard expects, and automatically reconnects to the access point on boot or after network interruptions.



\### Connect to the RPiAP using NetworkManager

```bash

\# Add the RPiAP network

sudo nmcli connection add type wifi con-name RPiAP ssid "RPiAP"



\# Set the WiFi password

sudo nmcli connection modify RPiAP wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Pharos1234"



\# Configure static IP address as expected by the dashboard

sudo nmcli connection modify RPiAP ipv4.addresses 192.168.4.10/24 ipv4.gateway 192.168.4.1 ipv4.method manual



\# Set high priority for auto-connection

sudo nmcli connection modify RPiAP connection.autoconnect yes connection.autoconnect-priority 100



\# Connect to the network

sudo nmcli connection up RPiAP

```



\### Verify connection

```bash

\# Check IP address (should show 192.168.4.10)

ip addr show wlan0



\# Test connectivity to AP

ping -c 3 192.168.4.1

```



\## Step 3: Create Project Directory and Application



\*\*What this provides:\*\* Creates the main client application that runs two services simultaneously: (1) A REST API server that listens for LED control commands from the dashboard, and (2) A sensor monitor that continuously sends simulated temperature data to the access point. The application includes automatic GPIO pin fallback and robust error handling.



\### Create project directory

```bash

mkdir -p /home/admin/client\_project

cd /home/admin/client\_project

```



\### Create the main application file

Create `/home/admin/client\_project/client\_app.py`:



```python

\#!/usr/bin/env python3

\# client\_app.py

import threading

import time

import datetime

import math

import random

import requests

from flask import Flask, request, jsonify

from gpiozero import LED



\# --- Configuration ---

AP\_IP = "192.168.4.1"

ALERT\_ENDPOINT = f"http://{AP\_IP}/api/alert"

LED\_PINS = \[17, 18, 19, 20]  # Try multiple pins in case one is busy



\# --- Flask API Server Setup ---

app = Flask(\_\_name\_\_)



\# Initialize LED with fallback pins

led = None

for pin in LED\_PINS:

&nbsp;   try:

&nbsp;       led = LED(pin)

&nbsp;       print(f"Successfully initialized LED on GPIO pin {pin}")

&nbsp;       break

&nbsp;   except Exception as e:

&nbsp;       print(f"Failed to initialize LED on GPIO pin {pin}: {e}")

&nbsp;       continue



if led is None:

&nbsp;   print("Failed to initialize LED on any available pin")



@app.route('/api/v1/actuators/led', methods=\['POST'])

def handle\_led\_command():

&nbsp;   """Controls the state of an LED."""

&nbsp;   if led is None:

&nbsp;       return jsonify({"error": "LED not available - GPIO initialization failed"}), 503

&nbsp;       

&nbsp;   request\_data = request.get\_json()

&nbsp;   state = request\_data.get('state')

&nbsp;   brightness = request\_data.get('brightness', 100)  # Default to 100% if not specified

&nbsp;   

&nbsp;   print(f"Received LED command: state={state}, brightness={brightness}")

&nbsp;   

&nbsp;   if state == 'on':

&nbsp;       led.on()

&nbsp;       status\_message = "LED turned on"

&nbsp;   elif state == 'off':

&nbsp;       led.off()

&nbsp;       status\_message = "LED turned off"

&nbsp;   else:

&nbsp;       return jsonify({"error": "Invalid state. Use 'on' or 'off'."}), 400

&nbsp;   return jsonify({'status': status\_message})



@app.route('/api/v1/actuators/led/status', methods=\['GET'])

def get\_led\_status():

&nbsp;   """Returns the current state of the LED."""

&nbsp;   if led is None:

&nbsp;       return jsonify({"error": "LED not available - GPIO initialization failed"}), 503

&nbsp;       

&nbsp;   is\_on = led.is\_lit

&nbsp;   return jsonify({'state': 'on' if is\_on else 'off', 'is\_lit': is\_on})



def run\_api\_server():

&nbsp;   """Runs the Flask app."""

&nbsp;   app.run(host='0.0.0.0', port=5000, debug=False, use\_reloader=False)



\# --- Alert Monitor Logic ---

def run\_alert\_monitor():

&nbsp;   """Simulates a sensor and pushes updates to the AP."""

&nbsp;   print("Starting simulated sensor alert monitor...")

&nbsp;   counter = 0

&nbsp;   while True:

&nbsp;       try:

&nbsp;           # Simulate a temperature value cycling smoothly between 10.0 and 40.0

&nbsp;           simulated\_temp = 25.0 + 15.0 \* math.sin(counter)

&nbsp;           counter += 0.1

&nbsp;           print(f"Simulated temp: {simulated\_temp:.2f}°C. Sending update.")

&nbsp;           

&nbsp;           alert\_payload = {

&nbsp;               "pi": "pi2",

&nbsp;               "sensor": "temperature",

&nbsp;               "value": simulated\_temp,

&nbsp;               "unit": "celsius",

&nbsp;               "timestamp": datetime.datetime.now().isoformat()

&nbsp;           }

&nbsp;           

&nbsp;           response = requests.post(ALERT\_ENDPOINT, json=alert\_payload, timeout=5)

&nbsp;           print(f"Response status: {response.status\_code}, Response: {response.text}")

&nbsp;           

&nbsp;       except Exception as e:

&nbsp;           print(f"Alert monitor error: {e}")

&nbsp;       

&nbsp;       # Random sleep between 5 and 30 seconds

&nbsp;       sleep\_time = random.randint(5, 30)

&nbsp;       time.sleep(sleep\_time)



\# --- Main Execution ---

if \_\_name\_\_ == '\_\_main\_\_':

&nbsp;   # Create a thread for the Flask API server

&nbsp;   api\_thread = threading.Thread(target=run\_api\_server)

&nbsp;   api\_thread.daemon = True

&nbsp;   

&nbsp;   # Create a thread for the alert monitor

&nbsp;   monitor\_thread = threading.Thread(target=run\_alert\_monitor)

&nbsp;   monitor\_thread.daemon = True

&nbsp;   

&nbsp;   print("Starting API server thread...")

&nbsp;   api\_thread.start()

&nbsp;   

&nbsp;   print("Starting alert monitor thread...")

&nbsp;   monitor\_thread.start()

&nbsp;   

&nbsp;   # Keep the main thread alive

&nbsp;   while True:

&nbsp;       time.sleep(1)

```



\### Make the script executable

```bash

chmod +x /home/admin/client\_project/client\_app.py

```



\## Step 4: Create Systemd Service for Auto-Start



\*\*What this provides:\*\* Creates a system service that automatically starts the client application on boot and restarts it if it crashes. This ensures the Pi functions autonomously without manual intervention, making it truly "plug-and-play" for the IoT network.



\### Create service file

Create `/home/admin/client\_project/client\_app.service`:



```ini

\[Unit]

Description=Client Pi Application (API and Alert Monitor)

After=network.target



\[Service]

User=admin

WorkingDirectory=/home/admin/client\_project

ExecStart=/usr/bin/python3 /home/admin/client\_project/client\_app.py

Restart=always



\[Install]

WantedBy=multi-user.target

```



\### Install and enable the service

```bash

\# Copy service file to systemd directory

sudo cp /home/admin/client\_project/client\_app.service /etc/systemd/system/



\# Reload systemd to recognize the new service

sudo systemctl daemon-reload



\# Enable the service to start automatically on boot

sudo systemctl enable client\_app.service



\# Start the service immediately

sudo systemctl start client\_app.service

```



\### Verify service is running

```bash

\# Check service status

sudo systemctl status client\_app.service



\# Follow live logs

journalctl -u client\_app.service -f

```



\## Step 5: GPIO Permissions Setup



\*\*What this provides:\*\* Grants the user account proper permissions to control GPIO pins without requiring root privileges. This is essential for LED control, sensor reading, and other hardware interactions while maintaining system security.



\### Add user to GPIO group

```bash

sudo usermod -a -G gpio admin

```



\### Verify group membership

```bash

groups admin

```



\## Step 6: Testing and Verification



\*\*What this provides:\*\* Comprehensive testing procedures to verify that all components work correctly: network connectivity, sensor data transmission, and LED control via REST API. These tests confirm the client Pi is fully functional before putting it into production use.



\### Test network connectivity

```bash

\# Verify IP address

ip addr show wlan0



\# Test AP connectivity

ping -c 3 192.168.4.1



\# Test HTTP endpoint

curl -X POST http://192.168.4.1/api/alert -H "Content-Type: application/json" -d '{"pi":"pi2","sensor":"temperature","value":25.5,"unit":"celsius","timestamp":"2025-07-19T11:30:00"}'

```



\### Test LED control (from another device on the network)

```bash

\# Turn LED on

curl -X POST http://192.168.4.10:5000/api/v1/actuators/led -H "Content-Type: application/json" -d '{"state":"on","brightness":100}'



\# Turn LED off

curl -X POST http://192.168.4.10:5000/api/v1/actuators/led -H "Content-Type: application/json" -d '{"state":"off"}'



\# Check LED status

curl http://192.168.4.10:5000/api/v1/actuators/led/status

```



\## Step 7: Service Management Commands



\*\*What this provides:\*\* Essential commands for ongoing maintenance and troubleshooting of the client service. These commands allow you to start, stop, restart, and monitor the client application, as well as view logs for debugging issues.



\### Useful commands for managing the service

```bash

\# Check service status

sudo systemctl status client\_app.service



\# Start the service

sudo systemctl start client\_app.service



\# Stop the service

sudo systemctl stop client\_app.service



\# Restart the service

sudo systemctl restart client\_app.service



\# View recent logs

journalctl -u client\_app.service -n 50



\# Follow live logs

journalctl -u client\_app.service -f



\# Disable auto-start (if needed)

sudo systemctl disable client\_app.service

```



\## Step 8: Troubleshooting



\*\*What this provides:\*\* Solutions to common problems you may encounter during setup or operation, including GPIO conflicts, network connectivity issues, service startup failures, and port conflicts. This section helps you quickly diagnose and resolve issues without starting over.



\### Common issues and solutions



\#### GPIO "busy" error

\- Try different GPIO pins (script automatically tries pins 17, 18, 19, 20)

\- Reboot the Pi to clear any held GPIO resources

\- Check for other processes using GPIO: `sudo lsof /dev/gpiomem`



\#### Network connectivity issues

\- Verify WiFi connection: `nmcli connection show --active`

\- Check IP assignment: `ip addr show wlan0`

\- Test AP connectivity: `ping 192.168.4.1`



\#### Service fails to start

\- Check service logs: `journalctl -u client\_app.service`

\- Verify Python dependencies: `python3 -c "import flask, requests, gpiozero"`

\- Check file permissions: `ls -la /home/admin/client\_project/`



\#### Port conflicts

\- Check what's using port 5000: `sudo lsof -i :5000`

\- Kill conflicting processes: `sudo pkill -f client\_app.py`



\## Current Configuration Summary



\*\*Network Configuration:\*\*

\- SSID: RPiAP

\- Password: Pharos1234

\- Static IP: 192.168.4.10/24

\- Gateway: 192.168.4.1



\*\*Application Features:\*\*

\- Temperature sensor simulation (sends data every 5-30 seconds randomly)

\- LED control via GPIO pin 17 (fallback to 18, 19, 20)

\- REST API server on port 5000

\- Auto-connects to RPiAP on boot

\- Auto-starts application service on boot

\- Automatic service restart on failure



\*\*API Endpoints:\*\*

\- POST `/api/v1/actuators/led` - Control LED (expects: `{"state":"on/off","brightness":100}`)

\- GET `/api/v1/actuators/led/status` - Get LED status



\*\*Data Format Sent to AP:\*\*

```json

{

&nbsp;   "pi": "pi2",

&nbsp;   "sensor": "temperature",

&nbsp;   "value": 25.5,

&nbsp;   "unit": "celsius",

&nbsp;   "timestamp": "2025-07-19T11:30:00.000000"

}

```



This configuration creates a fully autonomous client Pi that will automatically connect to the RPiAP and begin sending sensor data and accepting control commands as soon as it boots up.



\## Step 9: RPiAP (Access Point) Setup Guide



\*\*What this provides:\*\* Complete instructions for setting up the central Raspberry Pi that acts as the WiFi access point and dashboard server. This creates the network hub that all client Pis connect to, including WiFi access point functionality, DHCP server for IP assignment, and the web dashboard for monitoring and controlling all connected nodes.



This section covers setting up the Raspberry Pi Access Point that manages the client nodes.



\### RPiAP Prerequisites

\- Raspberry Pi with WiFi capability (Pi 3B+ or newer recommended)

\- Fresh Raspberry Pi OS installation

\- Ethernet connection for internet access (optional but recommended)



\### Install Access Point Software

```bash

\# Update system

sudo apt update \&\& sudo apt upgrade -y



\# Install hostapd and dnsmasq for AP functionality

sudo apt install hostapd dnsmasq -y



\# Install Python packages for dashboard

sudo apt install python3-flask python3-socketio python3-requests python3-gpiozero -y

```



\### Configure Access Point

```bash

\# Configure hostapd

sudo nano /etc/hostapd/hostapd.conf

```



Add the following configuration:

```

interface=wlan0

driver=nl80211

ssid=RPiAP

hw\_mode=g

channel=7

wmm\_enabled=0

macaddr\_acl=0

auth\_algs=1

ignore\_broadcast\_ssid=0

wpa=2

wpa\_passphrase=Pharos1234

wpa\_key\_mgmt=WPA-PSK

wpa\_pairwise=TKIP

rsn\_pairwise=CCMP

```



\### Configure DHCP Server

```bash

\# Backup original dnsmasq config

sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup



\# Configure dnsmasq

sudo nano /etc/dnsmasq.conf

```



Add these lines:

```

interface=wlan0

dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h

dhcp-option=3,192.168.4.1

dhcp-option=6,192.168.4.1

```



\### Configure Network Interface

```bash

\# Configure static IP for wlan0

sudo nano /etc/dhcpcd.conf

```



Add at the end:

```

interface wlan0

static ip\_address=192.168.4.1/24

nohook wpa\_supplicant

```



\### Enable Services

```bash

\# Enable and start services

sudo systemctl enable hostapd

sudo systemctl enable dnsmasq



\# Configure hostapd daemon

echo 'DAEMON\_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd



\# Reboot to apply changes

sudo reboot

```



\### Create Dashboard Application

Create `/home/admin/dashboard\_project/app.py` with your dashboard code, then create the service:



```bash

\# Create dashboard service

sudo nano /etc/systemd/system/dashboard.service

```



```ini

\[Unit]

Description=Dashboard Web Server for Pi Control

After=network.target



\[Service]

User=root

WorkingDirectory=/home/admin/dashboard\_project

ExecStart=/usr/bin/python3 /home/admin/dashboard\_project/app.py

Restart=always



\[Install]

WantedBy=multi-user.target

```



```bash

\# Enable dashboard service

sudo systemctl daemon-reload

sudo systemctl enable dashboard.service

sudo systemctl start dashboard.service

```



\## Step 10: IP Address Management Enhancement



\*\*What this provides:\*\* Advanced networking configuration that eliminates hardcoded IP addresses. Implements dynamic IP discovery and DHCP reservations, making the system more flexible and easier to deploy. Client Pis can automatically find the access point and get appropriate IP addresses without manual configuration.



Instead of hardcoding IP addresses, implement dynamic IP discovery and configuration.



\### Option 1: DHCP with Hostname Resolution

Modify the client application to use hostnames instead of fixed IPs:



```python

\# In client\_app.py, replace static IP configuration

import socket



def get\_ap\_ip():

&nbsp;   """Discover AP IP via gateway"""

&nbsp;   try:

&nbsp;       # Get default gateway (should be the AP)

&nbsp;       import subprocess

&nbsp;       result = subprocess.run(\['ip', 'route', 'show', 'default'], 

&nbsp;                             capture\_output=True, text=True)

&nbsp;       gateway\_line = result.stdout.strip()

&nbsp;       if gateway\_line:

&nbsp;           return gateway\_line.split()\[2]  # Extract gateway IP

&nbsp;       return "192.168.4.1"  # Fallback

&nbsp;   except:

&nbsp;       return "192.168.4.1"



def get\_my\_ip():

&nbsp;   """Get our current IP address"""

&nbsp;   try:

&nbsp;       s = socket.socket(socket.AF\_INET, socket.SOCK\_DGRAM)

&nbsp;       s.connect(("8.8.8.8", 80))

&nbsp;       ip = s.getsockname()\[0]

&nbsp;       s.close()

&nbsp;       return ip

&nbsp;   except:

&nbsp;       return "192.168.4.10"



\# Use dynamic discovery

AP\_IP = get\_ap\_ip()

MY\_IP = get\_my\_ip()

```



\### Option 2: Use DHCP Reservations on AP

Configure the AP to assign specific IPs based on MAC addresses:



```bash

\# On the AP, edit dnsmasq configuration

sudo nano /etc/dnsmasq.conf

```



Add MAC-based reservations:

```

\# DHCP reservations for specific clients

dhcp-host=aa:bb:cc:dd:ee:ff,pi2,192.168.4.10

dhcp-host=11:22:33:44:55:66,pi3,192.168.4.11

dhcp-host=77:88:99:aa:bb:cc,pi4,192.168.4.12

```



\## Step 11: Multi-Pi Network Enhancements



\*\*What this provides:\*\* Advanced features for scaling beyond a simple client-server setup. Includes automatic node discovery, support for multiple sensor types (temperature, humidity, motion, door, light), hardware abstraction for easy device management, and data buffering for offline resilience. These enhancements transform the basic setup into a robust IoT network capable of supporting 3-5+ Pi nodes with diverse sensor and actuator capabilities.



\### Client-Side Enhancements



\#### 1. Node Auto-Discovery and Registration

```python

\# Add to client\_app.py

import uuid

import psutil



def register\_with\_ap():

&nbsp;   """Register this node with the AP"""

&nbsp;   node\_info = {

&nbsp;       "node\_id": f"pi{socket.gethostname().split('-')\[-1]}",

&nbsp;       "mac\_address": get\_mac\_address(),

&nbsp;       "ip\_address": get\_my\_ip(),

&nbsp;       "hostname": socket.gethostname(),

&nbsp;       "capabilities": \["temperature", "led", "gpio"],

&nbsp;       "last\_boot": psutil.boot\_time()

&nbsp;   }

&nbsp;   

&nbsp;   try:

&nbsp;       response = requests.post(f"http://{AP\_IP}/api/register", 

&nbsp;                              json=node\_info, timeout=10)

&nbsp;       print(f"Registration response: {response.status\_code}")

&nbsp;   except Exception as e:

&nbsp;       print(f"Registration failed: {e}")



def get\_mac\_address():

&nbsp;   """Get WiFi interface MAC address"""

&nbsp;   import netifaces

&nbsp;   try:

&nbsp;       return netifaces.ifaddresses('wlan0')\[netifaces.AF\_LINK]\[0]\['addr']

&nbsp;   except:

&nbsp;       return "unknown"

```



\#### 2. Multiple Sensor Support

```python

\# Enhanced sensor system

class SensorManager:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.sensors = {

&nbsp;           "temperature": self.read\_temperature,

&nbsp;           "humidity": self.read\_humidity,

&nbsp;           "motion": self.read\_motion,

&nbsp;           "door": self.read\_door\_sensor,

&nbsp;           "light": self.read\_light\_level

&nbsp;       }

&nbsp;   

&nbsp;   def read\_temperature(self):

&nbsp;       # Actual sensor reading or simulation

&nbsp;       return {"value": 25.0 + 15.0 \* math.sin(time.time()), "unit": "celsius"}

&nbsp;   

&nbsp;   def read\_humidity(self):

&nbsp;       return {"value": 45.0 + 10.0 \* math.sin(time.time() \* 0.7), "unit": "percent"}

&nbsp;   

&nbsp;   def read\_motion(self):

&nbsp;       # PIR sensor reading

&nbsp;       return {"value": random.choice(\[True, False]), "unit": "boolean"}

&nbsp;   

&nbsp;   def read\_door\_sensor(self):

&nbsp;       # Magnetic door sensor

&nbsp;       return {"value": random.choice(\["open", "closed"]), "unit": "state"}

&nbsp;   

&nbsp;   def read\_light\_level(self):

&nbsp;       # LDR or light sensor

&nbsp;       return {"value": random.randint(0, 1023), "unit": "lux"}

```



\#### 3. Hardware Abstraction Layer

```python

\# GPIO device manager

class DeviceManager:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.devices = {}

&nbsp;       self.init\_devices()

&nbsp;   

&nbsp;   def init\_devices(self):

&nbsp;       """Initialize available GPIO devices"""

&nbsp;       device\_configs = \[

&nbsp;           {"type": "led", "pin": 17, "name": "status\_led"},

&nbsp;           {"type": "led", "pin": 18, "name": "alert\_led"},

&nbsp;           {"type": "servo", "pin": 19, "name": "door\_servo"},

&nbsp;           {"type": "relay", "pin": 20, "name": "pump\_relay"},

&nbsp;           {"type": "button", "pin": 21, "name": "reset\_button"}

&nbsp;       ]

&nbsp;       

&nbsp;       for config in device\_configs:

&nbsp;           try:

&nbsp;               if config\["type"] == "led":

&nbsp;                   self.devices\[config\["name"]] = LED(config\["pin"])

&nbsp;               elif config\["type"] == "servo":

&nbsp;                   from gpiozero import Servo

&nbsp;                   self.devices\[config\["name"]] = Servo(config\["pin"])

&nbsp;               elif config\["type"] == "relay":

&nbsp;                   self.devices\[config\["name"]] = LED(config\["pin"])  # Relay acts like LED

&nbsp;               # Add more device types as needed

&nbsp;               print(f"Initialized {config\['name']} on pin {config\['pin']}")

&nbsp;           except Exception as e:

&nbsp;               print(f"Failed to initialize {config\['name']}: {e}")

```



\#### 4. Advanced Communication Features

```python

\# Mesh networking capabilities

def setup\_peer\_to\_peer():

&nbsp;   """Enable direct communication between client nodes"""

&nbsp;   pass



\# Data buffering for offline scenarios

class DataBuffer:

&nbsp;   def \_\_init\_\_(self, max\_size=1000):

&nbsp;       self.buffer = \[]

&nbsp;       self.max\_size = max\_size

&nbsp;   

&nbsp;   def add\_reading(self, data):

&nbsp;       self.buffer.append(data)

&nbsp;       if len(self.buffer) > self.max\_size:

&nbsp;           self.buffer.pop(0)

&nbsp;   

&nbsp;   def flush\_to\_ap(self):

&nbsp;       """Send buffered data when connection restored"""

&nbsp;       for data in self.buffer:

&nbsp;           # Attempt to send each buffered reading

&nbsp;           pass

```



\### AP-Side Enhancements



\#### 1. Node Management Dashboard

```python

\# Enhanced dashboard features

class NodeManager:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.registered\_nodes = {}

&nbsp;       self.node\_status = {}

&nbsp;   

&nbsp;   def register\_node(self, node\_info):

&nbsp;       """Register a new client node"""

&nbsp;       node\_id = node\_info\["node\_id"]

&nbsp;       self.registered\_nodes\[node\_id] = node\_info

&nbsp;       self.node\_status\[node\_id] = {

&nbsp;           "last\_seen": time.time(),

&nbsp;           "status": "online",

&nbsp;           "alerts": \[]

&nbsp;       }

&nbsp;   

&nbsp;   def update\_node\_status(self, node\_id, data):

&nbsp;       """Update node status from incoming data"""

&nbsp;       if node\_id in self.node\_status:

&nbsp;           self.node\_status\[node\_id]\["last\_seen"] = time.time()

&nbsp;           self.node\_status\[node\_id]\["status"] = "online"

&nbsp;   

&nbsp;   def check\_offline\_nodes(self):

&nbsp;       """Mark nodes as offline if no recent communication"""

&nbsp;       current\_time = time.time()

&nbsp;       for node\_id, status in self.node\_status.items():

&nbsp;           if current\_time - status\["last\_seen"] > 60:  # 60 seconds timeout

&nbsp;               status\["status"] = "offline"

```



\#### 2. Advanced Alerting System

```python

\# Smart alerting with rules engine

class AlertRuleEngine:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.rules = \[

&nbsp;           {"sensor": "temperature", "condition": ">", "threshold": 35, "action": "email"},

&nbsp;           {"sensor": "motion", "condition": "==", "threshold": True, "action": "sms"},

&nbsp;           {"sensor": "door", "condition": "==", "threshold": "open", "action": "notification"}

&nbsp;       ]

&nbsp;   

&nbsp;   def evaluate\_alert(self, sensor\_data):

&nbsp;       """Check if sensor data triggers any alert rules"""

&nbsp;       for rule in self.rules:

&nbsp;           if self.rule\_matches(sensor\_data, rule):

&nbsp;               self.trigger\_action(rule\["action"], sensor\_data)

&nbsp;   

&nbsp;   def rule\_matches(self, data, rule):

&nbsp;       """Evaluate if data matches rule condition"""

&nbsp;       # Implementation of rule matching logic

&nbsp;       pass

```



\#### 3. Data Logging and Analytics

```python

\# Database integration for historical data

import sqlite3

from datetime import datetime, timedelta



class DataLogger:

&nbsp;   def \_\_init\_\_(self, db\_path="/home/admin/sensor\_data.db"):

&nbsp;       self.db\_path = db\_path

&nbsp;       self.init\_database()

&nbsp;   

&nbsp;   def init\_database(self):

&nbsp;       """Create database tables"""

&nbsp;       conn = sqlite3.connect(self.db\_path)

&nbsp;       conn.execute('''

&nbsp;           CREATE TABLE IF NOT EXISTS sensor\_readings (

&nbsp;               id INTEGER PRIMARY KEY AUTOINCREMENT,

&nbsp;               node\_id TEXT,

&nbsp;               sensor\_type TEXT,

&nbsp;               value REAL,

&nbsp;               unit TEXT,

&nbsp;               timestamp DATETIME,

&nbsp;               created\_at DATETIME DEFAULT CURRENT\_TIMESTAMP

&nbsp;           )

&nbsp;       ''')

&nbsp;       conn.commit()

&nbsp;       conn.close()

&nbsp;   

&nbsp;   def log\_reading(self, node\_id, sensor\_type, value, unit, timestamp):

&nbsp;       """Store sensor reading in database"""

&nbsp;       conn = sqlite3.connect(self.db\_path)

&nbsp;       conn.execute('''

&nbsp;           INSERT INTO sensor\_readings (node\_id, sensor\_type, value, unit, timestamp)

&nbsp;           VALUES (?, ?, ?, ?, ?)

&nbsp;       ''', (node\_id, sensor\_type, value, unit, timestamp))

&nbsp;       conn.commit()

&nbsp;       conn.close()

```



\#### 4. Web API for External Integration

```python

\# RESTful API for external systems

@app.route('/api/nodes', methods=\['GET'])

def get\_all\_nodes():

&nbsp;   """Return status of all registered nodes"""

&nbsp;   return jsonify(node\_manager.node\_status)



@app.route('/api/nodes/<node\_id>/command', methods=\['POST'])

def send\_command\_to\_node(node\_id):

&nbsp;   """Send command to specific node"""

&nbsp;   command\_data = request.get\_json()

&nbsp;   # Forward command to target node

&nbsp;   return jsonify({"status": "command\_sent"})



@app.route('/api/data/export', methods=\['GET'])

def export\_sensor\_data():

&nbsp;   """Export historical sensor data"""

&nbsp;   # Return CSV or JSON export of sensor data

&nbsp;   pass

```



\## Step 12: Advanced Features and Integrations



\*\*What this provides:\*\* Enterprise-grade features for professional IoT deployments. Includes API key-based security, mobile app support via WebSocket, and scalability features for multiple access points. These integrations enable secure remote access and the ability to scale to larger installations with multiple access points.



\### Security Enhancements

```python

\# API key authentication

import hashlib

import secrets



class SecurityManager:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.api\_keys = {}

&nbsp;       self.generate\_node\_keys()

&nbsp;   

&nbsp;   def generate\_node\_keys(self):

&nbsp;       """Generate unique API keys for each node"""

&nbsp;       for node\_id in \["pi2", "pi3", "pi4", "pi5"]:

&nbsp;           self.api\_keys\[node\_id] = secrets.token\_urlsafe(32)

&nbsp;   

&nbsp;   def validate\_request(self, node\_id, provided\_key):

&nbsp;       """Validate API key for node authentication"""

&nbsp;       return self.api\_keys.get(node\_id) == provided\_key

```



\### Mobile App Support

```python

\# WebSocket API for real-time mobile updates

from flask\_socketio import SocketIO, emit



socketio = SocketIO(app, cors\_allowed\_origins="\*")



@socketio.on('connect')

def handle\_connect():

&nbsp;   emit('status', {'msg': 'Connected to Pi network'})



@socketio.on('get\_node\_status')

def handle\_node\_status\_request():

&nbsp;   emit('node\_status', node\_manager.node\_status)

```



\### Scalability Features

```python

\# Load balancing for multiple APs

class APCluster:

&nbsp;   def \_\_init\_\_(self):

&nbsp;       self.access\_points = \[

&nbsp;           {"ip": "192.168.4.1", "load": 0},

&nbsp;           {"ip": "192.168.5.1", "load": 0}

&nbsp;       ]

&nbsp;   

&nbsp;   def get\_least\_loaded\_ap(self):

&nbsp;       """Return AP with lowest node count"""

&nbsp;       return min(self.access\_points, key=lambda ap: ap\["load"])

```



This enhanced configuration provides a robust foundation for a scalable IoT network with multiple Raspberry Pi nodes, comprehensive monitoring, advanced alerting, and integration capabilities for larger automation systems.



