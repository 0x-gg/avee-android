# Launch a Play-screenshot AVD with a clean AVEE debug install.
param(
    [ValidateSet('AVEE_Play_Phone', 'AVEE_Play_Tablet7', 'AVEE_Play_Tablet10')]
    [string]$Avd = 'AVEE_Play_Phone',
    [string]$Apk = 'build/app/outputs/flutter-apk/app-sideload-debug.apk',
    [switch]$WipeData
)

$ErrorActionPreference = 'Stop'
$env:Path = 'F:\Tools\android-sdk\platform-tools;F:\Tools\android-sdk\emulator;' + $env:Path
$env:ANDROID_HOME = 'F:\Tools\android-sdk'
$env:ANDROID_AVD_HOME = 'F:\Tools\android-avd'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

function Wait-Device {
    adb wait-for-device | Out-Null
    for ($i = 0; $i -lt 90; $i++) {
        try {
            $boot = & adb -e shell getprop sys.boot_completed 2>$null
            if ($boot -match '1') { return }
        } catch {
            # Emulator adb can briefly close while booting.
        }
        Start-Sleep -Seconds 2
    }
    throw "Emulator not ready"
}

function Reset-AveeApp {
    adb -e shell pm clear com.avee.vpn.debug | Out-Null
    adb -e shell am start -n com.avee.vpn.debug/com.avee.vpn.MainActivity | Out-Null
}

Write-Host "Stopping current emulator..."
adb -e emu kill 2>$null | Out-Null
Start-Sleep -Seconds 3

$launchArgs = @('-avd', $Avd, '-no-snapshot-load')
if ($WipeData) {
    $launchArgs += '-wipe-data'
}

Write-Host "Launching $Avd..."
Start-Process -FilePath 'emulator' -ArgumentList $launchArgs -WindowStyle Normal | Out-Null

Wait-Device

$apkPath = Join-Path $root $Apk
if (-not (Test-Path $apkPath)) {
    throw "APK not found: $apkPath"
}

Write-Host "Installing APK..."
adb -e install -r -g $apkPath | Out-Null

Write-Host "Resetting AVEE app data for a fresh test session..."
Reset-AveeApp

Write-Host "Ready: $Avd with clean Create account screen."
