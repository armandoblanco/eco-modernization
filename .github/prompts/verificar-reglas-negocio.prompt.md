---
description: Verifica trazabilidad de reglas de negocio (BR-####) contra evidencia, docs, código y pruebas
mode: agent
---

# Verificar reglas de negocio

```powershell
pwsh .github/skills/legacy-coverage/scripts/Find-RuleCandidates.ps1
pwsh .github/skills/legacy-coverage/scripts/Test-RuleTraceability.ps1 -Phase ${input:phase:Assessment} -Strict
```

(En `Migration`, antes: `dotnet test --logger trx --results-directory test-results`.)

1. Para cada candidato sin regla: lee el tramo con `Read-LegacyChunk.ps1`, y crea la BR (`Add-BusinessRule.ps1`) o descártalo con motivo (`dismissed-candidates.csv` / `no-rule-files.csv`).
2. Para cada BR sin código destino, sin pruebas o con pruebas rojas (Migration): impleméntala/pruébala; usa `Update-BusinessRule.ps1`.
3. Cambios de comportamiento solo con ADR y aprobación humana (`-Status DeviationApproved -Deviation 'ADR-00NN; aprobado por <persona>'`).
4. Repite hasta exit 0 y enlaza `docs/business-rules/traceability-report.md`.
