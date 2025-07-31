# Raspberry Pi IoT Network Project - AI Coding Guidelines

## Project Architecture Overview

This is a headless Raspberry Pi IoT network with automated deployment focusing on industrial-grade reliability and zero-touch provisioning.

### Core Architecture Patterns

**Dual-Mode Design**: Every node can function as either Access Point or Client for redundancy

- **Apple** (apple-pie): Primary AP at `192.168.4.1` broadcasting hidden "Apple" network
- **Clients**: Pumpkin(`192.168.4.10`), Cherry(`192.168.4.11`), Pecan(`192.168.4.12`), Peach(`192.168.4.13`)
- **Authentication**: All nodes use `admin:001234` with SSH key-based deployment

**Network Stack**: NetworkManager-based (not wpa_supplicant), supports automatic failover and hidden SSID handling

**Application Pattern**: Multi-threaded Python Flask apps with WebSocket support running as systemd services

- API thread: REST endpoints for actuator control
- Monitor thread: Sensor data collection and heartbeat transmission
- WebSocket thread: Real-time updates to web dashboard using Flask-SocketIO
- UART thread: Device communication and status logging
- Background services: Network monitoring and auto-reconnection

**Hardware Standard**: Each Pi has identical hardware setup

- 2 GPIO LEDs for status indication and control
- 1 UART device for external hardware communication
- All nodes capable of AP failover operation

## Critical Development Workflows

### Deployment Pipeline (Zero-Touch Provisioning)

**Fresh Pi Setup** (`setup-fresh-pi-official.sh`):

```bash
# Windows: ./setup-fresh-pi-official.sh /d
# Creates: ssh, userconf.txt, wpa_supplicant.conf on SD boot partition
# Handles Windows drive notation (D: → /d) for Git Bash compatibility
```

**Validation** (`validate-fresh-pi-official.sh`):

- Verifies all boot files created correctly
- Checks WiFi configuration format
- Validates SSH enablement

**One-Click Deployment** (`deploy-one-click-official.sh <ip> <node-name>`):

- SSH key-based authentication (no password prompts)
- Uploads and executes setup scripts remotely
- Handles network switch during WiFi reconfiguration
- Example: `./deploy-one-click-official.sh 192.168.86.56 pumpkin`

### Service Management Patterns

**Systemd Service Architecture**:

- Client services: Run as `User=admin` with GPIO group membership
- AP dashboard: Run as `User=root` for port 80 binding
- All services: `Restart=always`, `After=network.target`

**Essential Commands**:

```bash
# Service control
sudo systemctl status client_app.service
journalctl -u client_app.service -f

# GPIO permissions setup (required after deployment)
sudo usermod -a -G gpio admin  # Requires reboot

# Network troubleshooting
nmcli connection show --active
nmcli connection up Apple-Connection
```

## Project-Specific Patterns

### Multi-Threaded Client Architecture

Every client node follows this exact pattern:

```python
# Four daemon threads: API server + sensor monitor + WebSocket + UART
api_thread = threading.Thread(target=run_flask_server, daemon=True)
sensor_thread = threading.Thread(target=sensor_monitor, daemon=True)
uart_thread = threading.Thread(target=uart_monitor, daemon=True)

# Flask-SocketIO for real-time web updates
from flask_socketio import SocketIO, emit
socketio = SocketIO(app, cors_allowed_origins="*")

# Name-based API routing
@app.route(f'/{NODE_NAME}/api/v1/status', methods=['GET'])
@app.route(f'/{NODE_NAME}/api/v1/actuators/led', methods=['GET', 'POST'])
@app.route(f'/{NODE_NAME}/api/v1/uart/status', methods=['GET'])
```

### Standard Hardware Configuration

Each Pi has identical hardware setup:

```python
# Standard GPIO pin assignments
LED_PINS = [17, 18]  # Two LEDs per Pi
UART_DEVICE = "/dev/ttyUSB0"  # External device connection

# Hardware manager with fallback
class HardwareManager:
    def __init__(self):
        self.leds = []
        self.setup_leds()
        self.setup_uart()

    def setup_leds(self):
        for pin in LED_PINS:
            try:
                self.leds.append(LED(pin))
            except Exception as e:
                logger.warning(f"LED on pin {pin} failed: {e}")
```

### AP Failover Implementation

Automatic failover when Apple AP becomes unavailable:

```python
def monitor_ap_health():
    """Monitor primary AP and trigger failover if needed"""
    while True:
        if not ping_apple_ap() and should_become_ap():
            logger.info("Apple AP down, becoming backup AP")
            switch_to_ap_mode()
            broadcast_new_ap_announcement()
        time.sleep(30)

def switch_to_ap_mode():
    """Convert client to AP mode for failover"""
    stop_client_services()
    configure_ap_network()
    start_ap_services()
    update_ip_to_gateway()
```

### GPIO Fallback Strategy

Hardware control with automatic pin fallback:

```python
# Standard GPIO pin sequence for device conflicts
LED_PINS = [17, 18, 19, 20]
for pin in LED_PINS:
    try:
        device_manager.led = LED(pin)
        break
    except Exception as e:
        logger.warning(f"GPIO pin {pin} busy: {e}")
```

### WebSocket Real-Time Updates

Flask-SocketIO enables real-time communication between all Pis and the web dashboard:

```python
# AP Dashboard WebSocket implementation
@socketio.on('connect')
def handle_connect():
    emit('status', {'message': 'Connected to Apple IoT Network'})

@socketio.on('led_control')
def handle_led_control(data):
    node = data['node']
    state = data['state']
    # Forward to target Pi and broadcast result
    result = control_node_led(node, state)
    emit('led_update', {'node': node, 'state': state, 'success': result}, broadcast=True)

@socketio.on('request_uart_logs')
def handle_uart_request(data):
    node = data['node']
    logs = get_recent_uart_logs(node)
    emit('uart_logs', {'node': node, 'logs': logs})

# Client Pi WebSocket forwarding
def forward_uart_to_ap(message):
    """Forward UART messages to AP for dashboard display"""
    socketio.emit('uart_message', {
        'node': NODE_NAME,
        'message': message,
        'timestamp': datetime.now().isoformat()
    })
```

### Web Dashboard UI Layout Specification

The dashboard must match this exact layout structure:

**Header Section**:

- UTC timestamp display (top center): `XX:XX:XX UTC`

**Left Panel - Node Status Cards** (Pi 1 through Pi 5):

- Each Pi has a dedicated status card with:
  - **Status Indicators**: `Status: ● Ready` (green circle), `Rx: ●` (active/inactive), `TX Active: ●` (active/inactive)
  - **Command Counter**: `Tx Count: X` (number of commands sent)
  - **Timestamps**: `Last Command Received: With time stamp`, `Current Status: With time stamp`

**Right Panel Top - Command Interface**:

- **Commands Section**:
  - `Command:` dropdown with "Drop down list of commands"
  - **Send To** selector with individual Pi buttons (Pi 1, Pi 2, Pi 3, Pi 4, Pi 5) and "All" option
  - **SEND** button (yellow/prominent)
  - **Reset All** button (yellow/prominent)

**Right Panel Bottom - Logging Interface**:

- **Logs** tab and **Device Select** tab (yellow highlighting)
- **Active Log** area with scroll function for real-time UART messages
- Scrollable text area showing timestamped messages from all Pis

```html
<!-- Dashboard Layout Structure -->
<div class="dashboard-container">
  <!-- Header -->
  <div class="header">
    <div class="utc-time">XX:XX:XX UTC</div>
  </div>

  <!-- Main Content -->
  <div class="main-content">
    <!-- Left Panel - Node Status -->
    <div class="left-panel">
      <div class="node-card" id="pi1">
        <div class="node-header">Pi 1</div>
        <div class="status-line">
          Status: <span class="status-indicator ready">●</span> Ready
        </div>
        <div class="activity-line">
          Rx: <span class="rx-indicator">●</span> TX Active:
          <span class="tx-indicator">●</span>
        </div>
        <div class="counter-line">
          Tx Count: <span class="tx-count">X</span>
        </div>
        <div class="timestamp-line">
          Last Command Received:
          <span class="last-command">With time stamp</span>
        </div>
        <div class="status-line">
          Current Status: <span class="current-status">With time stamp</span>
        </div>
      </div>
      <!-- Repeat for Pi 2-5 -->
    </div>

    <!-- Right Panel -->
    <div class="right-panel">
      <!-- Command Interface -->
      <div class="command-section">
        <div class="commands-header">Commands</div>
        <div class="command-input">
          <label>Command:</label>
          <select id="command-dropdown">
            <option>Drop down list of commands</option>
          </select>
        </div>
        <div class="send-to-section">
          <label>Send to:</label>
          <div class="pi-buttons">
            <button class="pi-btn">Pi 1</button>
            <button class="pi-btn">Pi 2</button>
            <button class="pi-btn">Pi 3</button>
            <button class="pi-btn">Pi 4</button>
            <button class="pi-btn">Pi 5</button>
            <button class="pi-btn all-btn">All</button>
          </div>
        </div>
        <div class="action-buttons">
          <button class="send-btn">SEND</button>
          <button class="reset-btn">Reset All</button>
        </div>
      </div>

      <!-- Logging Interface -->
      <div class="logging-section">
        <div class="log-tabs">
          <button class="tab-btn active">Logs</button>
          <button class="tab-btn">Device Select</button>
        </div>
        <div class="log-area">
          <div class="log-content" id="active-log">
            Active Log with scroll function
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
```

### Web Dashboard UI Components

Real-time web interface implementing the above layout:

```javascript
// Dashboard WebSocket client
const socket = io();

// LED control buttons with visual feedback
function toggleLED(nodeName, ledIndex) {
  socket.emit("led_control", {
    node: nodeName,
    led: ledIndex,
    state: document.getElementById(`${nodeName}_led${ledIndex}`).checked,
  });
}

// Real-time UART log display
socket.on("uart_message", function (data) {
  const logArea = document.getElementById("active-log");
  const timestamp = new Date(data.timestamp).toLocaleTimeString();
  logArea.innerHTML += `[${timestamp}] ${data.node}: ${data.message}\n`;
  logArea.scrollTop = logArea.scrollHeight;
});

// Update Pi status indicators
function updatePiStatus(
  piNumber,
  status,
  rxActive,
  txActive,
  txCount,
  lastCommand,
  currentStatus
) {
  const piCard = document.getElementById(`pi${piNumber}`);
  piCard.querySelector(
    ".status-indicator"
  ).className = `status-indicator ${status.toLowerCase()}`;
  piCard.querySelector(".rx-indicator").className = rxActive
    ? "rx-indicator active"
    : "rx-indicator";
  piCard.querySelector(".tx-indicator").className = txActive
    ? "tx-indicator active"
    : "tx-indicator";
  piCard.querySelector(".tx-count").textContent = txCount;
  piCard.querySelector(".last-command").textContent = lastCommand;
  piCard.querySelector(".current-status").textContent = currentStatus;
}

// UTC time updates
function updateUTCTime() {
  const now = new Date();
  const utcTime = now.toUTCString().split(" ")[4];
  document.querySelector(".utc-time").textContent = `${utcTime} UTC`;
}
setInterval(updateUTCTime, 1000);
```

### Dashboard CSS Styling Requirements

```css
/* Dashboard layout matching the provided mockup */
.dashboard-container {
  font-family: Arial, sans-serif;
  padding: 10px;
  background-color: #f5f5f5;
}

.header {
  text-align: center;
  margin-bottom: 15px;
}

.utc-time {
  background-color: yellow;
  padding: 5px 15px;
  border: 2px solid #000;
  display: inline-block;
  font-weight: bold;
}

.main-content {
  display: flex;
  gap: 15px;
  height: calc(100vh - 100px);
}

/* Left Panel - Node Status Cards */
.left-panel {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.node-card {
  border: 2px solid #007acc;
  border-radius: 8px;
  padding: 10px;
  background-color: white;
  min-height: 100px;
}

.node-header {
  background-color: #007acc;
  color: white;
  padding: 5px;
  margin: -10px -10px 10px -10px;
  font-weight: bold;
}

.status-indicator.ready {
  color: green;
}
.status-indicator.offline {
  color: red;
}
.status-indicator.warning {
  color: orange;
}

.rx-indicator.active,
.tx-indicator.active {
  color: green;
}
.rx-indicator,
.tx-indicator {
  color: gray;
}

/* Right Panel */
.right-panel {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 15px;
}

/* Command Section */
.command-section {
  border: 2px solid #007acc;
  border-radius: 8px;
  padding: 15px;
  background-color: white;
}

.commands-header {
  background-color: #007acc;
  color: white;
  padding: 5px;
  margin: -15px -15px 15px -15px;
  font-weight: bold;
}

.pi-buttons {
  display: flex;
  gap: 5px;
  flex-wrap: wrap;
  margin: 10px 0;
}

.pi-btn {
  padding: 5px 10px;
  border: 2px solid #007acc;
  border-radius: 4px;
  background-color: white;
  cursor: pointer;
}

.pi-btn.active {
  background-color: #007acc;
  color: white;
}

.action-buttons {
  display: flex;
  gap: 10px;
  margin-top: 15px;
}

.send-btn,
.reset-btn {
  padding: 8px 20px;
  background-color: yellow;
  border: 2px solid #000;
  border-radius: 4px;
  font-weight: bold;
  cursor: pointer;
}

/* Logging Section */
.logging-section {
  border: 2px solid #007acc;
  border-radius: 8px;
  background-color: white;
  flex: 1;
  display: flex;
  flex-direction: column;
}

.log-tabs {
  display: flex;
  border-bottom: 2px solid #007acc;
}

.tab-btn {
  padding: 10px 20px;
  border: none;
  background-color: white;
  cursor: pointer;
  border-right: 1px solid #007acc;
}

.tab-btn.active {
  background-color: yellow;
  font-weight: bold;
}

.log-area {
  flex: 1;
  padding: 10px;
}

.log-content {
  width: 100%;
  height: 100%;
  border: 1px solid #ccc;
  padding: 10px;
  font-family: monospace;
  font-size: 12px;
  overflow-y: auto;
  background-color: #fafafa;
  white-space: pre-wrap;
}
```

### UART Device Communication

Each Pi monitors and logs UART device status:

```python
# UART monitoring thread
def uart_monitor():
    """Monitor UART device and forward logs to AP"""
    try:
        with serial.Serial(UART_DEVICE, 9600, timeout=1) as ser:
            while True:
                if ser.in_waiting:
                    message = ser.readline().decode('utf-8').strip()
                    log_uart_message(message)
                    forward_to_dashboard(message)
                time.sleep(0.1)
    except Exception as e:
        logger.error(f"UART monitoring error: {e}")

def log_uart_message(message):
    """Log UART message locally and send to AP dashboard"""
    logger.info(f"UART: {message}")
    if socketio:
        socketio.emit('uart_log', {
            'node': NODE_NAME,
            'message': message,
            'timestamp': datetime.now().isoformat()
        })
```

### NetworkManager Configuration (Not wpa_supplicant)

Always use NetworkManager for WiFi management:

```bash
# Create hidden network connection
sudo nmcli connection add type wifi con-name Apple ssid "Apple"
sudo nmcli connection modify Apple wifi-sec.key-mgmt wpa-psk wifi-sec.psk "Pharos12345"
sudo nmcli connection modify Apple 802-11-wireless.hidden yes
sudo nmcli connection modify Apple ipv4.addresses 192.168.4.10/24 ipv4.method manual
```

### Sensor Data Standard Format

All sensor data follows this JSON structure:

```json
{
  "pi": "node_name",
  "sensor": "temperature|humidity|motion|door|light",
  "value": 25.5,
  "unit": "celsius|percent|boolean|state|lux",
  "timestamp": "2025-07-19T11:30:00.000000"
}
```

## Common Troubleshooting Patterns

### GPIO "Device Busy" Errors

- Try different pins (17→18→19→20 fallback sequence)
- Check for zombie processes: `sudo lsof /dev/gpiomem`
- Reboot to clear GPIO state: `sudo reboot`

### Network Connectivity Issues

- Verify NetworkManager active: `systemctl is-active NetworkManager`
- Check WiFi connection: `nmcli connection show --active`
- Test AP reachability: `ping -c 3 192.168.4.1`

### Service Startup Failures

- Check Python dependencies: `python3 -c "import flask, requests, gpiozero"`
- Verify file permissions: `ls -la /home/admin/client_project/`
- Check systemd logs: `journalctl -u service_name -n 50`

### Zero-Touch Provisioning Debugging

- Validate boot files: `ls -la /boot/firmware/{ssh,userconf.txt,wpa_supplicant.conf}`
- Test SSH connectivity: `ssh -o ConnectTimeout=5 admin@<ip> "echo test"`
- Check WiFi configuration format in `wpa_supplicant.conf`

## Key Files and Locations

**Deployment Scripts**:

- `setup-fresh-pi-official.sh` - SD card boot file creation
- `deploy-one-click-official.sh` - Remote node deployment
- `validate-fresh-pi-official.sh` - Boot configuration validation

**Application Structure**:

- Client apps: `/home/admin/client_project/client_app.py`
- AP dashboard: `/home/admin/dashboard_project/app.py`
- Services: `/etc/systemd/system/{client-app,dashboard}.service`

**Monitoring Tools**:

- `monitor.py` - Network health and connectivity monitoring
- `validate-config.py` - System configuration validation with auto-fix

When working on this codebase, always use the automation tools for testing and deployment. Follow the systemd-based service architecture rather than direct script execution, and ensure both AP and client code paths work for redundancy.
