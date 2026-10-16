---
mode: 'agent'
description: Migra un módulo VB6 específico hacia .NET 10 con compile-and-test loop entre capas, respetando los ADRs aprobados.
---

# Migrar módulo VB6

Migra el módulo VB6 `${input:modulo_nombre}` al stack target definido en `docs/ARQUITECTURA-TARGET.md`.

**Archivos VB6 a migrar:**
${input:vb6_files}

**Reglas obligatorias:**

1. **Lee primero:**
   - `docs/features/${input:modulo_nombre}.md` (reglas de negocio)
   - Las reglas BR-#### del feature: `Import-Csv docs/business-rules/BR-catalog.csv | Where-Object Feature -eq '${input:modulo_nombre}'` (tu checklist de paridad)
   - `docs/ARQUITECTURA-TARGET.md` (stack y patrones)
   - `docs/adr/*.md` (decisiones específicas)
   - El código VB6 fuente directamente

2. **Migra por capas** en este orden estricto:
   - Domain (entidades, value objects, interfaces de repositorio)
   - Application (casos de uso, DTOs, validadores)
   - Infrastructure (EF Core, repositorios, servicios externos)
   - Presentation (ViewModels + Views si WPF, Forms si WinForms)

3. **Compile-and-test entre capas:**

   ```powershell
   # Después de cada capa
   dotnet build src/App.<Capa>/App.<Capa>.csproj
   dotnet test tests/App.<Capa>.Tests/App.<Capa>.Tests.csproj
   ```

   Si falla algo, NO avanzar a la siguiente capa. Corregir.

4. **Política de warnings:**
   - **Domain y Application**: 0 warnings (build con `TreatWarningsAsErrors=true`)
   - **Infrastructure y Presentation**: solo nullable críticos (CS8600-CS8604) son blocker; otros warnings se documentan en `migration-log.md` como deuda

5. **Helpers VB6:** usar `App.Shared.Compat.VB6Functions` para `Mid`, `Left`, `Right`, `Val`. NO migrar directo a `Substring` sin tests de paridad.

6. **OCX bloqueados:** si el módulo usa un OCX Crítico/Alto sin reemplazo:
   ```csharp
   // ADR-XXX: Funcionalidad de [OCX] reemplazada por [arquitectura].
   throw new NotImplementedException(
       "Integración con [Servicio] pendiente. Ver ADR-XXX.");
   ```

7. **Tests de paridad:** después de migrar, generar tests en `tests/App.ParityTests/<Modulo>/` que validan:
   - **Cada BR-####** del feature: ≥ 2 pruebas (Critical) o ≥ 1, con el ID en el nombre (`BR_0007_...`) y en un comentario XML en el código destino
   - Trampas semánticas relevantes (ver `docs/technologies/vb/trampas-vb6.md` o `trampas-vbnet.md`)
   - Casos borde (null, vacío, máximo, mínimo)

8. **Migration log:** después del feature, agregar entrada en `migration/migration-log.md`:

   ```markdown
   ## ${input:modulo_nombre} — YYYY-MM-DD
   
   **Archivos VB6 consumidos:** [lista]
   **Archivos C# generados:** [lista por capa]
   **Tests:** [conteos]
   **ADRs creados:** [lista]
   **OCX bloqueados:** [lista]
   **Decisiones tomadas autónomamente desde código VB6:** [lista con referencias]
   **Reglas BR:** [N/N implementadas]
   **Estado:** ✅ Migrado | ⚠️ Parcial | ❌ Bloqueado
   ```

9. **Cierre de trazabilidad (obligatorio):**

   ```powershell
   pwsh .github/skills/legacy-coverage/scripts/Update-BusinessRule.ps1 -Id BR-xxxx -Status Implemented -Target <archivo.cs> -Tests <archivoTests.cs>
   pwsh .github/skills/legacy-coverage/scripts/Update-Ledger.ps1 -Path <archivo legacy> -Disposition Migrated -Target <archivo.cs>
   dotnet test --logger trx --results-directory test-results
   pwsh .github/skills/legacy-coverage/scripts/Test-RuleTraceability.ps1 -Phase Migration
   ```

   No marques el módulo ✅ si el gate falla.

**Prohibido:**

- Avanzar a siguiente capa si la anterior tiene build roto o tests fallando
- Inventar comportamientos no documentados en `.md` ni en código VB6
- Migrar `On Error Resume Next` como `try/catch` silencioso sin auditar
- Lógica de negocio en ViewModel o code-behind
- Usar `dynamic` para `Variant` automáticamente
- Generar mocks/stubs sin marcarlos explícitamente

**Cuando una ambigüedad de negocio aparece:**

1. Buscar en `.md` del feature
2. Si no está, leer código VB6 fuente
3. Si está en VB6, replicar y documentar:
   ```csharp
   // Heredado de modCalculo.bas L240-L268.
   // Fórmula: días_trabajados / 365 × salario_base.
   ```
4. Si tampoco está claro en VB6, registrar en `migration-log.md` como "ambigüedad pendiente" y elegir interpretación conservadora.

**NO** preguntar al usuario por decisiones que ya están en ADRs. **SÍ** preguntar (consolidando dudas) cuando hay contradicción real entre `.md` y código VB6 que cambia comportamiento de negocio.

**Output esperado al terminar:**

```
## Módulo ${input:modulo_nombre} migrado

✅ Domain: build limpio, X tests pasando
✅ Application: build limpio, Y tests pasando  
✅ Infrastructure: build limpio, Z warnings de deuda documentados
✅ Presentation: build limpio, vista abre correctamente
✅ ParityTests: K tests pasando

ADRs creados: [lista]
OCX bloqueados: [lista]
Ambigüedades pendientes: [lista o "ninguna"]
```
