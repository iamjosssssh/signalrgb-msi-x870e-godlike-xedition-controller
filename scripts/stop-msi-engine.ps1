# Keeps MSI's CC_Engine closed while MSI Center isn't open. It competes with SignalRGB for the
# Mystic Light controller: on an animated effect, stalls went from 6 in 4 minutes to 0 without it.
# It's MSI Center's overclocking and gaming-mode engine, and MSI Center can still start it when open.
$pollSeconds = 30
while ($true) {
    if (-not (Get-Process DCv2 -ErrorAction SilentlyContinue)) {
        Get-Process CC_Engine_x64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds $pollSeconds
}
