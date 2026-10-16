<#
.SYNOPSIS
  Actualiza el ledger: asigna feature/disposicion/target o registra exclusiones aprobadas.

.EXAMPLE
  Update-Ledger.ps1 -Path 'legacy/Billing/**' -Feature billing
.EXAMPLE
  Update-Ledger.ps1 -Path 'legacy/Billing/Invoice.cs' -Disposition Migrated -Target 'src/Billing.Domain/Invoice.cs'
.EXAMPLE
  Update-Ledger.ps1 -Path 'legacy/web/jquery.min.js' -Exclude -Reason 'Libreria de terceros minificada' -ApprovedBy 'Nombre Apellido'
.NOTES
  Las exclusiones SOLO las aprueba un humano. El agente debe preguntar al usuario y nunca autoaprobar.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Path,
    [string]$Feature,
    [ValidateSet('Pending', 'Migrated', 'ReplacedByFramework', 'DeadCode', 'NotMigrated')][string]$Disposition,
    [string]$Target,
    [string]$Notes,
    [switch]$Exclude,
    [switch]$Unexclude,
    [string]$Reason,
    [string]$ApprovedBy
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Ledger.psm1') -Force

$rows = Import-Ledger
$regexes = @($Path | ForEach-Object { ConvertTo-GlobRegex (ConvertTo-RelPath $_.TrimEnd('/', '\')) })
$sel = @($rows | Where-Object { $p = $_.Path; ($regexes | Where-Object { $p -imatch $_ }).Count -gt 0 })
if ($sel.Count -eq 0) { throw "Ningun archivo del ledger coincide con: $($Path -join ', ')" }

if ($Exclude) {
    if ([string]::IsNullOrWhiteSpace($Reason) -or [string]::IsNullOrWhiteSpace($ApprovedBy)) { throw '-Exclude requiere -Reason y -ApprovedBy (persona humana que aprobo).' }
    if ($ApprovedBy -match '(?i)^(copilot|agent|agente|ai|ia|assistant|bot|claude|gpt)') { throw 'ApprovedBy debe ser una persona, no el agente.' }
}
if ($Disposition -in 'Migrated', 'ReplacedByFramework' -and [string]::IsNullOrWhiteSpace($Target)) { throw "Disposition $Disposition requiere -Target (archivo destino o API del framework que lo reemplaza)." }
if ($Disposition -in 'DeadCode', 'NotMigrated' -and [string]::IsNullOrWhiteSpace($Notes)) { throw "Disposition $Disposition requiere -Notes con la justificacion." }

foreach ($r in $sel) {
    if ($Feature) { $r.Feature = $Feature }
    if ($Disposition) { $r.Disposition = $Disposition }
    if ($Target) { $r.Target = $Target }
    if ($Notes) { $r.Notes = $Notes }
    if ($Exclude) { $r.Excluded = 'true'; $r.ExclusionReason = $Reason; $r.ApprovedBy = $ApprovedBy }
    if ($Unexclude) { $r.Excluded = 'false'; $r.ExclusionReason = ''; $r.ApprovedBy = '' }
}
Save-Ledger -Rows $rows
Write-Host "Actualizados $($sel.Count) archivo(s)."
