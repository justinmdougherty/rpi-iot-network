#!/usr/bin/env python3
"""
Raspberry Pi IoT Client Application
===================================
Complete client node implementation with REST API endpoints for:
- Device control (LEDs, actuators)
- Sensor data collection
- Network management
- System monitoring

API Routes:
- GET endpoints: Status, sensors, configuration
- POST endpoints: Control actions, data submission
- PUT endpoints: Configuration updates

Author: Apple IoT Network Project
Version: 2.0
"""

import os
import json
import time
import socket
import threading
import requests
import subprocess
from datetime import datetime, timedelta
from flask import Flask, request, jsonify, abort
import logging
import serial
import serial.tools.list_ports

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(f'/var/log/{os.environ.get("NODE_NAME", "client")}.log'),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Node configuration
NODE_NAME = os.environ.get("NODE_NAME", "unknown")
AP_IP = "192.168.4.1"


def get_actual_ip():
    """Get the actual IP address of this device"""
    try:
        # Connect to a remote server to determine local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception as e:
        logger.error(f"Failed to get IP: {e}")
        return "127.0.0.1"


NODE_IP = get_actual_ip()

# Global state variables
sensor_data = {}
device_status = {}
system_config = {
    "heartbeat_interval": 30,
    "sensor_poll_interval": 5,
    "led_auto_off_time": 300,  # 5 minutes
    "debug_mode": False,
}
last_heartbeat = None
uart_connections = {}

# Try to import GPIO libraries with fallback
try:
    from gpiozero import LED, Button, MCP3008, PWMOutputDevice
    from gpiozero.pins.pigpio import PiGPIOFactory
    from gpiozero import Device

    try:
        Device.pin_factory = PiGPIOFactory()
        logger.info("Using pigpio pin factory for better GPIO performance")
    except Exception:
        logger.info("Using default pin factory")

    GPIO_AVAILABLE = True
except ImportError as e:
    logger.warning(f"GPIO libraries not available: {e}")
    GPIO_AVAILABLE = False


# Enhanced Device Manager
class DeviceManager:
    def __init__(self):
        self.devices = {}
        self.led_pins = [17, 18, 19, 20, 21, 26, 27]
        self.button_pins = [2, 3, 4, 14, 15, 22, 23]
        self.pwm_pins = [12, 13, 16, 25]
        self.last_led_state = {}
        self.led_timers = {}
        self.init_devices()

    def init_devices(self):
        """Initialize GPIO devices with fallback strategy"""
        if not GPIO_AVAILABLE:
            logger.warning("GPIO not available, running in simulation mode")
            return

        # Initialize LEDs with fallback pins
        led_count = 2  # Standard 2 LEDs per Pi
        for i in range(led_count):
            for pin in self.led_pins:
                try:
                    led_name = f"led_{i+1}"
                    if led_name not in self.devices:
                        self.devices[led_name] = LED(pin)
                        self.last_led_state[led_name] = False
                        logger.info(f"LED {i+1} initialized on pin {pin}")
                        self.led_pins.remove(pin)  # Remove used pin
                        break
                except Exception as e:
                    logger.debug(f"Pin {pin} busy or failed for LED {i+1}: {e}")

        # Initialize buttons
        button_count = 1
        for i in range(button_count):
            for pin in self.button_pins:
                try:
                    button_name = f"button_{i+1}"
                    if button_name not in self.devices:
                        self.devices[button_name] = Button(pin, pull_up=True)
                        logger.info(f"Button {i+1} initialized on pin {pin}")
                        self.button_pins.remove(pin)
                        break
                except Exception as e:
                    logger.debug(f"Pin {pin} busy or failed for button {i+1}: {e}")

        # Initialize PWM outputs (for dimming, servo control, etc.)
        pwm_count = 1
        for i in range(pwm_count):
            for pin in self.pwm_pins:
                try:
                    pwm_name = f"pwm_{i+1}"
                    if pwm_name not in self.devices:
                        self.devices[pwm_name] = PWMOutputDevice(pin)
                        logger.info(f"PWM {i+1} initialized on pin {pin}")
                        self.pwm_pins.remove(pin)
                        break
                except Exception as e:
                    logger.debug(f"Pin {pin} busy or failed for PWM {i+1}: {e}")

    def control_led(self, led_name, action, value=None):
        """Control LED with various actions"""
        if led_name not in self.devices:
            return {"success": False, "message": f"LED {led_name} not available"}

        try:
            led = self.devices[led_name]

            if action == "on":
                led.on()
                self.last_led_state[led_name] = True
                self._set_auto_off_timer(led_name)
                return {
                    "success": True,
                    "state": "on",
                    "message": f"LED {led_name} turned on",
                }

            elif action == "off":
                led.off()
                self.last_led_state[led_name] = False
                self._clear_auto_off_timer(led_name)
                return {
                    "success": True,
                    "state": "off",
                    "message": f"LED {led_name} turned off",
                }

            elif action == "toggle":
                if hasattr(led, "is_lit") and led.is_lit:
                    led.off()
                    self.last_led_state[led_name] = False
                    self._clear_auto_off_timer(led_name)
                    new_state = "off"
                else:
                    led.on()
                    self.last_led_state[led_name] = True
                    self._set_auto_off_timer(led_name)
                    new_state = "on"
                return {
                    "success": True,
                    "state": new_state,
                    "message": f"LED {led_name} toggled {new_state}",
                }

            elif action == "blink":
                duration = value or 1.0
                led.blink(on_time=duration / 2, off_time=duration / 2, n=3)
                return {
                    "success": True,
                    "state": "blinking",
                    "message": f"LED {led_name} blinking for {duration}s",
                }

            elif action == "pulse":
                duration = value or 2.0
                led.pulse(fade_in_time=duration / 2, fade_out_time=duration / 2)
                return {
                    "success": True,
                    "state": "pulsing",
                    "message": f"LED {led_name} pulsing",
                }

            else:
                return {"success": False, "message": f"Unknown action: {action}"}

        except Exception as e:
            logger.error(f"LED control error for {led_name}: {e}")
            return {"success": False, "message": str(e)}

    def control_pwm(self, pwm_name, value):
        """Control PWM output (0.0 to 1.0)"""
        if pwm_name not in self.devices:
            return {"success": False, "message": f"PWM {pwm_name} not available"}

        try:
            pwm = self.devices[pwm_name]
            value = max(0.0, min(1.0, float(value)))  # Clamp to 0-1
            pwm.value = value
            return {
                "success": True,
                "value": value,
                "message": f"PWM {pwm_name} set to {value:.2f}",
            }
        except Exception as e:
            logger.error(f"PWM control error for {pwm_name}: {e}")
            return {"success": False, "message": str(e)}

    def read_button(self, button_name):
        """Read button state"""
        if button_name not in self.devices:
            return {"success": False, "message": f"Button {button_name} not available"}

        try:
            button = self.devices[button_name]
            is_pressed = button.is_pressed
            return {
                "success": True,
                "pressed": is_pressed,
                "message": f'Button {button_name} {"pressed" if is_pressed else "released"}',
            }
        except Exception as e:
            logger.error(f"Button read error for {button_name}: {e}")
            return {"success": False, "message": str(e)}

    def get_device_status(self):
        """Get status of all devices"""
        status = {}
        for name, device in self.devices.items():
            try:
                if "led" in name:
                    status[name] = {
                        "type": "led",
                        "available": True,
                        "state": (
                            "on"
                            if hasattr(device, "is_lit") and device.is_lit
                            else "off"
                        ),
                    }
                elif "button" in name:
                    status[name] = {
                        "type": "button",
                        "available": True,
                        "pressed": (
                            device.is_pressed
                            if hasattr(device, "is_pressed")
                            else False
                        ),
                    }
                elif "pwm" in name:
                    status[name] = {
                        "type": "pwm",
                        "available": True,
                        "value": device.value if hasattr(device, "value") else 0.0,
                    }
            except Exception as e:
                status[name] = {"type": "unknown", "available": False, "error": str(e)}

        return status

    def _set_auto_off_timer(self, led_name):
        """Set timer to automatically turn off LED"""
        if system_config["led_auto_off_time"] > 0:
            self._clear_auto_off_timer(led_name)
            timer = threading.Timer(
                system_config["led_auto_off_time"],
                lambda: self.control_led(led_name, "off"),
            )
            timer.start()
            self.led_timers[led_name] = timer

    def _clear_auto_off_timer(self, led_name):
        """Clear auto-off timer for LED"""
        if led_name in self.led_timers:
            self.led_timers[led_name].cancel()
            del self.led_timers[led_name]


# Initialize device manager
device_manager = DeviceManager()


# UART Device Manager
class UARTManager:
    def __init__(self):
        self.connections = {}
        self.scan_for_devices()

    def scan_for_devices(self):
        """Scan for available UART devices"""
        try:
            ports = serial.tools.list_ports.comports()
            for port in ports:
                if port.device.startswith("/dev/ttyUSB") or port.device.startswith(
                    "/dev/ttyACM"
                ):
                    logger.info(f"Found UART device: {port.device}")
        except Exception as e:
            logger.error(f"UART scan error: {e}")

    def connect_device(self, device_path, baud_rate=9600):
        """Connect to UART device"""
        try:
            conn = serial.Serial(device_path, baud_rate, timeout=1)
            self.connections[device_path] = conn
            logger.info(f"Connected to UART device: {device_path}")
            return {"success": True, "message": f"Connected to {device_path}"}
        except Exception as e:
            logger.error(f"UART connection error: {e}")
            return {"success": False, "message": str(e)}

    def send_command(self, device_path, command):
        """Send command to UART device"""
        if device_path not in self.connections:
            return {"success": False, "message": "Device not connected"}

        try:
            conn = self.connections[device_path]
            conn.write(f"{command}\n".encode())
            response = conn.readline().decode().strip()
            return {"success": True, "response": response}
        except Exception as e:
            return {"success": False, "message": str(e)}


uart_manager = UARTManager()


# Helper Functions
def get_system_info():
    """Get system information"""
    try:
        with open("/proc/meminfo") as f:
            meminfo = f.read()

        with open("/proc/loadavg") as f:
            loadavg = f.read().strip()

        uptime_cmd = subprocess.run(["uptime"], capture_output=True, text=True)
        disk_cmd = subprocess.run(["df", "-h", "/"], capture_output=True, text=True)

        return {
            "hostname": socket.gethostname(),
            "ip": NODE_IP,
            "uptime": (
                uptime_cmd.stdout.strip() if uptime_cmd.returncode == 0 else "unknown"
            ),
            "load_average": loadavg.split()[:3],
            "disk_usage": (
                disk_cmd.stdout.split("\n")[1]
                if disk_cmd.returncode == 0
                else "unknown"
            ),
            "timestamp": datetime.now().isoformat(),
        }
    except Exception as e:
        logger.error(f"System info error: {e}")
        return {"error": str(e)}


def send_heartbeat():
    """Send periodic heartbeat to AP"""
    global last_heartbeat
    while True:
        try:
            heartbeat_data = {
                "node": NODE_NAME,
                "ip": NODE_IP,
                "timestamp": datetime.now().isoformat(),
                "status": "online",
                "devices": list(device_manager.devices.keys()),
                "sensor_data": sensor_data,
                "system_info": get_system_info(),
            }

            response = requests.post(
                f"http://{AP_IP}/api/heartbeat", json=heartbeat_data, timeout=5
            )

            if response.status_code == 200:
                last_heartbeat = datetime.now()
                logger.debug(f"Heartbeat sent to {AP_IP}")
            else:
                logger.warning(f"Heartbeat failed: {response.status_code}")

        except Exception as e:
            logger.error(f"Heartbeat error: {e}")

        time.sleep(system_config["heartbeat_interval"])


def sensor_monitor():
    """Monitor sensors and update data"""
    while True:
        try:
            # Read all buttons
            for device_name in device_manager.devices:
                if "button" in device_name:
                    result = device_manager.read_button(device_name)
                    if result["success"] and result["pressed"]:
                        sensor_data[f"{device_name}_press"] = {
                            "state": "pressed",
                            "timestamp": datetime.now().isoformat(),
                        }

            # Simulate temperature sensor (replace with real sensor reading)
            import random

            sensor_data["temperature"] = {
                "value": round(20 + random.random() * 10, 1),
                "unit": "celsius",
                "timestamp": datetime.now().isoformat(),
            }

            # Add CPU temperature if available
            try:
                with open("/sys/class/thermal/thermal_zone0/temp") as f:
                    cpu_temp = int(f.read()) / 1000.0
                sensor_data["cpu_temperature"] = {
                    "value": round(cpu_temp, 1),
                    "unit": "celsius",
                    "timestamp": datetime.now().isoformat(),
                }
            except:
                pass

            time.sleep(system_config["sensor_poll_interval"])

        except Exception as e:
            logger.error(f"Sensor monitoring error: {e}")
            time.sleep(10)


# ===================================
# REST API ROUTES
# ===================================

# ===============================
# GET ENDPOINTS - Read Operations
# ===============================


@app.route(f"/{NODE_NAME}/api/v1/status", methods=["GET"])
def get_node_status():
    """Get complete node status"""
    return jsonify(
        {
            "node": NODE_NAME,
            "ip": NODE_IP,
            "status": "online",
            "timestamp": datetime.now().isoformat(),
            "devices": list(device_manager.devices.keys()),
            "device_status": device_manager.get_device_status(),
            "last_heartbeat": last_heartbeat.isoformat() if last_heartbeat else None,
            "sensor_data": sensor_data,
            "system_info": get_system_info(),
            "config": system_config,
        }
    )


@app.route(f"/{NODE_NAME}/api/v1/devices", methods=["GET"])
def get_devices():
    """Get all available devices"""
    return jsonify(
        {
            "devices": device_manager.get_device_status(),
            "count": len(device_manager.devices),
            "timestamp": datetime.now().isoformat(),
        }
    )


@app.route(f"/{NODE_NAME}/api/v1/devices/<device_name>", methods=["GET"])
def get_device_status(device_name):
    """Get specific device status"""
    if device_name not in device_manager.devices:
        abort(404, f"Device {device_name} not found")

    status = device_manager.get_device_status()
    return jsonify(
        {
            "device": device_name,
            "status": status.get(device_name, {}),
            "timestamp": datetime.now().isoformat(),
        }
    )


@app.route(f"/{NODE_NAME}/api/v1/sensors", methods=["GET"])
def get_all_sensors():
    """Get all sensor data"""
    return jsonify(
        {
            "sensors": list(sensor_data.keys()),
            "data": sensor_data,
            "count": len(sensor_data),
            "timestamp": datetime.now().isoformat(),
        }
    )


@app.route(f"/{NODE_NAME}/api/v1/sensors/<sensor_name>", methods=["GET"])
def get_sensor_data(sensor_name):
    """Get specific sensor data"""
    if sensor_name not in sensor_data:
        abort(404, f"Sensor {sensor_name} not found")

    return jsonify(
        {
            "sensor": sensor_name,
            "data": sensor_data[sensor_name],
            "timestamp": datetime.now().isoformat(),
        }
    )


@app.route(f"/{NODE_NAME}/api/v1/config", methods=["GET"])
def get_config():
    """Get system configuration"""
    return jsonify({"config": system_config, "timestamp": datetime.now().isoformat()})


@app.route(f"/{NODE_NAME}/api/v1/logs", methods=["GET"])
def get_logs():
    """Get recent log entries"""
    try:
        log_file = f"/var/log/{NODE_NAME}.log"
        lines = int(request.args.get("lines", 50))

        with open(log_file, "r") as f:
            log_lines = f.readlines()[-lines:]

        return jsonify(
            {
                "logs": [line.strip() for line in log_lines],
                "lines": len(log_lines),
                "timestamp": datetime.now().isoformat(),
            }
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route(f"/{NODE_NAME}/api/v1/uart/devices", methods=["GET"])
def get_uart_devices():
    """Get available UART devices"""
    uart_manager.scan_for_devices()
    ports = []
    try:
        for port in serial.tools.list_ports.comports():
            ports.append(
                {
                    "device": port.device,
                    "description": port.description,
                    "connected": port.device in uart_manager.connections,
                }
            )
    except Exception as e:
        logger.error(f"UART device scan error: {e}")

    return jsonify(
        {
            "devices": ports,
            "active_connections": list(uart_manager.connections.keys()),
            "timestamp": datetime.now().isoformat(),
        }
    )


# ================================
# POST ENDPOINTS - Action/Control
# ================================


@app.route(f"/{NODE_NAME}/api/v1/devices/<device_name>/action", methods=["POST"])
def control_device(device_name):
    """Control a device (LEDs, PWM, etc.)"""
    if device_name not in device_manager.devices:
        abort(404, f"Device {device_name} not found")

    data = request.get_json() or {}
    action = data.get("action")
    value = data.get("value")

    if not action:
        abort(400, "Action parameter required")

    try:
        if "led" in device_name:
            result = device_manager.control_led(device_name, action, value)
        elif "pwm" in device_name:
            if action == "set":
                result = device_manager.control_pwm(device_name, value or 0)
            else:
                result = {
                    "success": False,
                    "message": f"Action {action} not supported for PWM",
                }
        elif "button" in device_name:
            if action == "read":
                result = device_manager.read_button(device_name)
            else:
                result = {"success": False, "message": "Buttons are read-only"}
        else:
            result = {
                "success": False,
                "message": f"Device type not supported: {device_name}",
            }

        result["timestamp"] = datetime.now().isoformat()
        return jsonify(result)

    except Exception as e:
        logger.error(f"Device control error: {e}")
        return jsonify({"success": False, "message": str(e)}), 500


@app.route(f"/{NODE_NAME}/api/v1/actuators/led", methods=["POST"])
def control_primary_led():
    """Control primary LED (backward compatibility)"""
    data = request.get_json() or {}
    state = data.get("state", "off")

    # Use first available LED
    led_devices = [name for name in device_manager.devices if "led" in name]
    if not led_devices:
        return jsonify({"success": False, "message": "No LED devices available"}), 404

    primary_led = led_devices[0]
    result = device_manager.control_led(primary_led, state)
    result["device"] = primary_led
    result["timestamp"] = datetime.now().isoformat()

    return jsonify(result)


@app.route(f"/{NODE_NAME}/api/v1/uart/connect", methods=["POST"])
def connect_uart():
    """Connect to UART device"""
    data = request.get_json() or {}
    device_path = data.get("device")
    baud_rate = data.get("baud_rate", 9600)

    if not device_path:
        abort(400, "Device path required")

    result = uart_manager.connect_device(device_path, baud_rate)
    result["timestamp"] = datetime.now().isoformat()

    return jsonify(result)


@app.route(f"/{NODE_NAME}/api/v1/uart/command", methods=["POST"])
def send_uart_command():
    """Send command to UART device"""
    data = request.get_json() or {}
    device_path = data.get("device")
    command = data.get("command")

    if not device_path or not command:
        abort(400, "Device path and command required")

    result = uart_manager.send_command(device_path, command)
    result["timestamp"] = datetime.now().isoformat()

    return jsonify(result)


@app.route(f"/{NODE_NAME}/api/v1/system/reboot", methods=["POST"])
def reboot_system():
    """Reboot the system"""
    try:
        logger.info("System reboot requested via API")

        # Schedule reboot in background
        def delayed_reboot():
            time.sleep(2)
            subprocess.run(["sudo", "reboot"])

        threading.Thread(target=delayed_reboot, daemon=True).start()

        return jsonify(
            {
                "success": True,
                "message": "System reboot initiated",
                "timestamp": datetime.now().isoformat(),
            }
        )
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


@app.route(f"/{NODE_NAME}/api/v1/network/reconnect", methods=["POST"])
def reconnect_network():
    """Reconnect to Apple AP"""
    try:
        logger.info("Network reconnection requested via API")

        # Reconnect to Apple network
        subprocess.run(
            ["sudo", "nmcli", "connection", "down", "Apple-Connection"],
            capture_output=True,
        )
        time.sleep(2)
        result = subprocess.run(
            ["sudo", "nmcli", "connection", "up", "Apple-Connection"],
            capture_output=True,
            text=True,
        )

        success = result.returncode == 0

        return jsonify(
            {
                "success": success,
                "message": (
                    "Network reconnection completed"
                    if success
                    else "Network reconnection failed"
                ),
                "output": result.stdout if success else result.stderr,
                "timestamp": datetime.now().isoformat(),
            }
        )
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500


# ===============================
# PUT ENDPOINTS - Update/Modify
# ===============================


@app.route(f"/{NODE_NAME}/api/v1/config", methods=["PUT"])
def update_config():
    """Update system configuration"""
    global system_config

    data = request.get_json() or {}

    # Validate and update config
    valid_keys = [
        "heartbeat_interval",
        "sensor_poll_interval",
        "led_auto_off_time",
        "debug_mode",
    ]
    updated_keys = []

    for key, value in data.items():
        if key in valid_keys:
            if key in [
                "heartbeat_interval",
                "sensor_poll_interval",
                "led_auto_off_time",
            ]:
                try:
                    system_config[key] = max(1, int(value))  # Minimum 1 second
                    updated_keys.append(key)
                except ValueError:
                    abort(400, f"Invalid value for {key}: must be integer")
            elif key == "debug_mode":
                system_config[key] = bool(value)
                updated_keys.append(key)

                # Update logging level
                log_level = logging.DEBUG if value else logging.INFO
                logging.getLogger().setLevel(log_level)

    return jsonify(
        {
            "success": True,
            "updated_keys": updated_keys,
            "config": system_config,
            "timestamp": datetime.now().isoformat(),
        }
    )


@app.route(f"/{NODE_NAME}/api/v1/devices/<device_name>/config", methods=["PUT"])
def update_device_config(device_name):
    """Update device-specific configuration"""
    if device_name not in device_manager.devices:
        abort(404, f"Device {device_name} not found")

    data = request.get_json() or {}

    # Device-specific config updates could go here
    # For now, return success with current status

    return jsonify(
        {
            "success": True,
            "device": device_name,
            "message": "Device configuration updated",
            "status": device_manager.get_device_status().get(device_name, {}),
            "timestamp": datetime.now().isoformat(),
        }
    )


# ===============================
# UTILITY ENDPOINTS
# ===============================


@app.route("/health", methods=["GET"])
def health_check():
    """Health check endpoint"""
    return jsonify(
        {
            "status": "healthy",
            "node": NODE_NAME,
            "ip": NODE_IP,
            "timestamp": datetime.now().isoformat(),
        }
    )


@app.route("/ping", methods=["GET"])
def ping():
    """Simple ping endpoint"""
    return jsonify({"pong": True, "timestamp": datetime.now().isoformat()})


@app.route(f"/{NODE_NAME}/api/v1/info", methods=["GET"])
def get_node_info():
    """Get node information and capabilities"""
    return jsonify(
        {
            "node": NODE_NAME,
            "ip": NODE_IP,
            "capabilities": {
                "gpio_available": GPIO_AVAILABLE,
                "device_count": len(device_manager.devices),
                "uart_support": True,
                "api_version": "2.0",
            },
            "api_endpoints": {
                "GET": [
                    f"/{NODE_NAME}/api/v1/status",
                    f"/{NODE_NAME}/api/v1/devices",
                    f"/{NODE_NAME}/api/v1/sensors",
                    f"/{NODE_NAME}/api/v1/config",
                    f"/{NODE_NAME}/api/v1/logs",
                ],
                "POST": [
                    f"/{NODE_NAME}/api/v1/devices/<device_name>/action",
                    f"/{NODE_NAME}/api/v1/uart/connect",
                    f"/{NODE_NAME}/api/v1/system/reboot",
                ],
                "PUT": [
                    f"/{NODE_NAME}/api/v1/config",
                    f"/{NODE_NAME}/api/v1/devices/<device_name>/config",
                ],
            },
            "timestamp": datetime.now().isoformat(),
        }
    )


# Error Handlers
@app.errorhandler(404)
def not_found(error):
    return (
        jsonify(
            {
                "error": "Not Found",
                "message": str(error.description),
                "timestamp": datetime.now().isoformat(),
            }
        ),
        404,
    )


@app.errorhandler(400)
def bad_request(error):
    return (
        jsonify(
            {
                "error": "Bad Request",
                "message": str(error.description),
                "timestamp": datetime.now().isoformat(),
            }
        ),
        400,
    )


@app.errorhandler(500)
def internal_error(error):
    return (
        jsonify(
            {
                "error": "Internal Server Error",
                "message": "An unexpected error occurred",
                "timestamp": datetime.now().isoformat(),
            }
        ),
        500,
    )


# Flask Server Runner
def run_flask_server():
    """Run Flask server"""
    logger.info(f"Starting Flask server for {NODE_NAME} on {NODE_IP}:5000")
    logger.info(f"Available devices: {list(device_manager.devices.keys())}")
    app.run(host="0.0.0.0", port=5000, debug=system_config["debug_mode"])


# Main Application
if __name__ == "__main__":
    logger.info(f"=== Starting {NODE_NAME} Client Application ===")
    logger.info(f"Node IP: {NODE_IP}")
    logger.info(f"GPIO Available: {GPIO_AVAILABLE}")
    logger.info(f"Device Count: {len(device_manager.devices)}")

    # Start background threads
    logger.info("Starting background services...")

    heartbeat_thread = threading.Thread(target=send_heartbeat, daemon=True)
    heartbeat_thread.start()

    sensor_thread = threading.Thread(target=sensor_monitor, daemon=True)
    sensor_thread.start()

    logger.info("Background services started")

    # Start Flask server
    try:
        run_flask_server()
    except KeyboardInterrupt:
        logger.info(f"{NODE_NAME} client application stopping")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
