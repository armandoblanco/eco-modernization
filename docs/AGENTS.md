# Catálogo de agentes Copilot

Lista completa de agentes incluidos en el playbook, con prompts de ejemplo y referencia al archivo de definición.

Todos los agentes se invocan desde GitHub Copilot Chat en VS Code con la sintaxis `@<nombre-agente> <prompt>`. Cubren **solo .NET Framework y VB6/VB.NET** y corren en **Windows** (PowerShell).

## Garantías de los agentes de assessment y migración

Los agentes `@*-assessment` y `@*-migration` no "declaran" cobertura: la **demuestran** con `.github/skills/legacy-coverage/scripts/`:

- **Cobertura 100%**: ledger de todos los archivos, lectura solo con `Read-LegacyChunk.ps1`, batches con subagentes, reanudación con `Get-NextBatch.ps1`, cierre con `Test-Coverage.ps1` (exit 0). Ver [`coverage-protocol`](../.github/skills/legacy-coverage/references/coverage-protocol.md).
- **Reglas de negocio**: catálogo `BR-catalog.csv`, escáner `Find-RuleCandidates.ps1`, y en Fase 3 trazabilidad regla → código (`BR-NNNN`) → pruebas (TRX) con `Test-RuleTraceability.ps1`. Ver [`business-rules-protocol`](../.github/skills/legacy-coverage/references/business-rules-protocol.md).
- Si el contexto se agota: `@<agente> Continúa` retoma desde el siguiente batch pendiente.

---

## Agentes compartidos

### `@business-case-analyst`

**Fase 0: Construye el caso de negocio del proyecto.**

Entrevista al usuario, estima TCO actual del legacy, calcula ROI esperado de la modernización, evalúa riesgos, y produce un resumen ejecutivo para el cliente. Todos los entregables en versión Markdown + HTML autocontenido (offline).

Archivo: [`.github/agents/00-business-case.agent.md`](../.github/agents/00-business-case.agent.md)

Prompts típicos:

```text
@business-case-analyst Construye el caso de negocio para mi proyecto
```

```text
@business-case-analyst Estima el TCO del sistema legacy comparado con la versión modernizada
```

```text
@business-case-analyst Genera el resumen ejecutivo para presentar al sponsor
```

Outputs en `assessment/{ProjectName}/`:
- `tco-actual-DDMMYYYY.{md,html}`
- `roi-DDMMYYYY.{md,html}`
- `riesgo-DDMMYYYY.{md,html}`
- `ejecutivo-DDMMYYYY.{md,html}`

---

### `@security-assessor`

**Fase 0: Análisis de seguridad whitehat del código legacy.**

Revisa el código en `legacy/` desde la perspectiva de un atacante: vulnerabilidades comunes (SQL injection, XSS, deserialización insegura, hardcoded secrets, criptografía débil), dependencias con CVEs conocidas, y configuraciones inseguras.

Archivo: [`.github/agents/02-security-assessor.agent.md`](../.github/agents/02-security-assessor.agent.md)

Prompts típicos:

```text
@security-assessor Revisa la seguridad del código en legacy/
```

```text
@security-assessor Enfócate en la capa de autenticación y manejo de sesiones
```

```text
@security-assessor Genera el reporte de findings con clasificación CVSS
```

Output: `assessment/{ProjectName}/seguridad-DDMMYYYY.{md,html}`

---

### `@modernization-strategy`

**Fase 2: recomienda el patrón de modernización (6 R's de Gartner).** Pregunta, no asume; incluye sub-flujo para apps desktop (mantener vs. migrar a web).

Archivo: [`.github/agents/03-modernization-strategy.agent.md`](../.github/agents/03-modernization-strategy.agent.md)

### `@plan-refiner`

**Fase 2: refina el plan de migración** (orden, dependencias, riesgos) antes de ejecutar.

Archivo: [`.github/agents/06-plan-refiner.agent.md`](../.github/agents/06-plan-refiner.agent.md)

### `@migration-tester`

**Fase 3: genera y ejecuta pruebas de paridad** contra el legacy, con matriz regla → prueba (IDs `BR-NNNN`) y reporte de gaps.

Archivo: [`.github/agents/07-migration-tester.agent.md`](../.github/agents/07-migration-tester.agent.md)

### `@cloud-architect`

**Fase 4: propone 2-3 arquitecturas candidatas (Azure / on-premise / híbrido)** con trade-offs, ADRs e IaC base.

Archivo: [`.github/agents/04-cloud-architect.agent.md`](../.github/agents/04-cloud-architect.agent.md)

---

### `@azure-architect`

**Fase 4: Diseña arquitectura cloud target en Azure con precios validados.**

Produce diagrama Mermaid, lista de servicios Azure recomendados, ADRs de cada decisión arquitectónica, IaC base, y costos estimados validados contra Azure Retail Prices API (no inventa precios).

Archivo: [`.github/agents/05-azure-architect.agent.md`](../.github/agents/05-azure-architect.agent.md)

Prompts típicos:

```text
@azure-architect Diseña la arquitectura cloud para MiProyecto en Azure
```

```text
@azure-architect Compara opciones de hosting: App Service vs Container Apps vs AKS
```

```text
@azure-architect Estima el costo mensual del entorno productivo según el ADR-001
```

```text
@azure-architect Genera el Bicep para desplegar la arquitectura aprobada
```

Output: `cloud-architectures/azure/`

---

## Agentes Visual Basic (VB6 + VB.NET)

### `@vb-assessment`

**Fase 1: Analiza un sistema VB6 o VB.NET legacy.**

Detecta automáticamente si es VB6 o VB.NET. Inventaria formularios, módulos, clases. Clasifica OCX/COM (VB6) o APIs deprecadas (VB.NET). Extrae reglas de negocio implícitas. Detecta dependencias entre módulos.

Archivo: [`.github/agents/01-vb-assessment.agent.md`](../.github/agents/01-vb-assessment.agent.md)

Prompts típicos:

```text
@vb-assessment Analiza el sistema en legacy/
```

```text
@vb-assessment Empieza por el módulo de facturación y profundiza en sus dependencias
```

```text
@vb-assessment Identifica todos los OCX usados y clasifícalos por criticidad
```

Output: `docs/features/`, `docs/dependency-graph.md`, `docs/SUMMARY.md`, `docs/inventory/coverage-ledger.csv`, `docs/business-rules/BR-catalog.csv`. No cierra hasta que `Test-Coverage.ps1` y `Test-RuleTraceability.ps1 -Strict` dan exit 0.

---

### `@vb-planning`

**Fase 2: Diseña arquitectura target y produce ADRs.**

Lee el assessment de Fase 1, pregunta decisiones críticas (stack target, replacement de OCX bloqueantes, ORM, framework MVVM, patrón arquitectónico), y documenta cada decisión como ADR.

Archivo: [`.github/agents/02-vb-planning.agent.md`](../.github/agents/02-vb-planning.agent.md)

Prompts típicos:

```text
@vb-planning Revisa el assessment y planifica la migración
```

```text
@vb-planning Quiero discutir el target: WPF vs Blazor vs WinForms moderno
```

```text
@vb-planning Genera el ADR para reemplazar el OCX de SigPlusNET
```

Output: `docs/ARQUITECTURA-TARGET.md`, `docs/adr/`, `docs/migration-plan.md`

---

### `@vb-migration`

**Fase 3: Ejecuta la migración del sistema legacy a C# moderno.**

Lee `ARQUITECTURA-TARGET.md` y los ADRs, sigue el orden topológico del plan, genera código en `src/` con tests embebidos (Domain, Application, Parity). Trabaja feature por feature con compile-and-test entre capas.

Archivo: [`.github/agents/03-vb-migration.agent.md`](../.github/agents/03-vb-migration.agent.md)

Prompts típicos:

```text
@vb-migration Ejecuta la migración del sistema legacy
```

```text
@vb-migration Empieza por el feature autenticación
```

```text
@vb-migration Continúa con el siguiente feature del plan
```

```text
@vb-migration Reporta el estado actual de la migración con tabla de "Done" por feature
```

Output: `src/` (estructura Clean Architecture), `migration/migration-log.md`, `migration/parity-report.md`

---

## Agentes .NET Framework (2.0-4.8)

### `@dotnet-assessment`

**Fase 1: Analiza un sistema .NET Framework legacy.**

Detecta versión actual, tipo de proyecto (WebForms, WCF, MVC, Service), paquetes NuGet legacy con análisis de compatibilidad .NET 10, APIs deprecadas, configuración en `Web.config` que no migra 1:1.

Archivo: [`.github/agents/01-dotnet-assessment.agent.md`](../.github/agents/01-dotnet-assessment.agent.md)

Prompts típicos:

```text
@dotnet-assessment Analiza el sistema en legacy/
```

```text
@dotnet-assessment Identifica las dependencias NuGet sin versión .NET 10
```

```text
@dotnet-assessment Analiza específicamente el módulo de WCF y sus contratos
```

---

### `@dotnet-planning`

**Fase 2: Diseña target y produce ADRs.**

Decisiones: target framework (fijo: .NET 10), tipo de proyecto target, estrategia de WCF (CoreWCF vs gRPC vs REST), upgrade in-place vs greenfield, hosting target.

Archivo: [`.github/agents/02-dotnet-planning.agent.md`](../.github/agents/02-dotnet-planning.agent.md)

Prompts típicos:

```text
@dotnet-planning Revisa el assessment y planifica la migración
```

```text
@dotnet-planning Decidamos si vamos upgrade in-place o greenfield
```

```text
@dotnet-planning Genera el ADR de reemplazo de WCF
```

---

### `@dotnet-migration`

**Fase 3: Ejecuta migración a .NET 10.**

Aplica `.NET Upgrade Assistant` si la decisión fue in-place. Para greenfield: crea la solución ASP.NET Core, migra feature por feature.

Archivo: [`.github/agents/03-dotnet-migration.agent.md`](../.github/agents/03-dotnet-migration.agent.md)

Prompts típicos:

```text
@dotnet-migration Ejecuta la migración del sistema legacy
```

```text
@dotnet-migration Migra los servicios WCF a CoreWCF según el ADR-003
```

```text
@dotnet-migration Reporta cobertura de tests post-migración
```

---

## Modelos recomendados

Cada agente declara su modelo recomendado en el frontmatter. Puedes override en `.copilot-project.yml` o cambiando `model:` en el agente.

| Tipo de tarea | Modelo recomendado | Por qué |
| --- | --- | --- |
| Assessment, business case | **Claude Opus 4.6** | Razonamiento profundo en análisis de código complejo |
| Planning, ADRs | **Claude Opus 4.6** | Razonamiento estructurado y trade-offs |
| Migration (refactor de código) | **Claude Sonnet 4.6** | Velocidad + precisión en transformaciones iterativas |
| Security assessment | **Claude Opus 4.6** | Análisis adversarial |
| Cloud architecture | **Claude Opus 4.6** | Trade-offs y validación de precios |

---

## Prompts adicionales (slash commands)

Además de los agentes, hay prompts reusables en `.github/prompts/` que se invocan con `/` en Copilot Chat:

Todos están en [`.github/prompts/`](../.github/prompts/) (sin subcarpetas). Guía de uso: [`PROMPTS.md`](../PROMPTS.md).

- **VB:** `/vb-analizar-feature`, `/vb-generar-adr`, `/vb-migrar-modulo`, `/vb-validar-paridad`
- **.NET Framework:** `/dotnet-analizar-proyecto`, `/dotnet-generar-adr`, `/dotnet-migrar-proyecto`, `/dotnet-validar-paridad`
- **Compartidos:** `/construir-business-case`, `/assessment-seguridad`, `/disenar-arquitectura-cloud`, `/validar-precios-azure`
- **Cobertura y reglas (shared):** `/verificar-cobertura`, `/verificar-reglas-negocio`, `/reanudar-sesion`
