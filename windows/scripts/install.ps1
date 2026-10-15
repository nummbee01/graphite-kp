<#
.SYNOPSIS
  Installs the Graphite KP Windows keyboard layout. Must run elevated.

.DESCRIPTION
  1. Copies graphkp.dll into System32 (64-bit) and SysWOW64 (32-bit).
     If a copy is locked because the DLL is already loaded, the file is
     renamed aside (or the replacement is scheduled) and completed on reboot.
  2. Registers the layout under HKLM\...\Control\Keyboard Layouts.
  3. Adds it to the current user's input list so it appears in Win+Space.

.PARAMETER BuildDir
  Where build.ps1 wrote amd64\ and wow64\. Defaults to build\ next to this script.

.PARAMETER SetDefault
  Make Graphite KP the default input method for the current user.

.EXAMPLE
  .\install.ps1 -SetDefault
#>
[CmdletBinding()]
param(
    [string]$BuildDir,
    [string]$LayoutId   = 'a0020409',
    [string]$LayoutName = 'Graphite KP',
    [string]$DllName    = 'graphkp.dll',
    [switch]$SetDefault
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated yet inside a param() default, so resolve here.
if (-not $PSScriptRoot) { throw 'Run this from a file: powershell -File install.ps1' }
if (-not $BuildDir) { $BuildDir = Join-Path $PSScriptRoot 'build' }

# --- must be elevated ------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'Administrator rights are required. Right-click Install.cmd and pick "Run as administrator".'
}

Add-Type -Namespace GraphiteKP -Name Native -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
public static extern bool MoveFileEx(string lpExistingFileName, string lpNewFileName, int dwFlags);
'@
$DELAY_UNTIL_REBOOT = 0x4

function Install-Dll([string]$Src, [string]$Dst) {
    if (-not (Test-Path $Src)) { throw "missing $Src - run build.ps1 first" }

    # Fast path: plain overwrite.
    try {
        Copy-Item $Src $Dst -Force -ErrorAction Stop
        Write-Host "OK  $Dst"
        return
    } catch {
        Write-Host "    $Dst is in use, swapping..."
    }

    # Rename the loaded DLL aside, then drop the new one in place.
    $old = "$Dst.old"
    try {
        if (Test-Path $old) { Remove-Item $old -Force -ErrorAction Stop }
        Rename-Item -LiteralPath $Dst -NewName (Split-Path $old -Leaf) -ErrorAction Stop
        Copy-Item $Src $Dst -Force -ErrorAction Stop
        [void][GraphiteKP.Native]::MoveFileEx($old, $null, $DELAY_UNTIL_REBOOT)
        Write-Host "OK  $Dst  (old file queued for deletion on reboot)"
        return
    } catch {
        # Last resort: stage the file and let the session manager move it at boot.
        $staged = "$Dst.new"
        Copy-Item $Src $staged -Force -ErrorAction Stop
        [void][GraphiteKP.Native]::MoveFileEx($Dst,   $null,   $DELAY_UNTIL_REBOOT)
        [void][GraphiteKP.Native]::MoveFileEx($staged, $Dst,   $DELAY_UNTIL_REBOOT)
        Write-Host "OK  $Dst  (replacement queued for reboot)"
    }
}

Install-Dll (Join-Path $BuildDir "amd64\$DllName") (Join-Path $env:SystemRoot "System32\$DllName")
Install-Dll (Join-Path $BuildDir "wow64\$DllName") (Join-Path $env:SystemRoot "SysWOW64\$DllName")

# --- register the layout ---------------------------------------------------
$key = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\$LayoutId"
New-Item -Path $key -Force | Out-Null
New-ItemProperty -Path $key -Name 'Layout Text'         -Value $LayoutName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name 'Layout File'         -Value $DllName    -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name 'Layout Display Name' -Value "@%SystemRoot%\system32\$DllName,-1000" -PropertyType String -Force | Out-Null
Write-Host "OK  registered $LayoutId  ($LayoutName)"

# --- add to this user's input list ----------------------------------------
$tip  = "0409:$LayoutId"
$list = Get-WinUserLanguageList
if ($list[0].InputMethodTips -contains $tip) {
    Write-Host "OK  $tip already in the input list"
} else {
    $list[0].InputMethodTips.Add($tip)
    Set-WinUserLanguageList -LanguageList $list -Force
    Write-Host "OK  added $tip to the input list"
}

if ($SetDefault) {
    $list = Get-WinUserLanguageList
    $list[0].InputMethodTips = @($tip) + ($list[0].InputMethodTips | Where-Object { $_ -ne $tip })
    Set-WinUserLanguageList -LanguageList $list -Force
    Write-Host "OK  set $tip as the default input method"
}

Write-Host ''
Write-Host 'Installed. Sign out and back in (or reboot) to activate the layout.'
Write-Host 'Switch layouts with Win+Space.'
