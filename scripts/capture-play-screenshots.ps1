# Capture Google Play store screenshots from running emulator.
param(
    [string]$OutDir = "dist/play-store-screenshots",
    [string]$Apk = "build/app/outputs/flutter-apk/app-sideload-debug.apk"
)

$ErrorActionPreference = "Stop"
$env:Path = "F:\Tools\android-sdk\platform-tools;" + $env:Path
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$phoneDir = Join-Path $root "$OutDir/phone"
$tablet7Dir = Join-Path $root "$OutDir/tablet-7"
$tablet10Dir = Join-Path $root "$OutDir/tablet-10"
foreach ($d in @($phoneDir, $tablet7Dir, $tablet10Dir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

function Wait-Device {
    for ($i = 0; $i -lt 40; $i++) {
        $boot = adb -e shell getprop sys.boot_completed 2>$null
        if ($boot -match "1") { return }
        Start-Sleep -Seconds 2
    }
    throw "Emulator not ready"
}

function Prep-Device([string]$Size) {
    adb -e shell wm size $Size | Out-Null
    adb -e shell settings put global policy_control "immersive.navigation=*" | Out-Null
    adb -e shell cmd statusbar collapse 2>$null | Out-Null
}

function Capture([string]$Path) {
    Start-Sleep -Milliseconds 900
    adb -e exec-out screencap -p | Set-Content -Path $Path -Encoding Byte -NoNewline
    $img = [System.Drawing.Image]::FromFile($Path)
    Write-Host "Captured $($img.Width)x$($img.Height) -> $Path"
    $img.Dispose()
}

function Tap([int]$X, [int]$Y) {
    adb -e shell input tap $X $Y | Out-Null
    Start-Sleep -Milliseconds 700
}

function Back {
    adb -e shell input keyevent 4 | Out-Null
    Start-Sleep -Milliseconds 600
}

function Launch-App {
    adb -e shell pm clear com.avee.vpn.debug | Out-Null
    adb -e shell am start -n com.avee.vpn.debug/com.avee.vpn.MainActivity | Out-Null
    Start-Sleep -Seconds 8
}

Wait-Device
adb -e install -r (Join-Path $root $Apk) | Out-Null

# Phone 9:16 (1080x1920) — Play compliant aspect ratio.
Prep-Device "1080x1920"
Launch-App
Capture (Join-Path $phoneDir "01-home.png")

Tap 540 1698
Start-Sleep -Seconds 2
Capture (Join-Path $phoneDir "02-locations.png")
Back
Start-Sleep -Seconds 1

Tap 996 142
Start-Sleep -Seconds 1
Tap 540 420
Start-Sleep -Seconds 2
Capture (Join-Path $phoneDir "03-account.png")
Back
Start-Sleep -Seconds 1

Tap 996 142
Start-Sleep -Seconds 1
Tap 540 520
Start-Sleep -Seconds 2
Capture (Join-Path $phoneDir "04-subscription.png")
Back
Start-Sleep -Seconds 1
Back

Launch-App
Tap 540 750
Start-Sleep -Seconds 2
# Accept VPN permission if shown
adb -e shell input tap 810 1450 2>$null | Out-Null
Start-Sleep -Seconds 4
Capture (Join-Path $phoneDir "05-connected.png")

# Tablet folders: reuse phone shots (app has no tablet-specific layout).
Get-ChildItem $phoneDir -Filter "*.png" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $tablet7Dir $_.Name) -Force
    Copy-Item $_.FullName (Join-Path $tablet10Dir $_.Name) -Force
}

Write-Host "Done. Screenshots in $OutDir"
