#!/bin/bash
# Apple Node Validation Script
# Run this after setup to verify everything is working correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SUCCESS_COUNT=0
TOTAL_TESTS=0

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo "======================================"
echo "Apple Node Validation Script"
echo "======================================"

# Test 1: Check hostname
log_test "Checking hostname..."
if [ "$(hostname)" = "apple" ]; then
    log_pass "Hostname is correctly set to 'apple'"
else
    log_fail "Hostname is '$(hostname)', expected 'apple'"
fi

# Test 2: Check admin user exists
log_test "Checking admin user..."
if id admin &>/dev/null; then
    log_pass "Admin user exists"
else
    log_fail "Admin user does not exist"
fi

# Test 3: Check IP address
log_test "Checking IP address..."
if ip addr show wlan0 2>/dev/null | grep -q "192.168.4.12"; then
    log_pass "Static IP 192.168.4.12 is assigned"
else
    log_fail "Static IP 192.168.4.12 not found"
    ip addr show wlan0 2>/dev/null || echo "wlan0 interface not found"
fi

# Test 4: Check WiFi connection
log_test "Checking WiFi connection..."
if nmcli connection show --active | grep -q "Apple"; then
    log_pass "Connected to Apple network"
else
    log_fail "Not connected to Apple network"
    nmcli connection show --active
fi

# Test 5: Check connectivity to AP
log_test "Testing connectivity to AP..."
if ping -c 3 192.168.4.1 &>/dev/null; then
    log_pass "Can reach AP at 192.168.4.1"
else
    log_fail "Cannot reach AP at 192.168.4.1"
fi

# Test 6: Check Python dependencies
log_test "Checking Python dependencies..."
if python3 -c "import flask, requests, gpiozero" 2>/dev/null; then
    log_pass "All Python dependencies are installed"
else
    log_fail "Missing Python dependencies"
fi

# Test 7: Check project files
log_test "Checking project files..."
if [ -f "/home/admin/client_project/client_app.py" ]; then
    log_pass "Client application file exists"
else
    log_fail "Client application file missing"
fi

# Test 8: Check systemd service
log_test "Checking systemd service..."
if systemctl is-enabled client_app.service &>/dev/null; then
    log_pass "client_app.service is enabled"
else
    log_fail "client_app.service is not enabled"
fi

# Test 9: Check if service is running
log_test "Checking if service is running..."
if systemctl is-active client_app.service &>/dev/null; then
    log_pass "client_app.service is running"
else
    log_warn "client_app.service is not running (may need to start manually)"
fi

# Test 10: Check API response
log_test "Testing API endpoints..."
sleep 2  # Give service time to start if it was just started
if curl -s http://localhost:5000/apple/api/v1/status &>/dev/null; then
    log_pass "API endpoint responds"
else
    log_warn "API endpoint not responding (service may be starting)"
fi

# Test 11: Check GPIO group membership
log_test "Checking GPIO permissions..."
if groups admin | grep -q gpio; then
    log_pass "Admin user is in GPIO group"
else
    log_fail "Admin user not in GPIO group"
fi

echo ""
echo "======================================"
echo "Validation Summary"
echo "======================================"
echo "Tests passed: $SUCCESS_COUNT/$TOTAL_TESTS"

if [ $SUCCESS_COUNT -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}✅ All tests passed! Apple node is fully configured.${NC}"
    echo ""
    echo "Apple node is ready for use:"
    echo "- SSH: ssh admin@192.168.4.12"
    echo "- API: http://192.168.4.12:5000/apple/api/v1/status"
    echo "- LED Control: POST http://192.168.4.12:5000/apple/api/v1/actuators/led"
else
    echo -e "${YELLOW}⚠️  Some tests failed. Check the output above.${NC}"
    echo ""
    echo "Common fixes:"
    echo "- Start service: sudo systemctl start client_app.service"
    echo "- Connect WiFi: sudo nmcli connection up Apple"
    echo "- Check logs: journalctl -u client_app.service -f"
fi

echo "======================================"
