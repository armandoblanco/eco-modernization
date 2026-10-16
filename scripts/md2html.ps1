<#
.SYNOPSIS
  Convierte Markdown a HTML autocontenido (CSS embebido, abre offline).

.DESCRIPTION
  Usa ConvertFrom-Markdown (PowerShell 7+) o pandoc si esta disponible.
  Instalar PowerShell 7 en Windows: winget install Microsoft.PowerShell

.EXAMPLE
  pwsh scripts/md2html.ps1 assessment/MiProyecto/seguridad-08052026.md
.EXAMPLE
  pwsh scripts/md2html.ps1 -Path docs/features -Recurse
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Path,
    [switch]$Recurse
)
$ErrorActionPreference = 'Stop'

$css = @'
:root { color-scheme: light dark; }
body { font-family: "Segoe UI", -apple-system, Roboto, Arial, sans-serif; max-width: 920px; margin: 2rem auto; padding: 0 1.25rem; line-height: 1.55; color: #1f2328; background: #fff; }
@media (prefers-color-scheme: dark) { body { color: #e6edf3; background: #0d1117; } a { color: #58a6ff; } table, th, td { border-color: #30363d !important; } pre, code { background: #161b22 !important; color: #e6edf3 !important; } th { background: #161b22 !important; } }
h1,h2,h3,h4 { line-height: 1.25; margin-top: 1.6em; }
h1, h2 { border-bottom: 1px solid #d0d7de; padding-bottom: .25em; }
code { font-family: Consolas, ui-monospace, Menlo, monospace; background: #f6f8fa; padding: .15em .35em; border-radius: 4px; font-size: 90%; }
pre { background: #f6f8fa; padding: 1em; overflow: auto; border-radius: 6px; }
pre code { background: transparent; padding: 0; }
table { border-collapse: collapse; width: 100%; margin: 1em 0; }
th, td { border: 1px solid #d0d7de; padding: .45em .7em; text-align: left; vertical-align: top; }
th { background: #f6f8fa; }
blockquote { color: #57606a; border-left: .25em solid #d0d7de; padding: 0 1em; margin: 0 0 1em; }
img { max-width: 100%; }
.meta { font-size: .85em; color: #57606a; margin-bottom: 1.5em; }
'@

function Convert-One([string]$File) {
    $md = [IO.File]::ReadAllText($File)
    $body = $null
    if (Get-Command ConvertFrom-Markdown -ErrorAction SilentlyContinue) {
        $body = (ConvertFrom-Markdown -LiteralPath $File).Html
    } elseif (Get-Command pandoc -ErrorAction SilentlyContinue) {
        $body = ($md | & pandoc -f gfm -t html) -join "`n"
    } else {
        throw 'Se requiere PowerShell 7+ (winget install Microsoft.PowerShell) o pandoc (winget install JohnMacFarlane.Pandoc).'
    }
    $title = [System.Net.WebUtility]::HtmlEncode([IO.Path]::GetFileNameWithoutExtension($File))
    $html = "<!doctype html>`n<html lang=`"es`"><head>`n<meta charset=`"utf-8`">`n<meta name=`"viewport`" content=`"width=device-width, initial-scale=1`">`n<title>$title</title>`n<style>$css</style>`n</head><body>`n<div class=`"meta`">Generado offline.</div>`n$body`n</body></html>`n"
    $out = [IO.Path]::ChangeExtension($File, '.html')
    [IO.File]::WriteAllText($out, $html, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[ok] $out"
}

if (Test-Path $Path -PathType Container) {
    Get-ChildItem -Path $Path -Filter *.md -File -Recurse:$Recurse | ForEach-Object { Convert-One $_.FullName }
} elseif (Test-Path $Path -PathType Leaf) {
    Convert-One (Resolve-Path $Path).Path
} else {
    throw "No existe: $Path"
}
