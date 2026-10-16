# Protocolo de reglas de negocio (trazabilidad end-to-end)

> Complementa `coverage-protocol.md`. Cobertura de líneas ≠ reglas migradas: aquí se garantiza lo segundo.

## 1. Principio

Una regla de negocio **no existe** hasta que tiene un ID (`BR-0001`), una evidencia `archivo:líneas` leída con
`Read-LegacyChunk.ps1`, y —en migración— un destino en código y **pruebas con ese ID que pasan**.
El gate `Test-RuleTraceability.ps1` verifica todo esto de forma mecánica.

## 2. Catálogo

`docs/business-rules/BR-catalog.csv` (se modifica **solo** con `Add-BusinessRule.ps1` / `Update-BusinessRule.ps1`).

| Columna | Valores |
|---|---|
| `Id` | `BR-0001`… (asignado por el script) |
| `Feature` | nombre del feature (existe `docs/features/<feature>.md`) |
| `Title` / `Rule` | título y enunciado **con valores concretos** (umbral, tasa, redondeo, mensaje, orden) |
| `Type` | `Explicit` (código claro), `Implicit` (efecto de un framework/orden/valor por defecto), `Data` (constraint, trigger, SP), `Config`, `UI` (validación en formulario/aspx), `Security`, `Calculation`, `Integration`, `Workflow` |
| `Criticality` | `Critical` (dinero, legal, seguridad), `High`, `Medium`, `Low` |
| `Source` | `ruta:inicio-fin;ruta:inicio-fin` (todas las líneas deben haberse leído) |
| `Status` | `Identified → Planned → Implemented → Verified`; `DeviationApproved` / `Retired` solo con ADR + aprobador humano |
| `Target` / `Tests` | archivos destino y de tests (separados por `;`) |
| `Deviation` | referencia ADR y persona que aprobó el cambio de comportamiento |

## 3. Dónde buscar reglas (no solo `if`)

El assessment debe revisar activamente estas fuentes; el escáner determinista las marca como candidatas:

1. Condicionales con literales, `Select Case` / `switch`, comparaciones de strings (estados, códigos, tipos).
2. Cálculos: tasas, impuestos, descuentos, **redondeo** (`Math.Round`, `Round`, `CDec`, `CCur`), fechas y calendarios.
3. Validaciones: DataAnnotations, validators ASP.NET, `Like`, expresiones regulares, mensajes de `MsgBox`/`MessageBox`/excepciones.
4. Reglas **implícitas**: valores por defecto, orden de ejecución, `On Error Resume Next` (errores silenciados), conversiones implícitas de tipo VB, comparación de strings insensible a mayúsculas (`Option Compare`), `DateTime.Now`, zona horaria, cultura.
5. Base de datos: stored procedures, triggers, constraints, vistas, `CASE WHEN`, `RAISERROR`.
6. Seguridad/autorización: roles, `IsInRole`, `Authorize`, permisos por pantalla/botón.
7. Configuración: `appSettings`, tablas de parámetros, registro de Windows, archivos `.ini`.
8. UI: habilitar/deshabilitar controles, campos obligatorios, máscaras, orden de tabulación con lógica.
9. Integraciones: formatos de archivo, reintentos, timeouts, códigos de respuesta, mapeos.
10. Lo que **no** está en el repo → `docs/inventory/external-logic.md` y, si afecta, una BR con `Source` del llamador.

## 4. Candidatos deterministas

```powershell
pwsh .github/skills/legacy-coverage/scripts/Find-RuleCandidates.ps1      # -> docs/business-rules/rule-candidates.csv
```

`Test-RuleTraceability.ps1` exige que:

- todo archivo con candidatos tenga ≥ 1 BR cuyo `Source` lo incluya, o esté en
  `docs/business-rules/no-rule-files.csv` (`Path,Reason`);
- las líneas candidatas fuera de toda BR estén en `docs/business-rules/dismissed-candidates.csv`
  (`Path,Lines,Reason`). Son **aviso** por defecto y **error** con `-Strict` (recomendado antes del checkpoint HITL).

## 5. Convención en el código y en los tests

```csharp
/// <summary>BR-0001: descuento 15% si el total supera 1000 (legacy/Billing/Invoice.cs:120-134)</summary>
public decimal ApplyVolumeDiscount(decimal total) { ... }
```

```csharp
[Fact(DisplayName = "BR-0001 descuento 15% sobre 1000")]
public void BR_0001_Discount_Applies_Over_Threshold() { ... }

[Theory(DisplayName = "BR-0001 borde del umbral")]
[InlineData(1000, 0)] [InlineData(1000.01, 150.0015)]
public void BR_0001_Threshold_Boundary(decimal total, decimal expected) { ... }
```

El ID debe aparecer en: el doc del feature, el código destino y los tests. Las pruebas de `Critical` requieren
**≥ 2** casos (típico + borde); el resto ≥ 1. Cuando sea posible, el valor esperado proviene de **caracterización
del legacy** (ejecutar el código viejo con la misma entrada), no de la intuición del modelo.

## 6. Gate de migración

```powershell
dotnet test --logger trx --results-directory test-results
pwsh .github/skills/legacy-coverage/scripts/Test-RuleTraceability.ps1 -Phase Migration
pwsh .github/skills/legacy-coverage/scripts/Test-Coverage.ps1 -Phase Migration
```

Falla si: una BR sigue `Identified`/`Planned`; su `Target` no existe o no contiene el ID; faltan tests o no
llevan el ID; el TRX no muestra suficientes pruebas **aprobadas** con ese ID; hay alguna **fallida**.
Genera `docs/business-rules/traceability-report.md` (matriz legacy → destino → tests → resultado).

## 7. Cambios de comportamiento

Si el negocio decide cambiar una regla (bug conocido, norma nueva), no se "corrige en silencio": se registra
`Update-BusinessRule.ps1 -Id BR-xxxx -Status DeviationApproved -Deviation 'ADR-00NN; aprobado por <persona>'`.
