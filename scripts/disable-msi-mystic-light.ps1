# Stops MSI's Mystic Light from starting with Windows, because it takes the board and RAM back
# from SignalRGB. MSI Center's other features are left alone. Needs admin.
# Undo with enable-msi-mystic-light.ps1.
$log = Join-Path $PSScriptRoot 'mystic.log'
$services = 'LightKeeperService', 'Mystic_Light_Service'
$task = 'MSI Task Host - LEDKeeper2_Host'
"--- disable $(Get-Date)" | Out-File $log -Append -Encoding utf8

# MSI Center re-registers and re-enables the logon task at every boot, so disabling it does not
# last. Blocking the executable by name does, including across MSI Center updates. Both registry
# views are set because 32-bit and 64-bit launchers read different ones.
$blockKeys = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LEDKeeper2.exe',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LEDKeeper2.exe'
foreach ($key in $blockKeys) {
    if (-not (Test-Path $key)) {
        New-Item $key | Out-Null
    }
    Set-ItemProperty $key -Name Debugger -Value "$env:WINDIR\System32\systray.exe"
}
Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Stop-Process -Name LEDKeeper2 -Force -ErrorAction SilentlyContinue

# The MSI Center app starts itself at sign-in through a Windows startup task.
$startup = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\9426MICRO-STARINTERNATION.MSICenter_kzh8wxbdkxb8p\MSI_Center_UWP'
Set-ItemProperty $startup -Name State -Value 1
Stop-Process -Name DCv2 -Force -ErrorAction SilentlyContinue
"MSI Center startup state=$((Get-ItemProperty $startup).State)" | Out-File $log -Append -Encoding utf8

# Prove the block: launch the task the way Windows would, then look for the process.
Start-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
"block test: LEDKeeper2 running=$([bool](Get-Process LEDKeeper2 -ErrorAction SilentlyContinue)) systray running=$([bool](Get-Process systray -ErrorAction SilentlyContinue)) task=$((Get-ScheduledTask -TaskName $task).State)" | Out-File $log -Append -Encoding utf8
Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue

foreach ($name in $services) {
    try {
        Stop-Service $name -Force -ErrorAction Stop
        Set-Service $name -StartupType Disabled -ErrorAction Stop
    }
    catch {
        "error on ${name}: $_" | Out-File $log -Append -Encoding utf8
    }
    $s = Get-Service $name
    "$name status=$($s.Status) startup=$($s.StartType)" | Out-File $log -Append -Encoding utf8
}
