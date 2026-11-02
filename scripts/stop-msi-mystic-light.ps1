# Stops MSI's lighting helpers so SignalRGB can drive the board, for this session only.
# Startup settings are not changed, so they return after a reboot. Needs admin.
$log = Join-Path $PSScriptRoot 'mystic.log'
function Mark($text) { "$(Get-Date -Format 'HH:mm:ss') $text" | Out-File $log -Append -Encoding utf8 }
Mark '--- stop'
Mark "before: $((Get-Process LEDKeeper2, LEDKeeper, DCv2, Mystic_Light_Service, LightKeeperService -ErrorAction SilentlyContinue).Name -join ',')"
try {
    Stop-Service LightKeeperService, Mystic_Light_Service -Force -ErrorAction Stop
}
catch {
    Mark "service stop error: $_"
}
Get-Process LEDKeeper2, LEDKeeper, DCv2 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 15
Mark "services: $((Get-Service LightKeeperService, Mystic_Light_Service | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',')"
Mark "after 15s: $((Get-Process LEDKeeper2, LEDKeeper, DCv2, Mystic_Light_Service, LightKeeperService -ErrorAction SilentlyContinue).Name -join ',')"
