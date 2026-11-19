# Local Windows x64 build (Flutter) – mirrors .github/workflows/flutter-build.yml
# Usage:  .\build-windows.ps1 -Server <host> -PubKey <key>   -> regenerate bridge + build
#         .\build-windows.ps1 ... -SkipBridge                -> build only (flutter_ffi.rs unchanged)
# -Server / -PubKey are compiled into hbb_common (RENDEZVOUS_SERVER / RS_PUB_KEY).
# Without them the client falls back to the upstream public RustDesk servers.
param(
    [string]$Server,
    [string]$PubKey,
    [switch]$SkipBridge
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

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

Invoke-InVsEnv 'python .\build.py --portable --flutter --skip-portable-pack --hwcodec --vram'
Write-Host "OK -> flutter\build\windows\x64\runner\Release\rustdesk.exe"
