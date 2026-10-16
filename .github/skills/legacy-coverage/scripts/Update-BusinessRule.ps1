<#
.SYNOPSIS
  Actualiza el estado/destino/tests/desviacion de una regla de negocio existente.

.EXAMPLE
  Update-BusinessRule.ps1 -Id BR-0001 -Status Implemented -Target 'src/Billing.Domain/DiscountPolicy.cs' -Tests 'tests/Billing.Tests/DiscountPolicyTests.cs'
.EXAMPLE
  Update-BusinessRule.ps1 -Id BR-0007 -Status DeviationApproved -Deviation 'ADR-0014; aprobado por Maria Lopez (Finanzas)'
.NOTES
  Planned/Implemented/Verified requieren -Target. Retired y DeviationApproved requieren -Deviation
  con referencia a ADR y persona humana que aprueba.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Id,
    [ValidateSet('Identified', 'Planned', 'Implemented', 'Verified', 'DeviationApproved', 'Retired')][string]$Status,
    [string]$Target,
    [string]$Tests,
    [string]$Deviation,
    [string]$Title,
    [string]$Rule,
    [ValidateSet('Critical', 'High', 'Medium', 'Low')][string]$Criticality,
    [string]$Source,
    [string]$Notes
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ledger.psm1') -Force

if ($Source) {
    $ledger = Import-Ledger
    $sha = @{}; foreach ($r in $ledger) { $sha[$r.Path] = $r.Sha256 }
    $errs = Test-BrSource -Source $Source -LedgerRows $ledger -ReadMap (Get-ReadMap -ShaByPath $sha)
    if ($errs.Count -gt 0) { $errs | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }; exit 1 }
}
$cat = Get-BrCatalogPath
Invoke-WithFileLock -Target $cat -Action {
    $rows = @(Import-BrCatalog)
    $br = $rows | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $br) { throw "No existe la regla $Id" }
    if ($Status) { $br.Status = $Status }
    if ($Target) { $br.Target = $Target }
    if ($Tests) { $br.Tests = $Tests }
    if ($Deviation) { $br.Deviation = $Deviation }
    if ($Title) { $br.Title = $Title }
    if ($Rule) { $br.Rule = $Rule }
    if ($Criticality) { $br.Criticality = $Criticality }
    if ($Source) { $br.Source = $Source }
    if ($Notes) { $br.Notes = $Notes }
    if ($br.Status -in 'Planned', 'Implemented', 'Verified' -and [string]::IsNullOrWhiteSpace($br.Target)) { throw "$Id en estado $($br.Status) requiere -Target." }
    if ($br.Status -in 'DeviationApproved', 'Retired' -and [string]::IsNullOrWhiteSpace($br.Deviation)) { throw "$Id en estado $($br.Status) requiere -Deviation (ADR + aprobador humano)." }
    Save-BrCatalog -Rows $rows
}
Write-Host "$Id actualizada."
