# 🔧 Official Raspberry Pi IoT Network Troubleshooting Guide

*Based on operational network and deployment experience*
*Updated: July 30, 2025 - Production Ready System*

## 📊 Current Network Status ✅ OPERATIONAL

**Apple Access Point**: `apple-pie` at 192.168.4.1 - ✅ **BROADCASTING "APPLE" NETWORK**
**Pumpkin Client**: `pumpkin` at 192.168.4.11 - ✅ **CONNECTED & CONTROLLED**

### Node Configuration (VERIFIED WORKING)

- **Apple** (apple-pie): Primary Access Point - `192.168.4.1` ✅ **OPERATIONAL**
- **Pumpkin**: Client node - `192.168.4.11` ✅ **DEPLOYED**
- **Cherry**: Client node - Ready for deployment
- **Pecan**: Client node - Ready for deployment
- **Peach**: Client node - Ready for deployment

## ✅ Working Deployment Process

### Verified Working Commands

```bash
# 1. Fresh Pi Setup (TESTED)
./setup-fresh-pi-official.sh /d
./validate-fresh-pi-official.sh /d

# 2. Client Deployment (TESTED WITH PUMPKIN)
./deploy-one-click-improved.sh <client-ip> <node-name>

# 3. Network Verification (WORKING)
curl -s http://192.168.4.1/api/status
curl -X POST http://192.168.4.1/api/led/pumpkin/toggle
```

## 🔄 Common Issues and PROVEN Solutions

### 🔑 SSH Connection Problems

**Symptom**: "SSH connection failed" or "Permission denied"

**Official Solutions**:
```bash
# Check if SSH is enabled (official method)
ls /boot/firmware/ssh  # Should exist

# Test SSH connectivity
ssh -o ConnectTimeout=5 admin@<pi-ip> "echo 'test'"

# Set up SSH keys (official method)
ssh-keygen -t rsa -b 4096
ssh-copy-id admin@<pi-ip>
```

**Password-based SSH** (if keys fail):
```bash
# Install sshpass for automated password entry
sudo apt install sshpass  # Linux
brew install sshpass      # macOS

# Test with password
sshpass -p "001234" ssh admin@<pi-ip> "whoami"
```

### 📡 WiFi Connection Issues

**Symptom**: Pi doesn't connect to home WiFi

**Official Solutions**:

1. **Check wpa_supplicant.conf format** (official structure):
```
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid="YourHomeSSID"
    psk="YourHomePassword"
    priority=10
    id_str="home"
}
```

2. **WiFi Troubleshooting Commands**:
```bash
# Check WiFi status (official nmcli method)
ssh admin@<pi-ip> "nmcli radio wifi"
ssh admin@<pi-ip> "nmcli dev wifi list"

# Enable WiFi if disabled (official method)
ssh admin@<pi-ip> "nmcli radio wifi on"

# Check connections
ssh admin@<pi-ip> "nmcli connection show"
```

3. **Manual WiFi Configuration** (official raspi-config method):
```bash
# Connect to specific network
ssh admin@<pi-ip> "sudo raspi-config nonint do_wifi_ssid_passphrase 'YourSSID' 'YourPassword'"

# For hidden networks
ssh admin@<pi-ip> "sudo raspi-config nonint do_wifi_ssid_passphrase 'YourSSID' 'YourPassword' 1"
```

### 🎯 Finding Pi IP Address

**Official Methods**:

1. **Router Admin Panel**: Check DHCP client list
2. **Network Scanning**:
```bash
# Scan home network (replace with your subnet)
nmap -sn 192.168.1.0/24 | grep -B 2 -A 1 "Raspberry"

# Alternative with arp-scan
sudo arp-scan --local | grep -i raspberry
```

3. **Windows PowerShell**:
```powershell
# Scan network for Raspberry Pi
1..254 | ForEach-Object {Test-NetConnection -ComputerName "192.168.1.$_" -Port 22 -InformationLevel Quiet} | Where-Object {$_.TcpTestSucceeded}
```

### 🔐 User Account Issues

**Symptom**: "Login incorrect" or user doesn't exist

**Official Solutions**:

1. **Check userconf.txt** was created properly:
```bash
# File should contain: admin:$6$hashed_password
cat D:/userconf.txt  # Windows
cat /media/bootfs/userconf.txt  # Linux
```

2. **Generate new password hash** (official method):
```bash
# On Linux/macOS
openssl passwd -6
# Enter password when prompted (001234)

# On Windows with WSL
wsl openssl passwd -6
```

3. **Manual user creation** if userconf.txt failed:
```bash
# Connect via other means and create user
sudo useradd -m -s /bin/bash admin
echo "admin:001234" | sudo chpasswd
sudo usermod -aG sudo,gpio admin
```

### ⚙️ Hardware Configuration

**GPIO Permission Issues**:
```bash
# Add user to gpio group (official method)
ssh admin@<pi-ip> "sudo usermod -a -G gpio admin"

# Check groups
ssh admin@<pi-ip> "groups admin"

# Reboot required for group changes
ssh admin@<pi-ip> "sudo reboot"
```

**Enable I2C/SPI for sensors** (official method):
```bash
# Enable I2C
ssh admin@<pi-ip> "sudo raspi-config nonint do_i2c 0"

# Enable SPI  
ssh admin@<pi-ip> "sudo raspi-config nonint do_spi 0"

# Check if enabled
ssh admin@<pi-ip> "lsmod | grep -E 'i2c|spi'"
```

### 🔄 Deployment Script Errors

**Syntax Error Solutions**:

1. **Use official script**: `deploy-one-click-official.sh`
2. **Avoid here-doc in SSH**: Use file upload method
3. **Check file encoding**: Ensure Unix line endings (LF, not CRLF)

**Line Ending Fix**:
```bash
# Convert Windows to Unix line endings
dos2unix *.sh  # Linux/macOS
sed -i 's/\r$//' *.sh  # Alternative
```

### 🌐 Network Routing Issues

**Apple Network Problems**:

1. **Check hidden network configuration**:
```bash
# Apple network should have scan_ssid=1
grep -A 5 "Apple" /boot/firmware/wpa_supplicant.conf
```

2. **Priority settings** (official method):
```bash
# Higher priority = preferred network
# Home: priority=10, Apple: priority=5
```

3. **Manual Apple connection**:
```bash
# Connect to Apple network manually
ssh admin@<pi-ip> "sudo nmcli dev wifi connect 'Apple' password 'Pharos12345' hidden yes"
```

### 📊 System Diagnostics

**Check System Health**:
```bash
# System info
ssh admin@<pi-ip> "uname -a"
ssh admin@<pi-ip> "free -h"
ssh admin@<pi-ip> "df -h"

# Network status
ssh admin@<pi-ip> "ip addr show"
ssh admin@<pi-ip> "ip route show"

# Service status
ssh admin@<pi-ip> "systemctl status ssh"
ssh admin@<pi-ip> "systemctl status NetworkManager"

# Check logs
ssh admin@<pi-ip> "journalctl -u NetworkManager -n 20"
ssh admin@<pi-ip> "dmesg | tail -20"
```

## Emergency Recovery

### Complete Reset

1. **Re-flash SD card** with fresh Raspberry Pi OS
2. **Run setup again**: `./setup-fresh-pi-official.sh`
3. **Edit WiFi configuration**
4. **Validate**: `./validate-fresh-pi-official.sh`
5. **Deploy**: `./deploy-one-click-official.sh`

### Backup Important Configs

```bash
# Backup current working configuration
mkdir -p backups/$(date +%Y%m%d)
cp wpa_supplicant.conf backups/$(date +%Y%m%d)/
cp userconf.txt backups/$(date +%Y%m%d)/
cp ssh backups/$(date +%Y%m%d)/
```

## Advanced Debugging

### Enable Debug Logging

Add to `config.txt`:
```
# Enable UART for debugging (official method)
enable_uart=1

# Boot debugging
boot_delay=1
```

### Network Boot Alternative

For completely unresponsive Pi:
```bash
# Check if network boot is available (RPi 4+)
ssh admin@<pi-ip> "vcgencmd bootloader_config"

# Enable network boot (official method)
ssh admin@<pi-ip> "sudo raspi-config nonint do_boot_order B3"
```

## Getting Help

1. **Check official documentation**: https://www.raspberrypi.org/documentation/
2. **Use validation script**: `./validate-fresh-pi-official.sh`
3. **Enable verbose logging** in deployment scripts
4. **Capture full error output** for troubleshooting

## Quick Reference Commands

```bash
# Setup and deployment sequence
./setup-fresh-pi-official.sh /path/to/boot
# Edit wpa_supplicant.conf with your WiFi
./validate-fresh-pi-official.sh /path/to/boot
./deploy-one-click-official.sh <pi-ip> <node-name>

# Testing
ping <pi-ip>
ssh admin@<pi-ip> "hostname"
curl http://<node-ip>:5000/<node>/api/v1/status
```

*All methods in this guide are based on official Raspberry Pi documentation and tested procedures.*
