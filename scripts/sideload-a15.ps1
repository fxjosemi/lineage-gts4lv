<#
  Espera a que la tablet entre en modo sideload y flashea el zip de A15.

  Uso:
    .\scripts\sideload-a15.ps1                # espera hasta 45 min
    .\scripts\sideload-a15.ps1 -Wait 10       # minutos de espera
    .\scripts\sideload-a15.ps1 -NoFlash       # solo espera y avisa

  En la tablet (recovery de LineageOS 22.2), antes:
    Factory reset > Format data / factory reset > escribe "yes"
    Apply update > Apply from ADB
#>
param(
  [string]$Zip = '',
  [int]$Wait = 45,
  [switch]$NoFlash
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$adb  = Join-Path $root 'tools\platform-tools\adb.exe'
$art  = Join-Path $root 'out\lineage-22-a15'

if (-not (Test-Path $adb)) { throw "No encuentro adb en $adb" }
if (-not $Zip) {
  $Zip = Get-ChildItem $art -Filter 'lineage-22.2-*-UNOFFICIAL-gts4lv.zip' |
    Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Zip -or -not (Test-Path $Zip)) { throw "No encuentro el zip de A15 en $art" }

# checksum
$sums = Join-Path $art 'SHA256SUMS.txt'
if (Test-Path $sums) {
  $name = Split-Path $Zip -Leaf
  $line = (Get-Content $sums | Select-String ([regex]::Escape($name))).Line
  if ($line) {
    $expected = ($line -split '\s+')[0]
    $actual = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) { throw "Checksum de $name no coincide" }
    Write-Host "OK checksum $name" -ForegroundColor Green
  }
}

Write-Host "==> Esperando modo sideload (hasta $Wait min)..." -ForegroundColor Cyan
Write-Host "    En la tablet: Apply update > Apply from ADB" -ForegroundColor Yellow
Write-Host "    (y ANTES, si vienes de A13: Factory reset > Format data)" -ForegroundColor Yellow

$deadline = (Get-Date).AddMinutes($Wait)
$found = $false
while ((Get-Date) -lt $deadline) {
  if ((& $adb devices 2>&1) -match 'sideload') { $found = $true; break }
  Start-Sleep -Seconds 2
}

if (-not $found) {
  Write-Host "No ha entrado en sideload. Estado actual:" -ForegroundColor Red
  & $adb devices -l
  exit 1
}

Write-Host "==> Modo sideload detectado" -ForegroundColor Green
if ($NoFlash) { exit 0 }

Write-Host "==> Enviando $(Split-Path $Zip -Leaf) ($([math]::Round((Get-Item $Zip).Length/1GB,2)) GB)" -ForegroundColor Cyan
& $adb sideload $Zip

if ($LASTEXITCODE -ne 0) {
  Write-Host "adb sideload devolvio $LASTEXITCODE (el 'failed to read command: Success' final es normal)." -ForegroundColor Yellow
}
Write-Host "==> Hecho. En la tablet: Reboot system now." -ForegroundColor Green
