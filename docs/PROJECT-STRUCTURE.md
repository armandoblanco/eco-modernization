# Estructura del repo

Este documento explica carpeta por carpeta qué contiene el repo y cuándo se usa cada cosa.

---

## Top level

```
legacy-modernization-playbook/
├── README.md                            Guía de uso paso a paso (prompts)
├── .copilot-project.yml                Contexto del proyecto (opcional; los agentes lo completan)
├── .github/                             Agentes, prompts e instructions de Copilot
├── docs/                                Metodología, guías, tecnologías
├── assessment/                          Outputs de Fase 0 (business case + seguridad)
├── cloud-architectures/                 Outputs de Fase 4 (cloud)
├── src/ tests/ migration/               Código migrado, pruebas y plan de migración (vacíos al inicio)
├── scripts/                             md2html.ps1
├── .github/skills/legacy-coverage/      Skill: cobertura 100% y reglas de negocio (SKILL.md, scripts/, references/)
└── legacy/                              Código del cliente (read-only)
```

---

## `.github/`

Donde viven los componentes de Copilot. La estructura es:

```
.github/
├── agents/                             Planos (VS Code no lee subcarpetas)
│   ├── 00-business-case.agent.md         @business-case-analyst      (compartido)
│   ├── 01-dotnet-assessment.agent.md     @dotnet-assessment          (.NET)
│   ├── 01-vb-assessment.agent.md         @vb-assessment              (VB)
│   ├── 02-dotnet-planning.agent.md       @dotnet-planning
│   ├── 02-vb-planning.agent.md           @vb-planning
│   ├── 02-security-assessor.agent.md     @security-assessor
│   ├── 03-dotnet-migration.agent.md      @dotnet-migration
│   ├── 03-vb-migration.agent.md          @vb-migration
│   ├── 03-modernization-strategy.agent.md @modernization-strategy
│   ├── 04-cloud-architect.agent.md       @cloud-architect
│   ├── 05-azure-architect.agent.md       @azure-architect
│   ├── 06-plan-refiner.agent.md          @plan-refiner
│   └── 07-migration-tester.agent.md      @migration-tester
├── instructions/                       Planas; prefijo `vb-` o `dotnet-`
│   ├── testing-strategy                  (compartida: pirámide, paridad, tests por BR-id)
│   ├── vb-csharp-style, vb-winforms, vb-wpf-mvvm, vb-blazor   (winforms/wpf/blazor se activan por carpeta en src/)
│   └── dotnet-csharp-modern              (.NET 10)
└── prompts/                            Planos; prefijo `dotnet-` o `vb-` según la tecnología
    ├── construir-business-case, assessment-seguridad, disenar-arquitectura-cloud, validar-precios-azure
    ├── verificar-cobertura, verificar-reglas-negocio, reanudar-sesion
    ├── dotnet-analizar-proyecto, dotnet-generar-adr, dotnet-migrar-proyecto, dotnet-validar-paridad
    └── vb-analizar-feature, vb-generar-adr, vb-migrar-modulo, vb-validar-paridad
```

### Cómo elegir tecnología (sin configuración)

El repo trae ambas familias listas. No hay script de instalación:

1. **.NET Framework:** usa `@dotnet-assessment` → `@dotnet-planning` → `@dotnet-migration` y los prompts `/dotnet-*`.
2. **VB6 / VB.NET:** usa `@vb-assessment` → `@vb-planning` → `@vb-migration` y los prompts `/vb-*`.
3. Los agentes compartidos y `.github/skills/legacy-coverage/scripts/` sirven a ambas.
4. Las instrucciones `vb-winforms`, `vb-wpf-mvvm` y `vb-blazor` se activan solo si existen carpetas `*WinForms*`, `*Wpf*` o `*Web*`/`*Blazor*` en `src/`.
5. En un repo de cliente puedes borrar lo de la otra tecnología (agentes `*-vb-*` o `*-dotnet-*`, prompts con su prefijo, `docs/technologies/<otra>/`).

---

## `docs/`

Donde van los outputs de los agentes y la documentación del playbook.

```
docs/
├── README.md
├── PHILOSOPHY.md                       Filosofía, lecciones, qué NO es esta plantilla
├── AGENTS.md                           Catálogo de agentes con prompts ejemplo
├── PROJECT-STRUCTURE.md                Este archivo
├── QUICKSTART-dotnet.md                Quickstart .NET Framework
├── methodology/                        Metodología
│   ├── 00-overview.md
│   ├── 01-business-case.md             Fase 0
│   ├── 02-assessment-planning-execution.md   Fases 1, 2, 3
│   └── 05-cloud-deployment.md          Fase 4
├── shared/                             Lecciones, anti-patrones (transversal)
└── technologies/                       Catálogo por tecnología
    ├── README.md
    ├── vb/                             Trampas VB6/VBNet, decision-stack
    └── dotnet-framework/               Guía técnica .NET Framework
```

### Outputs por fase (se generan en proyectos reales)

Cuando los agentes corren, agregan documentos a `docs/`:

#### Después de Fase 1 (Assessment)

```
docs/
├── README.md                           Índice maestro (actualizado por agente)
├── SUMMARY.md                          Resumen ejecutivo
├── dependency-graph.md                 Grafo Mermaid + orden topológico
└── features/
    └── <NN>-<feature-name>.md          Un .md por feature funcional
```

Evidencia de cobertura y reglas (generada por `.github/skills/legacy-coverage/scripts/`):

```
docs/inventory/
├── coverage-ledger.csv                 Todos los archivos legacy: feature, disposición, destino
├── read-log.tsv                        Líneas leídas (append-only, ligado al SHA del archivo)
├── projects.md / nuget-packages.md ... Inventarios técnicos (.NET)
docs/business-rules/
├── BR-catalog.csv                      Catálogo de reglas BR-NNNN
└── traceability-report.md              Reporte del gate de trazabilidad
```

#### Después de Fase 2 (Planning)

```
docs/
├── ARQUITECTURA-TARGET.md              Stack target + mapping legacy → moderno
├── migration-plan.md                   Orden de migración con dependencias
└── adr/
    └── ADR-NNN-<decision-slug>.md      Un ADR por decisión arquitectónica
```

#### Después de Fase 3 (Migration)

```
<Proyecto>.Migrated.sln
src/                                     Código moderno
tests/                                   Unit / integration / parity (nombres con BR-NNNN)
test-results/                            TRX (evidencia usada por Test-RuleTraceability)
migration/
├── migration-log.md                    Bitácora por feature (VB)  /  {scenarioId}/tasks.md (.NET)
└── blockers-found.md                   Bloqueos no anticipados con propuestas
```

---

## `assessment/`

Outputs de Fase 0 (Business Case + Security) por proyecto.

```
assessment/
├── _templates/                         Plantillas tco-actual, roi, riesgo, ejecutivo, seguridad
└── {ProjectName}/
    ├── tco-actual-DDMMYYYY.{md,html}
    ├── roi-DDMMYYYY.{md,html}
    ├── riesgo-DDMMYYYY.{md,html}
    ├── ejecutivo-DDMMYYYY.{md,html}
    └── seguridad-DDMMYYYY.{md,html}
```

Cada entregable se genera en Markdown + HTML autocontenido (CSS embebido, sin dependencias externas) usando `pwsh scripts/md2html.ps1`. El HTML se puede enviar al cliente offline.

---

## `cloud-architectures/`

Outputs de Fase 4: arquitectura cloud target.

```
cloud-architectures/
├── README.md
├── _templates/                         Plantilla de ADR cloud
├── azure/                              5 patrones documentados + @azure-architect
│   ├── 01-iaas-lift-and-shift.md
│   ├── 02-paas-app-service.md
│   ├── 03-containers-aks.md
│   ├── 04-serverless-functions.md
│   └── 05-microservices-event-driven.md
└── on-premise/                         Patrón on-premise / híbrido
```

Cuando se corre `@azure-architect`, agrega en `cloud-architectures/azure/{ProjectName}/`:

```
cloud-architectures/azure/{ProjectName}/
├── ARQUITECTURA-CLOUD.md               Diagrama Mermaid + servicios elegidos
├── adr-cloud/                          ADRs específicos de cloud
├── pricing-estimate.md                 Costos validados vía Retail Prices API
└── iac/                                Bicep / Terraform base
```

---

## `scripts/`

```
scripts/
└── md2html.ps1                         HTML autocontenido offline desde .md
```

Se usa para producir versiones HTML de los entregables (business case, security, ARQUITECTURA-TARGET, ADRs) que se pueden enviar al cliente sin dependencias.

---

## `legacy/`

Viene vacía. **El código fuente del cliente va acá.**

Reglas:

1. Read-only para los agentes
2. No commitear secretos (limpia connection strings, API keys)
3. Respeta la estructura original (`.sln`, `.csproj`, `.vbp`, `.config`)
4. Anonimiza datos sensibles según regulación

Si el legacy es muy grande o propietario, deja un `LEGACY_LOCATION.md` con la ruta del snapshot analizado.

---

## `src/`

Viene vacía (junto con `tests/`). **El código moderno va acá.**

La estructura específica depende del stack target y del patrón arquitectónico elegido en el ADR-006 (o equivalente):

- Clean Architecture (Domain + Application + Infrastructure + UI)
- Hexagonal (Domain + Ports + Adapters)
- Capas tradicionales (Presentation + Business + Data)

El agente de Fase 3 genera la estructura según el ADR.

---

## `migration/`

Se crea cuando empieza Fase 3. Contiene la bitácora del trabajo:

```
migration/
├── migration-log.md                    Qué se migró, cuándo, con qué decisiones (VB)
├── {scenarioId}/tasks.md               Task list persistente (.NET Framework)
└── blockers-found.md                   Bloqueos no anticipados encontrados
```

Es útil para auditoría posterior y para que un nuevo miembro del equipo entienda decisiones tomadas durante la migración.
