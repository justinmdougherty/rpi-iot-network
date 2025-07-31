/*
 * ESP32 Network Monitor for Raspberry Pi IoT Network
 * Monitors Apple AP failover and network health
 * 
 * Hardware: ESP32 Dev Module
 * Port: COM14
 * 
 * Features:
 * - WiFi network scanning for Apple APs
 * - Ping monitoring of primary and backup APs
 * - Client device detection
 * - Failover event detection and logging
 * - Serial output for real-time monitoring
 * - Web dashboard integration
 */

#include <WiFi.h>
#include <WiFiClient.h>
#include <WebServer.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Ping.h>

// Network Configuration
const char* home_ssid = "Fios";  // Your home WiFi - change as needed
const char* home_password = "your_home_password";  // Change this

const char* apple_ssid = "Apple";
const char* apple_password = "Pharos12345";

// Network Targets for Monitoring
const char* primary_ap = "192.168.4.1";    // Apple AP
const char* pumpkin_client = "192.168.4.11"; // Pumpkin client
const char* backup_ap = "192.168.4.11";    // Potential backup AP (Pumpkin)

// Monitoring Configuration
const int SCAN_INTERVAL = 10000;    // WiFi scan every 10 seconds
const int PING_INTERVAL = 5000;     // Ping test every 5 seconds
const int STATUS_INTERVAL = 30000;  // Status report every 30 seconds

// Global Variables
unsigned long lastScan = 0;
unsigned long lastPing = 0;
unsigned long lastStatus = 0;
unsigned long monitorStartTime = 0;

bool primaryApOnline = false;
bool backupApOnline = false;
bool failoverDetected = false;
String currentActiveAp = "none";
int apChangeCount = 0;

WebServer server(80);
WiFiClient client;

// Network State Structure
struct NetworkState {
  bool primaryReachable;
  bool backupReachable;
  String activeApMAC;
  int apSignalStrength;
  int connectedClients;
  String lastFailoverTime;
  unsigned long uptimeSeconds;
};

NetworkState currentState;

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n" + String("=").repeat(50));
  Serial.println("🔍 ESP32 Network Monitor Starting");
  Serial.println("📡 Raspberry Pi IoT Network Failover Monitor");
  Serial.println("⏰ " + getTimestamp());
  Serial.println(String("=").repeat(50));
  
  monitorStartTime = millis();
  
  // Initialize WiFi in station mode for monitoring
  WiFi.mode(WIFI_STA);
  
  // Start web server for status dashboard
  setupWebServer();
  
  // Initial network scan
  scanForAppleNetworks();
  
  Serial.println("🚀 Monitor ready - watching for network changes...");
  Serial.println("📊 Monitoring targets:");
  Serial.println("   • Primary AP: " + String(primary_ap));
  Serial.println("   • Backup AP: " + String(backup_ap));
  Serial.println("   • Client: " + String(pumpkin_client));
  Serial.println("");
}

void loop() {
  // Handle web server requests
  server.handleClient();
  
  // Periodic WiFi scanning
  if (millis() - lastScan > SCAN_INTERVAL) {
    scanForAppleNetworks();
    lastScan = millis();
  }
  
  // Periodic ping monitoring
  if (millis() - lastPing > PING_INTERVAL) {
    monitorNetworkHealth();
    lastPing = millis();
  }
  
  // Periodic status reporting
  if (millis() - lastStatus > STATUS_INTERVAL) {
    reportNetworkStatus();
    lastStatus = millis();
  }
  
  // Small delay to prevent watchdog issues
  delay(100);
}

void scanForAppleNetworks() {
  Serial.print("🔍 Scanning for Apple networks... ");
  
  int networkCount = WiFi.scanNetworks();
  bool appleFound = false;
  bool appleBackupFound = false;
  
  for (int i = 0; i < networkCount; i++) {
    String ssid = WiFi.SSID(i);
    String bssid = WiFi.BSSIDstr(i);
    int rssi = WiFi.RSSI(i);
    
    if (ssid == "Apple") {
      appleFound = true;
      currentState.activeApMAC = bssid;
      currentState.apSignalStrength = rssi;
      
      Serial.println("✅ Apple network found!");
      Serial.println("   📍 BSSID: " + bssid);
      Serial.println("   📶 Signal: " + String(rssi) + " dBm");
      
      if (currentActiveAp != bssid) {
        // AP change detected!
        if (currentActiveAp != "none") {
          apChangeCount++;
          failoverDetected = true;
          currentState.lastFailoverTime = getTimestamp();
          
          Serial.println("🚨 FAILOVER DETECTED! 🚨");
          Serial.println("   Previous AP: " + currentActiveAp);
          Serial.println("   New AP: " + bssid);
          Serial.println("   Change #" + String(apChangeCount));
          Serial.println("   Time: " + getTimestamp());
        }
        currentActiveAp = bssid;
      }
    }
    
    if (ssid == "Apple-Backup") {
      appleBackupFound = true;
      Serial.println("⚠️  Backup Apple network detected!");
      Serial.println("   📍 BSSID: " + bssid);
      Serial.println("   📶 Signal: " + String(rssi) + " dBm");
    }
  }
  
  if (!appleFound && !appleBackupFound) {
    Serial.println("❌ No Apple networks found");
    if (currentActiveAp != "none") {
      Serial.println("🚨 NETWORK DOWN! All Apple APs offline");
      currentActiveAp = "none";
    }
  }
  
  WiFi.scanDelete();
}

void monitorNetworkHealth() {
  // Test primary AP connectivity
  bool primaryPing = testPing(primary_ap);
  bool backupPing = testPing(backup_ap);
  
  // Detect state changes
  if (primaryPing != primaryApOnline) {
    primaryApOnline = primaryPing;
    Serial.println(primaryPing ? 
      "✅ Primary AP back online: " + String(primary_ap) :
      "❌ Primary AP offline: " + String(primary_ap));
  }
  
  if (backupPing != backupApOnline) {
    backupApOnline = backupPing;
    Serial.println(backupPing ? 
      "✅ Backup AP online: " + String(backup_ap) :
      "❌ Backup AP offline: " + String(backup_ap));
  }
  
  currentState.primaryReachable = primaryPing;
  currentState.backupReachable = backupPing;
  
  // Detect failover scenario
  if (!primaryPing && backupPing && !failoverDetected) {
    Serial.println("🔄 POTENTIAL FAILOVER: Primary down, backup up");
    Serial.println("   Monitoring for client migration...");
  }
}

bool testPing(const char* target) {
  // Simple connectivity test using HTTP request
  // (ESP32 Ping library can be unreliable, HTTP is more definitive)
  HTTPClient http;
  http.begin("http://" + String(target) + "/api/status");
  http.setTimeout(2000);  // 2 second timeout
  
  int httpCode = http.GET();
  http.end();
  
  return (httpCode > 0);  // Any HTTP response means reachable
}

void reportNetworkStatus() {
  currentState.uptimeSeconds = (millis() - monitorStartTime) / 1000;
  
  Serial.println("\n" + String("=").repeat(40));
  Serial.println("📊 NETWORK MONITOR STATUS REPORT");
  Serial.println("⏰ " + getTimestamp());
  Serial.println(String("-").repeat(40));
  
  Serial.println("🌐 Network State:");
  Serial.println("   Primary AP (" + String(primary_ap) + "): " + 
                 (currentState.primaryReachable ? "✅ Online" : "❌ Offline"));
  Serial.println("   Backup AP (" + String(backup_ap) + "): " + 
                 (currentState.backupReachable ? "✅ Online" : "❌ Offline"));
  
  Serial.println("\n📡 Apple Network:");
  if (currentActiveAp != "none") {
    Serial.println("   Active AP MAC: " + currentActiveAp);
    Serial.println("   Signal Strength: " + String(currentState.apSignalStrength) + " dBm");
  } else {
    Serial.println("   Status: ❌ No Apple network detected");
  }
  
  Serial.println("\n🔄 Failover Monitoring:");
  Serial.println("   AP Changes Detected: " + String(apChangeCount));
  Serial.println("   Last Failover: " + 
                 (currentState.lastFailoverTime.length() > 0 ? 
                  currentState.lastFailoverTime : "None detected"));
  
  Serial.println("\n⏱️  Monitor Uptime: " + formatUptime(currentState.uptimeSeconds));
  
  Serial.println(String("=").repeat(40) + "\n");
  
  // Reset failover flag after reporting
  failoverDetected = false;
}

void setupWebServer() {
  // Root status page
  server.on("/", HTTP_GET, []() {
    String html = generateStatusHTML();
    server.send(200, "text/html", html);
  });
  
  // JSON API endpoint
  server.on("/api/status", HTTP_GET, []() {
    DynamicJsonDocument doc(1024);
    
    doc["monitor_uptime"] = currentState.uptimeSeconds;
    doc["timestamp"] = getTimestamp();
    doc["primary_ap_online"] = currentState.primaryReachable;
    doc["backup_ap_online"] = currentState.backupReachable;
    doc["active_ap_mac"] = currentActiveAp;
    doc["signal_strength"] = currentState.apSignalStrength;
    doc["failover_count"] = apChangeCount;
    doc["last_failover"] = currentState.lastFailoverTime;
    
    String response;
    serializeJson(doc, response);
    
    server.send(200, "application/json", response);
  });
  
  server.begin();
  Serial.println("🌐 Web server started on ESP32 IP (will be assigned)");
}

String generateStatusHTML() {
  String html = R"(
<!DOCTYPE html>
<html>
<head>
    <title>ESP32 Network Monitor</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background-color: #2c3e50; color: white; padding: 15px; border-radius: 8px; }
        .status-card { background-color: white; margin: 10px 0; padding: 15px; border-radius: 8px; border-left: 4px solid #3498db; }
        .online { border-left-color: #27ae60; }
        .offline { border-left-color: #e74c3c; }
        .metric { display: inline-block; margin: 5px 15px 5px 0; }
        .failover-alert { background-color: #f39c12; color: white; padding: 10px; border-radius: 5px; margin: 10px 0; }
        .refresh { margin: 10px 0; }
    </style>
    <script>
        function refreshData() {
            location.reload();
        }
        setInterval(refreshData, 10000); // Auto-refresh every 10 seconds
    </script>
</head>
<body>
    <div class="header">
        <h1>🔍 ESP32 Network Monitor</h1>
        <p>Raspberry Pi IoT Network Failover Detection</p>
    </div>
    
    <div class="refresh">
        <button onclick="refreshData()">🔄 Refresh Now</button>
        <span style="float: right;">⏰ Last Update: )" + getTimestamp() + R"(</span>
    </div>
    
    <div class="status-card )" + (currentState.primaryReachable ? "online" : "offline") + R"(">
        <h3>🍎 Primary Apple AP ()" + String(primary_ap) + R"()</h3>
        <div class="metric">Status: )" + (currentState.primaryReachable ? "✅ Online" : "❌ Offline") + R"(</div>
    </div>
    
    <div class="status-card )" + (currentState.backupReachable ? "online" : "offline") + R"(">
        <h3>🔄 Backup AP ()" + String(backup_ap) + R"()</h3>
        <div class="metric">Status: )" + (currentState.backupReachable ? "✅ Online" : "❌ Offline") + R"(</div>
    </div>
    
    <div class="status-card">
        <h3>📡 Active Apple Network</h3>
        <div class="metric">MAC Address: )" + (currentActiveAp != "none" ? currentActiveAp : "None detected") + R"(</div>
        <div class="metric">Signal: )" + String(currentState.apSignalStrength) + R"( dBm</div>
    </div>
    
    )" + (apChangeCount > 0 ? 
    R"(<div class="failover-alert">
        <h3>🚨 Failover Activity Detected</h3>
        <div class="metric">Total Changes: )" + String(apChangeCount) + R"(</div>
        <div class="metric">Last Failover: )" + currentState.lastFailoverTime + R"(</div>
    </div>)" : "") + R"(
    
    <div class="status-card">
        <h3>⏱️ Monitor Statistics</h3>
        <div class="metric">Uptime: )" + formatUptime(currentState.uptimeSeconds) + R"(</div>
        <div class="metric">AP Changes: )" + String(apChangeCount) + R"(</div>
    </div>
</body>
</html>
)";
  
  return html;
}

String getTimestamp() {
  return String(millis() / 1000) + "s";  // Simple timestamp
  // For real timestamp, you'd need NTP or RTC
}

String formatUptime(unsigned long seconds) {
  unsigned long hours = seconds / 3600;
  unsigned long minutes = (seconds % 3600) / 60;
  unsigned long secs = seconds % 60;
  
  return String(hours) + "h " + String(minutes) + "m " + String(secs) + "s";
}
