# 🍎 Raspberry Pi IoT Network Project

*Industrial-grade IoT network with automated deployment and zero-touch provisioning*

## 🌟 Project Overview

A production-ready 5-node Raspberry Pi IoT network featuring:

- **Apple Pi**: Primary Access Point with web dashboard
- **4 Client Nodes**: Pumpkin, Cherry, Pecan, Peach
- **Real-time Control**: LED manipulation via web interface
- **REST API Architecture**: Complete endpoint coverage
- **Automated Deployment**: One-click client provisioning
- **Failover Capability**: Dual-mode AP/Client operation

## ✅ Current Status: PRODUCTION READY

### 🟢 Operational Components

- ✅ **Apple AP**: Broadcasting "Apple" WiFi network at 192.168.4.1
- ✅ **Pumpkin Client**: Deployed and controlled at 192.168.4.11
- ✅ **Web Dashboard**: Real-time interface with time displays
- ✅ **LED Control**: Working through dashboard API
- ✅ **Enhanced Deployment**: v2.0 script with all fixes

### 🔄 Ready for Deployment

- 🔄 **Cherry Pi**: Ready with improved deployment script
- 🔄 **Pecan Pi**: Ready with improved deployment script  
- 🔄 **Peach Pi**: Ready with improved deployment script

## 🚀 Quick Start Guide

### Prerequisites

- Windows machine with Git Bash
- 5 Raspberry Pi devices (Pi 3B+ or newer)
- MicroSD cards (16GB+ recommended)
- Home WiFi network access

### 1. Fresh Pi Setup

```bash
# Setup fresh Raspberry Pi SD card
./setup-fresh-pi-official.sh /d

# Validate configuration
./validate-fresh-pi-official.sh /d

# Insert SD card into Pi and boot
# Wait for Pi to connect to home WiFi
```

### 2. Deploy Apple Access Point

```bash
# SSH into Pi when connected to home network
ssh admin@<apple-pi-ip>

# Deploy AP configuration (manual process documented)
# See: setup-apple-pie-complete.sh
```

### 3. Deploy Client Nodes

```bash
# Deploy each client using enhanced script
./deploy-one-click-improved.sh <client-ip> pumpkin
./deploy-one-click-improved.sh <client-ip> cherry
./deploy-one-click-improved.sh <client-ip> pecan
./deploy-one-click-improved.sh <client-ip> peach
```

### 4. Access Dashboard

```bash
# Open web browser to Apple AP
http://192.168.4.1

# View connected clients and control LEDs
# Real-time status updates via WebSocket
```

## 🏗️ Network Architecture

### Production Network Topology

```text
Internet
   ↓
Home Router (192.168.86.1)
   └── Apple AP (192.168.86.62) [Ethernet backhaul]
       └── Apple WiFi Network 📡 "Apple" (hidden SSID)
           ├── Pumpkin (192.168.4.11) ✅ DEPLOYED
           ├── Cherry (192.168.4.12) 🔄 READY
           ├── Pecan (192.168.4.13) 🔄 READY
           └── Peach (192.168.4.14) 🔄 READY
```

### Network Configuration

**Apple WiFi Network**:
- SSID: "Apple" (hidden)
- Password: "Pharos12345"
- IP Range: 192.168.4.0/24
- DHCP: 192.168.4.10-192.168.4.50

**Credentials**:
- Username: `admin`
- Password: `001234`
- SSH: Key-based authentication

## 🛠️ Technology Stack

### Hardware Platform
- **Raspberry Pi OS**: Latest 64-bit
- **NetworkManager**: WiFi management (not wpa_supplicant)
- **GPIO Control**: 2 LEDs per Pi for status/control
- **UART Support**: External device communication

### Software Architecture
- **Access Point**: hostapd + dnsmasq + Flask dashboard
- **Client Applications**: Multi-threaded Python with REST API
- **Web Interface**: Real-time dashboard with WebSocket updates
- **Service Management**: systemd for auto-start and monitoring

### API Endpoints

**Apple Dashboard** (192.168.4.1):
- `GET /api/status` - Network and client status
- `POST /api/led/<node>/toggle` - LED control forwarding
- `GET /` - Web dashboard interface

**Client APIs** (Port 5000 on each node):
- `GET /<node>/api/v1/status` - Node status and capabilities
- `GET /<node>/api/v1/devices` - Available GPIO devices
- `POST /<node>/api/v1/devices/<device>/action` - Device control
- `PUT /<node>/api/v1/config` - Configuration updates
- `POST /<node>/api/v1/system/reboot` - System management

## 📁 Project Structure

### Core Scripts
- `setup-fresh-pi-official.sh` - SD card provisioning
- `validate-fresh-pi-official.sh` - Setup validation
- `deploy-one-click-improved.sh` - Enhanced client deployment v2.0
- `deploy-one-click-official.sh` - Original deployment script

### Application Files  
- `apple-dashboard-fixed.py` - Web dashboard with all features
- `example-client_app.py` - Complete client application template
- `setup-apple-pie-complete.sh` - AP setup automation
- `setup-client-complete.sh` - Client setup automation

### Configuration
- `wpa_supplicant.conf` - WiFi settings (dual networks)
- `userconf.txt` - User account configuration
- `boot-config.txt` - Pi boot settings

### Documentation
- `PROJECT-STATUS-CURRENT.md` - Current operational status
- `CLIENT-DEPLOYMENT-FIXES.md` - Deployment improvements analysis
- `TROUBLESHOOTING-OFFICIAL.md` - Issue resolution guide
- `.github/copilot-instructions.md` - Development guidelines

## 🎯 Key Features

### Web Dashboard Capabilities
- **Real-time Time Display**: UTC and local time updates
- **Client Status Cards**: Live connection and activity monitoring
- **LED Control Interface**: Toggle client LEDs remotely
- **Compact AP Status**: Space-efficient network information
- **WebSocket Updates**: Live status without page refresh

### Advanced Client Features
- **Multi-threaded Architecture**: API + Heartbeat + Sensor + UART threads
- **GPIO Fallback Strategy**: Automatic pin conflict resolution
- **Device Abstraction**: LEDs, PWM, buttons with unified API
- **Remote Management**: Reboot, configuration, logging via API
- **Auto-reconnection**: Network failure recovery

### Deployment Automation
- **Zero-touch Provisioning**: SD card to running client
- **SSH Key Management**: Automatic host key cleanup
- **DHCP Integration**: Dynamic IP assignment and detection
- **Error Recovery**: Enhanced logging and failure handling
- **Validation Testing**: Pre and post-deployment verification

## 🔧 Deployment Improvements (v2.0)

Based on successful Pumpkin deployment, the enhanced deployment script includes:

### Automated Fixes
- ✅ SSH host key cleanup for conflict resolution
- ✅ DHCP-based IP assignment (more reliable than static)
- ✅ Dynamic IP detection for client applications
- ✅ Enhanced error handling and progress logging
- ✅ All manual fixes from initial deployment automated

### Testing Workflow
1. **Pre-deployment**: Apple AP status verification
2. **During deployment**: Real-time progress monitoring
3. **Post-deployment**: Automatic validation and LED testing
4. **Dashboard integration**: Client appears within 30 seconds

## 📊 Monitoring and Management

### Health Monitoring
```bash
# Check Apple AP status
curl -s http://192.168.4.1/api/status | python3 -m json.tool

# Test client connectivity
curl -s http://192.168.4.11:5000/pumpkin/api/v1/status

# LED control test
curl -X POST http://192.168.4.1/api/led/pumpkin/toggle
```

### Service Management
```bash
# Apple AP services
sudo systemctl status hostapd dnsmasq dashboard

# Client services
sudo systemctl status client-app network-monitor
```

### Log Analysis
```bash
# Dashboard logs
journalctl -u dashboard -f

# Client application logs
journalctl -u client-app -f

# Network connectivity
journalctl -u NetworkManager -n 20
```

## 🎉 Production Metrics

### Achieved Milestones
- ✅ **Hidden WiFi Network**: Apple SSID broadcasting correctly
- ✅ **Client Registration**: Automatic discovery and heartbeat
- ✅ **LED Control**: Dashboard toggle functionality working
- ✅ **Real-time Updates**: WebSocket communication established
- ✅ **REST API Coverage**: Complete endpoint implementation
- ✅ **Enhanced UI**: Time displays and compact status
- ✅ **Deployment Automation**: One-click provisioning

### Performance Targets
- **Client Connection**: < 30 seconds to dashboard appearance
- **LED Response**: < 2 seconds toggle response time
- **Heartbeat Interval**: 30 seconds for status updates
- **API Response**: < 1 second for status queries
- **Network Recovery**: < 60 seconds reconnection time

## 🔄 Next Steps

### Immediate Deployment
1. **Cherry Pi**: Deploy using enhanced script
2. **Pecan Pi**: Verify multi-client operation
3. **Peach Pi**: Complete 5-node network

### Advanced Features (Future)
- **UART Device Integration**: Temperature/humidity sensors
- **Mobile Application**: iOS/Android client control
- **Alert System**: Email/SMS notifications for issues
- **Data Logging**: Historical sensor data collection
- **Cloud Integration**: Remote monitoring capabilities

## 📞 Support and Troubleshooting

### Common Issues
- **SSH Connection**: Use `deploy-one-click-improved.sh` for auto-cleanup
- **LED Control**: Verify Apple AP has forwarding endpoints
- **Client Missing**: Check heartbeat system and network connectivity
- **IP Conflicts**: Enhanced script uses DHCP to avoid conflicts

### Debug Commands
```bash
# Network diagnostics
ping 192.168.4.1
nmcli connection show
ip addr show

# Service status
systemctl status client-app
systemctl status hostapd
systemctl status dnsmasq

# API testing
curl http://192.168.4.1/api/status
curl http://192.168.4.11:5000/pumpkin/api/v1/status
```

---

**Project Status**: 🟢 **PRODUCTION READY** - Core network operational, ready for expansion

*Last Updated: July 30, 2025*
