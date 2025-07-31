# 📋 Deployment Checklist and Procedures

*Complete guide for deploying additional client nodes*

## 🎯 Pre-Deployment Requirements

### ✅ Apple AP Status Verification

Before deploying any new client, verify the Apple Access Point is operational:

```bash
# 1. Test Apple AP accessibility
curl -s http://192.168.4.1/api/status

# 2. Verify WiFi network broadcasting
nmcli dev wifi list | grep Apple

# 3. Check current client count
curl -s http://192.168.4.1/api/status | grep client_count

# 4. Test LED control system
curl -X POST http://192.168.4.1/api/led/pumpkin/toggle
```

**Expected Results**:
- Apple AP responds with JSON status
- "Apple" network visible (hidden SSID)
- Current client count shows connected nodes
- LED toggle returns success response

### ✅ Hardware Preparation

For each new client Pi:

- [ ] Fresh Raspberry Pi (3B+ or newer)
- [ ] MicroSD card (16GB minimum, 32GB recommended)
- [ ] Power supply (5V 3A recommended)
- [ ] Network connectivity for initial provisioning

### ✅ Software Requirements

- [ ] Git Bash on Windows (or terminal on Linux/macOS)
- [ ] SSH access to home network
- [ ] Latest deployment scripts from repository
- [ ] Valid SSH keys for password-less authentication

## 🚀 Deployment Sequence

### Phase 1: SD Card Preparation

#### Step 1: Fresh Pi Setup

```bash
# Navigate to project directory
cd "/c/Users/Justin/OneDrive/Desktop/RPiAP GUI"

# Setup fresh SD card (Windows)
./setup-fresh-pi-official.sh /d

# Validate configuration
./validate-fresh-pi-official.sh /d
```

**Validation checklist**:
- [ ] SSH file exists
- [ ] userconf.txt contains admin user
- [ ] wpa_supplicant.conf has home WiFi settings

#### Step 2: WiFi Configuration Check

Edit `wpa_supplicant.conf` if needed:

```bash
# Open for editing
notepad.exe /d/wpa_supplicant.conf

# Verify contains both networks:
# - Home WiFi for provisioning
# - Apple network for production
```

**Required networks**:
- [ ] Home WiFi (priority=10, id_str="home")
- [ ] Apple network (priority=5, id_str="apple", hidden=yes)

### Phase 2: Initial Boot and Network Connection

#### Step 3: First Boot

1. **Insert SD card** into target Raspberry Pi
2. **Power on** and wait for boot (2-3 minutes)
3. **Check home router** for new device connection
4. **Note IP address** assigned by home DHCP

#### Step 4: SSH Connectivity Test

```bash
# Test basic connectivity
ping <client-home-ip>

# Test SSH access (should work with keys)
ssh admin@<client-home-ip> "hostname && date"

# If SSH keys not working, use password method
ssh admin@<client-home-ip>
# Password: 001234
```

**Troubleshooting**:
- If no IP assigned: Check wpa_supplicant.conf format
- If SSH fails: Verify SSH file exists on boot partition
- If connection refused: Wait longer for full boot

### Phase 3: Client Deployment

#### Step 5: Enhanced Deployment

Use the improved deployment script with all fixes:

```bash
# Deploy using enhanced script v2.0
./deploy-one-click-improved.sh <client-home-ip> <node-name>

# Examples:
./deploy-one-click-improved.sh 192.168.86.25 cherry
./deploy-one-click-improved.sh 192.168.86.26 pecan
./deploy-one-click-improved.sh 192.168.86.27 peach
```

**Script features**:
- [ ] Automatic SSH host key cleanup
- [ ] DHCP-based IP assignment
- [ ] Dynamic IP detection in client app
- [ ] Enhanced error handling
- [ ] Progress monitoring

#### Step 6: Monitor Deployment Progress

The enhanced script provides real-time feedback:

```text
🔧 Deploying cherry client to 192.168.86.25
🧹 Cleaning SSH host keys...
📤 Uploading setup scripts...
🔧 Running client setup...
📡 Configuring Apple network connection...
🔌 Switching to Apple WiFi...
⚙️ Installing client application...
🏃 Starting services...
✅ Deployment completed successfully!
```

### Phase 4: Post-Deployment Verification

#### Step 7: Network Connection Verification

After deployment, the client should automatically connect to Apple network:

```bash
# Check if client appeared on Apple network
# (Wait 30-60 seconds for network switch)

# 1. Check Apple AP for new client
curl -s http://192.168.4.1/api/status | grep -A 10 "connected_clients"

# 2. Find client's new Apple network IP
nmap -sn 192.168.4.0/24 | grep -B 2 -A 1 "Raspberry"

# 3. Test client API directly
curl -s http://192.168.4.X:5000/<node>/api/v1/status
```

#### Step 8: Dashboard Integration Test

1. **Open Apple Dashboard**: http://192.168.4.1
2. **Verify client appears** in connected clients list
3. **Check heartbeat timestamp** (should be recent)
4. **Test LED control** using dashboard toggle

#### Step 9: Full Functionality Test

```bash
# Test all major client endpoints
CLIENT_IP="192.168.4.X"  # Replace with actual IP
NODE_NAME="cherry"       # Replace with actual node name

# 1. Status endpoint
curl -s http://$CLIENT_IP:5000/$NODE_NAME/api/v1/status

# 2. Device list
curl -s http://$CLIENT_IP:5000/$NODE_NAME/api/v1/devices

# 3. LED control via Apple AP
curl -X POST http://192.168.4.1/api/led/$NODE_NAME/toggle

# 4. Direct LED control
curl -X POST http://$CLIENT_IP:5000/$NODE_NAME/api/v1/devices/led_1/action \
  -H "Content-Type: application/json" \
  -d '{"action": "toggle"}'

# 5. System information
curl -s http://$CLIENT_IP:5000/$NODE_NAME/api/v1/info
```

## 📊 Success Criteria

### ✅ Deployment Success Indicators

A successful deployment should achieve:

- [ ] **Network Connection**: Client connects to Apple WiFi automatically
- [ ] **IP Assignment**: Client receives IP in 192.168.4.X range
- [ ] **Dashboard Appearance**: Client visible in Apple dashboard within 30 seconds
- [ ] **Heartbeat Active**: Recent timestamp in dashboard status
- [ ] **LED Control Working**: Toggle responds within 2 seconds
- [ ] **API Responding**: All endpoints return valid JSON responses
- [ ] **Service Status**: client-app.service active and enabled

### 📈 Performance Benchmarks

Monitor these metrics during deployment:

- **Network Switch Time**: < 60 seconds from home WiFi to Apple network
- **Dashboard Registration**: < 30 seconds after network connection
- **LED Response Time**: < 2 seconds for toggle commands
- **API Response Time**: < 1 second for status queries
- **Heartbeat Interval**: Every 30 seconds consistently

## 🔧 Troubleshooting Common Issues

### Issue: Client Doesn't Appear in Dashboard

**Symptoms**: Deployment completes but client missing from Apple dashboard

**Diagnosis**:
```bash
# Check if client actually connected to Apple network
ssh admin@<client-home-ip> "nmcli connection show --active"

# Check client application logs
ssh admin@192.168.4.X "journalctl -u client-app -n 20"

# Check Apple AP logs for connection attempts
ssh admin@192.168.4.1 "journalctl -u hostapd -n 20"
```

**Solutions**:
1. **Manual network connection**:
```bash
ssh admin@<client-home-ip> "nmcli connection up Apple-Connection"
```

2. **Restart client services**:
```bash
ssh admin@192.168.4.X "sudo systemctl restart client-app"
```

3. **Check network configuration**:
```bash
ssh admin@192.168.4.X "nmcli connection show Apple-Connection"
```

### Issue: LED Control Not Working

**Symptoms**: Dashboard toggle shows "load failed" or no response

**Diagnosis**:
```bash
# Test Apple AP LED forwarding endpoint
curl -v -X POST http://192.168.4.1/api/led/<node>/toggle

# Test direct client control
curl -v -X POST http://192.168.4.X:5000/<node>/api/v1/devices/led_1/action \
  -H "Content-Type: application/json" \
  -d '{"action": "toggle"}'

# Check GPIO permissions
ssh admin@192.168.4.X "groups admin | grep gpio"
```

**Solutions**:
1. **Add GPIO permissions** (requires reboot):
```bash
ssh admin@192.168.4.X "sudo usermod -a -G gpio admin && sudo reboot"
```

2. **Restart client application**:
```bash
ssh admin@192.168.4.X "sudo systemctl restart client-app"
```

3. **Check LED hardware**:
```bash
ssh admin@192.168.4.X "python3 -c 'from gpiozero import LED; led=LED(17); led.on()'"
```

### Issue: SSH Connection Problems

**Symptoms**: Cannot SSH to client after deployment

**Diagnosis**:
```bash
# Check if client is reachable
ping 192.168.4.X

# Check SSH service
nmap -p 22 192.168.4.X

# Test with verbose SSH
ssh -v admin@192.168.4.X
```

**Solutions**:
1. **Use enhanced deployment script** (handles SSH keys automatically):
```bash
./deploy-one-click-improved.sh <ip> <node>
```

2. **Manual SSH key cleanup**:
```bash
ssh-keygen -R 192.168.4.X
ssh-keygen -R <original-ip>
```

3. **Fallback to password authentication**:
```bash
ssh -o PreferredAuthentications=password admin@192.168.4.X
# Password: 001234
```

## 📋 Deployment Record Template

### Cherry Pi Deployment Record

**Date**: _________________  
**Technician**: _________________

**Pre-Deployment**:
- [ ] Apple AP status verified
- [ ] Fresh SD card prepared
- [ ] SSH connectivity tested
- [ ] Home network IP: _________________

**Deployment**:
- [ ] Enhanced script executed successfully
- [ ] Network switch completed
- [ ] Apple network IP assigned: _________________
- [ ] Services started automatically

**Post-Deployment**:
- [ ] Dashboard registration confirmed
- [ ] LED control tested and working
- [ ] API endpoints responding
- [ ] Heartbeat system active
- [ ] Performance benchmarks met

**Notes**: _________________________________________________
_________________________________________________________

**Sign-off**: _________________ **Date**: _________________

## 🔄 Next Deployments

### Deployment Order

1. **Cherry Pi** (192.168.4.12)
   - Use as validation of enhanced deployment process
   - Document any remaining issues
   - Verify multi-client AP operation

2. **Pecan Pi** (192.168.4.13)
   - Confirm deployment automation working
   - Test load on Apple AP with 3 clients
   - Validate LED control with multiple clients

3. **Peach Pi** (192.168.4.14)
   - Complete 5-node network
   - Full system testing
   - Performance validation with all clients

### Post-Full-Deployment Testing

Once all clients are deployed:

```bash
# Test simultaneous LED control
for node in pumpkin cherry pecan peach; do
  curl -X POST http://192.168.4.1/api/led/$node/toggle &
done
wait

# Monitor network performance
watch -n 5 'curl -s http://192.168.4.1/api/status | grep client_count'

# Stress test with API calls
for i in {1..10}; do
  for node in pumpkin cherry pecan peach; do
    curl -s http://192.168.4.X:5000/$node/api/v1/status > /dev/null &
  done
done
```

---

**Document Version**: 2.0 - Enhanced with deployment fixes  
**Last Updated**: July 30, 2025  
**Next Review**: After Cherry Pi deployment
