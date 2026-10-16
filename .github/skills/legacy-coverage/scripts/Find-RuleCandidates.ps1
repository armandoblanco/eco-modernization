<#
.SYNOPSIS
  Escaneo DETERMINISTA de lineas candidatas a contener reglas de negocio (no depende del LLM).

.DESCRIPTION
  Recorre los archivos del ledger y marca lineas con: comparaciones con literales, constantes, aritmetica de
  tasas, redondeos/fechas/formatos, errores y mensajes de validacion, SQL con logica, seguridad/roles,
  appSettings, Select Case/switch, etc. Escribe docs/business-rules/rule-candidates.csv (File, Line, Type, Snippet).
  Test-RuleTraceability.ps1 exige que cada candidato quede cubierto por una BR (Source) o descartado con motivo
  en docs/business-rules/dismissed-candidates.csv (Path, Lines, Reason) / no-rule-files.csv (Path, Reason).
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ledger.psm1') -Force

$patterns = [ordered]@{
    'Comparison'   = '(?i)(>=|<=|<>|!=|==|\s>\s|\s<\s|\s=\s|\bIs(Greater|Less)\b)\s*[-+]?\d+(\.\d+)?[mMdDfF]?\b(?<!\b[01]\b)|\b(Then|if)\b.*[<>]=?\s*\d{2,}'
    'StringCompare'= '(?i)(==|<>|!=|\bEquals\(|\s=\s)\s*"[^"]{1,40}"|\bCase\s+"[^"]+"|case\s+"[^"]+"\s*:'
    'Constant'     = '(?i)\b(Const|const|static\s+readonly|readonly)\b.*(=|:=)\s*("|\d)'
    'Calculation'  = '(?i)[*/]\s*(0?\.\d+|\d{2,})[mMdDfF]?\b|\b(Math\.Round|Round|Math\.Floor|Math\.Ceiling|CDec|CCur|Fix|Int)\s*\('
    'DateFormat'   = '(?i)\b(DateAdd|DateDiff|DateSerial|AddDays|AddMonths|AddYears|DayOfWeek|Weekday|Format|FormatCurrency|ToString)\s*\(.*("[^"]*[dMyHhm#0]{2,}[^"]*")'
    'ErrorMessage' = '(?i)\b(Err\.Raise|throw\s+new|Throw\s+New|MsgBox|MessageBox\.Show|RaiseError|RAISERROR|ModelState\.AddModelError|Response\.Write)\b'
    'ErrorHandling'= '(?i)\bOn\s+Error\b|\bErr\.Number\b|\bcatch\s*\(\s*\w+Exception'
    'Sql'          = '(?i)\b(WHERE|CASE\s+WHEN|HAVING|RAISERROR|CREATE\s+(PROC|PROCEDURE|TRIGGER|FUNCTION|VIEW)|ALTER\s+(PROC|PROCEDURE|TRIGGER)|EXEC(UTE)?\s+\w+|UPDATE\s+\w+\s+SET|INSERT\s+INTO|DELETE\s+FROM|MERGE\s+INTO)\b'
    'Validation'   = '(?i)\[(Required|StringLength|Range|RegularExpression|MaxLength|MinLength|Compare|EmailAddress)\b|RequiredFieldValidator|RangeValidator|RegularExpressionValidator|CompareValidator|CustomValidator|\.IsMatch\(|Like\s+"'
    'Security'     = '(?i)\b(IsInRole|Authorize|PrincipalPermission|Roles\s*=|FormsAuthentication|CheckPermission|HasPermission|Impersonat)\w*'
    'Config'       = '(?i)\b(AppSettings|ConfigurationManager|GetSetting|ReadProfile|Registry\w*)\b|<add\s+key="'
    'Branching'    = '(?i)^\s*(Select\s+Case|switch\s*\()'
    'Time'         = '(?i)\b(DateTime\.(Now|Today|UtcNow)|Now\(\)|Date\(\)|Timer)\b'
}
$compiled = [ordered]@{}
foreach ($k in $patterns.Keys) { $compiled[$k] = New-Object System.Text.RegularExpressions.Regex($patterns[$k], 'Compiled') }
$commentRx = '^\s*(//|\x27|REM\s|--|/\*|\*|<!--|#region|#endregion)'

$rows = Import-Ledger
$out = New-Object System.Collections.Generic.List[object]
foreach ($r in $rows) {
    if ($r.Excluded -eq 'true' -or $r.Category -in 'Binary', 'Minified') { continue }
    $full = ConvertTo-FullPath $r.Path
    if (-not (Test-Path $full)) { continue }
    $lines = Get-TextLines $full
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $ln = $lines[$i]
        if ($ln.Trim().Length -eq 0 -or $ln -match $commentRx) { continue }
        foreach ($k in $compiled.Keys) {
            if ($compiled[$k].IsMatch($ln)) {
                $snippet = $ln.Trim(); if ($snippet.Length -gt 160) { $snippet = $snippet.Substring(0, 160) }
                $out.Add([pscustomobject]@{ File = $r.Path; Line = $i + 1; Type = $k; Snippet = $snippet })
                break
            }
        }
    }
}
$dir = Join-Path (Get-RepoRoot) 'docs/business-rules'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$csv = Join-Path $dir 'rule-candidates.csv'
$out | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
Write-Host "Candidatos: $($out.Count) lineas en $(@($out | Select-Object -ExpandProperty File -Unique).Count) archivos -> $csv"
$out | Group-Object Type | Sort-Object Count -Descending | ForEach-Object { Write-Host ("  {0,-14} {1,6}" -f $_.Name, $_.Count) }
