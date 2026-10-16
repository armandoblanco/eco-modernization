# Ledger.psm1 - funciones compartidas por los scripts de cobertura y reglas de negocio.
# Compatible con Windows PowerShell 5.1 y PowerShell 7+.
Set-StrictMode -Version 2.0

# Raiz del repo del proyecto: primero desde el directorio actual, luego desde la ubicacion del skill.
function Find-ProjectRoot([string]$start) {
    $d = $start
    while ($d) {
        if ((Test-Path (Join-Path $d '.copilot-project.yml')) -or (Test-Path (Join-Path $d '.git'))) { return $d }
        $parent = Split-Path -Parent $d
        if ($parent -eq $d) { break }
        $d = $parent
    }
    return $null
}
$script:RepoRoot = Find-ProjectRoot (Get-Location).Path
if (-not $script:RepoRoot) { $script:RepoRoot = Find-ProjectRoot $PSScriptRoot }
if (-not $script:RepoRoot) { throw 'No se encontro la raiz del proyecto (.copilot-project.yml o .git). Ejecuta desde la raiz del repo.' }
$script:LedgerRel = 'docs/inventory/coverage-ledger.csv'
$script:ReadLogRel = 'docs/inventory/read-log.tsv'
$script:LedgerColumns = @(
    'Path', 'Ext', 'Category', 'Lines', 'Bytes', 'Sha256', 'Batch',
    'Feature', 'Disposition', 'Target', 'Excluded', 'ExclusionReason', 'ApprovedBy', 'Notes'
)
$script:BinaryExt = @(
    '.dll', '.exe', '.ocx', '.pdb', '.png', '.jpg', '.jpeg', '.gif', '.ico', '.bmp', '.frx', '.res', '.rpt',
    '.mdb', '.accdb', '.zip', '.nupkg', '.snk', '.pfx', '.cab', '.msi', '.bin', '.doc', '.docx', '.xls',
    '.xlsx', '.ppt', '.pptx', '.pdf', '.ttf', '.woff', '.woff2', '.eot', '.cur', '.ani', '.tlb', '.lib',
    '.obj', '.cache', '.suo', '.ctx', '.dsx', '.mdf', '.ldf', '.bak', '.7z', '.rar', '.gz', '.tif', '.tiff',
    '.wav', '.mp3', '.mp4', '.avi', '.swf', '.p12', '.cer', '.der', '.vsd', '.vsdx'
)
$script:SkipDirs = @('.git', 'bin', 'obj', 'packages', '.vs', 'node_modules', 'TestResults', '_ReSharper.Caches', '.svn')
$script:MaxLineChars = 5000

function Get-RepoRoot { $script:RepoRoot }

function Get-LedgerPath { Join-Path $script:RepoRoot $script:LedgerRel }
function Get-ReadLogPath { Join-Path $script:RepoRoot $script:ReadLogRel }
function Get-LedgerColumns { $script:LedgerColumns }
function Get-SkipDirs { $script:SkipDirs }
function Get-MaxLineChars { $script:MaxLineChars }

function ConvertTo-RelPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = if ([IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $script:RepoRoot $Path }
    $full = [IO.Path]::GetFullPath($full)
    $root = $script:RepoRoot.TrimEnd('\', '/')
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        $full = $full.Substring($root.Length).TrimStart('\', '/')
    }
    return ($full -replace '\\', '/')
}

function ConvertTo-FullPath {
    param([Parameter(Mandatory)][string]$RelPath)
    [IO.Path]::GetFullPath((Join-Path $script:RepoRoot ($RelPath -replace '/', [IO.Path]::DirectorySeparatorChar)))
}

function Test-IsBinaryFile {
    param([Parameter(Mandatory)][string]$FullPath)
    $ext = [IO.Path]::GetExtension($FullPath).ToLowerInvariant()
    if ($script:BinaryExt -contains $ext) { return $true }
    $fs = [IO.File]::Open($FullPath, 'Open', 'Read', 'ReadWrite')
    try {
        $buf = New-Object byte[] 8000
        $n = $fs.Read($buf, 0, $buf.Length)
        for ($i = 0; $i -lt $n; $i++) { if ($buf[$i] -eq 0) { return $true } }
    } finally { $fs.Dispose() }
    return $false
}

function Get-TextLines {
    # Devuelve las lineas del archivo con la misma regla en TODOS los scripts:
    # separadores CRLF / LF / CR; un salto final no genera una linea extra.
    param([Parameter(Mandatory)][string]$FullPath)
    $bytes = [IO.File]::ReadAllBytes($FullPath)
    if ($bytes.Length -eq 0) { return , @() }
    $text = $null
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        $text = $utf8.GetString($bytes)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    } catch {
        try { [Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance) } catch { }
        $text = [Text.Encoding]::GetEncoding(1252).GetString($bytes)
    }
    $parts = [regex]::Split($text, "\r\n|\n|\r")
    if ($parts.Length -gt 0 -and $parts[$parts.Length - 1] -eq '') {
        $parts = $parts[0..($parts.Length - 2)]
    }
    return , @($parts)
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$FullPath)
    $sha = [Security.Cryptography.SHA256]::Create()
    $fs = [IO.File]::Open($FullPath, 'Open', 'Read', 'ReadWrite')
    try { ([BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLowerInvariant() }
    finally { $fs.Dispose(); $sha.Dispose() }
}

function Get-FileCategory {
    param([string]$Ext, [string]$Name, [bool]$IsBinary, [bool]$IsMinified)
    if ($IsBinary) { return 'Binary' }
    if ($IsMinified) { return 'Minified' }
    $e = $Ext.ToLowerInvariant()
    if ($Name -match '\.(Designer|designer|g|g\.i)\.(cs|vb)$' -or $Name -match '^Reference\.(cs|vb)$') { return 'Generated' }
    switch -Regex ($e) {
        '^\.(cs|vb|bas|cls|frm|ctl|dsr|pag|dob|vbs|fs)$' { return 'Source' }
        '^\.(aspx|ascx|master|asax|ashx|asmx|svc|cshtml|vbhtml|razor|xaml|html|htm|js|ts|css|rdlc|rdl|tt)$' { return 'Markup' }
        '^\.(config|settings|resx|json|xml|xsd|xslt|wsdl|disco|ini|props|targets|csproj|vbproj|sln|vbp|vbg|edmx|dbml|yml|yaml)$' { return 'Config' }
        '^\.(sql|prc|trg|fnc|vw|pkb|pks)$' { return 'Data' }
        '^\.(ps1|bat|cmd|sh)$' { return 'Script' }
        default { return 'Other' }
    }
}

function ConvertFrom-RangeString {
    param([string]$Text)
    $out = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($Text)) { return , $out.ToArray() }
    foreach ($p in ($Text -split '[;,]')) {
        $p = $p.Trim()
        if ($p -match '^(\d+)\s*-\s*(\d+)$') { $out.Add(@([int]$Matches[1], [int]$Matches[2])) }
        elseif ($p -match '^(\d+)$') { $out.Add(@([int]$Matches[1], [int]$Matches[1])) }
    }
    return , $out.ToArray()
}

function Merge-Ranges {
    param($Ranges)
    $sorted = @($Ranges | Sort-Object { $_[0] }, { $_[1] })
    $merged = New-Object System.Collections.Generic.List[object]
    foreach ($r in $sorted) {
        if ($merged.Count -gt 0 -and $r[0] -le ($merged[$merged.Count - 1][1] + 1)) {
            if ($r[1] -gt $merged[$merged.Count - 1][1]) { $merged[$merged.Count - 1][1] = $r[1] }
        } else { $merged.Add(@($r[0], $r[1])) }
    }
    return , $merged.ToArray()
}

function Get-RangeCount {
    param($Ranges)
    $n = 0
    foreach ($r in $Ranges) { $n += ($r[1] - $r[0] + 1) }
    return $n
}

function Get-MissingRanges {
    param($Merged, [int]$Total)
    $miss = New-Object System.Collections.Generic.List[object]
    $cursor = 1
    foreach ($r in $Merged) {
        if ($r[0] -gt $cursor) { $miss.Add(@($cursor, ($r[0] - 1))) }
        $cursor = [Math]::Max($cursor, $r[1] + 1)
    }
    if ($cursor -le $Total) { $miss.Add(@($cursor, $Total)) }
    return , $miss.ToArray()
}

function Format-Ranges {
    param($Ranges)
    (@($Ranges | ForEach-Object { if ($_[0] -eq $_[1]) { "$($_[0])" } else { "$($_[0])-$($_[1])" } })) -join ';'
}

function Import-Ledger {
    $p = Get-LedgerPath
    if (-not (Test-Path $p)) { throw "No existe el ledger: $p. Ejecuta .github/skills/legacy-coverage/scripts/Initialize-Ledger.ps1 primero." }
    @(Import-Csv -Path $p -Encoding UTF8)
}

function Save-Ledger {
    param([Parameter(Mandatory)]$Rows)
    $p = Get-LedgerPath
    $dir = Split-Path $p -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lock = "$p.lock"
    $got = $false
    for ($i = 0; $i -lt 100 -and -not $got; $i++) {
        try { $fs = [IO.File]::Open($lock, 'CreateNew', 'Write', 'None'); $fs.Dispose(); $got = $true }
        catch {
            if ((Test-Path $lock) -and ((Get-Date) - (Get-Item $lock).LastWriteTime).TotalSeconds -gt 60) { Remove-Item $lock -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Milliseconds 200
        }
    }
    if (-not $got) { throw "No se pudo obtener el lock del ledger ($lock)." }
    try {
        $tmp = "$p.tmp"
        $Rows | Select-Object $script:LedgerColumns | Export-Csv -Path $tmp -NoTypeInformation -Encoding UTF8
        Move-Item -Path $tmp -Destination $p -Force
    } finally { Remove-Item $lock -Force -ErrorAction SilentlyContinue }
}

function Add-ReadLogEntry {
    param([string]$RelPath, [int]$Start, [int]$End, [string]$Sha256)
    $p = Get-ReadLogPath
    $dir = Split-Path $p -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $line = ("{0}`t{1}`t{2}`t{3}`t{4}`n" -f $RelPath, $Start, $End, $Sha256.Substring(0, 8), (Get-Date).ToUniversalTime().ToString('s'))
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($line)
    for ($i = 0; $i -lt 50; $i++) {
        try {
            $fs = [IO.File]::Open($p, 'Append', 'Write', 'ReadWrite')
            try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
            return
        } catch { Start-Sleep -Milliseconds 100 }
    }
    throw "No se pudo escribir en $p"
}

function Get-ReadMap {
    # Devuelve hashtable Path -> lista de rangos [start,end], ignorando lecturas hechas con otra version del archivo.
    param([hashtable]$ShaByPath)
    $map = @{}
    $p = Get-ReadLogPath
    if (-not (Test-Path $p)) { return $map }
    foreach ($line in [IO.File]::ReadLines($p)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $f = $line.Split("`t")
        if ($f.Length -lt 4) { continue }
        $path = $f[0]
        if (-not $ShaByPath.ContainsKey($path)) { continue }
        if ($ShaByPath[$path].Substring(0, 8) -ne $f[3]) { continue }
        if (-not $map.ContainsKey($path)) { $map[$path] = New-Object System.Collections.Generic.List[object] }
        $map[$path].Add(@([int]$f[1], [int]$f[2]))
    }
    return $map
}

function ConvertTo-GlobRegex {
    param([Parameter(Mandatory)][string]$Glob)
    $g = ($Glob -replace '\\', '/')
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('^')
    $i = 0
    while ($i -lt $g.Length) {
        $c = $g[$i]
        if ($c -eq '*' -and $i + 1 -lt $g.Length -and $g[$i + 1] -eq '*') { [void]$sb.Append('.*'); $i += 2; if ($i -lt $g.Length -and $g[$i] -eq '/') { $i++ } ; continue }
        if ($c -eq '*') { [void]$sb.Append('[^/]*') }
        elseif ($c -eq '?') { [void]$sb.Append('[^/]') }
        else { [void]$sb.Append([regex]::Escape([string]$c)) }
        $i++
    }
    [void]$sb.Append('$')
    return $sb.ToString()
}

function Get-FeatureDocPath {
    param([string]$Feature)
    $reserved = @{ 'cross-cutting' = 'docs/cross-cuttings/README.md'; 'build-config' = 'docs/inventory/projects.md'; 'third-party' = 'docs/inventory/packages.md' }
    if ($reserved.ContainsKey($Feature)) { return $reserved[$Feature] }
    return "docs/features/$Feature.md"
}

$script:BrColumns = @('Id', 'Feature', 'Title', 'Rule', 'Type', 'Criticality', 'Source', 'Status', 'Target', 'Tests', 'Deviation', 'Notes')
$script:BrTypes = @('Explicit', 'Implicit', 'Data', 'Config', 'UI', 'Security', 'Calculation', 'Integration', 'Workflow')
$script:BrCriticalities = @('Critical', 'High', 'Medium', 'Low')
$script:BrStatuses = @('Identified', 'Planned', 'Implemented', 'Verified', 'DeviationApproved', 'Retired')

function Get-BrCatalogPath { Join-Path $script:RepoRoot 'docs/business-rules/BR-catalog.csv' }
function Get-BrColumns { $script:BrColumns }
function Get-BrTypes { $script:BrTypes }
function Get-BrCriticalities { $script:BrCriticalities }
function Get-BrStatuses { $script:BrStatuses }

function Import-BrCatalog {
    $p = Get-BrCatalogPath
    if (-not (Test-Path $p)) { return @() }
    @(Import-Csv -Path $p -Encoding UTF8)
}

function Invoke-WithFileLock {
    param([string]$Target, [scriptblock]$Action)
    $lock = "$Target.lock"
    $got = $false
    for ($i = 0; $i -lt 100 -and -not $got; $i++) {
        try { $fs = [IO.File]::Open($lock, 'CreateNew', 'Write', 'None'); $fs.Dispose(); $got = $true }
        catch {
            if ((Test-Path $lock) -and ((Get-Date) - (Get-Item $lock).LastWriteTime).TotalSeconds -gt 60) { Remove-Item $lock -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Milliseconds 200
        }
    }
    if (-not $got) { throw "No se pudo obtener el lock ($lock)." }
    try { & $Action } finally { Remove-Item $lock -Force -ErrorAction SilentlyContinue }
}

function Save-BrCatalog {
    param([Parameter(Mandatory)]$Rows)
    $p = Get-BrCatalogPath
    $dir = Split-Path $p -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $cols = $script:BrColumns
    $tmp = "$p.tmp"
    @($Rows) | Select-Object $cols | Export-Csv -Path $tmp -NoTypeInformation -Encoding UTF8
    Move-Item -Path $tmp -Destination $p -Force
}

function Test-BrSource {
    # Valida "ruta:lineas;ruta:lineas" contra el ledger y las lecturas registradas. Devuelve lista de errores.
    param([string]$Source, $LedgerRows, [hashtable]$ReadMap)
    $errs = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Source)) { $errs.Add('Source vacio'); return , $errs.ToArray() }
    foreach ($part in ($Source -split ';(?=[^;]*:)')) {
        $part = $part.Trim()
        if ($part -notmatch '^(?<f>.+?):(?<r>[\d,\-; ]+)$') { $errs.Add("Source invalido '$part' (formato ruta:inicio-fin)"); continue }
        $f = $Matches.f -replace '\\', '/'
        $row = $LedgerRows | Where-Object { $_.Path -ieq $f } | Select-Object -First 1
        if (-not $row) { $errs.Add("Source: $f no esta en el ledger"); continue }
        $total = [int]$row.Lines
        $merged = if ($ReadMap.ContainsKey($row.Path)) { Merge-Ranges $ReadMap[$row.Path] } else { @() }
        foreach ($r in (ConvertFrom-RangeString $Matches.r)) {
            if ($r[1] -lt $r[0] -or $r[1] -gt $total) { $errs.Add("Source: rango $($r[0])-$($r[1]) fuera de $f (1..$total)"); continue }
            $need = Get-RangeCount @(, $r)
            $have = 0
            foreach ($m in $merged) { $lo = [Math]::Max($m[0], $r[0]); $hi = [Math]::Min($m[1], $r[1]); if ($hi -ge $lo) { $have += ($hi - $lo + 1) } }
            if ($have -lt $need) { $errs.Add("Source: $f lineas $($r[0])-$($r[1]) no fueron leidas con Read-LegacyChunk.ps1") }
        }
    }
    return , $errs.ToArray()
}

Export-ModuleMember -Function *
