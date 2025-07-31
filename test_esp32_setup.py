#!/usr/bin/env python3
"""
Quick test script to verify ESP32 connection and Raspberry Pi network status
Run this before starting the full monitor to verify everything is working
"""

import serial
import time
import requests

def test_serial_connection():
    """Test connection to ESP32 on COM14"""
    print("🔍 Testing ESP32 Serial Connection...")
    try:
        ser = serial.Serial('COM14', 115200, timeout=2)
        time.sleep(2)
        
        print("✅ Serial connection established")
        
        # Try to read some data
        print("📡 Waiting for ESP32 output (10 seconds)...")
        start_time = time.time()
        data_received = False
        
        while time.time() - start_time < 10:
            if ser.in_waiting:
                data = ser.read(ser.in_waiting).decode('utf-8', errors='ignore')
                if data.strip():
                    print(f"📥 Received: {data.strip()}")
                    data_received = True
            time.sleep(0.1)
        
        ser.close()
        
        if data_received:
            print("✅ ESP32 is sending data!")
        else:
            print("⚠️  No data received - check ESP32 program is running")
        
        return data_received
        
    except Exception as e:
        print(f"❌ Serial connection failed: {e}")
        print("💡 Check: ESP32 connected to COM14, drivers installed, port available")
        return False

def test_raspberry_pi_network():
    """Test Raspberry Pi network connectivity"""
    print("\n🍎 Testing Raspberry Pi Network...")
    
    targets = [
        ("Apple AP (Primary)", "192.168.4.1"),
        ("Pumpkin Client", "192.168.4.11"),
        ("Apple Pi Ethernet", "192.168.86.62")
    ]
    
    results = {}
    
    for name, ip in targets:
        print(f"🔍 Testing {name} ({ip})...")
        try:
            response = requests.get(f"http://{ip}/api/status", timeout=3)
            print(f"✅ {name}: HTTP {response.status_code}")
            results[ip] = True
        except requests.exceptions.RequestException as e:
            print(f"❌ {name}: {str(e)}")
            results[ip] = False
    
    return results

def test_wifi_networks():
    """Scan for Apple WiFi networks (requires netsh on Windows)"""
    print("\n📡 Scanning for Apple WiFi Networks...")
    try:
        import subprocess
        result = subprocess.run(['netsh', 'wlan', 'show', 'profiles'], 
                              capture_output=True, text=True)
        
        if "Apple" in result.stdout:
            print("✅ Apple WiFi profile found on this computer")
        else:
            print("⚠️  Apple WiFi profile not found")
            print("💡 You may need to connect to Apple WiFi manually first")
        
        # Show current WiFi
        result = subprocess.run(['netsh', 'wlan', 'show', 'interfaces'], 
                              capture_output=True, text=True)
        
        for line in result.stdout.split('\n'):
            if 'SSID' in line and ':' in line:
                ssid = line.split(':')[1].strip()
                print(f"📶 Currently connected to: {ssid}")
                break
        
    except Exception as e:
        print(f"❌ WiFi scan failed: {e}")

def main():
    print("🔧 ESP32 Network Monitor Test Suite")
    print("=" * 50)
    
    # Test 1: Serial Connection
    serial_ok = test_serial_connection()
    
    # Test 2: Raspberry Pi Network
    pi_results = test_raspberry_pi_network()
    
    # Test 3: WiFi Networks
    test_wifi_networks()
    
    # Summary
    print("\n📊 Test Summary:")
    print("=" * 30)
    
    if serial_ok:
        print("✅ ESP32 Serial: Working")
    else:
        print("❌ ESP32 Serial: Failed")
    
    primary_ap = pi_results.get("192.168.4.1", False)
    backup_ap = pi_results.get("192.168.4.11", False)
    
    if primary_ap:
        print("✅ Primary AP: Online")
    else:
        print("❌ Primary AP: Offline")
    
    if backup_ap:
        print("✅ Backup AP: Online")
    else:
        print("❌ Backup AP: Offline")
    
    print("\n🚀 Next Steps:")
    if serial_ok and (primary_ap or backup_ap):
        print("1. ✅ Ready to run full monitor: python esp32_monitor_logger.py")
        print("2. 🧪 Test failover by powering off Apple Pi")
        print("3. 📊 Check logs in esp32_monitor_logs/ directory")
    else:
        print("1. ❌ Fix connection issues above")
        print("2. 🔧 Check ESP32 program is flashed correctly")
        print("3. 🌐 Verify Raspberry Pi network is operational")
    
    print(f"\n⚠️  For failover testing:")
    print(f"   - Power off Apple Pi to trigger failover")
    print(f"   - Watch ESP32 logs for BSSID changes")
    print(f"   - Monitor will detect when Pumpkin becomes AP")

if __name__ == "__main__":
    main()
