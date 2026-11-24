# Local Windows x64 build (Flutter) – mirrors .github/workflows/flutter-build.yml
# Usage:  .\build-windows.ps1 -Server <host> -PubKey <key>   -> regenerate bridge + build
#         .\build-windows.ps1 ... -SkipBridge                -> build only (flutter_ffi.rs unchanged)
# -Server / -PubKey are compiled into hbb_common (RENDEZVOUS_SERVER / RS_PUB_KEY).
# Without them the client falls back to the upstream public RustDesk servers.
# -ApiServer (e.g. https://api.daremoto.net) enables login, address book and groups
# (API_SERVER); without it those features are hidden.
param(
    [string]$Server,
    [string]$PubKey,
    [string]$ApiServer,
    [switch]$SkipBridge,
    [switch]$Portable   # also pack the single-file daremoto-<version>.exe (repo root)
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if ($ApiServer) {
    if ($ApiServer -notmatch '^https?://') { throw '-ApiServer must start with http:// or https://' }
    $env:API_SERVER = $ApiServer.TrimEnd('/')
    Write-Host "API server: $env:API_SERVER"
} else {
    Remove-Item Env:API_SERVER -ErrorAction SilentlyContinue
    Write-Host 'No -ApiServer: login, address book and groups hidden'
}

if ([bool]$Server -ne [bool]$PubKey) { throw '-Server and -PubKey must be given together' }
if ($Server) {
    $env:RENDEZVOUS_SERVER = $Server
    $env:RS_PUB_KEY = $PubKey
    Write-Host "Rendezvous server: $Server"
} else {
    Remove-Item Env:RENDEZVOUS_SERVER, Env:RS_PUB_KEY -ErrorAction SilentlyContinue
    Write-Warning 'No -Server/-PubKey: building against the public RustDesk servers'
}

# Everything must run inside the MSVC dev environment: libclang (bindgen / ffigen)
# needs its INCLUDE paths, otherwise stdint.h / stdbool.h are not found and the
# generated Dart bridge ends up with a bogus `typedef bool`.
$vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -products * `
      -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'

# vcvars64 overwrites VCPKG_ROOT with Visual Studio's bundled vcpkg: re-set it afterwards.
$vcpkgRoot = "$env:USERPROFILE\dev\vcpkg"
$env:LIBCLANG_PATH = 'C:\Program Files\LLVM\bin'
# x64 uses libsodium-sys' bundled lib: SODIUM_LIB_DIR must NOT be set (CI sets it only for arm64).
Remove-Item Env:SODIUM_LIB_DIR -ErrorAction SilentlyContinue

function Invoke-InVsEnv([string]$cmd) {
    cmd /c "`"$vcvars`" >nul && set `"VCPKG_ROOT=$vcpkgRoot`" && $cmd"
    if ($LASTEXITCODE -ne 0) { throw "Failed ($LASTEXITCODE): $cmd" }
}

if (-not $SkipBridge) {
    Push-Location flutter; flutter pub get; Pop-Location
    Invoke-InVsEnv 'flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h'
    Copy-Item ./flutter/macos/Runner/bridge_generated.h ./flutter/ios/Runner/bridge_generated.h
}

# Virtual display driver (Amyuni usbmmidd_v2), same package and same files as the official
# workflow: without it a PC with no monitor attached answers "No displays".
# build.py copies it into Release\usbmmidd_v2 before packing.
$idd = "$env:USERPROFILE\dev\daremoto-drivers\usbmmidd_v2"
if (-not (Test-Path "$idd\usbmmIdd.inf")) {
    $zip = "$env:TEMP\usbmmidd_v2.zip"
    Write-Host '==> Download del driver dello schermo virtuale (usbmmidd_v2)'
    Invoke-WebRequest -Uri https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip -OutFile $zip
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($hash -ne '629B51E9944762BAE73948171C65D09A79595CF4C771A82EBC003FBBA5B24F51') {
        Remove-Item $zip; throw "usbmmidd_v2.zip: SHA-256 inatteso ($hash)"
    }
    $tmp = "$env:TEMP\usbmmidd_v2_x"
    Remove-Item $tmp -Recurse -ErrorAction SilentlyContinue
    Expand-Archive $zip -DestinationPath $tmp
    Remove-Item "$tmp\usbmmidd_v2\Win32" -Recurse
    Remove-Item "$tmp\usbmmidd_v2\deviceinstaller64.exe", "$tmp\usbmmidd_v2\deviceinstaller.exe", "$tmp\usbmmidd_v2\usbmmidd.bat"
    New-Item -ItemType Directory -Force (Split-Path $idd) | Out-Null
    Move-Item "$tmp\usbmmidd_v2" $idd
    Remove-Item $zip, $tmp -Recurse -ErrorAction SilentlyContinue
}
$env:DAREMOTO_USBMMIDD_DIR = $idd

$pack = if ($Portable) { '' } else { ' --skip-portable-pack' }
# Dedicated venv (brotli for the portable packer), so no other Python on PATH is touched.
$venv = "$env:USERPROFILE\dev\daremoto-build-venv"
if (-not (Test-Path "$venv\Scripts\python.exe")) {
    py -3 -m venv $venv
    & "$venv\Scripts\python.exe" -m pip install -q -r libs\portable\requirements.txt
}
Invoke-InVsEnv "`"$venv\Scripts\python.exe`" .\build.py --portable --flutter$pack --hwcodec --vram"
Write-Host "OK -> flutter\build\windows\x64\runner\Release\daremoto.exe"
if ($Portable) { Get-ChildItem daremoto-*.exe | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { Write-Host "OK -> $($_.Name)" } }
