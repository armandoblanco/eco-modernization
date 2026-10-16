---
description: Reanuda un assessment o migración interrumpido (contexto agotado) desde el estado en disco
mode: agent
---

# Reanudar sesión

Nunca reinicies. El estado está en disco.

```powershell
pwsh .github/skills/legacy-coverage/scripts/Get-NextBatch.ps1 -Summary
```

- **Assessment (Fase 1):** continúa con el siguiente batch pendiente (`Get-NextBatch.ps1`), un subagente por batch, hasta "No quedan lineas pendientes de lectura"; luego los gates.
- **Migration (Fase 3):** lee `migration/{scenarioId}/tasks.md` (primer `[ ]`/`[~]`) y `progress-log.md`, o `migration/migration-log.md` + BR no `Implemented` (`Import-Csv docs/business-rules/BR-catalog.csv | Where-Object Status -ne 'Implemented'`).

Reporta: *"Reanudando en <batch/TASK/feature>. Pendiente: N líneas / M reglas. ¿Procedo?"* y continúa.
