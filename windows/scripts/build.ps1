<#
.SYNOPSIS
  Builds the Graphite KP Windows keyboard layout DLL with kbdutool (MSKLC).

.DESCRIPTION
  Produces an amd64 (64-bit) and a WOW64 (32-bit) DLL, which is what Windows
  wants for a keyboard layout that works in both 64-bit and 32-bit programs.

  The .klc files are stored in this repo as plain UTF-8 so they diff and render
  normally. kbdutool only understands UTF-16LE (it crashes on UTF-8), so this
  script re-encodes the source into a scratch copy before building. Both
  encodings are accepted as input, so a file re-saved by MSKLC also works.

  The output DLL is always named graphkp.dll because that is the KBD name
  declared inside the .klc file.

.PARAMETER Klc
  Path to the .klc source. Defaults to ..\source\graphite-kp.klc.

.PARAMETER OutDir
  Directory to write amd64\ and wow64\ into. Defaults to ..\build.

.EXAMPLE
  .\build.ps1
  .\build.ps1 -Klc ..\source\graphite-kp-qwerty-shortcuts.klc
#>
[CmdletBinding()]
param(
    [string]$Klc,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated yet inside a param() default, so resolve here.
if (-not $PSScriptRoot) { throw 'Run this from a file: powershell -File build.ps1' }
$windowsRoot = Split-Path $PSScriptRoot -Parent
if (-not $Klc)    { $Klc    = Join-Path $windowsRoot 'source\graphite-kp.klc' }
if (-not $OutDir) { $OutDir = Join-Path $windowsRoot 'build' }

# --- locate kbdutool (ships with MSKLC 1.4) -------------------------------
$candidates = @(
    'C:\Program Files (x86)\Microsoft Keyboard Layout Creator 1.4\bin\i386\kbdutool.exe',
    'C:\Program Files\Microsoft Keyboard Layout Creator 1.4\bin\i386\kbdutool.exe'
)
$kbdutool = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $kbdutool) {
    throw "kbdutool.exe not found. Install 'Microsoft Keyboard Layout Creator 1.4' from https://www.microsoft.com/en-us/download/details.aspx?id=102134"
}
Write-Host "kbdutool: $kbdutool"

if (-not (Test-Path $Klc)) { throw "klc source not found: $Klc" }
$Klc = (Resolve-Path $Klc).Path

# kbdutool needs its own folder (and the amd64 subfolder) on PATH
$binDir = Split-Path $kbdutool -Parent
$env:PATH = "$binDir;$binDir\amd64;$env:PATH"

# --- stage the source as UTF-16LE -----------------------------------------
function Read-KlcText([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)   # UTF-16LE
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)     # UTF-8 w/ BOM
    }
    return [Text.Encoding]::UTF8.GetString($bytes)                               # plain UTF-8/ASCII
}

$staging = Join-Path $env:TEMP 'graphkp-src'
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null
$stagedKlc = Join-Path $staging 'graphkp.klc'
$utf16 = New-Object Text.UnicodeEncoding($false, $true)   # little-endian, with BOM
# normalise to CRLF: a checkout with core.autocrlf=false would otherwise give LF
$text = (Read-KlcText $Klc) -replace "`r`n", "`n" -replace "`n", "`r`n"
[IO.File]::WriteAllText($stagedKlc, $text, $utf16)
Write-Host "staged  : $stagedKlc (UTF-16LE)"

# --- build one DLL per architecture, each in a scratch dir -----------------
$archs = @(
    @{ Name = 'amd64'; Flag = '-m' },   # 64-bit
    @{ Name = 'wow64'; Flag = '-o' }    # 32-bit
)

foreach ($a in $archs) {
    $scratch = Join-Path $env:TEMP ("graphkp-build-" + $a.Name)
    if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
    New-Item -ItemType Directory -Path $scratch | Out-Null

    Push-Location $scratch
    try {
        # -n : no message tables   -u : Unicode layout
        & $kbdutool -n -u $a.Flag $stagedKlc
        if ($LASTEXITCODE -ne 0) { throw "kbdutool failed for $($a.Name) (exit code $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }

    $built = Join-Path $scratch 'graphkp.dll'
    if (-not (Test-Path $built)) { throw "kbdutool did not produce graphkp.dll in $scratch" }

    $target = Join-Path $OutDir $a.Name
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item $built (Join-Path $target 'graphkp.dll') -Force

    $hash = (Get-FileHash (Join-Path $target 'graphkp.dll') -Algorithm SHA256).Hash
    Write-Host ("OK  {0,-5} -> {1}  (SHA256 {2})" -f $a.Name, (Join-Path $target 'graphkp.dll'), $hash)
}

Write-Host ''
Write-Host 'Done. Next: run install.ps1 as administrator (or double-click Install.cmd).'
