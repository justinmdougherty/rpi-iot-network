# PowerShell script to deploy Apple node configuration
# Run this from Windows to transfer files and configure the Apple Pi

param(
    [string]$PiIP,
    [string]$Username = "admin",
    [switch]$FindPi
)

Write-Host "======================================"
Write-Host "Apple Node Deployment Script"
Write-Host "======================================"

# Function to find Raspberry Pi on network
function Find-RaspberryPi {
    Write-Host "🔍 Scanning for Raspberry Pi devices on local network..."
    Write-Host "This may take a moment..."
    
    # Get local network range
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.*" -and $_.PrefixOrigin -eq "Dhcp" }).IPAddress
    if ($localIP) {
        $networkBase = $localIP.Substring(0, $localIP.LastIndexOf('.'))
        Write-Host "Scanning network: ${networkBase}.1-254"
        
        # Common Pi hostnames to check
        $piHostnames = @("raspberrypi", "raspberrypi.local")
        
        Write-Host "`nTrying common Pi hostnames:"
        foreach ($hostname in $piHostnames) {
            try {
                $result = Test-NetConnection -ComputerName $hostname -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue
                if ($result) {
                    $resolvedIP = [System.Net.Dns]::GetHostAddresses($hostname)[0].IPAddressToString
                    Write-Host "✅ Found Pi at: $hostname ($resolvedIP)"
                    return $resolvedIP
                }
            }
            catch {
                # Silently continue
            }
        }
        
        Write-Host "❌ No Pi found with common hostnames"
    }
    
    Write-Host "`n💡 Manual discovery options:"
    Write-Host "1. Check your router's admin page for connected devices"
    Write-Host "2. Use: arp -a | findstr b8-27-eb"
    Write-Host "3. Use network scanner like Advanced IP Scanner"
    Write-Host "4. Connect monitor/keyboard to Pi to see IP with: hostname -I"
    
    return $null
}

# Handle IP discovery
if ($FindPi) {
    $discoveredIP = Find-RaspberryPi
    if ($discoveredIP) {
        $PiIP = $discoveredIP
        Write-Host "Using discovered IP: $PiIP"
    }
    else {
        Write-Host "Unable to automatically discover Pi IP."
        exit 1
    }
}
elseif (-not $PiIP) {
    Write-Host "❌ No Pi IP specified."
    Write-Host ""
    Write-Host "Usage options:"
    Write-Host "  .\Deploy-AppleNode.ps1 -PiIP 192.168.1.100"
    Write-Host "  .\Deploy-AppleNode.ps1 -FindPi"
    Write-Host ""
    Write-Host "💡 To find your Pi's IP address:"
    Write-Host "1. Check router admin page for 'raspberrypi' device"
    Write-Host "2. Run: arp -a | findstr b8-27-eb"
    Write-Host "3. Connect monitor to Pi and run: hostname -I"
    Write-Host "4. Use network scanner like Advanced IP Scanner"
    exit 1
}

# Check if we have the required files
$requiredFiles = @("setup-apple-node.sh")
foreach ($file in $requiredFiles) {
    if (!(Test-Path $file)) {
        Write-Error "Required file $file not found in current directory"
        exit 1
    }
}

Write-Host "Transferring setup script to Pi at $PiIP..."

# Use SCP to transfer the setup script
try {
    Write-Host "Using credentials: admin/001234"
    scp setup-apple-node.sh "${Username}@${PiIP}:/home/admin/"
    Write-Host "✅ Setup script transferred successfully"
}
catch {
    Write-Error "❌ Failed to transfer setup script: $_"
    Write-Host "Please enter password: 001234"
    exit 1
}

Write-Host ""
Write-Host "Connecting to Pi and running setup..."
Write-Host "This will:"
Write-Host "  1. Create admin user (admin/001234)"
Write-Host "  2. Set hostname to 'apple'"
Write-Host "  3. Configure WiFi for hidden 'Apple' network"
Write-Host "  4. Set static IP to 192.168.4.12"
Write-Host "  5. Install and configure client application"
Write-Host ""

# Connect via SSH and run the setup
try {
    ssh "${Username}@${PiIP}" "chmod +x setup-apple-node.sh"
    ssh "${Username}@${PiIP}" "./setup-apple-node.sh"
    Write-Host "✅ Setup completed successfully"
}
catch {
    Write-Error "❌ Setup failed: $_"
    exit 1
}

Write-Host ""
Write-Host "======================================"
Write-Host "Apple Node Configuration Complete!"
Write-Host "======================================"
Write-Host "Node Details:"
Write-Host "  Name: apple"
Write-Host "  IP: 192.168.4.12"
Write-Host "  Network: Apple (hidden)"
Write-Host "  User: admin / Password: 001234"
Write-Host ""
Write-Host "Next Steps:"
Write-Host "  1. Reboot the Pi: ssh admin@192.168.4.12 'sudo reboot'"
Write-Host "  2. Verify connection: ssh admin@192.168.4.12"
Write-Host "  3. Check service: ssh admin@192.168.4.12 'sudo systemctl status client_app.service'"
Write-Host ""
Write-Host "API Endpoints available at:"
Write-Host "  - http://192.168.4.12:5000/apple/api/v1/status"
Write-Host "  - http://192.168.4.12:5000/apple/api/v1/actuators/led"
Write-Host "======================================"
