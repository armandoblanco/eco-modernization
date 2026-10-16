# Tecnologías legacy soportadas

Este playbook cubre **solo** .NET Framework y Visual Basic (VB6 + VB.NET), con ejecución en **Windows** (PowerShell). La metodología (fases 0–4) es la misma; cambia la capa táctica: trampas semánticas, stacks target, agentes e instrucciones.

---

## Estado

| Tecnología | Estado | Carpeta | Stack target |
| --- | --- | --- | --- |
| **Visual Basic** (VB6 + VB.NET legacy) | Completo | [`vb/`](vb/) | .NET 10 (WinForms / WPF / Blazor) |
| **.NET Framework 2.0–4.8** | Completo | [`dotnet-framework/`](dotnet-framework/) | .NET 10 / 9 |

---

## Agentes por tecnología

```
.github/agents/
├── shared/            business-case, security, strategy, cloud, azure, refiner, tester
├── dotnet-framework/  01-dotnet-assessment, 02-dotnet-planning, 03-dotnet-migration
└── vb/                01-vb-assessment, 02-vb-planning, 03-vb-migration
```

Ambas familias usan los mismos protocolos de **cobertura 100%** y **trazabilidad de reglas de negocio**:
[`coverage-protocol`](../../.github/skills/legacy-coverage/references/coverage-protocol.md) · [`business-rules-protocol`](../../.github/skills/legacy-coverage/references/business-rules-protocol.md) · scripts en [`.github/skills/legacy-coverage/scripts/`](../../scripts/README.md).

## Agentes shared

- [`@business-case-analyst`](../../.github/agents/00-business-case.agent.md) — Fase 0
- [`@security-assessor`](../../.github/agents/02-security-assessor.agent.md) — Fase 0
- [`@modernization-strategy`](../../.github/agents/03-modernization-strategy.agent.md), [`@plan-refiner`](../../.github/agents/06-plan-refiner.agent.md) — Fase 2
- [`@migration-tester`](../../.github/agents/07-migration-tester.agent.md) — Fase 3
- [`@cloud-architect`](../../.github/agents/04-cloud-architect.agent.md), [`@azure-architect`](../../.github/agents/05-azure-architect.agent.md) — Fase 4
