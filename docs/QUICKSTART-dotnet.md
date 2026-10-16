# Quickstart: .NET Framework 2.0-4.8

Guía rápida para modernizar un sistema en .NET Framework (WebForms, WCF, ASP.NET MVC clásico, Windows Services) a .NET 10 usando el playbook.

---

## Cuándo usar esta guía

Tu sistema legacy es .NET Framework si:

- El `.csproj` tiene `<TargetFrameworkVersion>v4.x</TargetFrameworkVersion>` o `<TargetFramework>net4x</TargetFramework>`
- Hay `packages.config` (no `PackageReference`)
- Usa WebForms (`.aspx`), WCF (`.svc`), ASMX, o ASP.NET MVC 4/5
- Hay `Global.asax`, `Web.config` con secciones grandes, o `app.config` con `<system.serviceModel>`
- Depende de `System.Web.*` o `Microsoft.AspNet.*`

Si en cambio tu legacy es VB6 / VB.NET, usa los agentes `@vb-*` (ver README principal).

---

## Pre-requisitos

1. **GitHub Copilot** habilitado en tu cuenta o organización
2. **VS Code** con la extensión GitHub Copilot Chat
3. **.NET 10 SDK** instalado localmente
4. **Windows** con **PowerShell 7** (`winget install Microsoft.PowerShell`); Windows PowerShell 5.1 sirve para los scripts de cobertura
5. Acceso al código fuente del sistema legacy (no solo binarios)

---

## Setup del proyecto

```powershell
git clone https://github.com/armandoblanco/legacy-modernization-playbook.git mi-proyecto
cd mi-proyecto
Remove-Item .git -Recurse -Force; git init
```

No hay paso de configuración: los agentes `@dotnet-*` ya están listos. Si quieres, llena `.copilot-project.yml` (`project.name`, `client`); lo que falte, el agente lo pregunta. El stack target se decide en Fase 2.

Coloca el código del sistema legacy:

```powershell
New-Item -ItemType Directory legacy -Force
Copy-Item C:\ruta\al\sistema-dotnet-framework\* legacy\ -Recurse
```

Copia **todo** (código, `.config`, `.sql`, `.rpt`, scripts, etc.): el gate de cobertura exige leer cada archivo.

---

## Cobertura 100% y reglas de negocio (obligatorio en apps grandes)

Los agentes ya no "declaran" haber leído todo: lo **demuestran** con scripts (`.github/skills/legacy-coverage/scripts/`).

```powershell
pwsh .github/skills/legacy-coverage/scripts/Initialize-Ledger.ps1          # inventario de TODOS los archivos
pwsh .github/skills/legacy-coverage/scripts/Get-NextBatch.ps1 -Summary     # avance / siguiente batch
```

- `@dotnet-assessment` divide el legacy en **batches** (un subagente por batch), lee solo con `Read-LegacyChunk.ps1` (queda registro de cada línea) y cataloga cada regla de negocio en `docs/business-rules/BR-catalog.csv`.
- Si se agota el contexto: `Get-NextBatch.ps1` y `@dotnet-assessment Continúa`; el avance se conserva en `docs/inventory/`.
- La fase **no cierra** hasta que ambos gates dan exit 0:

```powershell
pwsh .github/skills/legacy-coverage/scripts/Test-Coverage.ps1 -Phase Assessment
pwsh .github/skills/legacy-coverage/scripts/Test-RuleTraceability.ps1 -Phase Assessment -Strict
```

- En Fase 3 cada regla debe tener código con su ID `BR-NNNN` y pruebas (TRX) que lo referencien. Ver [`coverage-protocol`](../.github/skills/legacy-coverage/references/coverage-protocol.md) y [`business-rules-protocol`](../.github/skills/legacy-coverage/references/business-rules-protocol.md).

---

## Flujo de 3 agentes

### Fase 1: Assessment

```text
@dotnet-assessment Analiza el sistema en legacy/
```

Detecta:

- Versión de .NET Framework actual y dependencias
- Tipo de aplicación (WebForms, WCF, MVC clásico, Windows Service, Console)
- APIs deprecadas o removidas en .NET 10+ (`System.Web.HttpContext`, `WCF service host`, `Remoting`, `AppDomain.CreateDomain`, etc.)
- Paquetes NuGet legacy y su equivalente moderno
- Configuración en `Web.config` / `app.config` que no migra 1:1
- Tests existentes y framework usado

Produce:

```
docs/
├── README.md
├── SUMMARY.md
├── dependency-graph.md
└── features/
    └── ...               (un .md por feature funcional)

docs/inventory/
├── coverage-ledger.csv   Todos los archivos legacy y su disposición
├── read-log.tsv          Registro append-only de líneas leídas
├── projects.md           Inventario de .csproj con tipo y versión
├── nuget-packages.md     Paquetes con análisis de compatibilidad .NET 10
├── deprecated-apis.md    APIs problemáticas para migración
└── config-sections.md    Secciones de Web.config / app.config

docs/business-rules/
├── BR-catalog.csv        Catálogo de reglas de negocio (BR-0001…)
└── traceability-report.md
```

### Fase 2: Planning

```text
@dotnet-planning Revisa el assessment y planifica la migración
```

Pregunta al usuario decisiones clave:

- **Target framework:** .NET 10 LTS (fijo, no se discute)
- **Tipo de proyecto target:**
  - WebForms → Blazor Server, ASP.NET Core MVC, o Razor Pages
  - WCF SOAP → CoreWCF (si SOAP no es negociable) o gRPC / REST
  - ASP.NET MVC 5 → ASP.NET Core MVC (mecánico)
  - Windows Service → Worker Service
- **Estrategia de migración:** in-place upgrade (.NET Upgrade Assistant) o greenfield
- **Manejo de dependencias bloqueantes:** librerías sin versión .NET 10 (caso por caso)
- **Hosting target:** IIS, Kestrel standalone, contenedor, Azure App Service

Produce:

```
docs/
├── ARQUITECTURA-TARGET.md
├── migration-plan.md
└── adr/
    ├── ADR-001-target-framework.md         .NET 10 LTS
    ├── ADR-002-tipo-proyecto-target.md     ASP.NET Core MVC (vs Blazor)
    ├── ADR-003-wcf-replacement.md          CoreWCF / gRPC / REST según caso
    ├── ADR-004-config-strategy.md          appsettings.json + DI Options pattern
    ├── ADR-005-orm-strategy.md             EF Core 8
    ├── ADR-006-auth-strategy.md            Migración de Forms Auth / Windows Auth a ASP.NET Core Identity
    ├── ADR-007-logging-strategy.md         Serilog / ILogger
    └── ADR-008-upgrade-vs-greenfield.md    Estrategia elegida con justificación
```

### Fase 3: Migration

```text
@dotnet-migration Ejecuta la migración del sistema legacy
```

Ejecuta:

- Si la decisión fue **in-place upgrade**: aplica `.NET Upgrade Assistant`, migra `packages.config` → `PackageReference`, actualiza target framework, refactoriza APIs deprecadas caso por caso
- Si fue **greenfield**: crea solución nueva en `src/` con estructura ASP.NET Core moderna y migra feature por feature

Genera:

```
MiProyecto.Migrated.sln
src/
├── MiProyecto.Api/                  ASP.NET Core endpoints
├── MiProyecto.Application/          Use cases + DTOs
├── MiProyecto.Domain/               Entities + Value Objects
└── MiProyecto.Infrastructure/       EF Core, External APIs
tests/
├── MiProyecto.UnitTests/
└── MiProyecto.IntegrationTests/     Con WebApplicationFactory + Testcontainers
test-results/                        TRX (evidencia de pruebas por BR-NNNN)
```

Cierra con `Test-RuleTraceability.ps1 -Phase Migration` y `Test-Coverage.ps1 -Phase Migration` (exit 0). Reporta tabla de "Done" por proyecto y feature.

---

## Casos especiales

### Sistema con mezcla WebForms + ASP.NET MVC clásico

Migración a ASP.NET Core MVC unificado. Los flujos WebForms se reescriben como controllers + Razor views o Blazor pages según ADR-002.

### Sistema con WCF expuesto a clientes externos

Tres opciones según el ADR-003:

1. **CoreWCF** si los clientes externos no pueden cambiar (contratos SOAP intactos, atado a una librería relativamente nueva pero menos mainstream)
2. **gRPC** si los clientes son internos y se pueden actualizar (mejor performance, fuerte tipado)
3. **REST + OpenAPI** si los clientes pueden adoptar HTTP/JSON (más mainstream, ecosistema amplio)

### Sistema con dependencias NuGet sin versión .NET 10

El agente las identifica en `docs/inventory/nuget-packages.md`. Por cada una, la Fase 2 genera un ADR con la decisión:

- Buscar alternativa moderna equivalente
- Mantener la versión legacy si compila contra `netstandard2.0` (compatibilidad)
- Reescribir la funcionalidad internamente si no hay alternativa viable

### Web.config con custom config sections

El agente migra las secciones estándar a `appsettings.json`. Las custom sections (`ConfigurationSection` clases) se reescriben como `IOptions<T>` con el pattern moderno.

---

## Documentación complementaria

- **Tecnología:** [`docs/technologies/dotnet-framework/README.md`](technologies/dotnet-framework/README.md)
- **Convenciones de código:** [`.github/instructions/dotnet-csharp-modern.instructions.md`](../.github/instructions/dotnet-csharp-modern.instructions.md)
- **Prompts adicionales:** [`.github/prompts/dotnet-*`](../.github/prompts/) (`/dotnet-analizar-proyecto`, `/dotnet-migrar-proyecto`, …)
