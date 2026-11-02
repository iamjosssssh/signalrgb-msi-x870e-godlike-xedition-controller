# Shows real pictures for two devices that use SignalRGB's own plugins: G.Skill Trident Z5 Neo RAM and
# the Razer Basilisk V3 Pro's dongle. It copies the current plugin to the user plugins folder with only
# the image changed, so it needs no copy of SignalRGB's code in this repo. Run it again after a
# SignalRGB update to pick up changes. It prints True if a file changed, and then SignalRGB needs a
# restart. A plugin whose code no longer matches gets no copy, so it falls back to SignalRGB's own.
# -Remove deletes the copies.
param([switch]$Remove)
$images = 'https://raw.githubusercontent.com/iamjosssssh/signalrgb-msi-x870e-godlike-xedition-controller/main/assets/devices'
$folder = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WhirlwindFX\Plugins\DeviceImages'

if ($Remove) {
    Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
    return $true
}

$ram = @{
    Name = 'ENE_RAM.js'; Vendor = 'Asus'
    Find = 'export function ImageUrl\(\)\s*\{\s*return "[^"]+";\s*\}'
    Replace = "export function ImageUrl() { return `"$images/trident-z5-neo.png`"; }"
}
$razer = @{
    Name = 'Razer_Modern_Mouse.js'; Vendor = 'Razer'
    Find = 'export function Initialize\(\)\s*\{'
    Replace = "export function Initialize() {`n`tif (device.productId() === 0x00CD) { device.setImageFromUrl(`"$images/razer-dongle.png`"); }"
}

# SignalRGB prefers its downloaded plugin updates over the copies in its install folder.
function Get-Source($vendor, $name) {
    $cached = Join-Path $env:LOCALAPPDATA "WhirlwindFX\SignalRgb\cache\plugin_cdn\main\Plugins\$vendor\$name"
    if (Test-Path -LiteralPath $cached) { return $cached }
    $app = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'VortxEngine') -Directory -Filter 'app-*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($app) { Join-Path $app.FullName "Signal-x64\Plugins\$vendor\$name" }
}

$changed = $false
foreach ($patch in $ram, $razer) {
    $target = Join-Path $folder $patch.Name
    $source = Get-Source $patch.Vendor $patch.Name
    $text = if ($source -and (Test-Path -LiteralPath $source)) { [IO.File]::ReadAllText($source) } else { '' }
    $found = [regex]::Matches($text, $patch.Find).Count
    if ($found -ne 1) {
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Force
            $changed = $true
        }
        continue
    }
    $patched = [regex]::Replace($text, $patch.Find, { param($m) $patch.Replace })
    if ((Test-Path -LiteralPath $target) -and [IO.File]::ReadAllText($target) -ceq $patched) { continue }
    New-Item -ItemType Directory -Force $folder | Out-Null
    [IO.File]::WriteAllText($target, $patched)
    $changed = $true
}
$changed
