# Protocolo de cobertura 100% (verificable)

> Aplica a **todos** los agentes de assessment y migración de .NET Framework y VB6/VB.NET.
> Plataforma: **Windows** (PowerShell 5.1+ o PowerShell 7). Los scripts viven en `.github/skills/legacy-coverage/scripts/`.

## 1. Por qué existe

En repos grandes un agente que "lee el código" por su cuenta se queda sin contexto, resume, salta archivos o
solo lee las primeras N líneas, y aun así reporta "cobertura 100%". Esa afirmación no es verificable.

**Regla de oro: la cobertura la mide un script, no el agente.** El agente solo puede leer código legacy a
través de `Read-LegacyChunk.ps1`, que deja un registro. Un gate (`Test-Coverage.ps1`) compara lo leído contra
el inventario real y rechaza el cierre de la fase si falta una sola línea.

| Falla observada | Control que la elimina |
|---|---|
| El agente omite archivos | `Initialize-Ledger.ps1` inventaría **todo** `legacy/` (sin filtrar por extensión); el gate falla si hay archivos no registrados |
| El agente lee solo el inicio de archivos largos | Lectura por tramos con número de línea; el pie indica `SIGUIENTE -Start N`; el gate exige 100% de líneas por archivo |
| Se llena el contexto y se pierde el hilo | Trabajo en **batches** (~2500 líneas) con un subagente por batch y checkpoint en disco |
| Se reanuda y se repite o se salta trabajo | `Get-NextBatch.ps1` es la cola canónica: siempre dice qué falta |
| Solo se miran `.cs` / `.vb` | Se inventarían aspx, ascx, xaml, config, resx, sql, js, rpt, `.frm/.bas/.cls/.ctl`, scripts, etc. |
| Archivos modificados a mitad de proyecto | SHA-256 por archivo; las lecturas hechas con otra versión no cuentan; `-Refresh` conserva el progreso |
| "Excluyo lo que no me interesa" | Solo se excluye con razón y **aprobador humano**; el reporte lista todas las exclusiones |

## 2. Artefactos

| Archivo | Qué es |
|---|---|
| `docs/inventory/coverage-ledger.csv` | Un registro por archivo: ruta, categoría, líneas, SHA-256, batch, feature, disposición, target, exclusión |
| `docs/inventory/read-log.tsv` | Registro **append-only** de tramos leídos (lo escribe `Read-LegacyChunk.ps1`; no editar a mano) |
| `docs/inventory/coverage-report.md` | Resultado del último `Test-Coverage.ps1` |
| `docs/inventory/external-logic.md` | Lógica que vive fuera del repo (stored procs, jobs, DLLs de terceros sin fuente, servicios externos) |

## 3. Scripts

| Script | Uso |
|---|---|
| `Initialize-Ledger.ps1 [-Refresh] [-BatchLines 2500]` | Crea/actualiza el inventario. `-Refresh` conserva feature/disposición y avisa de archivos nuevos, cambiados o eliminados |
| `Get-NextBatch.ps1 [-Batch B0003] [-Summary]` | Cola de trabajo: siguiente batch con líneas pendientes y rangos exactos |
| `Read-LegacyChunk.ps1 -Path <f> [-Next] [-Start n] [-Count 300]` | **Única** forma de leer legacy. Imprime con números de línea y registra el tramo |
| `Update-Ledger.ps1 -Path <glob> -Feature x` | Asigna feature, disposición (`Migrated`, `ReplacedByFramework`, `DeadCode`, `NotMigrated`), target o exclusión |
| `Test-Coverage.ps1 -Phase Assessment\|Migration` | Gate. Exit 0 = aprobado, 1 = rechazado. Escribe `coverage-report.md` |

Ejecutar con `pwsh` (PowerShell 7) o `powershell` (5.1): `pwsh .github/skills/legacy-coverage/scripts/Get-NextBatch.ps1`.

## 4. Flujo del assessment (orquestador + subagentes)

```text
1. Initialize-Ledger.ps1                      -> inventario y batches
2. Orquestador: Get-NextBatch.ps1             -> toma el siguiente batch pendiente
3. Subagente por batch (contexto limpio):
     por cada archivo del batch:
       Read-LegacyChunk.ps1 -Path <f> -Next   (repetir hasta "EOF: archivo completamente leido")
     documenta en docs/features/<feature>.md  (mencionando cada archivo)
     registra reglas: Add-BusinessRule.ps1    (ver business-rules-protocol.md)
     Update-Ledger.ps1 -Path <f> -Feature <x>
4. Checkpoint: el orquestador valida con Get-NextBatch.ps1 -Summary y pasa al siguiente batch
5. Al terminar: Test-Coverage.ps1 -Phase Assessment  y  Test-RuleTraceability.ps1 -Phase Assessment
6. Solo con ambos en exit 0 se presenta el checkpoint HITL al usuario
```

**Reanudar** (nueva sesión, contexto perdido): leer `docs/inventory/coverage-report.md` si existe y ejecutar
`Get-NextBatch.ps1`. No hace falta recordar nada: el estado está en disco.

### Reglas para el subagente

1. Leer **solo** con `Read-LegacyChunk.ps1`. Leer con otra herramienta (`type`, `Get-Content`, el editor) no
   cuenta como lectura y no se acepta como evidencia.
2. No resumir sin haber leído: un archivo de 3 000 líneas son ~10 llamadas de 300 líneas.
3. Citar evidencia como `archivo:línea` usando los números del script.
4. Si un archivo está marcado `Minified` (líneas > 5 000 caracteres) o es binario, **no** inventar contenido:
   pedir al usuario la decisión (exclusión aprobada o clasificación).
5. Nunca autoaprobar una exclusión (`-ApprovedBy` debe ser una persona).

## 5. Categorías y tratamiento

| Categoría | Ejemplos | Tratamiento |
|---|---|---|
| `Source` | `.cs .vb .bas .cls .frm .ctl .dsr` | Lectura 100% línea a línea |
| `Markup` | `.aspx .ascx .master .cshtml .xaml .html .js .rdlc` | Lectura 100% (aquí viven reglas de UI y validación) |
| `Config` | `.config .resx .json .xml .xsd .edmx .csproj .vbp .sln` | Lectura 100% |
| `Data` | `.sql .prc .trg` | Lectura 100% (stored procs y triggers contienen reglas) |
| `Script` | `.bat .cmd .ps1` | Lectura 100% |
| `Generated` | `*.Designer.cs`, `Reference.cs` | Lectura 100% (el script no se salta nada); documentar de forma breve |
| `Binary` | `.dll .ocx .frx .rpt .png` | No se lee; se **clasifica** (feature + disposición + nota). DLL/OCX de terceros → `external-logic.md` |
| `Minified` | JS/CSS minificado, líneas > 5 000 chars | Exclusión **aprobada por humano** o decisión de reemplazo |

## 6. Migración: disposición por archivo

En la fase de migración **todo archivo legacy** termina con una disposición explícita:

| Disposición | Significado | Requiere |
|---|---|---|
| `Migrated` | Convertido a código en `src/` | `-Target` (rutas separadas por `;`, deben existir) |
| `ReplacedByFramework` | Lo cubre .NET moderno (Identity, EF Core, HttpClient…) | `-Target` con la API/ADR |
| `DeadCode` | Sin referencias ni uso | `-Notes` con la evidencia |
| `NotMigrated` | Decisión consciente de no migrar | `-Notes` con ADR/aprobación |

`Test-Coverage.ps1 -Phase Migration` falla con cualquier `Pending` o target inexistente.

## 7. Límites conocidos (honestidad)

- Los scripts garantizan que **cada línea pasó por `Read-LegacyChunk`**, no que el modelo la **comprendió**.
  La comprensión se verifica con el protocolo de reglas de negocio (BR-IDs, tests por regla) y con revisión humana.
- Lógica fuera del repositorio (BD en producción, jobs, servicios) no se ve: debe declararse en `external-logic.md`.
- Las carpetas `bin/obj/packages/.vs/node_modules` se omiten por defecto (se informa cuántas). Usa
  `Initialize-Ledger.ps1 -IncludeBuildDirs` si tu legacy guarda código real en alguna de ellas.
