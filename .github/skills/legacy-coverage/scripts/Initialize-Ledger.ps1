<#
.SYNOPSIS
  Inventaria TODOS los archivos de legacy/ y crea (o refresca) el ledger de cobertura.

.DESCRIPTION
  Genera docs/inventory/coverage-ledger.csv con un registro por archivo (ruta, categoria, lineas, SHA-256,
  batch de trabajo). Es la linea base objetiva contra la que se mide la cobertura 100%.
  Con -Refresh conserva feature/disposicion/exclusiones de los archivos que no cambiaron, agrega los nuevos
  y marca los eliminados. Las lecturas previas de un archivo cuyo hash cambio dejan de contar.

.PARAMETER LegacyRoot   Carpeta con el codigo legacy (relativa a la raiz del repo). Default: legacy
.PARAMETER BatchLines   Presupuesto de lineas por batch de trabajo (para subagentes / sesiones). Default: 2500
.PARAMETER Refresh      Actualiza un ledger existente en lugar de fallar.
.PARAMETER IncludeBuildDirs  Incluye bin/obj/packages/.vs/node_modules (por defecto se omiten).
#>
[CmdletBinding()]
param(
    [string]$LegacyRoot = 'legacy',
    [int]$BatchLines = 2500,
    [switch]$Refresh,
    [switch]$IncludeBuildDirs
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ledger.psm1') -Force

$root = Get-RepoRoot
$legacyFull = Join-Path $root $LegacyRoot
if (-not (Test-Path $legacyFull)) { throw "No existe $legacyFull. Coloca el codigo legacy en '$LegacyRoot/'." }
if ((Test-Path (Get-LedgerPath)) -and -not $Refresh) {
    throw "Ya existe $(Get-LedgerPath). Usa -Refresh para actualizarlo sin perder progreso."
}

$skip = if ($IncludeBuildDirs) { @('.git') } else { Get-SkipDirs }
$skippedDirs = @{}
$files = New-Object System.Collections.Generic.List[IO.FileInfo]
$stack = New-Object System.Collections.Generic.Stack[IO.DirectoryInfo]
$legacyRootItem = Get-Item $legacyFull
$stack.Push($legacyRootItem)
while ($stack.Count -gt 0) {
    $d = $stack.Pop()
    foreach ($sub in $d.GetDirectories()) {
        if ($skip -contains $sub.Name) { $skippedDirs[(ConvertTo-RelPath $sub.FullName)] = $true; continue }
        $stack.Push($sub)
    }
    foreach ($f in $d.GetFiles()) {
        # Marcadores de la plantilla en la raiz de legacy/ (no son codigo del cliente)
        if ($d.FullName -eq $legacyRootItem.FullName -and ($f.Name -eq '.gitkeep' -or $f.Name -eq 'LEEME-PLANTILLA.md')) { continue }
        $files.Add($f)
    }
}
$files = @($files | Sort-Object { ConvertTo-RelPath $_.FullName })
Write-Host "Archivos encontrados en $LegacyRoot/: $($files.Count)  (carpetas omitidas: $($skippedDirs.Count))"

$old = @{}
if (Test-Path (Get-LedgerPath)) { foreach ($r in (Import-Ledger)) { $old[$r.Path] = $r } }

$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($f in $files) {
    $i++
    if ($i % 200 -eq 0) { Write-Host "  inventariando $i / $($files.Count)" }
    $rel = ConvertTo-RelPath $f.FullName
    $sha = Get-FileSha256 $f.FullName
    if ($old.ContainsKey($rel) -and $old[$rel].Sha256 -eq $sha) { $rows.Add($old[$rel]); continue }

    $isBin = Test-IsBinaryFile $f.FullName
    $lines = 0; $minified = $false
    if (-not $isBin) {
        $txt = Get-TextLines $f.FullName
        $lines = $txt.Count
        foreach ($l in $txt) { if ($l.Length -gt (Get-MaxLineChars)) { $minified = $true; break } }
    }
    $row = [ordered]@{}
    foreach ($c in (Get-LedgerColumns)) { $row[$c] = '' }
    $row.Path = $rel
    $row.Ext = $f.Extension.ToLowerInvariant()
    $row.Category = Get-FileCategory -Ext $f.Extension -Name $f.Name -IsBinary $isBin -IsMinified $minified
    $row.Lines = $lines
    $row.Bytes = $f.Length
    $row.Sha256 = $sha
    $row.Disposition = 'Pending'
    $row.Excluded = 'false'
    if ($old.ContainsKey($rel)) {
        # Archivo modificado: se conserva la asignacion pero se invalidan lecturas (por hash) y se avisa.
        $row.Feature = $old[$rel].Feature
        $row.Notes = "CAMBIO DETECTADO en refresh $(Get-Date -Format 'yyyy-MM-dd'): releer completo."
    }
    $rows.Add([pscustomobject]$row)
}

$current = @{}
foreach ($r in $rows) { $current[$r.Path] = $true }
$removed = @($old.Keys | Where-Object { -not $current.ContainsKey($_) })

# Batches: agrupa por carpeta/proyecto y llena hasta $BatchLines lineas (los binarios no consumen presupuesto).
$batch = 1; $acc = 0; $prevDir = ''
foreach ($r in ($rows | Sort-Object Path)) {
    $dir = Split-Path $r.Path -Parent
    $cost = [int]$r.Lines
    if ($acc -gt 0 -and (($acc + $cost) -gt $BatchLines)) { $batch++; $acc = 0 }
    $r.Batch = ('B{0:D4}' -f $batch)
    $acc += $cost
    $prevDir = $dir
}

Save-Ledger -Rows $rows

$cat = $rows | Group-Object Category | Sort-Object Count -Descending
Write-Host ''
Write-Host "Ledger: $(Get-LedgerPath)"
Write-Host "Archivos: $($rows.Count) | Lineas de texto: $((($rows | Measure-Object Lines -Sum).Sum)) | Batches: $batch"
$cat | ForEach-Object { Write-Host ("  {0,-10} {1,6} archivos" -f $_.Name, $_.Count) }
if ($removed.Count -gt 0) { Write-Host "ELIMINADOS desde el ultimo ledger: $($removed.Count)" -ForegroundColor Yellow; $removed | Select-Object -First 20 | ForEach-Object { Write-Host "  - $_" } }
$bin = @($rows | Where-Object { $_.Category -eq 'Binary' }).Count
$min = @($rows | Where-Object { $_.Category -eq 'Minified' }).Count
if ($bin -gt 0) { Write-Host "Binarios: $bin (no se leen linea a linea; deben clasificarse con Update-Ledger.ps1 -Feature ...)" -ForegroundColor Yellow }
if ($min -gt 0) { Write-Host "Minified/lineas gigantes: $min (requieren exclusion APROBADA por el usuario)" -ForegroundColor Yellow }
if ($skippedDirs.Count -gt 0) { Write-Host "Carpetas omitidas (build/vcs): $((($skippedDirs.Keys | Sort-Object | Select-Object -First 8) -join ', '))" }
Write-Host ''
Write-Host 'Siguiente: .github/skills/legacy-coverage/scripts/Get-NextBatch.ps1'
