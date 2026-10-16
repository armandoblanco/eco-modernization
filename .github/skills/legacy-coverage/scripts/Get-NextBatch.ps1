<#
.SYNOPSIS
  Cola de trabajo: muestra el siguiente batch con lineas sin leer (y como retomarlo).

.PARAMETER Batch   Fuerza un batch concreto (ej: B0003).
.PARAMETER Summary Solo imprime el resumen global de cobertura.
#>
[CmdletBinding()]
param([string]$Batch, [switch]$Summary)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ledger.psm1') -Force

$rows = Import-Ledger
$sha = @{}; foreach ($r in $rows) { $sha[$r.Path] = $r.Sha256 }
$map = Get-ReadMap -ShaByPath $sha

$info = foreach ($r in $rows) {
    $total = [int]$r.Lines
    $isText = $r.Category -ne 'Binary'
    $active = $isText -and $r.Excluded -ne 'true' -and $r.Category -ne 'Minified'
    $covered = 0; $missing = @()
    if ($active) {
        $merged = if ($map.ContainsKey($r.Path)) { Merge-Ranges $map[$r.Path] } else { @() }
        $covered = [Math]::Min($total, (Get-RangeCount $merged))
        $missing = Get-MissingRanges $merged $total
    }
    $needsRead = $active -and $total -gt 0 -and $missing.Count -gt 0
    # Archivos vacios necesitan una lectura registrada para contar como leidos.
    if ($active -and $total -eq 0 -and -not $map.ContainsKey($r.Path)) { $needsRead = $true }
    [pscustomobject]@{ Path = $r.Path; Batch = $r.Batch; Lines = $total; Covered = $covered; Missing = $missing; NeedsRead = $needsRead; Active = $active }
}

$activeRows = @($info | Where-Object { $_.Active })
$totLines = ($activeRows | Measure-Object Lines -Sum).Sum
$totCov = ($activeRows | Measure-Object Covered -Sum).Sum
if (-not $totLines) { $totLines = 0 }; if (-not $totCov) { $totCov = 0 }
$pct = if ($totLines -gt 0) { [Math]::Round(100.0 * $totCov / $totLines, 2) } else { 100 }
$pendingFiles = @($info | Where-Object { $_.NeedsRead })
$batches = @($rows | Select-Object -ExpandProperty Batch -Unique | Sort-Object)
Write-Host "COBERTURA: $totCov / $totLines lineas ($pct%) | archivos pendientes: $($pendingFiles.Count) | batches: $($batches.Count)"
$noFeature = @($rows | Where-Object { $_.Excluded -ne 'true' -and [string]::IsNullOrWhiteSpace($_.Feature) }).Count
Write-Host "Archivos sin feature asignado: $noFeature"
if ($Summary) { return }

$target = if ($Batch) { $Batch } else { ($pendingFiles | Sort-Object Batch, Path | Select-Object -First 1).Batch }
if (-not $target) {
    Write-Host 'No quedan lineas pendientes de lectura. Siguiente: Test-Coverage.ps1 -Phase Assessment' -ForegroundColor Green
    return
}
$inBatch = @($info | Where-Object { $_.Batch -eq $target })
Write-Host ''
Write-Host "== Batch $target | $($inBatch.Count) archivos | $((($inBatch | Measure-Object Lines -Sum).Sum)) lineas =="
foreach ($f in $inBatch) {
    $state = if (-not $f.Active) { 'N/A (binario/excluido)' } elseif ($f.NeedsRead) { "pendiente $(Format-Ranges $f.Missing)" } else { 'completo' }
    Write-Host ("  {0}  [{1} lineas | {2}]" -f $f.Path, $f.Lines, $state)
}
Write-Host ''
Write-Host 'Para cada archivo pendiente ejecuta repetidamente:'
Write-Host '  pwsh .github/skills/legacy-coverage/scripts/Read-LegacyChunk.ps1 -Path <archivo> -Next'
Write-Host 'hasta ver "EOF: archivo completamente leido".'
