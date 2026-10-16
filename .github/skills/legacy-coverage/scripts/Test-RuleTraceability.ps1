<#
.SYNOPSIS
  Gate de trazabilidad de reglas de negocio. Exit 0 = aprobado, 1 = falla.

.DESCRIPTION
  Phase Assessment: cada BR tiene Source valido y 100% leido; el doc de la feature menciona el ID; todo archivo
    con candidatos tiene >=1 BR o esta en no-rule-files.csv; las lineas candidatas fuera de toda BR estan en
    dismissed-candidates.csv (aviso; error con -Strict).
  Phase Migration: ademas, cada BR esta Implemented/Verified/DeviationApproved/Retired; los Target existen y
    contienen el ID (comentario o XML doc); los Tests existen y contienen el ID; y los resultados TRX muestran
    pruebas aprobadas cuyo nombre contiene el ID (minimo 2 para Critical, 1 para el resto) y ninguna fallida.

.PARAMETER Phase            Assessment (default) | Migration
.PARAMETER TrxPath          Glob de TRX (default test-results/**/*.trx) generados con: dotnet test --logger trx --results-directory test-results
.PARAMETER MinTestsCritical Pruebas aprobadas minimas por BR Critical (default 2)
.PARAMETER Strict           Los candidatos sin cubrir/descartar son error (en Assessment son aviso por defecto).
#>
[CmdletBinding()]
param(
    [ValidateSet('Assessment', 'Migration')][string]$Phase = 'Assessment',
    [string]$TrxPath = 'test-results',
    [int]$MinTestsCritical = 2,
    [switch]$Strict
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ledger.psm1') -Force

$root = Get-RepoRoot
$errors = New-Object System.Collections.Generic.List[string]
$warns = New-Object System.Collections.Generic.List[string]
$ledger = Import-Ledger
$sha = @{}; foreach ($r in $ledger) { $sha[$r.Path] = $r.Sha256 }
$readMap = Get-ReadMap -ShaByPath $sha
$brs = @(Import-BrCatalog)
if ($brs.Count -eq 0) { $errors.Add('El catalogo docs/business-rules/BR-catalog.csv esta vacio o no existe. Un sistema real siempre tiene reglas: documentalas (o justifica archivo por archivo en no-rule-files.csv).') }

$dups = $brs | Group-Object Id | Where-Object { $_.Count -gt 1 }
foreach ($d in $dups) { $errors.Add("ID duplicado: $($d.Name)") }

# --- Rangos cubiertos por BR (para candidatos) ---
$brRanges = @{}
foreach ($b in $brs) {
    foreach ($part in ($b.Source -split ';(?=[^;]*:)')) {
        if ($part.Trim() -match '^(?<f>.+?):(?<r>[\d,\-; ]+)$') {
            $f = $Matches.f -replace '\\', '/'
            if (-not $brRanges.ContainsKey($f)) { $brRanges[$f] = New-Object System.Collections.Generic.List[object] }
            foreach ($r in (ConvertFrom-RangeString $Matches.r)) { $brRanges[$f].Add($r) }
        }
    }
}

# --- Validaciones por BR ---
$featureDocCache = @{}
$validStatus = Get-BrStatuses
foreach ($b in $brs) {
    $id = $b.Id
    if ($id -notmatch '^BR-\d{4,}$') { $errors.Add("ID invalido: '$id'") }
    if ($b.Type -notin (Get-BrTypes)) { $errors.Add("$id Type invalido: $($b.Type)") }
    if ($b.Criticality -notin (Get-BrCriticalities)) { $errors.Add("$id Criticality invalida: $($b.Criticality)") }
    if ($b.Status -notin $validStatus) { $errors.Add("$id Status invalido: $($b.Status)") }
    if ([string]::IsNullOrWhiteSpace($b.Rule) -or $b.Rule.Length -lt 15) { $errors.Add("$id Rule vacia o demasiado corta (describe la regla con valores concretos)") }
    foreach ($e in (Test-BrSource -Source $b.Source -LedgerRows $ledger -ReadMap $readMap)) { $errors.Add("$id $e") }

    if (-not $featureDocCache.ContainsKey($b.Feature)) {
        $doc = Join-Path $root (Get-FeatureDocPath $b.Feature)
        $featureDocCache[$b.Feature] = if (Test-Path $doc) { [IO.File]::ReadAllText($doc) } else { $null }
    }
    $docText = $featureDocCache[$b.Feature]
    if ($null -eq $docText) { $errors.Add("$id feature '$($b.Feature)' sin documento $(Get-FeatureDocPath $b.Feature)") }
    elseif ($docText.IndexOf($id, [StringComparison]::Ordinal) -lt 0) { $errors.Add("$id no aparece en $(Get-FeatureDocPath $b.Feature)") }
}

# --- Candidatos ---
$candPath = Join-Path $root 'docs/business-rules/rule-candidates.csv'
$candIssues = New-Object System.Collections.Generic.List[string]
if (-not (Test-Path $candPath)) { $errors.Add('Falta docs/business-rules/rule-candidates.csv (ejecuta .github/skills/legacy-coverage/scripts/Find-RuleCandidates.ps1).') }
else {
    $cands = @(Import-Csv $candPath -Encoding UTF8)
    $noRule = @{}
    $nrp = Join-Path $root 'docs/business-rules/no-rule-files.csv'
    if (Test-Path $nrp) { foreach ($x in (Import-Csv $nrp -Encoding UTF8)) { if ($x.Reason) { $noRule[($x.Path -replace '\\', '/')] = $true } } }
    $dismissed = @{}
    $dp = Join-Path $root 'docs/business-rules/dismissed-candidates.csv'
    if (Test-Path $dp) {
        foreach ($x in (Import-Csv $dp -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($x.Reason)) { continue }
            $k = $x.Path -replace '\\', '/'
            if (-not $dismissed.ContainsKey($k)) { $dismissed[$k] = New-Object System.Collections.Generic.List[object] }
            foreach ($r in (ConvertFrom-RangeString $x.Lines)) { $dismissed[$k].Add($r) }
        }
    }
    $byFile = $cands | Group-Object File
    foreach ($g in $byFile) {
        $f = $g.Name
        if ($noRule.ContainsKey($f)) { continue }
        if (-not $brRanges.ContainsKey($f) -and -not $dismissed.ContainsKey($f)) {
            $candIssues.Add("ARCHIVO CON $($g.Count) CANDIDATOS sin ninguna BR ni justificacion: $f")
            continue
        }
        foreach ($c in $g.Group) {
            $ln = [int]$c.Line
            $hit = $false
            foreach ($src in @($brRanges[$f], $dismissed[$f])) {
                if ($null -eq $src) { continue }
                foreach ($r in $src) { if ($ln -ge $r[0] -and $ln -le $r[1]) { $hit = $true; break } }
                if ($hit) { break }
            }
            if (-not $hit) { $candIssues.Add("candidato sin cubrir: ${f}:$ln [$($c.Type)] $($c.Snippet)") }
        }
    }
    $fileLevel = @($candIssues | Where-Object { $_ -like 'ARCHIVO CON*' })
    foreach ($m in $fileLevel) { $errors.Add($m) }
    $lineLevel = @($candIssues | Where-Object { $_ -notlike 'ARCHIVO CON*' })
    foreach ($m in $lineLevel) { if ($Strict) { $errors.Add($m) } else { $warns.Add($m) } }
}

# --- Migracion ---
$trxStats = @{}
if ($Phase -eq 'Migration') {
    $trxRoot = Join-Path $root $TrxPath
    $trxFiles = @()
    if (Test-Path $trxRoot) { $trxFiles = @(Get-ChildItem -Path $trxRoot -Filter *.trx -Recurse -File) }
    if ($trxFiles.Count -eq 0) { $errors.Add("No hay resultados TRX en $TrxPath. Ejecuta: dotnet test --logger trx --results-directory $TrxPath") }
    foreach ($t in $trxFiles) {
        $xml = New-Object System.Xml.XmlDocument
        $xml.Load($t.FullName)
        $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace('t', 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')
        foreach ($res in $xml.SelectNodes('//t:UnitTestResult', $ns)) {
            $name = $res.GetAttribute('testName'); $outc = $res.GetAttribute('outcome')
            foreach ($m in [regex]::Matches($name, 'BR[-_](\d{4,})')) {
                $k = 'BR-' + $m.Groups[1].Value
                if (-not $trxStats.ContainsKey($k)) { $trxStats[$k] = @{ Pass = 0; Fail = 0 } }
                if ($outc -eq 'Passed') { $trxStats[$k].Pass++ } elseif ($outc -in 'Failed', 'Error', 'Timeout', 'Aborted') { $trxStats[$k].Fail++ }
            }
        }
    }
    foreach ($b in $brs) {
        $id = $b.Id; $idRx = $id -replace '-', '[-_]'
        if ($b.Status -in 'Identified', 'Planned') { $errors.Add("$id sigue en estado $($b.Status): debe quedar Implemented/Verified/DeviationApproved/Retired"); continue }
        if ($b.Status -in 'DeviationApproved', 'Retired') {
            if ([string]::IsNullOrWhiteSpace($b.Deviation) -or $b.Deviation -notmatch '(?i)ADR') { $errors.Add("$id ($($b.Status)) requiere Deviation con referencia a ADR y aprobador humano") }
            continue
        }
        if ([string]::IsNullOrWhiteSpace($b.Target)) { $errors.Add("$id sin Target"); continue }
        foreach ($t in ($b.Target -split ';')) {
            $t = $t.Trim(); if (-not $t) { continue }
            $tp = ConvertTo-FullPath $t
            if (-not (Test-Path $tp -PathType Leaf)) { $errors.Add("$id Target no existe: $t"); continue }
            if ([IO.File]::ReadAllText($tp) -notmatch $idRx) { $errors.Add("$id no esta referenciado en el codigo destino $t (agrega comentario/XML doc con $id)") }
        }
        if ([string]::IsNullOrWhiteSpace($b.Tests)) { $errors.Add("$id sin Tests"); continue }
        foreach ($t in ($b.Tests -split ';')) {
            $t = $t.Trim(); if (-not $t) { continue }
            $tp = ConvertTo-FullPath $t
            if (-not (Test-Path $tp -PathType Leaf)) { $errors.Add("$id archivo de test no existe: $t"); continue }
            if ([IO.File]::ReadAllText($tp) -notmatch $idRx) { $errors.Add("$id no esta referenciado en el test $t (usa DisplayName/nombre con $id)") }
        }
        $need = if ($b.Criticality -eq 'Critical') { $MinTestsCritical } else { 1 }
        $st = if ($trxStats.ContainsKey($id)) { $trxStats[$id] } else { @{ Pass = 0; Fail = 0 } }
        if ($st.Fail -gt 0) { $errors.Add("$id tiene $($st.Fail) prueba(s) FALLIDA(S) en TRX") }
        if ($st.Pass -lt $need) { $errors.Add("$id tiene $($st.Pass) prueba(s) aprobada(s) en TRX; se requieren $need (nombre del test debe contener $id)") }
    }
}

# --- Reporte ---
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Trazabilidad de reglas de negocio ($Phase)")
[void]$sb.AppendLine('')
$res = if ($errors.Count -eq 0) { 'APROBADO' } else { 'RECHAZADO' }
[void]$sb.AppendLine("- Fecha UTC: $((Get-Date).ToUniversalTime().ToString('s')) | Resultado: **$res** | Reglas: $($brs.Count)")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| BR | Feature | Criticidad | Estado | Origen (legacy) | Destino | Tests | Pass/Fail TRX |')
[void]$sb.AppendLine('|---|---|---|---|---|---|---|---|')
foreach ($b in $brs) {
    $st = if ($trxStats.ContainsKey($b.Id)) { "$($trxStats[$b.Id].Pass)/$($trxStats[$b.Id].Fail)" } else { '-' }
    [void]$sb.AppendLine("| $($b.Id) | $($b.Feature) | $($b.Criticality) | $($b.Status) | $($b.Source) | $($b.Target) | $($b.Tests) | $st |")
}
if ($errors.Count -gt 0) { [void]$sb.AppendLine(''); [void]$sb.AppendLine("## Fallas ($($errors.Count))"); foreach ($e in $errors) { [void]$sb.AppendLine("- $e") } }
if ($warns.Count -gt 0) { [void]$sb.AppendLine(''); [void]$sb.AppendLine("## Avisos: candidatos sin cubrir ($($warns.Count))"); foreach ($e in $warns) { [void]$sb.AppendLine("- $e") } }
$out = Join-Path $root 'docs/business-rules/traceability-report.md'
[IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Trazabilidad ($Phase): $($brs.Count) reglas | $res | avisos: $($warns.Count)"
$errors | Select-Object -First 40 | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
if ($errors.Count -gt 40) { Write-Host "  ... y $($errors.Count - 40) mas (ver $out)" -ForegroundColor Red }
if ($warns.Count -gt 0) { $warns | Select-Object -First 10 | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow } }
if ($errors.Count -gt 0) { exit 1 }
Write-Host "Reporte: $out" -ForegroundColor Green
exit 0
