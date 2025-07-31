#!/usr/bin/env python3
import os
import json
import time
import threading
import requests
import subprocess
from datetime import datetime
from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# Global variables
connected_clients = {}
device_status = {}
last_heartbeat = {}

# HTML template for Apple IoT Dashboard
DASHBOARD_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>Apple IoT Dashboard</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            margin: 0; padding: 20px; 
            background: linear-gradient(135deg, #1a1a1a 0%, #2d2d2d 100%);
            min-height: 100vh; color: #e2e8f0;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        
        .time-display {
            text-align: center; margin-bottom: 20px;
            display: flex; justify-content: center; gap: 20px;
        }
        
        .time-box {
            background: #ffeb3b; color: #000; padding: 8px 20px;
            border-radius: 8px; font-weight: bold; font-size: 1.1em;
            border: 2px solid #000; box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }
        
        .header {
            text-align: center; background: rgba(255,255,255,0.95);
            color: #333; padding: 30px; border-radius: 15px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1); margin-bottom: 30px;
            backdrop-filter: blur(10px);
        }
        .header h1 { margin: 0; font-size: 2.5em; font-weight: 300; }
        .header p { margin: 10px 0 0 0; opacity: 0.8; font-size: 1.1em; }

        .dashboard-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 30px;
            margin-bottom: 30px;
        }

        .left-panel { display: flex; flex-direction: column; gap: 20px; }
        .right-panel { display: flex; flex-direction: column; gap: 20px; }

        .status-card, .command-card, .log-card {
            background: rgba(255,255,255,0.95);
            padding: 25px; border-radius: 15px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
            color: #333;
        }

        .status-card h3, .command-card h3, .log-card h3 {
            margin: 0 0 20px 0; color: #4a5568; font-weight: 600;
            border-bottom: 2px solid #e2e8f0; padding-bottom: 10px;
        }

        .node-grid {
            display: grid;
            grid-template-columns: 1fr;
            gap: 15px;
        }

        .node-panel {
            background: #f8fafc;
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #ff6b35;
        }

        .node-panel h4 {
            margin: 0 0 15px 0;
            color: #2d3748;
            font-size: 1.2em;
        }

        .ap-status-compact {
            background: linear-gradient(135deg, #4caf50, #45a049);
            color: white; padding: 12px 20px; border-radius: 8px;
            margin-bottom: 20px; display: flex; align-items: center;
            justify-content: space-between; font-weight: 500;
        }
        
        .ap-info {
            font-size: 1.1em;
        }
        
        .client-count {
            font-size: 0.9em; opacity: 0.9;
        }

        .status-indicator {
            display: inline-block; width: 12px; height: 12px;
            border-radius: 50%; margin-right: 10px;
        }
        .online { background: #4caf50; box-shadow: 0 0 10px rgba(76,175,80,0.5); }
        .offline { background: #f44336; }
        .warning { background: #ff9800; }

        .client-list {
            margin: 10px 0;
        }

        .client-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px;
            margin: 5px 0;
            background: #f8fafc;
            border-radius: 6px;
            border-left: 3px solid #4caf50;
        }

        .command-section {
            display: grid;
            grid-template-columns: 1fr auto;
            gap: 15px;
            align-items: end;
            margin-bottom: 20px;
        }

        .form-group {
            display: flex;
            flex-direction: column;
        }

        .form-group label {
            margin-bottom: 5px;
            font-weight: 600;
            color: #4a5568;
        }

        .form-control {
            padding: 12px;
            border: 2px solid #e2e8f0;
            border-radius: 8px;
            font-size: 16px;
            background: white;
        }

        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
        }

        .btn-primary {
            background: linear-gradient(135deg, #ff6b35, #f7931e);
            color: white;
        }

        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(255,107,53,0.4);
        }

        .log-area {
            background: #1a202c; color: #e2e8f0;
            padding: 20px; border-radius: 8px;
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 14px; line-height: 1.5;
            height: 300px; overflow-y: auto;
            border: 2px solid #2d3748;
        }

        .log-entry {
            margin: 5px 0;
            padding: 5px;
            border-radius: 4px;
        }

        .log-success { background: rgba(76, 175, 80, 0.1); }
        .log-error { background: rgba(244, 67, 54, 0.1); }
        .log-info { background: rgba(33, 150, 243, 0.1); }

        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }

        .metric {
            text-align: center;
            background: #edf2f7;
            padding: 20px;
            border-radius: 10px;
        }

        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #ff6b35;
        }

        .metric-label {
            color: #718096;
            font-size: 0.9em;
            margin-top: 5px;
        }

        @media (max-width: 768px) {
            .dashboard-grid {
                grid-template-columns: 1fr;
            }
            .command-section {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="time-display">
            <div class="time-box">
                Local: <span id="local-time">--:--:--</span>
            </div>
            <div class="time-box">
                UTC: <span id="utc-time">--:--:-- UTC</span>
            </div>
        </div>
        
        <div class="header">
            <h1>🍎 Apple IoT Network</h1>
            <p>Industrial IoT Network Control Center</p>
        </div>

        <div class="dashboard-grid">
            <div class="left-panel">
                <div class="status-card">
                    <h3>🌐 Network Status</h3>
                    
                    <!-- Compact AP Status Bar -->
                    <div class="ap-status-compact">
                        <span class="ap-info">🍏 Apple AP (192.168.4.1)</span>
                        <span class="status-indicator online"></span>
                        <span class="client-count" id="client-count-display">1 Client Connected</span>
                    </div>
                    
                    <div class="node-grid">
                        <div class="node-panel">
                            <h4>🔗 Connected Clients</h4>
                            <div id="connected-clients" class="client-list">
                                <div class="client-item">
                                    <span>🎃 Pumpkin (192.168.4.11)</span>
                                    <span class="status-indicator online"></span>
                                </div>
                                <div class="client-item">
                                    <span>🍒 Cherry</span>
                                    <span class="status-indicator offline"></span>
                                </div>
                                <div class="client-item">
                                    <span>🥧 Pecan</span>
                                    <span class="status-indicator offline"></span>
                                </div>
                                <div class="client-item">
                                    <span>🍑 Peach</span>
                                    <span class="status-indicator offline"></span>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="metrics">
                        <div class="metric">
                            <div class="metric-value" id="client-count">1</div>
                            <div class="metric-label">Active Clients</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value" id="uptime">00:00</div>
                            <div class="metric-label">Uptime</div>
                        </div>
                        <div class="metric">
                            <div class="metric-value" id="data-rate">0</div>
                            <div class="metric-label">Messages/min</div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="right-panel">
                <div class="command-card">
                    <h3>🎛️ Device Control</h3>
                    <div class="command-section">
                        <div class="form-group">
                            <label for="nodeSelect">Target Node:</label>
                            <select id="nodeSelect" class="form-control">
                                <option value="pumpkin">🎃 Pumpkin</option>
                                <option value="cherry">🍒 Cherry</option>
                                <option value="pecan">🥧 Pecan</option>
                                <option value="peach">🍑 Peach</option>
                                <option value="all">🌐 All Nodes</option>
                            </select>
                        </div>
                        <button class="btn btn-primary" onclick="toggleLED()">Toggle LED</button>
                    </div>
                    <div class="command-section">
                        <div class="form-group">
                            <label for="commandInput">Custom Command:</label>
                            <input type="text" id="commandInput" class="form-control" placeholder="Enter command...">
                        </div>
                        <button class="btn btn-primary" onclick="sendCommand()">Send</button>
                    </div>
                </div>

                <div class="log-card">
                    <h3>📋 Activity Log</h3>
                    <div id="log-area" class="log-area">
                        <div class="log-entry log-info">[INFO] Apple IoT Dashboard initialized</div>
                        <div class="log-entry log-success">[SUCCESS] Network monitoring started</div>
                        <div class="log-entry log-info">[INFO] DHCP server active on 192.168.4.1</div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        function addLog(message, type = 'info') {
            const logArea = document.getElementById('log-area');
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = document.createElement('div');
            logEntry.className = `log-entry log-${type}`;
            logEntry.innerHTML = `[${timestamp}] ${message}`;
            logArea.appendChild(logEntry);
            logArea.scrollTop = logArea.scrollHeight;
        }

        function toggleLED() {
            const nodeSelect = document.getElementById('nodeSelect');
            const selectedNode = nodeSelect.value;
            
            if (selectedNode === 'all') {
                addLog('Toggling LED on all nodes', 'info');
                // Send to all active nodes
                ['pumpkin', 'cherry', 'pecan', 'peach'].forEach(node => {
                    sendLEDCommand(node);
                });
            } else {
                addLog(`Toggling LED on ${selectedNode}`, 'info');
                sendLEDCommand(selectedNode);
            }
        }

        function sendLEDCommand(node) {
            fetch(`/api/led/${node}/toggle`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                }
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    addLog(`LED ${data.state} on ${node}`, 'success');
                } else {
                    addLog(`Failed to control LED on ${node}: ${data.message || 'Unknown error'}`, 'error');
                }
            })
            .catch(error => {
                addLog(`Error communicating with ${node}: ${error.message}`, 'error');
            });
        }

        function sendCommand() {
            const commandInput = document.getElementById('commandInput');
            const command = commandInput.value.trim();
            const nodeSelect = document.getElementById('nodeSelect');
            const selectedNode = nodeSelect.value;
            
            if (!command) {
                addLog('Please enter a command', 'error');
                return;
            }
            
            addLog(`Sending command "${command}" to ${selectedNode}`, 'info');
            commandInput.value = '';
            
            // Simulate command execution
            setTimeout(() => {
                addLog(`Command executed on ${selectedNode}`, 'success');
            }, 1000);
        }

        function updateUptime() {
            // Update uptime display
            const uptimeElement = document.getElementById('uptime');
            // This would normally fetch real uptime from the server
            const now = new Date();
            const hours = now.getHours().toString().padStart(2, '0');
            const minutes = now.getMinutes().toString().padStart(2, '0');
            uptimeElement.textContent = `${hours}:${minutes}`;
        }

        function updateTimeDisplays() {
            const now = new Date();
            
            // Update local time
            const localHours = now.getHours().toString().padStart(2, '0');
            const localMinutes = now.getMinutes().toString().padStart(2, '0');
            const localSeconds = now.getSeconds().toString().padStart(2, '0');
            document.getElementById('local-time').textContent = `${localHours}:${localMinutes}:${localSeconds}`;
            
            // Update UTC time
            const utcHours = now.getUTCHours().toString().padStart(2, '0');
            const utcMinutes = now.getUTCMinutes().toString().padStart(2, '0');
            const utcSeconds = now.getUTCSeconds().toString().padStart(2, '0');
            document.getElementById('utc-time').textContent = `${utcHours}:${utcMinutes}:${utcSeconds} UTC`;
        }

        function updateClientCount() {
            fetch('/api/status')
                .then(response => response.json())
                .then(data => {
                    const count = data.client_count || 0;
                    const clientCountDisplay = document.getElementById('client-count-display');
                    if (clientCountDisplay) {
                        clientCountDisplay.textContent = count === 1 ? '1 Client Connected' : `${count} Clients Connected`;
                    }
                })
                .catch(error => {
                    console.log('Error fetching client count:', error);
                });
        }

        // Initialize dashboard
        window.onload = function() {
            addLog('Apple IoT Dashboard loaded successfully', 'success');
            
            // Update time displays every second
            setInterval(updateTimeDisplays, 1000);
            updateTimeDisplays();
            
            // Update client count every 30 seconds
            setInterval(updateClientCount, 30000);
            updateClientCount();
            
            // Update uptime every minute
            setInterval(updateUptime, 60000);
            updateUptime();
            
            // Handle Enter key in command input
            document.getElementById('commandInput').addEventListener('keypress', function(e) {
                if (e.key === 'Enter') {
                    sendCommand();
                }
            });
        };
    </script>
</body>
</html>
"""


@app.route("/")
def dashboard():
    """Main dashboard page"""
    return render_template_string(DASHBOARD_HTML)


@app.route("/api/heartbeat", methods=["POST"])
def receive_heartbeat():
    """Receive heartbeat from client nodes"""
    try:
        data = request.get_json()
        node_name = data.get("node")
        if node_name:
            connected_clients[node_name] = {
                "ip": data.get("ip"),
                "status": data.get("status"),
                "timestamp": data.get("timestamp"),
                "devices": data.get("devices", []),
                "sensor_data": data.get("sensor_data", {}),
            }
            last_heartbeat[node_name] = datetime.now()

        return jsonify({"status": "received", "timestamp": datetime.now().isoformat()})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route("/api/status", methods=["GET"])
def get_status():
    """Get overall network status"""
    return jsonify(
        {
            "ap_status": "online",
            "connected_clients": connected_clients,
            "client_count": len(connected_clients),
            "timestamp": datetime.now().isoformat(),
            "uptime": time.time(),
        }
    )


@app.route("/api/nodes", methods=["GET"])
def list_nodes():
    """List all connected nodes"""
    return jsonify(
        {
            "nodes": list(connected_clients.keys()),
            "details": connected_clients,
            "timestamp": datetime.now().isoformat(),
        }
    )


@app.route("/api/led/<node_name>/toggle", methods=["POST"])
def toggle_led(node_name):
    """Toggle LED on a specific node"""
    import requests

    if node_name not in connected_clients:
        return (
            jsonify({"success": False, "message": f"Node {node_name} not connected"}),
            404,
        )

    node_info = connected_clients[node_name]
    node_ip = node_info.get("ip", "")

    if not node_ip:
        return (
            jsonify(
                {"success": False, "message": f"No IP address for node {node_name}"}
            ),
            400,
        )

    try:
        # Send LED toggle command to the client node
        response = requests.post(
            f"http://{node_ip}:5000/{node_name}/api/v1/actuators/led",
            json={"state": "toggle"},
            timeout=5,
        )

        if response.status_code == 200:
            data = response.json()
            return jsonify(
                {
                    "success": True,
                    "state": data.get("state", "unknown"),
                    "node": node_name,
                    "timestamp": datetime.now().isoformat(),
                }
            )
        else:
            return (
                jsonify(
                    {
                        "success": False,
                        "message": f"Node responded with status {response.status_code}",
                    }
                ),
                response.status_code,
            )

    except requests.exceptions.Timeout:
        return (
            jsonify(
                {"success": False, "message": f"Timeout connecting to {node_name}"}
            ),
            408,
        )

    except requests.exceptions.ConnectionError:
        return (
            jsonify(
                {
                    "success": False,
                    "message": f"Cannot connect to {node_name} at {node_ip}",
                }
            ),
            503,
        )

    except Exception as e:
        return jsonify({"success": False, "message": f"Error: {str(e)}"}), 500


if __name__ == "__main__":
    print("🍎 Starting Apple IoT Dashboard...")
    print("🌐 Dashboard: http://192.168.4.1/")
    print("📡 API: http://192.168.4.1/api/")
    print("🔧 Status: http://192.168.4.1/api/status")
    app.run(host="0.0.0.0", port=80, debug=False)
