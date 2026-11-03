# One-command setup for this board. Asks for admin rights.
#  - Installs the plugin in SignalRGB's user plugins folder. It has to go there: a user plugin replaces
#    SignalRGB's own by file name, but a plugin in an add-on loses to SignalRGB's downloaded copy.
#  - Stops MSI's Mystic Light from taking the board and RAM back, if MSI Center is installed.
#  - Keeps MSI's CC_Engine closed unless MSI Center is open, which stops the RAM stutter.
#  - Turns off the copy of OpenRGB bundled with L-Connect 3, if it's there.
#  - Builds the helper that puts SignalRGB's LCD frames on the Dynamic Dashboard, and starts it at sign-in.
# -DevicePictures also runs tools\apply-device-images.ps1. -DryRun lists the steps and changes nothing.
# -Remove undoes it all.
param([switch]$DryRun, [switch]$Remove, [switch]$DevicePictures)

$repo = Split-Path $PSScriptRoot -Parent
$pluginFolder = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WhirlwindFX\Plugins\MSI_Godlike_X'
$installFolder = Join-Path $env:LOCALAPPDATA 'MSIGodlikeSignalRGB'
$engineTask = 'Keep MSI CC_Engine Closed'
$bridgeTask = 'MSI Dashboard LCD Bridge'
$openRgb = 'C:\Program Files\Lian-Li\L-Connect 3\OpenRGB\OpenRGB.exe'
$msiCenter = 'LightKeeperService', 'Mystic_Light_Service'

if ($DryRun) {
    "Would copy the plugin to $pluginFolder"
    "Would add the sign-in task '$engineTask', run from $installFolder"
    "Would build the LCD helper with the C# compiler that ships with Windows, and add the sign-in task '$bridgeTask'"
    if (Get-Service $msiCenter -ErrorAction SilentlyContinue) { "Would run disable-msi-mystic-light.ps1" } else { 'MSI Center not found, nothing to do for it' }
    if (Test-Path $openRgb) { "Would run disable-lconnect-openrgb.ps1" } else { 'L-Connect OpenRGB not found, nothing to do for it' }
    return
}

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Remove) { $arguments += '-Remove' }
    if ($DevicePictures) { $arguments += '-DevicePictures' }
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList $arguments
    return
}
$ErrorActionPreference = 'Stop'

if ($Remove) {
    Unregister-ScheduledTask -TaskName $engineTask -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $bridgeTask -Confirm:$false -ErrorAction SilentlyContinue
    Get-Process GodlikeLcdBridge -ErrorAction SilentlyContinue | Stop-Process -Force
    Remove-Item $installFolder -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $pluginFolder -Recurse -Force -ErrorAction SilentlyContinue
    & (Join-Path $PSScriptRoot 'enable-msi-mystic-light.ps1')
    if (Test-Path "$openRgb.disabled") { & (Join-Path $PSScriptRoot 'enable-lconnect-openrgb.ps1') }
    & (Join-Path $repo 'tools\apply-device-images.ps1') -Remove | Out-Null
    'Removed. Restart SignalRGB.'
    return
}

New-Item -ItemType Directory -Force $pluginFolder | Out-Null
Copy-Item (Join-Path $repo 'plugin\MSI_185Byte_Controller_0x0DB0.js') $pluginFolder -Force

# SignalRGB can replace or delete its add-on folder, so the sign-in task runs from its own copy.
New-Item -ItemType Directory -Force $installFolder | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'stop-msi-engine.ps1') $installFolder -Force
$user = "$env:USERDOMAIN\$env:USERNAME"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installFolder\stop-msi-engine.ps1`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $engineTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $engineTask

Get-Process GodlikeLcdBridge -ErrorAction SilentlyContinue | Stop-Process -Force
$bridge = Join-Path $installFolder 'GodlikeLcdBridge.exe'
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /optimize+ /target:winexe /r:System.Drawing.dll "/out:$bridge" (Join-Path $repo 'bridge\GodlikeLcdBridge.cs')
if ($LASTEXITCODE -ne 0) { throw 'The LCD helper did not compile.' }
$bridgeAction = New-ScheduledTaskAction -Execute $bridge
$bridgePrincipal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $bridgeTask -Action $bridgeAction -Trigger $trigger -Principal $bridgePrincipal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $bridgeTask

if (Get-Service $msiCenter -ErrorAction SilentlyContinue) { & (Join-Path $PSScriptRoot 'disable-msi-mystic-light.ps1') }
if (Test-Path $openRgb) { & (Join-Path $PSScriptRoot 'disable-lconnect-openrgb.ps1') }
if ($DevicePictures) { & (Join-Path $repo 'tools\apply-device-images.ps1') | Out-Null }
'Done. Restart SignalRGB. Its log should show Custom Plugin File Loaded for this plugin.'
