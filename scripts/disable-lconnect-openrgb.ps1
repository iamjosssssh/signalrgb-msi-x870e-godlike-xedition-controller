# L-Connect 3 starts a bundled OpenRGB that drives RAM, GPU, keyboard and Mystic Light,
# and corrupts SignalRGB's RAM scan. This turns off only that copy of OpenRGB. L-Connect
# keeps running fans, pump and LCDs. L-Connect updates may restore the file. Needs admin.
# Undo with enable-lconnect-openrgb.ps1.
$dir = 'C:\Program Files\Lian-Li\L-Connect 3\OpenRGB'
$log = Join-Path $PSScriptRoot 'openrgb.log'
"--- disable $(Get-Date)" | Out-File $log -Append -Encoding utf8
try {
    if (Test-Path "$dir\OpenRGB.exe") {
        Rename-Item "$dir\OpenRGB.exe" 'OpenRGB.exe.disabled' -ErrorAction Stop
    }
    Get-Process OpenRGB -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    "exe present: $(Test-Path "$dir\OpenRGB.exe")" | Out-File $log -Append -Encoding utf8
    "running: $([bool](Get-Process OpenRGB -ErrorAction SilentlyContinue))" | Out-File $log -Append -Encoding utf8
}
catch {
    "error: $_" | Out-File $log -Append -Encoding utf8
}
