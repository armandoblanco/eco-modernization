<#
.SYNOPSIS
  Lee un tramo de un archivo legacy con numeros de linea y REGISTRA el tramo leido en el read-log.

.DESCRIPTION
  Es la UNICA forma valida de "leer" archivos legacy durante el assessment: la cobertura se mide a partir
  de las lecturas registradas por este script, no de lo que el agente afirme. La salida incluye numeros de
  linea (usar para citar evidencia archivo:linea) y un pie con la siguiente instruccion.

.PARAMETER Path      Ruta del archivo (relativa a la raiz del repo, ej: legacy/Billing/Invoice.cs)
.PARAMETER Start     Primera linea a leer (default 1). Con -Next se ignora.
.PARAMETER Count     Maximo de lineas por llamada (default 300).
.PARAMETER MaxChars  Maximo de caracteres por llamada (default 24000); el tramo se acorta si lo excede.
.PARAMETER Next      Empieza en la primera linea aun sin leer del archivo.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Path,
    [int]$Start = 1,
    [int]$Count = 300,
    [int]$MaxChars = 24000,
    [switch]$Next
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ledger.psm1') -Force

$rel = ConvertTo-RelPath $Path
$row = Import-Ledger | Where-Object { $_.Path -ieq $rel } | Select-Object -First 1
if (-not $row) { throw "El archivo no esta en el ledger: $rel. Ejecuta Initialize-Ledger.ps1 -Refresh si es nuevo." }
if ($row.Category -eq 'Binary') { throw "$rel es binario: clasificalo con Update-Ledger.ps1, no se lee." }
if ($row.Category -eq 'Minified') { throw "$rel tiene lineas gigantes (minificado): pide al usuario aprobar su exclusion (Update-Ledger.ps1 -Exclude -Reason ... -ApprovedBy ...)." }
if ($row.Excluded -eq 'true') { throw "$rel esta excluido (aprobado por $($row.ApprovedBy))." }

$full = ConvertTo-FullPath $rel
if (-not (Test-Path $full)) { throw "No existe en disco: $rel" }
$sha = Get-FileSha256 $full
if ($sha -ne $row.Sha256) { throw "El archivo cambio desde el inventario: $rel. Ejecuta Initialize-Ledger.ps1 -Refresh." }

$lines = Get-TextLines $full
$total = $lines.Count
$sha8 = @{ $rel = $sha }
$map = Get-ReadMap -ShaByPath $sha8
$prior = if ($map.ContainsKey($rel)) { Merge-Ranges $map[$rel] } else { @() }

if ($total -eq 0) {
    Write-Output "=== $rel | archivo vacio (0 lineas) ==="
    Add-ReadLogEntry -RelPath $rel -Start 1 -End 0 -Sha256 $sha
    Write-Output '--- EOF: archivo completamente leido ---'
    return
}
if ($Next) {
    $missing = Get-MissingRanges $prior $total
    if ($missing.Count -eq 0) { Write-Output "=== $rel | ya estaba 100% leido ($total/$total) ==="; return }
    $Start = $missing[0][0]
}
if ($Start -lt 1 -or $Start -gt $total) { throw "Start fuera de rango (1..$total)." }

$end = [Math]::Min($total, $Start + $Count - 1)
$chars = 0
$sb = New-Object System.Text.StringBuilder
for ($n = $Start; $n -le $end; $n++) {
    $text = $lines[$n - 1]
    $chars += $text.Length + 8
    if ($chars -gt $MaxChars -and $n -gt $Start) { $end = $n - 1; break }
    [void]$sb.AppendLine(('{0,6}| {1}' -f $n, $text))
}

Write-Output "=== $rel | lineas $Start-$end de $total ==="
Write-Output $sb.ToString().TrimEnd("`r", "`n")
Add-ReadLogEntry -RelPath $rel -Start $Start -End $end -Sha256 $sha

$all = Merge-Ranges (@($prior) + , @($Start, $end))
$covered = Get-RangeCount $all
$pct = [Math]::Round(100.0 * $covered / $total, 1)
$missing = Get-MissingRanges $all $total
if ($missing.Count -eq 0) {
    Write-Output "--- EOF: archivo completamente leido ($covered/$total, 100%) ---"
} else {
    Write-Output "--- leido $covered/$total ($pct%) | SIGUIENTE: Read-LegacyChunk.ps1 -Path $rel -Start $($missing[0][0]) ---"
}
