#!/usr/bin/env python3
"""
Raspberry Pi Network Monitor
Monitors network status, service health, and node connectivity
Usage: python3 monitor.py [--mode client|ap] [--continuous]
"""

import argparse
import time
import subprocess
import requests
import socket
import json
import datetime
import sys
from typing import Dict, List, Optional

class NetworkMonitor:
    def __init__(self, mode: str = "auto"):
        self.mode = mode
        self.results = {}
        
    def detect_mode(self) -> str:
        """Auto-detect if this is an AP or client node"""
        try:
            # Check if hostapd is running (AP mode)
            result = subprocess.run(['systemctl', 'is-active', 'hostapd'], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                return "ap"
            
            # Check if connected to RPiAP (client mode)
            result = subprocess.run(['nmcli', 'connection', 'show', '--active'], 
                                  capture_output=True, text=True)
            if "RPiAP" in result.stdout:
                return "client"
                
            return "unknown"
        except:
            return "unknown"
    
    def get_network_info(self) -> Dict:
        """Get current network configuration"""
        info = {}
        try:
            # Get IP address
            result = subprocess.run(['ip', 'addr', 'show', 'wlan0'], 
                                  capture_output=True, text=True)
            for line in result.stdout.split('\n'):
                if 'inet ' in line:
                    info['ip'] = line.split()[1].split('/')[0]
                    break
            
            # Get gateway
            result = subprocess.run(['ip', 'route', 'show', 'default'], 
                                  capture_output=True, text=True)
            if result.stdout:
                info['gateway'] = result.stdout.split()[2]
            
            # Get WiFi status
            result = subprocess.run(['nmcli', 'device', 'wifi', 'list'], 
                                  capture_output=True, text=True)
            info['wifi_available'] = len(result.stdout.split('\n')) > 1
            
        except Exception as e:
            info['error'] = str(e)
        
        return info
    
    def check_services(self) -> Dict:
        """Check status of relevant services"""
        services = {}
        
        if self.mode == "ap":
            service_list = ['hostapd', 'dnsmasq', 'dashboard']
        elif self.mode == "client":
            service_list = ['client_app']
        else:
            service_list = ['hostapd', 'dnsmasq', 'dashboard', 'client_app']
        
        for service in service_list:
            try:
                result = subprocess.run(['systemctl', 'is-active', service], 
                                      capture_output=True, text=True)
                services[service] = result.stdout.strip()
            except:
                services[service] = "unknown"
        
        return services
    
    def check_connectivity(self) -> Dict:
        """Test network connectivity"""
        tests = {}
        
        # Test gateway connectivity
        try:
            gateway = self.get_network_info().get('gateway', '192.168.4.1')
            result = subprocess.run(['ping', '-c', '3', gateway], 
                                  capture_output=True, text=True)
            tests['gateway'] = result.returncode == 0
        except:
            tests['gateway'] = False
        
        # Test internet connectivity (if available)
        try:
            result = subprocess.run(['ping', '-c', '2', '8.8.8.8'], 
                                  capture_output=True, text=True, timeout=10)
            tests['internet'] = result.returncode == 0
        except:
            tests['internet'] = False
        
        # Test local API endpoints
        if self.mode == "client":
            tests['local_api'] = self.test_local_api()
        elif self.mode == "ap":
            tests['dashboard'] = self.test_dashboard()
        
        return tests
    
    def test_local_api(self) -> bool:
        """Test local API endpoint"""
        try:
            response = requests.get('http://localhost:5000/api/v1/status', timeout=5)
            return response.status_code == 200
        except:
            return False
    
    def test_dashboard(self) -> bool:
        """Test dashboard endpoint"""
        try:
            response = requests.get('http://localhost/api/nodes', timeout=5)
            return response.status_code == 200
        except:
            return False
    
    def scan_network_nodes(self) -> List[Dict]:
        """Scan for active nodes on network (AP mode)"""
        if self.mode != "ap":
            return []
        
        nodes = []
        base_ip = "192.168.4."
        
        for i in range(10, 50):  # Scan DHCP range
            ip = f"{base_ip}{i}"
            try:
                # Quick ping test
                result = subprocess.run(['ping', '-c', '1', '-W', '1', ip], 
                                      capture_output=True, text=True)
                if result.returncode == 0:
                    node_info = {'ip': ip, 'reachable': True}
                    
                    # Try to get node status via API
                    try:
                        response = requests.get(f'http://{ip}:5000/api/v1/status', timeout=2)
                        if response.status_code == 200:
                            node_info.update(response.json())
                    except:
                        pass
                    
                    nodes.append(node_info)
            except:
                continue
        
        return nodes
    
    def get_system_stats(self) -> Dict:
        """Get system resource statistics"""
        stats = {}
        try:
            # CPU usage
            result = subprocess.run(['top', '-bn1'], capture_output=True, text=True)
            for line in result.stdout.split('\n'):
                if 'Cpu(s)' in line:
                    stats['cpu_usage'] = line.split(',')[0].split()[1]
                    break
            
            # Memory usage
            result = subprocess.run(['free', '-h'], capture_output=True, text=True)
            lines = result.stdout.split('\n')
            if len(lines) > 1:
                memory_line = lines[1].split()
                stats['memory_total'] = memory_line[1]
                stats['memory_used'] = memory_line[2]
                stats['memory_free'] = memory_line[3]
            
            # Disk usage
            result = subprocess.run(['df', '-h', '/'], capture_output=True, text=True)
            lines = result.stdout.split('\n')
            if len(lines) > 1:
                disk_line = lines[1].split()
                stats['disk_total'] = disk_line[1]
                stats['disk_used'] = disk_line[2]
                stats['disk_free'] = disk_line[3]
                stats['disk_usage_percent'] = disk_line[4]
            
            # Temperature
            try:
                with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                    temp = int(f.read().strip()) / 1000
                    stats['temperature'] = f"{temp:.1f}°C"
            except:
                stats['temperature'] = "N/A"
                
        except Exception as e:
            stats['error'] = str(e)
        
        return stats
    
    def run_full_check(self) -> Dict:
        """Run comprehensive system check"""
        if self.mode == "auto":
            self.mode = self.detect_mode()
        
        timestamp = datetime.datetime.now().isoformat()
        
        report = {
            'timestamp': timestamp,
            'mode': self.mode,
            'network_info': self.get_network_info(),
            'services': self.check_services(),
            'connectivity': self.check_connectivity(),
            'system_stats': self.get_system_stats()
        }
        
        if self.mode == "ap":
            report['active_nodes'] = self.scan_network_nodes()
        
        return report
    
    def print_report(self, report: Dict):
        """Print formatted monitoring report"""
        print(f"\n{'='*60}")
        print(f"Raspberry Pi Network Monitor Report")
        print(f"Timestamp: {report['timestamp']}")
        print(f"Mode: {report['mode'].upper()}")
        print(f"{'='*60}")
        
        # Network Information
        print(f"\n📡 NETWORK INFORMATION")
        print(f"{'─'*30}")
        network = report['network_info']
        print(f"IP Address: {network.get('ip', 'Unknown')}")
        print(f"Gateway: {network.get('gateway', 'Unknown')}")
        print(f"WiFi Available: {network.get('wifi_available', False)}")
        
        # Service Status
        print(f"\n🔧 SERVICE STATUS")
        print(f"{'─'*30}")
        for service, status in report['services'].items():
            status_icon = "✅" if status == "active" else "❌"
            print(f"{status_icon} {service}: {status}")
        
        # Connectivity Tests
        print(f"\n🌐 CONNECTIVITY TESTS")
        print(f"{'─'*30}")
        for test, result in report['connectivity'].items():
            result_icon = "✅" if result else "❌"
            print(f"{result_icon} {test}: {'PASS' if result else 'FAIL'}")
        
        # System Statistics
        print(f"\n📊 SYSTEM STATISTICS")
        print(f"{'─'*30}")
        stats = report['system_stats']
        print(f"Temperature: {stats.get('temperature', 'N/A')}")
        print(f"CPU Usage: {stats.get('cpu_usage', 'N/A')}")
        print(f"Memory: {stats.get('memory_used', 'N/A')}/{stats.get('memory_total', 'N/A')}")
        print(f"Disk: {stats.get('disk_used', 'N/A')}/{stats.get('disk_total', 'N/A')} ({stats.get('disk_usage_percent', 'N/A')})")
        
        # Active Nodes (AP mode only)
        if 'active_nodes' in report:
            print(f"\n🔗 ACTIVE NODES")
            print(f"{'─'*30}")
            nodes = report['active_nodes']
            if nodes:
                for node in nodes:
                    node_id = node.get('node_id', 'Unknown')
                    ip = node.get('ip', 'Unknown')
                    print(f"• {node_id} ({ip})")
            else:
                print("No active nodes detected")
        
        print(f"\n{'='*60}")
    
    def save_report(self, report: Dict, filename: Optional[str] = None):
        """Save report to JSON file"""
        if not filename:
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"monitor_report_{timestamp}.json"
        
        with open(filename, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"Report saved to: {filename}")

def main():
    parser = argparse.ArgumentParser(description='Raspberry Pi Network Monitor')
    parser.add_argument('--mode', choices=['client', 'ap', 'auto'], default='auto',
                      help='Operation mode (auto-detect by default)')
    parser.add_argument('--continuous', action='store_true',
                      help='Run continuous monitoring')
    parser.add_argument('--interval', type=int, default=30,
                      help='Monitoring interval in seconds (default: 30)')
    parser.add_argument('--save', action='store_true',
                      help='Save report to JSON file')
    parser.add_argument('--quiet', action='store_true',
                      help='Minimal output')
    
    args = parser.parse_args()
    
    monitor = NetworkMonitor(args.mode)
    
    try:
        if args.continuous:
            print(f"Starting continuous monitoring (interval: {args.interval}s)")
            print("Press Ctrl+C to stop")
            
            while True:
                report = monitor.run_full_check()
                
                if not args.quiet:
                    monitor.print_report(report)
                else:
                    status = "🟢" if all(report['connectivity'].values()) else "🔴"
                    print(f"{status} {report['timestamp']} - Mode: {report['mode']}")
                
                if args.save:
                    monitor.save_report(report)
                
                time.sleep(args.interval)
        else:
            report = monitor.run_full_check()
            monitor.print_report(report)
            
            if args.save:
                monitor.save_report(report)
                
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped by user")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
