# Raspberry Pi IP Discovery Helper (PowerShell)
# Various methods to find your Pi's IP address on the network

Write-Host "======================================"
Write-Host "Raspberry Pi IP Discovery Helper"
Write-Host "======================================"

$foundIPs = @()

Write-Host "🔍 Method 1: Checking common hostnames..."
$commonHostnames = @("raspberrypi", "raspberrypi.local")

foreach ($hostname in $commonHostnames) {
    Write-Host "Trying $hostname... " -NoNewline
    try {
        $result = Test-NetConnection -ComputerName $hostname -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($result) {
            $ip = [System.Net.Dns]::GetHostAddresses($hostname)[0].IPAddressToString
            Write-Host "✅ FOUND: $hostname ($ip)" -ForegroundColor Green
            $foundIPs += $ip
        }
        else {
            Write-Host "❌ Not found" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "❌ Not found" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "🔍 Method 2: Scanning ARP table for Pi MAC addresses..."
Write-Host "Looking for Raspberry Pi Foundation MAC addresses (B8-27-EB, DC-A6-32, E4-5F-01)..."

try {
    $arpEntries = arp -a | Select-String -Pattern "(b8-27-eb|dc-a6-32|e4-5f-01)" -AllMatches
    
    if ($arpEntries) {
        foreach ($entry in $arpEntries) {
            $line = $entry.Line
            $ip = ($line | Select-String -Pattern "\d+\.\d+\.\d+\.\d+").Matches[0].Value
            $mac = ($line | Select-String -Pattern "([0-9a-f]{2}-){5}[0-9a-f]{2}").Matches[0].Value
            Write-Host "✅ FOUND Pi: $ip ($mac)" -ForegroundColor Green
            $foundIPs += $ip
        }
    }
    else {
        Write-Host "❌ No Pi MAC addresses found in ARP table" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "❌ Error scanning ARP table" -ForegroundColor Red
}

Write-Host ""
Write-Host "🔍 Method 3: Network scan (advanced)..."
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "192.168.*" -and $_.PrefixOrigin -eq "Dhcp" }).IPAddress

if ($localIP) {
    $networkBase = $localIP.Substring(0, $localIP.LastIndexOf('.'))
    Write-Host "Scanning network: $networkBase.1-254 (this may take time)"
    Write-Host "Note: This requires PowerShell 5.1+ and may be slow"
    
    # Only scan if user wants to wait
    $response = Read-Host "Perform network scan? This can take several minutes (y/N)"
    if ($response -eq 'y' -or $response -eq 'Y') {
        $jobs = @()
        for ($i = 1; $i -le 254; $i++) {
            $ip = "$networkBase.$i"
            $jobs += Start-Job -ScriptBlock {
                param($targetIP)
                if (Test-NetConnection -ComputerName $targetIP -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue) {
                    return $targetIP
                }
            } -ArgumentList $ip
        }
        
        Write-Host "Waiting for scan to complete..."
        $jobs | Wait-Job | ForEach-Object {
            $result = Receive-Job $_
            if ($result) {
                Write-Host "✅ SSH responding: $result" -ForegroundColor Green
                $foundIPs += $result
            }
            Remove-Job $_
        }
    }
}

Write-Host ""
Write-Host "🔍 Method 4: Manual discovery options..."
Write-Host "If automatic discovery didn't work, try these:"
Write-Host ""
Write-Host "Router Admin Page:"
Write-Host "  1. Open your router's web interface (usually http://192.168.1.1 or http://192.168.0.1)"
Write-Host "  2. Look for connected devices or DHCP client list"
Write-Host "  3. Find device named 'raspberrypi' or with Pi MAC address"
Write-Host ""
Write-Host "Command Line Options:"
Write-Host "  • arp -a | findstr /i \"b8-27-eb dc-a6-32 e4-5f-01\""
Write-Host "  • Use network scanner like Advanced IP Scanner"
Write-Host "  • Use Angry IP Scanner or similar tool"
Write-Host ""
Write-Host "Direct Pi Access:"
Write-Host "  • Connect monitor and keyboard to Pi"
Write-Host "  • Run: hostname -I"
Write-Host "  • Or check: ip addr show"

Write-Host ""
Write-Host "======================================"

$uniqueIPs = $foundIPs | Sort-Object | Get-Unique

if ($uniqueIPs.Count -gt 0) {
    Write-Host "✅ Found potential Pi IP(s):" -ForegroundColor Green
    foreach ($ip in $uniqueIPs) {
        Write-Host "  $ip" -ForegroundColor Cyan
    }
    
    if ($uniqueIPs.Count -eq 1) {
        Write-Host ""
        Write-Host "To deploy Apple node configuration:"
        Write-Host "  .\Deploy-AppleNode.ps1 -PiIP $($uniqueIPs[0])" -ForegroundColor Yellow
    }
    else {
        Write-Host ""
        Write-Host "Multiple IPs found. Test each one:"
        foreach ($ip in $uniqueIPs) {
            Write-Host "  .\Deploy-AppleNode.ps1 -PiIP $ip" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "❌ No Pi automatically discovered" -ForegroundColor Red
    Write-Host "Try the manual methods listed above" -ForegroundColor Yellow
}

Write-Host "======================================"
