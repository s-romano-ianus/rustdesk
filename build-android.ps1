<#
.SYNOPSIS
  Builds the DareMoto Android APK (arm64 + armv7) locally, in Docker: same steps and
  versions as .github/workflows/daremoto-android.yml, without GitHub Actions.

.DESCRIPTION
  - Builds the toolchain image (build-android\Dockerfile) the first time or with -RebuildImage.
  - Compiles the committed HEAD of this repository (uncommitted changes are NOT included),
    with the flutter_rust_bridge files already generated on this PC by build-windows.ps1.
  - Writes daremoto-<version>-unsigned.apk here; with -Sign it then signs it with the
    DareMoto keystore (build-android-sign.ps1) -> daremoto-<version>.apk.
  Caches live in Docker volumes (daremoto-android-*): the first build takes 1-2 hours
  (vcpkg dependencies, Rust), the next ones much less. Remove them with -CleanCache.

.EXAMPLE
  .\build-android.ps1 -Sign
  .\build-android.ps1 -Abis arm64-v8a          # only arm64, faster for a test
  .\build-android.ps1 -RebuildImage -Sign      # after changing build-android\*
#>
param(
    [string]$Server = 'desk.daremoto.net',
    [string]$PubKey = 'ZHj0xodd+MazMaPs696wDVVzN2ewcUdPTVFycOvilAE=',
    [string]$ApiServer = 'https://api.daremoto.net',
    [string]$Version = '1.5.3',
    [ValidateSet('arm64-v8a', 'armeabi-v7a')] [string[]]$Abis = @('arm64-v8a', 'armeabi-v7a'),
    [switch]$Sign,
    [switch]$RebuildImage,
    [switch]$CleanCache
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$image = 'daremoto-android-builder:1'
$volumes = @{
    'daremoto-android-target'     = '/cache/target'
    'daremoto-android-vcpkg-bin'  = '/cache/vcpkg-bin'
    'daremoto-android-vcpkg-inst' = '/opt/vcpkg/installed'
    'daremoto-android-vcpkg-dl'   = '/opt/vcpkg/downloads'
    'daremoto-android-cargo'      = '/opt/cargo/registry'
    'daremoto-android-cargo-git'  = '/opt/cargo/git'
    'daremoto-android-gradle'     = '/root/.gradle'
    'daremoto-android-pub'        = '/root/.pub-cache'
}

# --- Docker running ---
function Test-Docker { docker info *> $null; return $LASTEXITCODE -eq 0 }
if (-not (Test-Docker)) {
    $dd = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path $dd)) { throw 'Docker Desktop non trovato: installalo o avvialo a mano' }
    Write-Host '==> Avvio Docker Desktop'
    Start-Process $dd
    $until = (Get-Date).AddMinutes(4)
    while (-not (Test-Docker)) {
        if ((Get-Date) -gt $until) { throw 'Docker non risponde dopo 4 minuti' }
        Start-Sleep 5
    }
}

if ($CleanCache) {
    Write-Host '==> Rimozione delle cache'
    foreach ($v in $volumes.Keys) { docker volume rm $v 2>$null | Out-Null }
}

# --- checks on the sources ---
Push-Location $repo
try {
    $dirty = git status --porcelain --untracked-files=no
    if ($dirty) {
        Write-Warning "Modifiche non committate (non entrano nella build, che usa HEAD):`n$($dirty -join "`n")"
    }
    $bridge = 'flutter\lib\generated_bridge.dart'
    foreach ($f in 'src\bridge_generated.rs', 'src\bridge_generated.io.rs', $bridge,
        'flutter\lib\generated_bridge.freezed.dart', 'flutter\macos\Runner\bridge_generated.h') {
        if (-not (Test-Path $f)) { throw "Manca ${f}: esegui prima .\build-windows.ps1 senza -SkipBridge" }
    }
    # the bridge must match src\flutter_ffi.rs at HEAD
    $ffiChanged = git log -1 --format=%ct -- src/flutter_ffi.rs
    $bridgeTime = [DateTimeOffset](Get-Item $bridge).LastWriteTimeUtc
    if ([long]$ffiChanged -gt $bridgeTime.ToUnixTimeSeconds()) {
        throw 'src\flutter_ffi.rs è cambiato dopo la generazione del bridge: esegui .\build-windows.ps1 senza -SkipBridge'
    }
    $commit = git rev-parse --short HEAD
} finally { Pop-Location }

# --- toolchain image ---
docker image inspect $image *> $null
if ($RebuildImage -or $LASTEXITCODE) {
    Write-Host "==> Immagine $image (la prima volta circa 15 minuti)"
    docker build -t $image (Join-Path $repo 'build-android')
    if ($LASTEXITCODE) { throw 'docker build fallito' }
}

# --- build ---
$unsigned = Join-Path $repo "daremoto-$Version-unsigned.apk"
Remove-Item $unsigned -ErrorAction SilentlyContinue
# fixed DNS: Docker's resolver drops lookups under load (Gradle then fails to download)
$runArgs = @('run', '--rm', '--dns', '1.1.1.1', '--dns', '8.8.8.8', '-v', "${repo}:/src:ro", '-v', "${repo}:/out")
foreach ($v in $volumes.GetEnumerator()) { $runArgs += @('-v', "$($v.Key):$($v.Value)") }
$runArgs += @('-e', "RENDEZVOUS_SERVER=$Server", '-e', "RS_PUB_KEY=$PubKey", '-e', "API_SERVER=$ApiServer",
    '-e', "VERSION=$Version", '-e', "ABIS=$($Abis -join ' ')", $image, 'daremoto-build-android')
Write-Host "==> Build Android di $commit ($($Abis -join ', ')), server $Server"
$t0 = Get-Date
docker @runArgs
if ($LASTEXITCODE -or -not (Test-Path $unsigned)) { throw 'Build Android fallita' }
Write-Host ("==> Build completata in {0:hh\:mm\:ss}: $unsigned" -f ((Get-Date) - $t0)) -ForegroundColor Green

if ($Sign) {
    & (Join-Path $repo 'build-android-sign.ps1') -Apk $unsigned -OutDir $repo
}
