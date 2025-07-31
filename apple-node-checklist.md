# Apple Node Configuration Checklist
# Complete setup guide for Raspberry Pi Apple node (192.168.4.12)

## Pre-Setup Requirements
- [  ] Fresh Raspberry Pi OS installed on SD card
- [  ] Pi connected via Ethernet or temporary WiFi for initial setup
- [  ] SSH enabled (add empty `ssh` file to boot partition)
- [  ] setup-apple-node.sh script copied to Pi
- [  ] Pi's initial IP address discovered (see discovery methods below)

## IP Discovery Methods

### Method 1: Automatic Discovery Scripts
```bash
# Linux/Mac
./find-pi-ip.sh

# Windows PowerShell
.\Find-PiIP.ps1
```

### Method 2: Common Hostnames
```bash
# Try connecting to default hostname
ssh pi@raspberrypi.local
# or
ssh pi@raspberrypi
```

### Method 3: Router Admin Page
1. Open router web interface (usually http://192.168.1.1 or http://192.168.0.1)
2. Look for "Connected Devices" or "DHCP Client List"
3. Find device named "raspberrypi" or with Pi MAC address (B8:27:EB, DC:A6:32, E4:5F:01)

### Method 4: Network Scanning
```bash
# Linux/Mac
nmap -sn 192.168.1.0/24 | grep -A 2 "raspberrypi"
arp -a | grep -i "b8:27:eb\|dc:a6:32\|e4:5f:01"

# Windows
arp -a | findstr /i "b8-27-eb dc-a6-32 e4-5f-01"
```

### Method 5: Direct Pi Access
- Connect monitor and keyboard to Pi
- Boot Pi and run: `hostname -I`

## Step-by-Step Configuration

### 1. Initial Connection
```bash
# First, discover your Pi's IP address using one of the methods above
# Then connect via SSH (use initial Pi credentials)
ssh pi@<discovered-ip>

# Copy the setup script to the Pi
scp setup-apple-node.sh pi@<discovered-ip>:/home/pi/

# OR use automated deployment:
# Windows: .\Deploy-AppleNode.ps1 -PiIP <discovered-ip>
# Linux/Mac: ./deploy-apple.sh <discovered-ip>
```

### 2. Run Automated Setup
```bash
# Make script executable and run
chmod +x setup-apple-node.sh
./setup-apple-node.sh
```

### 3. Post-Setup Verification
```bash
# Switch to admin user
su - admin
# Password: 001234

# Connect to Apple network
sudo nmcli connection up Apple

# Verify IP assignment
ip addr show wlan0 | grep 192.168.4.12

# Start the client service
sudo systemctl start client_app.service

# Check service status
sudo systemctl status client_app.service

# Run tests
./test_apple_node.sh
```

### 4. Network Verification Commands
```bash
# Check WiFi connection
nmcli connection show --active

# Test connectivity to AP
ping -c 3 192.168.4.1

# Test API endpoints
curl http://localhost:5000/apple/api/v1/status
curl -X POST http://localhost:5000/apple/api/v1/actuators/led \
  -H "Content-Type: application/json" \
  -d '{"state":"on"}'
```

### 5. Service Management
```bash
# View live logs
journalctl -u client_app.service -f

# Restart service
sudo systemctl restart client_app.service

# Stop service
sudo systemctl stop client_app.service

# Disable auto-start
sudo systemctl disable client_app.service
```

## Expected Network Configuration
- **Node Name**: apple
- **Static IP**: 192.168.4.12/24
- **Gateway**: 192.168.4.1 (Pumpkin AP)
- **Network**: Apple (hidden SSID)
- **Password**: Pharos12345
- **User**: admin / 001234

## API Endpoints
- Node Status: `GET http://192.168.4.12:5000/apple/api/v1/status`
- LED Control: `POST http://192.168.4.12:5000/apple/api/v1/actuators/led`
- LED Status: `GET http://192.168.4.12:5000/apple/api/v1/actuators/led/status`

## Troubleshooting

### WiFi Connection Issues
```bash
# Check NetworkManager status
systemctl status NetworkManager

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Manually connect to Apple network
sudo nmcli device wifi connect "Apple" password "Pharos12345" hidden yes

# Check available networks
sudo nmcli device wifi list
```

### Service Startup Issues
```bash
# Check Python dependencies
python3 -c "import flask, requests, gpiozero"

# Check file permissions
ls -la /home/admin/client_project/

# Check service logs
journalctl -u client_app.service -n 50

# Manual test run
cd /home/admin/client_project
python3 client_app.py
```

### GPIO Issues
```bash
# Check GPIO group membership
groups admin

# Add to GPIO group if missing
sudo usermod -a -G gpio admin

# Check for GPIO conflicts
sudo lsof /dev/gpiomem

# Reboot to clear GPIO state
sudo reboot
```

### Network Connectivity
```bash
# Check routing table
ip route show

# Check DNS resolution
nslookup google.com

# Test internal network
ping 192.168.4.1

# Check if port 5000 is in use
sudo netstat -tulpn | grep :5000
```

## Testing from Other Nodes
```bash
# From Pumpkin or other nodes, test Apple APIs
curl http://192.168.4.12:5000/apple/api/v1/status

curl -X POST http://192.168.4.12:5000/apple/api/v1/actuators/led \
  -H "Content-Type: application/json" \
  -d '{"state":"on","brightness":100}'

curl -X POST http://192.168.4.12:5000/apple/api/v1/actuators/led \
  -H "Content-Type: application/json" \
  -d '{"state":"off"}'
```

## Success Criteria
- [  ] Apple node connects to hidden Apple network automatically
- [  ] Static IP 192.168.4.12 assigned correctly
- [  ] client_app.service starts automatically on boot
- [  ] API endpoints respond correctly
- [  ] LED control works via GPIO
- [  ] Sensor data sends to AP successfully
- [  ] SSH access works with admin/001234
- [  ] Service logs show no errors
