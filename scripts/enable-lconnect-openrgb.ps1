# Restores L-Connect 3's bundled OpenRGB. Needs admin.
$dir = 'C:\Program Files\Lian-Li\L-Connect 3\OpenRGB'
$log = Join-Path $PSScriptRoot 'openrgb.log'
"--- enable $(Get-Date)" | Out-File $log -Append -Encoding utf8
try {
    if (Test-Path "$dir\OpenRGB.exe.disabled") {
        Rename-Item "$dir\OpenRGB.exe.disabled" 'OpenRGB.exe' -ErrorAction Stop
    }
    Restart-Service LConnectService -Force -ErrorAction Stop
    "exe present: $(Test-Path "$dir\OpenRGB.exe")" | Out-File $log -Append -Encoding utf8
}
catch {
    "error: $_" | Out-File $log -Append -Encoding utf8
}
