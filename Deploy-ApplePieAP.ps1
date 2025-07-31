# Apple Pie AP - Windows PowerShell Deployment Script
# Handles SSH authentication and deployment without constant password prompts

param(
    [string]$PiIP = "192.168.86.62",
    [string]$PiUser = "admin",
    [string]$PiPass = "001234"
)

Write-Host "🍎 Apple Pie AP - Windows PowerShell Deployment" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green

# Check if we have the required files
if (-not (Test-Path "fix-apple-pie-ap.sh")) {
    Write-Host "❌ fix-apple-pie-ap.sh not found!" -ForegroundColor Red
    exit 1
}

# Step 1: Upload the configuration script
Write-Host "📤 Uploading Apple Pie AP configuration script..." -ForegroundColor Yellow

# Use SCP with expect-like functionality for Windows
$scpProcess = Start-Process -FilePath "scp" -ArgumentList @(
    "-o", "StrictHostKeyChecking=no",
    "fix-apple-pie-ap.sh",
    "$PiUser@${PiIP}:/home/admin/"
) -PassThru -Wait -NoNewWindow

if ($scpProcess.ExitCode -eq 0) {
    Write-Host "✅ Upload successful!" -ForegroundColor Green
}
else {
    Write-Host "❌ Upload failed. Trying alternative method..." -ForegroundColor Red
    
    # Alternative: Use PowerShell SSH session
    try {
        # Create SSH session and upload file content
        $sshSession = New-PSSession -HostName $PiIP -UserName $PiUser
        
        # Read the script content and create it on the Pi
        $scriptContent = Get-Content "fix-apple-pie-ap.sh" -Raw
        Invoke-Command -Session $sshSession -ScriptBlock {
            param($content)
            $content | Out-File -FilePath "/home/admin/fix-apple-pie-ap.sh" -Encoding UTF8
            chmod +x /home/admin/fix-apple-pie-ap.sh
        } -ArgumentList $scriptContent
        
        Write-Host "✅ Upload via PowerShell SSH successful!" -ForegroundColor Green
        
        # Step 2: Execute the configuration script
        Write-Host "🚀 Executing Apple Pie AP configuration..." -ForegroundColor Yellow
        Write-Host "This will:" -ForegroundColor Cyan
        Write-Host "  - Fix WiFi blocking issues" -ForegroundColor Cyan
        Write-Host "  - Configure hidden 'Apple' WiFi network" -ForegroundColor Cyan
        Write-Host "  - Set up DHCP server (192.168.4.10-50)" -ForegroundColor Cyan
        Write-Host "  - Install Flask dashboard with UART control" -ForegroundColor Cyan
        Write-Host "  - Start all AP services" -ForegroundColor Cyan
        Write-Host ""
        
        # Execute the script on the Pi
        $result = Invoke-Command -Session $sshSession -ScriptBlock {
            sudo ./fix-apple-pie-ap.sh 2>&1
        }
        
        Write-Host $result
        
        # Clean up SSH session
        Remove-PSSession $sshSession
        
    }
    catch {
        Write-Host "❌ PowerShell SSH failed: $_" -ForegroundColor Red
        Write-Host "Please run manually: ssh admin@$PiIP" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host ""
Write-Host "🎯 Deployment Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "📱 Connect to Apple Pie AP:" -ForegroundColor Cyan
Write-Host "  📶 Network: Apple (Hidden SSID)" -ForegroundColor White
Write-Host "  🔐 Password: Pharos12345" -ForegroundColor White
Write-Host "  🌐 Gateway: 192.168.4.1" -ForegroundColor White
Write-Host ""
Write-Host "🖥️  Access Dashboard:" -ForegroundColor Cyan
Write-Host "  🍎 Main: http://192.168.4.1:5000" -ForegroundColor White
Write-Host "  🔧 UART API: http://192.168.4.1:5000/api/v1/uart/" -ForegroundColor White
Write-Host ""
Write-Host "🔧 Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Connect your device to 'Apple' WiFi network" -ForegroundColor White
Write-Host "  2. Open http://192.168.4.1:5000 in browser" -ForegroundColor White
Write-Host "  3. Connect UART devices for control" -ForegroundColor White
Write-Host "  4. Deploy other Pi nodes (Cherry, Pecan, Peach) as clients" -ForegroundColor White
