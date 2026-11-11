# Compacta el disco virtual de WSL (ext4.vhdx) y devuelve el espacio a la unidad.
#
#   Click derecho > "Ejecutar con PowerShell"  (o desde PowerShell como admin:)
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\compact-vhdx.ps1
#
# Borrar ficheros dentro de WSL no encoge el .vhdx: hay que compactarlo. Requiere
# administrador (diskpart) y WSL parado. Con -SkipCompact solo lo deja apagado.
param(
    [string]$Vhdx = "E:\WSL\gts4lv\ext4.vhdx",
    [switch]$SkipCompact
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Vhdx)) { throw "no encuentro $Vhdx" }

$before = (Get-Item $Vhdx).Length / 1GB
$freeBefore = (Get-PSDrive E).Free / 1GB
"vhdx antes : {0:N1} GB" -f $before
"unidad libre: {0:N1} GB" -f $freeBefore

"parando WSL..."
wsl --shutdown
Start-Sleep -Seconds 8

# el disco no puede estar enganchado por nadie (si lo esta, hay que reiniciar)
try {
    $fs = [System.IO.File]::Open($Vhdx, 'Open', 'ReadWrite', 'None')
    $fs.Close()
} catch {
    throw "el .vhdx sigue en uso por otro proceso. Reinicia Windows y vuelve a intentarlo."
}

if ($SkipCompact) { "WSL parado, sin compactar."; exit 0 }

$script = Join-Path $env:TEMP "compact-wsl.txt"
@"
select vdisk file="$Vhdx"
attach vdisk readonly
compact vdisk
detach vdisk
exit
"@ | Out-File -FilePath $script -Encoding ASCII

"compactando (puede tardar varios minutos)..."
$p = Start-Process -FilePath "diskpart.exe" -ArgumentList "/s", "`"$script`"" -Verb RunAs -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "diskpart fallo con codigo $($p.ExitCode)" }

$after = (Get-Item $Vhdx).Length / 1GB
$freeAfter = (Get-PSDrive E).Free / 1GB
"vhdx despues: {0:N1} GB  (liberado {1:N1} GB)" -f $after, ($before - $after)
"unidad libre: {0:N1} GB  (+{1:N1} GB)" -f $freeAfter, ($freeAfter - $freeBefore)
