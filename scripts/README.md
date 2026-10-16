# scripts/

Utilidades PowerShell del repo (**Windows**; PowerShell 7 recomendado, 5.1 compatible salvo `md2html.ps1`). No modifican el código legacy de cliente.

Instalar PowerShell 7: `winget install Microsoft.PowerShell`

## Skill `legacy-coverage` — cobertura 100% y reglas de negocio

Vive en [`.github/skills/legacy-coverage/`](../.github/skills/legacy-coverage/SKILL.md) (`SKILL.md`, `scripts/`, `references/`); los agentes lo cargan explícitamente. Ejecuta los scripts desde la raíz del repo. Herramientas que dan **evidencia verificable** (no declarativa) de que el agente leyó todo el legacy y migró cada regla de negocio. Protocolos completos:
[`.github/skills/legacy-coverage/references/coverage-protocol.md`](../.github/skills/legacy-coverage/references/coverage-protocol.md) y [`.github/skills/legacy-coverage/references/business-rules-protocol.md`](../.github/skills/legacy-coverage/references/business-rules-protocol.md).

| Script | Para qué |
| --- | --- |
| `Initialize-Ledger.ps1` | Inventaría **todos** los archivos de `legacy/` (líneas, bytes, SHA-256, batch) y crea/refresca `docs/inventory/coverage-ledger.csv`. `-Refresh` tras cambios en `legacy/`. |
| `Get-NextBatch.ps1` | Cola de trabajo: siguiente batch con líneas sin leer. `-Summary` muestra el avance; sirve para **reanudar** tras agotar el contexto. |
| `Read-LegacyChunk.ps1` | Único modo de leer legacy: devuelve el tramo con números de línea y lo **registra** en `docs/inventory/read-log.tsv` (append-only, ligado al SHA del archivo). |
| `Update-Ledger.ps1` | Asigna feature/disposición/destino a cada archivo o registra exclusiones aprobadas (con motivo y aprobador). |
| `Test-Coverage.ps1` | **Gate 100%**: cada línea leída, cada archivo con feature y disposición, cada feature documentado. Exit 0 = OK. `-Phase Assessment\|Migration`. |
| `Find-RuleCandidates.ps1` | Escaneo determinista de líneas candidatas a regla de negocio (condicionales, comparaciones, redondeos, constantes, SQL, etc.), independiente del LLM. |
| `Add-BusinessRule.ps1` | Registra una regla en `docs/business-rules/BR-catalog.csv` con ID `BR-0001…`. |
| `Update-BusinessRule.ps1` | Avanza el estado (Identified → Planned → Implemented → Verified) con destino, tests y desviaciones (ADR). |
| `Test-RuleTraceability.ps1` | **Gate de reglas**: cada regla con fuente, código y pruebas (TRX con el ID `BR-NNNN`). Genera `traceability-report.md`. `-Strict`, `-Phase`. |

Flujo típico:

```powershell
pwsh .github/skills/legacy-coverage/scripts/Initialize-Ledger.ps1
pwsh .github/skills/legacy-coverage/scripts/Get-NextBatch.ps1 -Summary
# ... los agentes leen con Read-LegacyChunk.ps1 y registran reglas ...
pwsh .github/skills/legacy-coverage/scripts/Test-Coverage.ps1 -Phase Assessment
pwsh .github/skills/legacy-coverage/scripts/Test-RuleTraceability.ps1 -Phase Assessment -Strict
# Fase 3
dotnet test --logger trx --results-directory test-results
pwsh .github/skills/legacy-coverage/scripts/Test-RuleTraceability.ps1 -Phase Migration
pwsh .github/skills/legacy-coverage/scripts/Test-Coverage.ps1 -Phase Migration
```

> Límite honesto: los scripts garantizan que cada línea **pasó por el lector** y que cada regla **tiene código y pruebas**; no pueden garantizar que el LLM la *entendió* bien. Por eso existen el escáner determinista, la revisión HITL y las pruebas de paridad.

## md2html.ps1

Convierte Markdown a HTML autocontenido (CSS embebido, abre offline). Usa `ConvertFrom-Markdown` (PowerShell 7+) o `pandoc` como alternativa (`winget install JohnMacFarlane.Pandoc`).

```powershell
pwsh scripts/md2html.ps1 assessment/MiProyecto/seguridad-08052026.md
pwsh scripts/md2html.ps1 -Path assessment/MiProyecto -Recurse
```

## Convención de nombres de los reportes

`assessment/{ProjectName}/{categoria}-{DDMMYYYY}.{md,html}`

Categorías: `seguridad`, `tco-actual`, `roi-modernizacion`, `riesgo-no-hacer`, `business-case-ejecutivo`.

Cada nuevo run **no sobreescribe** el anterior: nueva fecha = nuevo archivo.
