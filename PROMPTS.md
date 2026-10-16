# Guía de uso: modernizar un sistema .NET Framework o VB con Copilot

Guía paso a paso para ejecutar una modernización en **tres etapas**: Assessment, Planning y Migration. Todo corre en **Windows** con **PowerShell 7**.

```text
Preparación  ->  1. Assessment  ->  2. Planning  ->  3. Migration
(clonar + legacy/) ¿qué hay?          ¿hacia dónde?     construir
```

**Regla de oro:** no pases a la siguiente etapa hasta que el *gate* de la actual termine con **exit 0**. Los gates son scripts, no opiniones del modelo.

**Agente vs prompt:** el **agente** (`@nombre`) ejecuta una etapa completa. El **prompt** (`/nombre`) es un atajo para una tarea puntual o una verificación.

---

## 0. Preparación

El repo **ya viene listo** para .NET Framework y para VB; no hay script de instalación ni configuración.

### Requisitos
- Windows 10/11, **PowerShell 7** (`pwsh`), Git y **.NET SDK 8 o 9**.
- **VS Code** con **GitHub Copilot Chat** (modo agente habilitado).

### Pasos
1. Clona este repositorio como base del proyecto del cliente:
   ```powershell
   git clone https://github.com/armandoblanco/legacy-modernization-playbook.git mi-proyecto
   cd mi-proyecto
   Remove-Item .git -Recurse -Force; git init
   ```
2. Elige tu familia de agentes (no necesitas desactivar la otra):

   | Tu sistema legacy | Agentes | Prompts |
   |---|---|---|
   | **.NET Framework** (2.0 a 4.8) | `@dotnet-assessment`, `@dotnet-planning`, `@dotnet-migration` | `/dotnet-...` |
   | **VB6 o VB.NET** | `@vb-assessment`, `@vb-planning`, `@vb-migration` | `/vb-...` |

3. Copia **todo** el código legacy del cliente en `legacy/` (código, proyectos, configs, scripts SQL, recursos). Lo que no esté aquí no se migrará. Borra `legacy/LEEME-PLANTILLA.md` (no es parte del inventario).
   ```powershell
   Copy-Item C:\ruta\al\sistema\* legacy\ -Recurse
   ```
4. (Opcional) Llena `.copilot-project.yml`: nombre del proyecto, cliente, `legacy_lang` (`vb6` | `vbnet`) y stack/cloud si ya los conoces. Lo que dejes vacío, el agente te lo pregunta y lo escribe.
5. Abre la carpeta en VS Code y abre Copilot Chat en modo **Agent**. Escribe `@` para confirmar que ves los agentes y `/` para ver los prompts.

---

## 1. Assessment: entender qué hay (100% del código leído)

**Objetivo:** inventariar cada archivo de `legacy/`, leer cada línea y extraer las reglas de negocio (`BR-####`).

### Pasos
1. Lanza el agente según tu tecnología:
   ```text
   @dotnet-assessment Analiza el sistema en legacy/
   ```
   ```text
   @vb-assessment Analiza el sistema en legacy/
   ```
2. El agente crea el inventario (`docs/inventory/coverage-ledger.csv`), lo lee en batches con subagentes y escribe un documento por feature en `docs/features/`, el catálogo `docs/business-rules/BR-catalog.csv` y `docs/SUMMARY.md`.
3. **Si el contexto se agota o la sesión se corta, no reinicies**; el avance está en disco:
   ```text
   /reanudar-sesion
   ```
4. Si quieres profundizar en una pieza concreta:
   - .NET: `/dotnet-analizar-proyecto` (un `.csproj`).
   - VB: `/vb-analizar-feature` (un módulo).
5. Cuando el agente diga que terminó, **verifica los gates**:
   ```text
   /verificar-cobertura
   /verificar-reglas-negocio
   ```
   Equivalen a:
   ```powershell
   pwsh .github/skills/legacy-coverage/scripts/Test-Coverage.ps1 -Phase Assessment
   pwsh .github/skills/legacy-coverage/scripts/Test-RuleTraceability.ps1 -Phase Assessment -Strict
   ```
6. Si algún gate falla, ejecuta `/reanudar-sesion` y repite hasta exit 0.

### Revisión humana (antes de avanzar)
- Los top bloqueantes del `docs/SUMMARY.md` tienen sentido.
- Las agrupaciones por feature coinciden con cómo el negocio ve el sistema.
- Las reglas críticas tienen la evidencia `archivo:líneas` correcta.

**Salida:** `docs/` completo, ledger sin líneas pendientes y catálogo de reglas con evidencia. **Gate:** ambos scripts en exit 0.

---

## 2. Planning: decidir hacia dónde

**Objetivo:** convertir el assessment en decisiones formales (ADRs), arquitectura destino y un plan de migración ordenado. **Aquí no se genera código.**

### Pasos
1. Lanza el agente de planning:
   ```text
   @dotnet-planning Genera la arquitectura target, los ADRs y el plan de migración
   ```
   ```text
   @vb-planning Genera la arquitectura target, los ADRs y el plan de migración
   ```
2. Responde sus preguntas (restricciones, plazos, stack, preferencias). Si no sabes algo, dilo; el agente documenta el supuesto en un ADR.
3. (Opcional, recomendado) Pide una segunda opinión sobre el enfoque y el plan:
   ```text
   @modernization-strategy Evalúa el patrón de modernización recomendado
   @plan-refiner Revisa y refina el plan
   ```
4. Para agregar una decisión puntual: `/dotnet-generar-adr` (.NET) o `/vb-generar-adr` (VB).
5. **Revisa y aprueba** cada ADR y el plan. Confirma que cada feature lista sus reglas `BR-####` y su criterio de salida.

### Entregables
| | .NET Framework | VB |
|---|---|---|
| Arquitectura | `docs/ARQUITECTURA-TARGET.md` | `docs/ARQUITECTURA-TARGET.md` |
| Decisiones | `docs/adr/` | `docs/adr/` |
| Plan | `migration/{scenarioId}/plan.md` | `docs/migration-plan.md` |

**Gate:** ADRs y plan **aprobados por una persona**. Sin esto no empieza la migración.

---

## 3. Migration: construir

**Objetivo:** migrar feature por feature a .NET 10 en `src/` y `tests/`, con una prueba por cada regla de negocio.

### Pasos
1. Lanza el agente de migración:
   ```text
   @dotnet-migration Ejecuta el plan de migración
   ```
   ```text
   @vb-migration Ejecuta el plan de migración
   ```
   El agente migra en el orden del plan, compila (`dotnet build`) y prueba (`dotnet test`) tras cada tarea.
2. Para migrar una pieza específica en vez de todo el plan:
   - .NET: `/dotnet-migrar-proyecto`
   - VB: `/vb-migrar-modulo`
3. Valida que el código migrado se comporta igual que el legacy:
   `/dotnet-validar-paridad` (.NET) o `/vb-validar-paridad` (VB), o pide al agente de pruebas: `@migration-tester Verifica la paridad de <feature>`.
4. Si se corta la sesión: `/reanudar-sesion` (retoma la primera tarea pendiente).
5. Al terminar cada feature y al final, corre las pruebas y los gates:
   ```powershell
   dotnet test --logger trx --results-directory test-results
   ```
   ```text
   /verificar-reglas-negocio
   /verificar-cobertura
   ```
   Equivalen a:
   ```powershell
   pwsh .github/skills/legacy-coverage/scripts/Test-RuleTraceability.ps1 -Phase Migration -Strict
   pwsh .github/skills/legacy-coverage/scripts/Test-Coverage.ps1 -Phase Migration
   ```
   (En los dos prompts, elige la fase **Migration** cuando te la pidan.)

### Qué validan los gates
- **Cada regla `BR-####`** está implementada en código que cita su ID y tiene pruebas pasando (≥2 si es crítica).
- **Cada archivo legacy** terminó con una disposición explícita: `Migrated`, `ReplacedByFramework`, `DeadCode` o `NotMigrated` (este último con justificación aprobada).

**Salida:** solución `<Proyecto>.Migrated.sln` compilando, `test-results/` con TRX verde y ambos gates en exit 0.

---

## Resumen: qué ejecutar y en qué orden

| # | Etapa | Escribe en el chat | Verifica |
|---|---|---|---|
| 0 | Preparación | Clona el repo y copia el código a `legacy/` | `legacy/` con todo el código |
| 1 | Assessment | `@dotnet-assessment` o `@vb-assessment` (+ `/reanudar-sesion` si se corta) | `/verificar-cobertura` y `/verificar-reglas-negocio` en exit 0 |
| 2 | Planning | `@dotnet-planning` o `@vb-planning` (+ `/dotnet-generar-adr` o `/vb-generar-adr`) | ADRs y plan aprobados por una persona |
| 3 | Migration | `@dotnet-migration` o `@vb-migration` (+ `/dotnet-validar-paridad` o `/vb-validar-paridad`) | `dotnet test` verde y gates en exit 0 |

## Referencia de prompts

| Prompt | Etapa | Uso |
|---|---|---|
| `/dotnet-analizar-proyecto` | 1 (.NET) | Perfil de un `.csproj` concreto |
| `/vb-analizar-feature` | 1 (VB) | Analiza un módulo y genera su `docs/features/<feature>.md` |
| `/verificar-cobertura` | 1 y 3 | Corre `Get-NextBatch -Summary` y `Test-Coverage` |
| `/verificar-reglas-negocio` | 1 y 3 | Corre `Find-RuleCandidates` y `Test-RuleTraceability -Strict` |
| `/reanudar-sesion` | 1 y 3 | Retoma desde el estado en disco |
| `/dotnet-generar-adr`, `/vb-generar-adr` | 2 | Crea un ADR en `docs/adr/` |
| `/dotnet-migrar-proyecto` | 3 (.NET) | Migra un proyecto o feature |
| `/vb-migrar-modulo` | 3 (VB) | Migra un módulo |
| `/dotnet-validar-paridad`, `/vb-validar-paridad` | 3 | Pruebas de paridad legacy vs migrado |

## Problemas frecuentes

- **No aparecen `@agentes` o `/prompts`:** abre la carpeta raíz del repo (la que contiene `.github/`) y verifica que Copilot Chat esté en modo Agent. Recarga la ventana de VS Code.
- **El gate falla con líneas o reglas pendientes:** es el comportamiento esperado; ejecuta `/reanudar-sesion` y no edites a mano `coverage-ledger.csv` ni `read-log.tsv`.
- **Se llenó el chat:** abre uno nuevo y usa `/reanudar-sesion`. El estado no vive en la conversación.
- **`pwsh` no se reconoce:** instala PowerShell 7 (`winget install Microsoft.PowerShell`).

Detalle técnico: [`.github/skills/legacy-coverage/references/coverage-protocol.md`](.github/skills/legacy-coverage/references/coverage-protocol.md), [`.github/skills/legacy-coverage/references/business-rules-protocol.md`](.github/skills/legacy-coverage/references/business-rules-protocol.md) y [`scripts/README.md`](scripts/README.md).
