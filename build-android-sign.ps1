<#
.SYNOPSIS
  Scarica l'APK prodotto dal workflow "DareMoto Android" e lo firma con la keystore DareMoto.

.EXAMPLE
  .\build-android-sign.ps1                 # ultima esecuzione riuscita
  .\build-android-sign.ps1 -RunId 123456   # esecuzione specifica
  .\build-android-sign.ps1 -Apk .\daremoto-1.5.3-unsigned.apk   # APK già scaricato
#>
param(
    [string]$RunId,
    [string]$Apk,
    [string]$Repo = 's-romano-ianus/rustdesk',
    [string]$KeystoreProps = "$env:USERPROFILE\dev\daremoto-signing\keystore.properties",
    [string]$OutDir = '.'
)
$ErrorActionPreference = 'Stop'

# --- strumenti ---
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = "$env:LOCALAPPDATA\Android\Sdk" }
$bt = Get-ChildItem "$sdk\build-tools" -Directory | Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } | Select-Object -Last 1
if (-not $bt) { throw "Android build-tools non trovati in $sdk" }
$apksigner = Join-Path $bt.FullName 'apksigner.bat'

# --- keystore ---
if (-not (Test-Path $KeystoreProps)) { throw "Keystore non trovata: $KeystoreProps" }
$props = @{}
Get-Content $KeystoreProps | Where-Object { $_ -match '^\s*([^#=]+)=(.*)$' } | ForEach-Object { $props[$Matches[1].Trim()] = $Matches[2].Trim() }

# --- APK di partenza ---
if (-not $Apk) {
    if (-not $RunId) {
        $RunId = gh run list -R $Repo --workflow daremoto-android.yml --status success --limit 1 --json databaseId --jq '.[0].databaseId'
        if (-not $RunId) { throw 'Nessuna esecuzione riuscita del workflow DareMoto Android' }
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "daremoto-apk-$RunId"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    gh run download $RunId -R $Repo -n daremoto-android -D $tmp
    if ($LASTEXITCODE) { throw "Download dell'artifact fallito (run $RunId)" }
    $Apk = (Get-ChildItem $tmp -Filter *.apk | Select-Object -First 1).FullName
}
$Apk = (Resolve-Path $Apk).Path

$name = [IO.Path]::GetFileName($Apk) -replace '-unsigned', ''
$out = Join-Path (Resolve-Path $OutDir).Path $name

# --- firma (v1+v2+v3) e verifica ---
$env:DAREMOTO_KS_PASS = $props.storePassword
$env:DAREMOTO_KEY_PASS = $props.keyPassword
try {
    & $apksigner sign --ks $props.storeFile --ks-key-alias $props.keyAlias `
        --ks-pass env:DAREMOTO_KS_PASS --key-pass env:DAREMOTO_KEY_PASS `
        --out $out $Apk
    if ($LASTEXITCODE) { throw 'apksigner sign fallito' }
} finally {
    Remove-Item Env:DAREMOTO_KS_PASS, Env:DAREMOTO_KEY_PASS -ErrorAction SilentlyContinue
}
& $apksigner verify --print-certs $out | Select-String 'Signer #1 certificate (DN|SHA-256)'
if ($LASTEXITCODE) { throw 'Verifica firma fallita' }
Remove-Item "$out.idsig" -ErrorAction SilentlyContinue

$size = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Host "APK firmato: $out ($size MB)" -ForegroundColor Green
