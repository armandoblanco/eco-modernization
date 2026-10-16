<#
.SYNOPSIS
  Gate de cobertura 100%. Exit code 0 = aprobado, 1 = falla.

.PARAMETER Phase        Assessment (default) o Migration.
.PARAMETER SkipDocCheck No verifica que docs/features/<feature>.md mencione cada archivo.
.PARAMETER LegacyRoot   Carpeta legacy (default legacy) - se usa para detectar archivos no registrados.
#>
[CmdletBinding()]
param(
    [ValidateSet('Assessment', 'Migration')][string]$Phase = 'Assessment',
    [switch]$SkipDocCheck,
    [string]$LegacyRoot = 'legacy'
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ledger.psm1') -Force

$root = Get-RepoRoot
$rows = Import-Ledger
$errors = New-Object System.Collections.Generic.List[string]
$warns = New-Object System.Collections.Generic.List[string]
function Fail($m) { $errors.Add($m) }

$sha = @{}; foreach ($r in $rows) { $sha[$r.Path] = $r.Sha256 }
$map = Get-ReadMap -ShaByPath $sha

# 1) Archivos en disco vs ledger
$skip = Get-SkipDirs
$onDisk = @{}
$legacyFull = Join-Path $root $LegacyRoot
$stack = New-Object System.Collections.Generic.Stack[IO.DirectoryInfo]
$stack.Push((Get-Item $legacyFull))
while ($stack.Count -gt 0) {
    $d = $stack.Pop()
    foreach ($s in $d.GetDirectories()) { if ($skip -notcontains $s.Name) { $stack.Push($s) } }
    foreach ($f in $d.GetFiles()) { $onDisk[(ConvertTo-RelPath $f.FullName)] = $f.FullName }
}
foreach ($p in $onDisk.Keys) { if (-not $sha.ContainsKey($p)) { Fail "ARCHIVO NO REGISTRADO en el ledger: $p (ejecuta Initialize-Ledger.ps1 -Refresh)" } }

$totLines = 0; $totCov = 0; $filesChecked = 0
$featureFiles = @{}
foreach ($r in $rows) {
    $p = $r.Path
    if (-not $onDisk.ContainsKey($p)) { Fail "ARCHIVO DEL LEDGER NO EXISTE en disco: $p"; continue }
    $cur = Get-FileSha256 $onDisk[$p]
    if ($cur -ne $r.Sha256) { Fail "HASH CAMBIO (archivo modificado tras el inventario): $p"; continue }

    if ($r.Excluded -eq 'true') {
        if ([string]::IsNullOrWhiteSpace($r.ExclusionReason) -or [string]::IsNullOrWhiteSpace($r.ApprovedBy)) { Fail "EXCLUSION sin razon/aprobador: $p" }
        continue
    }
    if ([string]::IsNullOrWhiteSpace($r.Feature)) { Fail "SIN FEATURE asignado: $p" }
    else {
        if (-not $featureFiles.ContainsKey($r.Feature)) { $featureFiles[$r.Feature] = New-Object System.Collections.Generic.List[string] }
        $featureFiles[$r.Feature].Add($p)
    }

    if ($r.Category -eq 'Binary') { continue }
    if ($r.Category -eq 'Minified') { Fail "MINIFICADO sin exclusion aprobada: $p"; continue }

    $filesChecked++
    $total = [int]$r.Lines
    $merged = if ($map.ContainsKey($p)) { Merge-Ranges $map[$p] } else { @() }
    $covered = [Math]::Min($total, (Get-RangeCount $merged))
    $totLines += $total; $totCov += $covered
    if ($total -eq 0) {
        if (-not $map.ContainsKey($p)) { Fail "ARCHIVO VACIO sin lectura registrada: $p" }
    } else {
        $miss = Get-MissingRanges $merged $total
        if ($miss.Count -gt 0) { Fail ("LECTURA INCOMPLETA {0}: {1}/{2} lineas; faltan {3}" -f $p, $covered, $total, (Format-Ranges $miss)) }
    }

    if ($Phase -eq 'Migration') {
        if ($r.Disposition -eq 'Pending') { Fail "DISPOSICION PENDIENTE (Migrated/ReplacedByFramework/DeadCode/NotMigrated): $p" }
        if ($r.Disposition -in 'Migrated', 'ReplacedByFramework') {
            if ([string]::IsNullOrWhiteSpace($r.Target)) { Fail "SIN TARGET: $p" }
            elseif ($r.Disposition -eq 'Migrated') {
                foreach ($t in ($r.Target -split ';')) {
                    $tp = ConvertTo-FullPath $t.Trim()
                    if (-not (Test-Path $tp)) { Fail "TARGET NO EXISTE: $p -> $t" }
                }
            }
        }
        if ($r.Disposition -in 'DeadCode', 'NotMigrated' -and [string]::IsNullOrWhiteSpace($r.Notes)) { Fail "SIN JUSTIFICACION ($($r.Disposition)): $p" }
    }
}

# 2) Documentacion por feature (assessment): cada archivo debe aparecer en el doc de su feature
if (-not $SkipDocCheck -and $Phase -eq 'Assessment') {
    foreach ($feat in $featureFiles.Keys) {
        $doc = Join-Path $root (Get-FeatureDocPath $feat)
        if (-not (Test-Path $doc)) { Fail "FALTA documento de feature '$feat': $(Get-FeatureDocPath $feat)"; continue }
        $content = [IO.File]::ReadAllText($doc)
        foreach ($p in $featureFiles[$feat]) {
            $leaf = Split-Path $p -Leaf
            if ($content.IndexOf($p, [StringComparison]::OrdinalIgnoreCase) -lt 0 -and $content.IndexOf($leaf, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                Fail "NO DOCUMENTADO: $p no se menciona en $(Get-FeatureDocPath $feat)"
            }
        }
    }
}

$pct = if ($totLines -gt 0) { [Math]::Round(100.0 * $totCov / $totLines, 2) } else { 100 }
$status = if ($errors.Count -eq 0) { 'APROBADO' } else { 'RECHAZADO' }
$report = New-Object System.Text.StringBuilder
[void]$report.AppendLine("# Reporte de cobertura ($Phase)")
[void]$report.AppendLine('')
[void]$report.AppendLine("- Fecha UTC: $((Get-Date).ToUniversalTime().ToString('s'))")
[void]$report.AppendLine("- Resultado: **$status**")
[void]$report.AppendLine("- Archivos en ledger: $($rows.Count) | archivos de texto verificados: $filesChecked")
[void]$report.AppendLine("- Lineas leidas: $totCov / $totLines ($pct%)")
$excl = @($rows | Where-Object { $_.Excluded -eq 'true' })
[void]$report.AppendLine("- Exclusiones aprobadas: $($excl.Count)")
[void]$report.AppendLine('')
if ($excl.Count -gt 0) {
    [void]$report.AppendLine('## Exclusiones'); [void]$report.AppendLine('')
    [void]$report.AppendLine('| Archivo | Razon | Aprobado por |'); [void]$report.AppendLine('|---|---|---|')
    foreach ($e in $excl) { [void]$report.AppendLine("| $($e.Path) | $($e.ExclusionReason) | $($e.ApprovedBy) |") }
    [void]$report.AppendLine('')
}
if ($errors.Count -gt 0) {
    [void]$report.AppendLine("## Fallas ($($errors.Count))"); [void]$report.AppendLine('')
    foreach ($e in $errors) { [void]$report.AppendLine("- $e") }
}
$out = Join-Path $root 'docs/inventory/coverage-report.md'
[IO.File]::WriteAllText($out, $report.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Cobertura ($Phase): $totCov / $totLines lineas ($pct%) en $filesChecked archivos de texto | $status"
if ($errors.Count -gt 0) {
    $errors | Select-Object -First 40 | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
    if ($errors.Count -gt 40) { Write-Host "  ... y $($errors.Count - 40) mas (ver $out)" -ForegroundColor Red }
    exit 1
}
Write-Host "Reporte: $out" -ForegroundColor Green
exit 0
