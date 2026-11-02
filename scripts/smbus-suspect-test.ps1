# Finds what holds the SMBus mutex: stops Nexus, then MSI's services as well, 90 seconds each,
# recording the times, then starts them again. Compare with SignalRGB's lock timeouts. Needs admin.
$log = Join-Path $PSScriptRoot 'smbus-test.log'
function Mark($text) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $text" | Out-File $log -Append -Encoding utf8 }

$nexusServices = Get-Service | Where-Object { $_.Name -match '^Nexus' -and $_.Status -eq 'Running' }
$msiServices = Get-Service | Where-Object { ($_.Name -match '^MSI|Mystic') -and $_.Status -eq 'Running' }
Mark "nexus services: $($nexusServices.Name -join ',')"
Mark "msi services: $($msiServices.Name -join ',')"

try {
    $nexusServices | Stop-Service -Force -ErrorAction Continue
    Get-Process Nexus, nexus-overlay -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 5
    Mark "A-start nexus off; running: $((Get-Process Nexus, nexus-overlay -ErrorAction SilentlyContinue).Name -join ',')"
    Start-Sleep -Seconds 90
    Mark 'A-end'

    $msiServices | Stop-Service -Force -ErrorAction Continue
    Get-Process | Where-Object { $_.Name -match '^MSI[._]' } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    Mark "B-start nexus and msi off; running: $((Get-Process | Where-Object { $_.Name -match '^MSI[._]|^Nexus' }).Name -join ',')"
    Start-Sleep -Seconds 90
    Mark 'B-end'
}
catch {
    Mark "error: $_"
}
finally {
    $msiServices | Start-Service -ErrorAction Continue
    $nexusServices | Start-Service -ErrorAction Continue
    Mark "restarted services: $((Get-Service $msiServices.Name, $nexusServices.Name | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',')"
}
