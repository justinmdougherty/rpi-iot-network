#!/usr/bin/env python3
"""
Raspberry Pi Configuration Validator
Validates system configuration and identifies common issues
Usage: python3 validate-config.py [--mode client|ap] [--fix]
"""

import argparse
import subprocess
import os
import re
import json
import sys
from typing import Dict, List, Tuple, Optional

class ConfigValidator:
    def __init__(self, mode: str = "auto"):
        self.mode = mode
        self.issues = []
        self.fixes_applied = []
    
    def detect_mode(self) -> str:
        """Auto-detect if this is an AP or client node"""
        try:
            # Check for hostapd config
            if os.path.exists('/etc/hostapd/hostapd.conf'):
                return "ap"
            
            # Check for client app
            if os.path.exists('/home/admin/client_project/client_app.py'):
                return "client"
                
            return "unknown"
        except:
            return "unknown"
    
    def log_issue(self, category: str, severity: str, description: str, fix_cmd: Optional[str] = None):
        """Log a configuration issue"""
        issue = {
            'category': category,
            'severity': severity,
            'description': description,
            'fix_command': fix_cmd
        }
        self.issues.append(issue)
    
    def run_command(self, cmd: List[str], capture_output: bool = True) -> Tuple[int, str, str]:
        """Run a system command and return results"""
        try:
            result = subprocess.run(cmd, capture_output=capture_output, text=True, timeout=30)
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return -1, "", "Command timed out"
        except Exception as e:
            return -1, "", str(e)
    
    def validate_network_config(self):
        """Validate network configuration"""
        print("Validating network configuration...")
        
        # Check if NetworkManager is running
        returncode, stdout, stderr = self.run_command(['systemctl', 'is-active', 'NetworkManager'])
        if returncode != 0:
            self.log_issue("network", "high", "NetworkManager service not active", 
                          "sudo systemctl start NetworkManager")
        
        # Check WiFi interface
        returncode, stdout, stderr = self.run_command(['ip', 'link', 'show', 'wlan0'])
        if returncode != 0:
            self.log_issue("network", "critical", "WiFi interface wlan0 not found")
        
        # Mode-specific network validation
        if self.mode == "client":
            self.validate_client_network()
        elif self.mode == "ap":
            self.validate_ap_network()
    
    def validate_client_network(self):
        """Validate client-specific network configuration"""
        # Check RPiAP connection
        returncode, stdout, stderr = self.run_command(['nmcli', 'connection', 'show', 'RPiAP'])
        if returncode != 0:
            self.log_issue("network", "high", "RPiAP connection not configured",
                          "Configure WiFi connection using setup-client.sh")
        
        # Check static IP configuration
        returncode, stdout, stderr = self.run_command(['ip', 'addr', 'show', 'wlan0'])
        if "192.168.4." not in stdout:
            self.log_issue("network", "medium", "Client not on expected IP range")
        
        # Test gateway connectivity
        returncode, stdout, stderr = self.run_command(['ping', '-c', '2', '192.168.4.1'])
        if returncode != 0:
            self.log_issue("network", "high", "Cannot reach gateway (AP)")
    
    def validate_ap_network(self):
        """Validate AP-specific network configuration"""
        # Check hostapd configuration
        if not os.path.exists('/etc/hostapd/hostapd.conf'):
            self.log_issue("network", "critical", "hostapd configuration file missing")
        else:
            with open('/etc/hostapd/hostapd.conf', 'r') as f:
                config = f.read()
                if 'interface=wlan0' not in config:
                    self.log_issue("network", "high", "hostapd not configured for wlan0")
        
        # Check dnsmasq configuration
        if not os.path.exists('/etc/dnsmasq.conf'):
            self.log_issue("network", "critical", "dnsmasq configuration file missing")
        
        # Check static IP configuration
        returncode, stdout, stderr = self.run_command(['ip', 'addr', 'show', 'wlan0'])
        if "192.168.4.1" not in stdout:
            self.log_issue("network", "high", "AP not configured with static IP 192.168.4.1")
    
    def validate_services(self):
        """Validate system services"""
        print("Validating system services...")
        
        if self.mode == "client":
            services = ['client_app']
        elif self.mode == "ap":
            services = ['hostapd', 'dnsmasq', 'dashboard']
        else:
            services = ['NetworkManager']
        
        for service in services:
            # Check if service exists
            returncode, stdout, stderr = self.run_command(['systemctl', 'list-unit-files', service])
            if service not in stdout:
                self.log_issue("services", "high", f"Service {service} not found")
                continue
            
            # Check if service is enabled
            returncode, stdout, stderr = self.run_command(['systemctl', 'is-enabled', service])
            if returncode != 0:
                self.log_issue("services", "medium", f"Service {service} not enabled",
                              f"sudo systemctl enable {service}")
            
            # Check if service is active
            returncode, stdout, stderr = self.run_command(['systemctl', 'is-active', service])
            if returncode != 0:
                self.log_issue("services", "high", f"Service {service} not active",
                              f"sudo systemctl start {service}")
    
    def validate_application_files(self):
        """Validate application files and permissions"""
        print("Validating application files...")
        
        if self.mode == "client":
            # Check client application files
            required_files = [
                '/home/admin/client_project/client_app.py',
                '/etc/systemd/system/client_app.service'
            ]
            
            for file_path in required_files:
                if not os.path.exists(file_path):
                    self.log_issue("files", "high", f"Required file missing: {file_path}")
                elif not os.access(file_path, os.R_OK):
                    self.log_issue("files", "medium", f"File not readable: {file_path}",
                                  f"sudo chmod +r {file_path}")
        
        elif self.mode == "ap":
            # Check AP application files
            required_files = [
                '/home/admin/dashboard_project/app.py',
                '/etc/systemd/system/dashboard.service'
            ]
            
            for file_path in required_files:
                if not os.path.exists(file_path):
                    self.log_issue("files", "high", f"Required file missing: {file_path}")
    
    def validate_python_dependencies(self):
        """Validate Python package dependencies"""
        print("Validating Python dependencies...")
        
        required_packages = ['flask', 'requests', 'gpiozero']
        
        for package in required_packages:
            returncode, stdout, stderr = self.run_command(['python3', '-c', f'import {package}'])
            if returncode != 0:
                self.log_issue("dependencies", "high", f"Python package missing: {package}",
                              f"sudo apt install python3-{package}")
    
    def validate_gpio_permissions(self):
        """Validate GPIO permissions (client mode)"""
        if self.mode != "client":
            return
        
        print("Validating GPIO permissions...")
        
        # Check if admin user is in gpio group
        returncode, stdout, stderr = self.run_command(['groups', 'admin'])
        if 'gpio' not in stdout:
            self.log_issue("permissions", "medium", "User 'admin' not in gpio group",
                          "sudo usermod -a -G gpio admin")
        
        # Check GPIO device access
        if os.path.exists('/dev/gpiomem'):
            if not os.access('/dev/gpiomem', os.R_OK):
                self.log_issue("permissions", "high", "Cannot access /dev/gpiomem")
        else:
            self.log_issue("permissions", "high", "/dev/gpiomem device not found")
    
    def validate_system_resources(self):
        """Validate system resources and performance"""
        print("Validating system resources...")
        
        # Check disk space
        returncode, stdout, stderr = self.run_command(['df', '/'])
        if returncode == 0:
            lines = stdout.split('\n')
            if len(lines) > 1:
                disk_info = lines[1].split()
                if len(disk_info) > 4:
                    usage_percent = int(disk_info[4].replace('%', ''))
                    if usage_percent > 90:
                        self.log_issue("resources", "high", f"Disk usage high: {usage_percent}%")
                    elif usage_percent > 80:
                        self.log_issue("resources", "medium", f"Disk usage moderate: {usage_percent}%")
        
        # Check memory
        returncode, stdout, stderr = self.run_command(['free'])
        if returncode == 0:
            lines = stdout.split('\n')
            if len(lines) > 1:
                memory_info = lines[1].split()
                if len(memory_info) > 2:
                    total_mem = int(memory_info[1])
                    used_mem = int(memory_info[2])
                    usage_percent = (used_mem / total_mem) * 100
                    if usage_percent > 90:
                        self.log_issue("resources", "medium", f"Memory usage high: {usage_percent:.1f}%")
        
        # Check temperature
        try:
            with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                temp = int(f.read().strip()) / 1000
                if temp > 80:
                    self.log_issue("resources", "high", f"CPU temperature high: {temp:.1f}°C")
                elif temp > 70:
                    self.log_issue("resources", "medium", f"CPU temperature elevated: {temp:.1f}°C")
        except:
            self.log_issue("resources", "low", "Cannot read CPU temperature")
    
    def run_full_validation(self) -> Dict:
        """Run complete configuration validation"""
        if self.mode == "auto":
            self.mode = self.detect_mode()
        
        print(f"Starting validation for {self.mode.upper()} mode...")
        print("=" * 50)
        
        # Run all validation checks
        self.validate_network_config()
        self.validate_services()
        self.validate_application_files()
        self.validate_python_dependencies()
        self.validate_gpio_permissions()
        self.validate_system_resources()
        
        # Generate summary
        critical_issues = [i for i in self.issues if i['severity'] == 'critical']
        high_issues = [i for i in self.issues if i['severity'] == 'high']
        medium_issues = [i for i in self.issues if i['severity'] == 'medium']
        low_issues = [i for i in self.issues if i['severity'] == 'low']
        
        summary = {
            'mode': self.mode,
            'total_issues': len(self.issues),
            'critical_issues': len(critical_issues),
            'high_issues': len(high_issues),
            'medium_issues': len(medium_issues),
            'low_issues': len(low_issues),
            'issues': self.issues,
            'fixes_applied': self.fixes_applied
        }
        
        return summary
    
    def print_summary(self, summary: Dict):
        """Print validation summary"""
        print("\n" + "=" * 60)
        print("CONFIGURATION VALIDATION SUMMARY")
        print("=" * 60)
        print(f"Mode: {summary['mode'].upper()}")
        print(f"Total Issues Found: {summary['total_issues']}")
        print(f"  Critical: {summary['critical_issues']}")
        print(f"  High: {summary['high_issues']}")
        print(f"  Medium: {summary['medium_issues']}")
        print(f"  Low: {summary['low_issues']}")
        
        if summary['total_issues'] == 0:
            print("\n🎉 CONFIGURATION VALID - No issues found!")
            return
        
        # Group issues by category
        categories = {}
        for issue in summary['issues']:
            cat = issue['category']
            if cat not in categories:
                categories[cat] = []
            categories[cat].append(issue)
        
        # Print issues by category
        for category, issues in categories.items():
            print(f"\n📋 {category.upper()} ISSUES")
            print("-" * 40)
            
            for issue in issues:
                severity_icons = {
                    'critical': '🔴',
                    'high': '🟠',
                    'medium': '🟡',
                    'low': '🟢'
                }
                icon = severity_icons.get(issue['severity'], '⚪')
                print(f"{icon} {issue['severity'].upper()}: {issue['description']}")
                
                if issue['fix_command']:
                    print(f"   Fix: {issue['fix_command']}")
        
        print(f"\n{'='*60}")
    
    def apply_fixes(self, summary: Dict) -> int:
        """Apply automatic fixes for issues"""
        fixed_count = 0
        
        print("\n🔧 APPLYING AUTOMATIC FIXES...")
        print("-" * 40)
        
        for issue in summary['issues']:
            if issue['fix_command'] and issue['severity'] in ['high', 'medium']:
                print(f"Applying fix for: {issue['description']}")
                print(f"Command: {issue['fix_command']}")
                
                # Parse and execute fix command
                cmd_parts = issue['fix_command'].split()
                returncode, stdout, stderr = self.run_command(cmd_parts)
                
                if returncode == 0:
                    print("✅ Fix applied successfully")
                    self.fixes_applied.append(issue['description'])
                    fixed_count += 1
                else:
                    print(f"❌ Fix failed: {stderr}")
                
                print()
        
        if fixed_count > 0:
            print(f"Applied {fixed_count} automatic fixes")
            print("Re-run validation to check if issues are resolved")
        else:
            print("No automatic fixes available")
        
        return fixed_count

def main():
    parser = argparse.ArgumentParser(description='Raspberry Pi Configuration Validator')
    parser.add_argument('--mode', choices=['client', 'ap', 'auto'], default='auto',
                      help='Operation mode (auto-detect by default)')
    parser.add_argument('--fix', action='store_true',
                      help='Apply automatic fixes for issues')
    parser.add_argument('--save', action='store_true',
                      help='Save validation report to JSON file')
    parser.add_argument('--quiet', action='store_true',
                      help='Minimal output')
    
    args = parser.parse_args()
    
    validator = ConfigValidator(args.mode)
    
    try:
        summary = validator.run_full_validation()
        
        if not args.quiet:
            validator.print_summary(summary)
        
        if args.fix and summary['total_issues'] > 0:
            validator.apply_fixes(summary)
        
        if args.save:
            import datetime
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"validation_report_{timestamp}.json"
            with open(filename, 'w') as f:
                json.dump(summary, f, indent=2)
            print(f"Report saved to: {filename}")
        
        # Exit with appropriate code
        if summary['critical_issues'] > 0:
            sys.exit(2)  # Critical issues
        elif summary['high_issues'] > 0:
            sys.exit(1)  # High priority issues
        else:
            sys.exit(0)  # Success or only low/medium issues
            
    except Exception as e:
        print(f"Validation error: {e}")
        sys.exit(3)

if __name__ == "__main__":
    main()
