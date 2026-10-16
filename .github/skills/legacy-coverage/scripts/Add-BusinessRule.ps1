<#
.SYNOPSIS
  Registra una regla de negocio en docs/business-rules/BR-catalog.csv y le asigna un ID BR-0001...

.EXAMPLE
  Add-BusinessRule.ps1 -Feature billing -Title 'Descuento por volumen' `
    -Rule 'Si el total de la factura supera 1000 se aplica 15% de descuento; el redondeo es a 2 decimales (away from zero).' `
    -Type Calculation -Criticality Critical -Source 'legacy/Billing/Invoice.cs:120-134;legacy/Billing/Rates.vb:10-22'

.NOTES
  Source solo se acepta si TODAS esas lineas fueron leidas con Read-LegacyChunk.ps1 (evidencia verificable).
  Documenta ademas la regla en docs/features/<feature>.md mencionando su ID (BR-xxxx).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Feature,
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Rule,
    [Parameter(Mandatory)][ValidateSet('Explicit', 'Implicit', 'Data', 'Config', 'UI', 'Security', 'Calculation', 'Integration', 'Workflow')][string]$Type,
    [Parameter(Mandatory)][ValidateSet('Critical', 'High', 'Medium', 'Low')][string]$Criticality,
    [Parameter(Mandatory)][string]$Source,
    [string]$Notes = ''
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ledger.psm1') -Force

$ledger = Import-Ledger
$sha = @{}; foreach ($r in $ledger) { $sha[$r.Path] = $r.Sha256 }
$errs = Test-BrSource -Source $Source -LedgerRows $ledger -ReadMap (Get-ReadMap -ShaByPath $sha)
if ($errs.Count -gt 0) { $errs | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }; exit 1 }

$cat = Get-BrCatalogPath
$new = Invoke-WithFileLock -Target $cat -Action {
    $rows = @(Import-BrCatalog)
    $max = 0
    foreach ($r in $rows) { if ($r.Id -match '^BR-(\d+)$') { $max = [Math]::Max($max, [int]$Matches[1]) } }
    $id = 'BR-{0:D4}' -f ($max + 1)
    $o = [ordered]@{}
    foreach ($c in (Get-BrColumns)) { $o[$c] = '' }
    $o.Id = $id; $o.Feature = $Feature; $o.Title = $Title; $o.Rule = $Rule; $o.Type = $Type
    $o.Criticality = $Criticality; $o.Source = $Source; $o.Status = 'Identified'; $o.Notes = $Notes
    Save-BrCatalog -Rows (@($rows) + [pscustomobject]$o)
    $id
}
Write-Output $new
