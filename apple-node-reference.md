# Apple Access Point - Quick Reference

*Essential commands and information for the Apple AP node*

## Connection Details ✅ OPERATIONAL

- **Node Role**: Primary Access Point
- **AP IP**: 192.168.4.1 (Apple WiFi network)
- **Ethernet IP**: 192.168.86.62 (home network backhaul)
- **SSH**: `ssh admin@192.168.4.1` (when on Apple network)
- **SSH**: `ssh admin@192.168.86.62` (when on home network)
- **Password**: 001234
- **WiFi SSID**: Apple (hidden network)
- **WiFi Password**: Pharos12345

## Dashboard Access

- **Web Interface**: http://192.168.4.1
- **Features**: Real-time client monitoring, LED control, time displays
- **API Base**: http://192.168.4.1/api/

## Service Commands

### AP Services (Critical)

```bash
# Check AP services status
sudo systemctl status hostapd dnsmasq dashboard

# Start AP services
sudo systemctl start hostapd dnsmasq dashboard

# Enable for boot
sudo systemctl enable hostapd dnsmasq dashboard

# Restart AP services
sudo systemctl restart hostapd dnsmasq dashboard

# View logs
journalctl -u hostapd -f
journalctl -u dnsmasq -f
journalctl -u dashboard -f
```

### Network Monitoring

```bash
# Check WiFi interface
iwconfig wlan0
iw dev wlan0 info

# Check connected clients
iw dev wlan0 station dump

# Monitor DHCP assignments
tail -f /var/log/daemon.log | grep dnsmasq
```

## API Testing

### Dashboard API Endpoints

```bash
# Network status
curl -s http://192.168.4.1/api/status | python3 -m json.tool

# Connected clients
curl -s http://192.168.4.1/api/status | grep -A 10 connected_clients

# Control client LED (Pumpkin example)
curl -X POST http://192.168.4.1/api/led/pumpkin/toggle

# Control specific client LED
curl -X POST http://192.168.4.1/api/led/cherry/toggle
curl -X POST http://192.168.4.1/api/led/pecan/toggle
curl -X POST http://192.168.4.1/api/led/peach/toggle
```

### Client Status Queries

```bash
# Check if client is reachable
ping -c 3 192.168.4.11  # Pumpkin
ping -c 3 192.168.4.12  # Cherry
ping -c 3 192.168.4.13  # Pecan
ping -c 3 192.168.4.14  # Peach

# Client heartbeat status
curl -s http://192.168.4.1/api/status | grep -A 5 "pumpkin\|cherry\|pecan\|peach"
```

## Network Configuration Files

### hostapd Configuration

```bash
# Check AP configuration
cat /etc/hostapd/hostapd.conf

# Key settings:
# interface=wlan0
# ssid=Apple
# channel=7
# hw_mode=g
# ignore_broadcast_ssid=1  # Hidden network
```

### dnsmasq Configuration

```bash
# Check DHCP configuration
cat /etc/dnsmasq.conf

# Key settings:
# interface=wlan0
# dhcp-range=192.168.4.10,192.168.4.50,255.255.255.0,24h
# dhcp-option=3,192.168.4.1  # Gateway
# dhcp-option=6,8.8.8.8,8.8.4.4  # DNS
```

### Network Interfaces

```bash
# Check current IP configuration
ip addr show

# Verify bridge/routing
ip route show

# Check iptables (if using NAT)
sudo iptables -t nat -L
```

## Client Management

### View Connected Clients

```bash
# Active DHCP leases
cat /var/lib/dhcp/dhcpd.leases

# ARP table (connected devices)
arp -a | grep 192.168.4

# WiFi station list
iw dev wlan0 station dump
```

### Client Registration System

```bash
# Check dashboard logs for client registration
journalctl -u dashboard -f | grep heartbeat

# Manual client lookup
curl -s http://192.168.4.1/api/status | grep -A 20 connected_clients
```

## Troubleshooting

### AP Not Broadcasting

```bash
# Check if hostapd is running
sudo systemctl status hostapd

# Check for errors
journalctl -u hostapd -n 20

# Test WiFi interface
iwconfig wlan0

# Restart WiFi interface
sudo ip link set wlan0 down
sudo ip link set wlan0 up
sudo systemctl restart hostapd
```

### No Client Connections

```bash
# Check dnsmasq status
sudo systemctl status dnsmasq

# Check DHCP logs
journalctl -u dnsmasq -n 20

# Test DHCP range
# Should be 192.168.4.10-192.168.4.50

# Verify WiFi password
grep -A 5 "Apple" /etc/hostapd/hostapd.conf
```

### Dashboard Issues

```bash
# Check dashboard service
sudo systemctl status dashboard

# View dashboard logs
journalctl -u dashboard -f

# Test dashboard API
curl -v http://192.168.4.1/api/status

# Check if port 80 is available
sudo netstat -tlnp | grep :80
```

### LED Control Problems

```bash
# Test direct client connection
ssh admin@192.168.4.11 "python3 -c 'from gpiozero import LED; LED(17).toggle()'"

# Check LED forwarding API
curl -v -X POST http://192.168.4.1/api/led/pumpkin/toggle

# Check client reachability
curl -s http://192.168.4.11:5000/pumpkin/api/v1/status
```

## Performance Monitoring

### Network Performance

```bash
# Check WiFi signal strength from clients
ssh admin@192.168.4.11 "iwconfig wlan0"

# Monitor network traffic
sudo iftop -i wlan0

# Check for WiFi interference
iwlist wlan0 scan | grep -E "Cell|ESSID|Channel|Signal"
```

### System Performance

```bash
# Check CPU/memory on AP
top -n 1

# Check disk space
df -h

# Monitor temperature
vcgencmd measure_temp

# Check system load
uptime
```

## Backup and Recovery

### Configuration Backup

```bash
# Backup critical configs
sudo tar -czf apple-ap-backup-$(date +%Y%m%d).tar.gz \
  /etc/hostapd/hostapd.conf \
  /etc/dnsmasq.conf \
  /etc/dhcpcd.conf \
  /home/admin/dashboard_project/

# Store backup securely
scp apple-ap-backup-*.tar.gz user@backup-server:backups/
```

### Service Recovery

```bash
# Emergency restart all services
sudo systemctl restart hostapd dnsmasq dashboard NetworkManager

# Nuclear option - full reboot
sudo reboot

# Verify services after restart
sudo systemctl status hostapd dnsmasq dashboard
```

## Security

### SSH Key Management

```bash
# Check authorized keys
cat /home/admin/.ssh/authorized_keys

# Regenerate SSH host keys if needed
sudo ssh-keygen -A
sudo systemctl restart ssh
```

### Network Security

```bash
# Check firewall status
sudo ufw status

# Monitor failed connection attempts
sudo tail -f /var/log/auth.log

# Check for unusual network activity
sudo netstat -tlnp
```

## File Locations

### Application Files

- **Dashboard**: `/home/admin/dashboard_project/app.py`
- **Dashboard Service**: `/etc/systemd/system/dashboard.service`
- **Static Files**: `/home/admin/dashboard_project/static/`
- **Templates**: `/home/admin/dashboard_project/templates/`

### Configuration Files

- **hostapd**: `/etc/hostapd/hostapd.conf`
- **dnsmasq**: `/etc/dnsmasq.conf`
- **Network**: `/etc/dhcpcd.conf`
- **SSH**: `/etc/ssh/sshd_config`

### Log Files

- **Dashboard**: `journalctl -u dashboard`
- **hostapd**: `journalctl -u hostapd`
- **dnsmasq**: `journalctl -u dnsmasq`
- **System**: `/var/log/syslog`

## Quick Health Check

```bash
#!/bin/bash
# Apple AP health check script

echo "=== Apple AP Health Check ==="
echo "Date: $(date)"
echo

echo "1. Service Status:"
systemctl is-active hostapd dnsmasq dashboard

echo "2. Network Interface:"
ip addr show wlan0 | grep "inet 192.168.4.1"

echo "3. Connected Clients:"
iw dev wlan0 station dump | grep Station | wc -l

echo "4. Dashboard API:"
curl -s http://192.168.4.1/api/status > /dev/null && echo "OK" || echo "FAIL"

echo "5. DHCP Leases:"
cat /var/lib/dhcp/dhcpd.leases | grep "binding state active" | wc -l

echo "=== End Health Check ==="
```

---

**Status**: 🟢 **OPERATIONAL** - Apple AP fully functional  
**Last Updated**: July 30, 2025  
**Next Maintenance**: Monitor after full 5-client deployment
