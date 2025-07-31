#!/usr/bin/env python3
"""
ESP32 Network Monitor Data Logger
Reads ESP32 serial output and logs network monitoring data

Usage: python esp32_monitor_logger.py
Port: COM14 (ESP32 Dev Module)
"""

import serial
import time
import json
import csv
import datetime
import threading
import requests
from pathlib import Path

class ESP32NetworkLogger:
    def __init__(self, port='COM14', baudrate=115200):
        self.port = port
        self.baudrate = baudrate
        self.serial_conn = None
        self.running = False
        
        # Create log directories
        self.log_dir = Path('esp32_monitor_logs')
        self.log_dir.mkdir(exist_ok=True)
        
        # Log files
        self.raw_log = self.log_dir / f'esp32_raw_{datetime.datetime.now().strftime("%Y%m%d_%H%M%S")}.log'
        self.events_log = self.log_dir / f'network_events_{datetime.datetime.now().strftime("%Y%m%d_%H%M%S")}.csv'
        self.failover_log = self.log_dir / f'failover_events_{datetime.datetime.now().strftime("%Y%m%d_%H%M%S")}.log'
        
        # Initialize CSV for events
        self.init_csv_log()
        
        print(f"🔍 ESP32 Network Monitor Logger")
        print(f"📱 Port: {port}")
        print(f"📊 Logs: {self.log_dir}")
        print("="*50)
    
    def init_csv_log(self):
        """Initialize CSV log with headers"""
        with open(self.events_log, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([
                'timestamp',
                'event_type',
                'primary_ap_status',
                'backup_ap_status',
                'active_ap_mac',
                'signal_strength',
                'failover_detected',
                'details'
            ])
    
    def connect_serial(self):
        """Connect to ESP32 via serial"""
        try:
            self.serial_conn = serial.Serial(self.port, self.baudrate, timeout=1)
            time.sleep(2)  # Wait for ESP32 to initialize
            print(f"✅ Connected to ESP32 on {self.port}")
            return True
        except Exception as e:
            print(f"❌ Failed to connect to ESP32: {e}")
            return False
    
    def start_monitoring(self):
        """Start monitoring ESP32 output"""
        if not self.connect_serial():
            return
        
        self.running = True
        print("🚀 Starting ESP32 monitoring...")
        print("📊 Watching for network events and failover detection")
        print("")
        
        # Start monitoring thread
        monitor_thread = threading.Thread(target=self.monitor_loop)
        monitor_thread.daemon = True
        monitor_thread.start()
        
        # Start periodic status requests
        status_thread = threading.Thread(target=self.periodic_status)
        status_thread.daemon = True
        status_thread.start()
        
        try:
            while self.running:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n🛑 Stopping monitor...")
            self.running = False
    
    def monitor_loop(self):
        """Main monitoring loop reading serial data"""
        buffer = ""
        
        while self.running:
            try:
                if self.serial_conn and self.serial_conn.in_waiting:
                    data = self.serial_conn.read(self.serial_conn.in_waiting).decode('utf-8', errors='ignore')
                    buffer += data
                    
                    # Process complete lines
                    while '\n' in buffer:
                        line, buffer = buffer.split('\n', 1)
                        self.process_line(line.strip())
                
                time.sleep(0.1)
                
            except Exception as e:
                print(f"❌ Serial read error: {e}")
                time.sleep(1)
    
    def process_line(self, line):
        """Process a line of ESP32 output"""
        if not line:
            return
        
        timestamp = datetime.datetime.now().isoformat()
        
        # Log raw output
        with open(self.raw_log, 'a', encoding='utf-8') as f:
            f.write(f"{timestamp} | {line}\n")
        
        # Print to console with timestamp
        print(f"[{datetime.datetime.now().strftime('%H:%M:%S')}] {line}")
        
        # Detect specific events
        self.detect_events(line, timestamp)
    
    def detect_events(self, line, timestamp):
        """Detect and log specific network events"""
        event_data = {
            'timestamp': timestamp,
            'event_type': 'unknown',
            'primary_ap_status': 'unknown',
            'backup_ap_status': 'unknown',
            'active_ap_mac': '',
            'signal_strength': 0,
            'failover_detected': False,
            'details': line
        }
        
        # Detect failover events
        if "FAILOVER DETECTED" in line:
            event_data['event_type'] = 'failover'
            event_data['failover_detected'] = True
            
            # Log to special failover file
            with open(self.failover_log, 'a') as f:
                f.write(f"{timestamp} | FAILOVER EVENT\n")
                f.write(f"Details: {line}\n")
                f.write("-" * 50 + "\n")
            
            print(f"🚨 FAILOVER EVENT LOGGED: {timestamp}")
        
        # Detect AP status changes
        elif "Primary AP" in line:
            if "online" in line.lower():
                event_data['primary_ap_status'] = 'online'
                event_data['event_type'] = 'primary_ap_online'
            elif "offline" in line.lower():
                event_data['primary_ap_status'] = 'offline'
                event_data['event_type'] = 'primary_ap_offline'
        
        elif "Backup AP" in line:
            if "online" in line.lower():
                event_data['backup_ap_status'] = 'online'
                event_data['event_type'] = 'backup_ap_online'
            elif "offline" in line.lower():
                event_data['backup_ap_status'] = 'offline'
                event_data['event_type'] = 'backup_ap_offline'
        
        # Detect Apple network found
        elif "Apple network found" in line:
            event_data['event_type'] = 'apple_network_detected'
        
        elif "No Apple networks found" in line:
            event_data['event_type'] = 'apple_network_lost'
        
        # Extract signal strength if present
        if "Signal:" in line and "dBm" in line:
            try:
                signal_part = line.split("Signal:")[1].split("dBm")[0].strip()
                event_data['signal_strength'] = int(signal_part)
            except:
                pass
        
        # Extract MAC address if present
        if "BSSID:" in line:
            try:
                mac_part = line.split("BSSID:")[1].strip()
                event_data['active_ap_mac'] = mac_part
            except:
                pass
        
        # Log significant events to CSV
        if event_data['event_type'] != 'unknown':
            self.log_event_csv(event_data)
    
    def log_event_csv(self, event_data):
        """Log event to CSV file"""
        with open(self.events_log, 'a', newline='') as f:
            writer = csv.writer(f)
            writer.writerow([
                event_data['timestamp'],
                event_data['event_type'],
                event_data['primary_ap_status'],
                event_data['backup_ap_status'],
                event_data['active_ap_mac'],
                event_data['signal_strength'],
                event_data['failover_detected'],
                event_data['details']
            ])
    
    def periodic_status(self):
        """Periodically request status from ESP32 web server"""
        while self.running:
            time.sleep(60)  # Every minute
            
            # Try to get ESP32 status via HTTP (if connected to same network)
            try:
                # This would work if ESP32 is connected to home network
                # We'll just log a periodic marker for now
                timestamp = datetime.datetime.now().isoformat()
                with open(self.raw_log, 'a') as f:
                    f.write(f"{timestamp} | STATUS_CHECK: Monitor still active\n")
            except:
                pass
    
    def test_raspberry_pi_connectivity(self):
        """Test connectivity to Raspberry Pi network"""
        targets = [
            "192.168.4.1",    # Primary Apple AP
            "192.168.4.11",   # Pumpkin client
            "192.168.86.62"   # Apple Pi ethernet
        ]
        
        print("\n🔍 Testing Raspberry Pi connectivity...")
        for target in targets:
            try:
                response = requests.get(f"http://{target}/api/status", timeout=2)
                print(f"✅ {target}: HTTP {response.status_code}")
            except requests.RequestException:
                print(f"❌ {target}: Unreachable")
        print("")

def main():
    """Main function"""
    logger = ESP32NetworkLogger()
    
    # Test Pi connectivity first
    logger.test_raspberry_pi_connectivity()
    
    print("📱 ESP32 Monitor Instructions:")
    print("1. Flash esp32-network-monitor.ino to your ESP32")
    print("2. Update WiFi credentials in the code")
    print("3. Connect ESP32 to COM14")
    print("4. Monitor logs in esp32_monitor_logs/ directory")
    print("")
    print("🚨 Failover Testing:")
    print("- Power off Apple Pi to trigger failover")
    print("- ESP32 will detect and log the event")
    print("- Check failover_events_*.log for details")
    print("")
    
    try:
        logger.start_monitoring()
    except KeyboardInterrupt:
        print("\n✅ Monitoring stopped")

if __name__ == "__main__":
    main()
