<#
.SYNOPSIS
  Installs the Graphite KP Windows keyboard layout. Must run elevated.

.DESCRIPTION
  1. Copies graphkp.dll into System32 (64-bit) and SysWOW64 (32-bit).
     If a copy is locked because the DLL is already loaded, the file is
     renamed aside (or the replacement is scheduled) and completed on reboot.
  2. Registers the layout under HKLM\...\Control\Keyboard Layouts, including a
     "Layout Id", which Windows requires before it will treat the layout as a
     real input method.
  3. Adds it to the current user's input list so it appears in Win+Space.

.PARAMETER BuildDir
  Where build.ps1 wrote amd64\ and wow64\. Defaults to ..\build.

.PARAMETER SetDefault
  Make Graphite KP the default input method for the current user.

.EXAMPLE
  .\install.ps1 -SetDefault
#>
[CmdletBinding()]
param(
    [string]$BuildDir,
    [string]$LayoutId    = 'a0020409',
    [string]$LayoutName  = 'Graphite KP',
    [string]$DllName     = 'graphkp.dll',
    [string]$ComponentId = '{9761D3FD-CAC2-4640-B217-A52C870CC6CB}',
    [switch]$SetDefault
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated yet inside a param() default, so resolve here.
if (-not $PSScriptRoot) { throw 'Run this from a file: powershell -File install.ps1' }
if (-not $BuildDir) { $BuildDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'build' }

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
# "Layout Id" is what Windows uses to give the layout a real device id and a
# proper HKL (0xF0xx....). Without it the layout can only load through the
# substitute path, gets HKL 0xFFFE...., and is never adopted as an input
# method: every app silently falls back to the language default. MSKLC starts
# assigning at 00c0, so do the same and skip anything already taken.
function Get-FreeLayoutId {
    $used = @{}
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts' | ForEach-Object {
        $id = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).'Layout Id'
        if ($id) { $used[$id.ToLower()] = $true }
    }
    foreach ($i in 0x00c0..0x0fff) {
        $hex = '{0:x4}' -f $i
        if (-not $used.ContainsKey($hex)) { return $hex }
    }
    throw 'No free Layout Id available.'
}

$key = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\$LayoutId"
New-Item -Path $key -Force | Out-Null
New-ItemProperty -Path $key -Name 'Layout Text'         -Value $LayoutName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name 'Layout File'         -Value $DllName    -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name 'Layout Display Name' -Value "@%SystemRoot%\system32\$DllName,-1000" -PropertyType String -Force | Out-Null

$layoutIdValue = (Get-ItemProperty $key).'Layout Id'
if (-not $layoutIdValue) { $layoutIdValue = Get-FreeLayoutId }
New-ItemProperty -Path $key -Name 'Layout Id'           -Value $layoutIdValue -PropertyType String -Force | Out-Null
New-ItemProperty -Path $key -Name 'Layout Component ID' -Value $ComponentId    -PropertyType String -Force | Out-Null
Write-Host "OK  registered $LayoutId  ($LayoutName, Layout Id $layoutIdValue)"

# --- add to this user's input list ----------------------------------------
$tip  = "0409:$LayoutId"
$list = Get-WinUserLanguageList
if ($list[0].InputMethodTips -notcontains $tip) {
    $list[0].InputMethodTips.Add($tip)
    Write-Host "OK  added $tip to the input list"
} else {
    Write-Host "OK  $tip already in the input list"
}
# Always re-apply: this is also what makes Windows rebuild the Preload and
# Substitutes entries, which it must do after a Layout Id is registered.
Set-WinUserLanguageList -LanguageList $list -Force

if ($SetDefault) {
    # InputMethodTips is read only, so reorder by clearing and re-adding.
    $list = Get-WinUserLanguageList
    $tips = @($tip) + @($list[0].InputMethodTips | Where-Object { $_ -ne $tip })
    $list[0].InputMethodTips.Clear()
    foreach ($t in $tips) { $list[0].InputMethodTips.Add($t) }
    Set-WinUserLanguageList -LanguageList $list -Force
    Write-Host "OK  set $tip as the default input method"
}

Write-Host ''
Write-Host 'Installed. Sign out and back in (or reboot) to activate the layout.'
Write-Host 'Switch layouts with Win+Space.'
