# Restores MSI's Mystic Light to start with Windows. Needs admin.
$log = Join-Path $PSScriptRoot 'mystic.log'
$services = 'LightKeeperService', 'Mystic_Light_Service'
$task = 'MSI Task Host - LEDKeeper2_Host'
"--- enable $(Get-Date)" | Out-File $log -Append -Encoding utf8
$blockKeys = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LEDKeeper2.exe',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LEDKeeper2.exe'
foreach ($key in $blockKeys) {
    if (Test-Path $key) {
        Remove-Item $key
    }
}
$startup = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\9426MICRO-STARINTERNATION.MSICenter_kzh8wxbdkxb8p\MSI_Center_UWP'
Set-ItemProperty $startup -Name State -Value 2
try {
    Enable-ScheduledTask -TaskName $task -ErrorAction Stop | Out-Null
}
catch {
    "error on ${task}: $_" | Out-File $log -Append -Encoding utf8
}
"$task state=$((Get-ScheduledTask -TaskName $task).State)" | Out-File $log -Append -Encoding utf8
foreach ($name in $services) {
    try {
        Set-Service $name -StartupType Automatic -ErrorAction Stop
        Start-Service $name -ErrorAction Stop
    }
    catch {
        "error on ${name}: $_" | Out-File $log -Append -Encoding utf8
    }
    $s = Get-Service $name
    "$name status=$($s.Status) startup=$($s.StartType)" | Out-File $log -Append -Encoding utf8
}
