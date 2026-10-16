---
name: legacy-coverage
description: Garantiza cobertura 100% verificable al analizar o migrar código legacy .NET Framework / VB6 / VB.NET y que cada regla de negocio (BR-####) quede catalogada, implementada y probada. Úsalo siempre que un agente de assessment o migración deba leer legacy/, inventariar archivos, extraer reglas de negocio, reanudar una sesión interrumpida o cerrar una fase con gates. Provee scripts PowerShell (ledger, lector por tramos, gates) para Windows.
---

# Skill: cobertura 100% y reglas de negocio

La cobertura la mide un **script**, no el agente. Un agente que "dice" haber leído todo no es evidencia: aquí solo cuenta lo que el lector registró y lo que los gates aprueban.

Corre desde la **raíz del repo** (PowerShell 7 o Windows PowerShell 5.1). Scripts en `.github/skills/legacy-coverage/scripts/`; abreviamos `$S = .github/skills/legacy-coverage/scripts`.

## Reglas no negociables

1. Lee código de `legacy/` **solo** con `Read-LegacyChunk.ps1`. Leerlo por otra vía no cuenta como cobertura.
2. Nunca edites a mano `docs/inventory/coverage-ledger.csv`, `docs/inventory/read-log.tsv` ni `docs/business-rules/BR-catalog.csv`; usa los scripts.
3. No declares una fase completa si un gate no devolvió **exit 0**. Reporta el resultado literal.
4. Excluir un archivo exige razón y aprobador humano: `Update-Ledger.ps1 -Path <archivo> -Exclude -Reason "..." -ApprovedBy "<persona>"`.
5. Si el contexto se agota, **no reinicies**: ejecuta `Get-NextBatch.ps1 -Summary` y continúa.

## Flujo: Assessment (Fase 1)

```powershell
& "$S/Initialize-Ledger.ps1"              # inventario de TODO legacy/ (primera vez); -Refresh para actualizar sin perder progreso
& "$S/Get-NextBatch.ps1"                  # siguiente batch pendiente (un subagente por batch)
& "$S/Read-LegacyChunk.ps1" -Path <archivo> -Start 1   # lectura por tramos; el pie indica el siguiente -Start
& "$S/Find-RuleCandidates.ps1"            # candidatas a regla de negocio (escáner determinista)
& "$S/Add-BusinessRule.ps1" -Feature <f> -Title "..." -Rule "..." -Type <t> -Criticality <c> -Source "archivo:lineas"   # registra BR-####
& "$S/Update-Ledger.ps1" -Path <archivo> -Feature <feature>   # asigna feature a cada archivo
```

Gates de salida (exit 0 obligatorio):

```powershell
& "$S/Test-Coverage.ps1" -Phase Assessment
& "$S/Test-RuleTraceability.ps1" -Phase Assessment -Strict
```

Cada feature debe tener `docs/features/<feature>.md` que mencione sus archivos. Nombres reservados de feature: `cross-cutting`, `build-config`, `third-party`.

## Flujo: Migration (Fase 3)

Tras cada feature migrada: cierra sus archivos y avanza el estado de sus reglas.

```powershell
& "$S/Update-Ledger.ps1" -Path <archivo legacy> -Disposition Migrated -Target <destino>
& "$S/Update-BusinessRule.ps1" -Id BR-0001 -Status Implemented -Target <archivo destino> -Tests <pruebas>
dotnet test --logger trx --results-directory test-results
& "$S/Test-RuleTraceability.ps1" -Phase Migration -Strict
& "$S/Test-Coverage.ps1" -Phase Migration
```

- Disposiciones válidas: `Migrated`, `ReplacedByFramework`, `DeadCode`, `NotMigrated` (estas dos últimas con justificación).
- Estados de regla: `Identified` → `Planned` → `Implemented` → `Verified`; `DeviationApproved`/`Retired` exigen un ADR.
- El código destino debe contener el id `BR-NNNN`; las pruebas se enlazan por el patrón `BR_NNNN`/`BR-NNNN` en `test-results/**/*.trx` (reglas críticas: ≥2 pruebas pasando; el resto: ≥1).

## Reanudar una sesión

```powershell
& "$S/Get-NextBatch.ps1" -Summary
```

- Assessment: continúa con el siguiente batch hasta "No quedan lineas pendientes de lectura", luego los gates.
- Migration: retoma la primera tarea pendiente del plan y las BR que no estén `Implemented`.

## Referencias (cárgalas solo si necesitas el detalle)

- [`references/coverage-protocol.md`](references/coverage-protocol.md): ledger, columnas, batches, SHA-256, exclusiones.
- [`references/business-rules-protocol.md`](references/business-rules-protocol.md): catálogo BR, estados, trazabilidad hacia código y pruebas.

## Límite honesto

Los scripts garantizan que **cada línea pasó por el lector** y que cada regla tiene código y pruebas trazables; no garantizan que el modelo la **entendió**. Se mitiga con el escáner de candidatas, los checkpoints humanos y las pruebas de paridad.
