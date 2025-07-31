# ESP32 Network Monitor Setup Guide

## Overview
This ESP32 monitor will watch your Raspberry Pi IoT network and detect when failover happens between the primary Apple AP and backup systems.

## Hardware Requirements
- ESP32 Dev Module (connected to COM14)
- USB cable for programming and power
- WiFi capability (built into ESP32)

## Software Requirements
- Arduino IDE with ESP32 support
- Python 3.x with required libraries
- Serial driver for ESP32

## Setup Instructions

### 1. Arduino IDE Setup

**Install ESP32 Board Support:**
1. Open Arduino IDE
2. Go to File → Preferences
3. Add this URL to "Additional Board Manager URLs":
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
4. Go to Tools → Board → Boards Manager
5. Search for "ESP32" and install "ESP32 by Espressif Systems"

**Install Required Libraries:**
1. Go to Sketch → Include Library → Manage Libraries
2. Install these libraries:
   - `ArduinoJson` by Benoit Blanchon
   - `ESP32Ping` by marian-craciunescu (for ping functionality)

### 2. Configure ESP32 Code

**Update WiFi Credentials in `esp32-network-monitor.ino`:**
```cpp
const char* home_ssid = "Fios";  // Change to your home WiFi
const char* home_password = "your_actual_password";  // Your WiFi password
```

**Upload to ESP32:**
1. Connect ESP32 to COM14
2. Select Tools → Board → ESP32 Dev Module
3. Select Tools → Port → COM14
4. Click Upload

### 3. Python Logger Setup

**Install Python Dependencies:**
```bash
pip install pyserial requests
```

**Run the Logger:**
```bash
python esp32_monitor_logger.py
```

## Monitoring Features

### 🔍 Network Scanning
- Scans for "Apple" and "Apple-Backup" WiFi networks every 10 seconds
- Detects BSSID (MAC address) changes indicating AP failover
- Monitors signal strength

### 📡 Connectivity Testing
- Pings primary AP (192.168.4.1) every 5 seconds
- Pings backup AP (192.168.4.11 - Pumpkin) every 5 seconds
- Uses HTTP requests to test API endpoints

### 🚨 Failover Detection
- Detects when Apple network BSSID changes (different Pi becomes AP)
- Monitors primary AP going offline and backup coming online
- Logs all events with timestamps

### 📊 Web Dashboard
The ESP32 hosts a web dashboard accessible when connected to your home network:
- Real-time network status
- Failover event history
- Signal strength monitoring
- Auto-refreshing display

## Testing Failover

### Scenario 1: Power Off Apple AP
1. **Start monitoring:** Run `python esp32_monitor_logger.py`
2. **Baseline check:** Verify Apple Pi is online at 192.168.4.1
3. **Trigger failover:** Power off the Apple Pi
4. **Watch logs:** ESP32 should detect:
   - Primary AP going offline
   - Apple network disappearing
   - Backup network appearing (if Pumpkin takes over)
   - BSSID change when network comes back

### Scenario 2: Network Disruption
1. **Disconnect Ethernet:** Unplug Apple Pi's ethernet cable
2. **Monitor response:** Watch how backup systems respond
3. **Reconnect:** Observe failback behavior

## Log Files Generated

The Python logger creates several log files in `esp32_monitor_logs/`:

- **`esp32_raw_*.log`** - All ESP32 serial output with timestamps
- **`network_events_*.csv`** - Structured event data for analysis
- **`failover_events_*.log`** - Specific failover events with details

## Expected Output Examples

### Normal Operation:
```
[14:23:15] 🔍 Scanning for Apple networks... ✅ Apple network found!
[14:23:15]    📍 BSSID: 2c:cf:67:5c:7a:1a
[14:23:15]    📶 Signal: -45 dBm
[14:23:20] ✅ Primary AP online: 192.168.4.1
[14:23:20] ❌ Backup AP offline: 192.168.4.11
```

### Failover Event:
```
[14:25:30] ❌ Primary AP offline: 192.168.4.1
[14:25:35] ❌ No Apple networks found
[14:25:40] 🚨 NETWORK DOWN! All Apple APs offline
[14:26:15] 🔍 Scanning for Apple networks... ✅ Apple network found!
[14:26:15] 🚨 FAILOVER DETECTED! 🚨
[14:26:15]    Previous AP: 2c:cf:67:5c:7a:1a
[14:26:15]    New AP: 2c:cf:67:59:09:7f
[14:26:15]    Change #1
[14:26:20] ✅ Backup AP online: 192.168.4.11
```

## Network Configuration

The ESP32 monitor watches these targets:

- **Primary AP:** 192.168.4.1 (Apple Pi)
- **Backup AP:** 192.168.4.11 (Pumpkin Pi)
- **Apple Network:** SSID "Apple" (hidden)
- **Backup Network:** SSID "Apple-Backup" (if implemented)

## Troubleshooting

### ESP32 Not Responding:
1. Check COM14 is correct port
2. Verify ESP32 is powered and connected
3. Try pressing RST button on ESP32
4. Check Arduino IDE serial monitor

### No Network Detection:
1. Verify ESP32 can connect to home WiFi
2. Check WiFi credentials in code
3. Ensure ESP32 is in range of both home and Apple networks

### Python Logger Issues:
1. Check COM14 port is available
2. Verify `pyserial` is installed
3. Make sure no other programs are using COM14

## Analysis Tools

### CSV Data Analysis:
The generated CSV files can be opened in Excel or analyzed with Python:

```python
import pandas as pd
df = pd.read_csv('esp32_monitor_logs/network_events_*.csv')
failovers = df[df['failover_detected'] == True]
print(f"Total failover events: {len(failovers)}")
```

### Real-time Monitoring:
```bash
# Watch live logs
tail -f esp32_monitor_logs/esp32_raw_*.log

# Monitor just failover events
tail -f esp32_monitor_logs/failover_events_*.log
```

## Integration with Raspberry Pi Network

The ESP32 monitor complements your Raspberry Pi network by providing:
- **External monitoring** - Independent of the Pi network
- **Failover validation** - Confirms when failover actually works
- **Performance metrics** - Signal strength and connectivity data
- **Historical analysis** - Long-term network behavior patterns

This gives you complete visibility into how your dual-Pi failover system performs under various conditions!
