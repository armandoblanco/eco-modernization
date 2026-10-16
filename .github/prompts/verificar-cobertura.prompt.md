---
description: Verifica la cobertura 100% de lectura del legacy (ledger + gate) y reporta lo pendiente
mode: agent
---

# Verificar cobertura del legacy

Ejecuta en PowerShell (Windows) y reporta el resultado sin interpretarlo a tu favor:

```powershell
pwsh .github/skills/legacy-coverage/scripts/Get-NextBatch.ps1 -Summary
pwsh .github/skills/legacy-coverage/scripts/Test-Coverage.ps1 -Phase ${input:phase:Assessment}
```

1. Si el ledger no existe: `pwsh .github/skills/legacy-coverage/scripts/Initialize-Ledger.ps1`. Si hay archivos nuevos o cambiados: `Initialize-Ledger.ps1 -Refresh`.
2. Si el gate falla, lista por categoría: archivos sin registrar, líneas sin leer (rangos exactos), archivos sin feature, sin doc de feature, exclusiones sin aprobador humano.
3. Para cada hueco, léelo **solo** con `pwsh .github/skills/legacy-coverage/scripts/Read-LegacyChunk.ps1 -Path <archivo> -Start <n>` y completa el análisis/BR correspondiente.
4. Repite hasta exit 0. No afirmes "100%" sin exit 0.
5. Las exclusiones las aprueba una persona: pregunta y registra con `Update-Ledger.ps1 -Exclude -Reason ... -ApprovedBy <persona>`.
