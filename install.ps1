<#
.SYNOPSIS
    dev-shell installer for PowerShell.
.DESCRIPTION
    Writes a dev-shell block to your $PROFILE. Run it with no arguments and it
    asks where your projects live and, where WSL is present, which distro and
    path inside it -Code should open. Re-running replaces the block, so this
    is also how you change the settings later. Without a terminal to ask on
    (-NonInteractive, redirected input, CI) -DevRoot must be given.
.EXAMPLE
    ./install.ps1
.EXAMPLE
    ./install.ps1 -DevRoot C:\code
.EXAMPLE
    ./install.ps1 -DevRoot $HOME\dev -WslDistro Ubuntu -WslRoot /home/you/dev
#>
[CmdletBinding()]
param(
    [string]$DevRoot,
    [string]$WslDistro,
    [string]$WslRoot
)

$ErrorActionPreference = "Stop"

$repo   = Split-Path -Parent $MyInvocation.MyCommand.Path
$module = Join-Path $repo "powershell\dev-shell.ps1"
$start  = "# >>> dev-shell >>>"
$end    = "# <<< dev-shell <<<"

if (-not (Test-Path $module)) { throw "module not found: $module" }

# Read-Host has no default, so show it in brackets and take Enter as "keep it".
# Returns $null when there is no terminal to ask on (redirected input, or
# -NonInteractive, where Read-Host throws).
function Read-Answer([string]$Prompt, [string]$Default) {
    if ([Console]::IsInputRedirected) { return $null }
    $shown = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    try { $answer = Read-Host $shown } catch { return $null }
    if ($answer) { return $answer.Trim() }
    return $Default
}

# Projects directory: -DevRoot wins; otherwise ask, offering the current
# setting (a profile that already loaded dev-shell sets $DevRoot globally) or
# ~\dev as the default. With no terminal to ask on, insist on being told.
if (-not $PSBoundParameters.ContainsKey('DevRoot')) {
    $default = if ($global:DevRoot) { $global:DevRoot } else { Join-Path $HOME "dev" }
    # Loop on an untyped local: $DevRoot is a [string] parameter, so assigning
    # $null to it would silently become "" and hide the no-terminal case.
    while ($true) {
        $answer = Read-Answer "Projects directory" $default
        if ($null -eq $answer) {
            throw "no terminal to ask on. Pass the projects directory: ./install.ps1 -DevRoot C:\path\to\projects"
        }
        $answer = $answer -replace '^~', $HOME
        if ([System.IO.Path]::IsPathRooted($answer)) { break }
        Write-Host "  please give a full path (or ~\...)"
    }
    $DevRoot = $answer
}
if (-not $DevRoot) { throw "-DevRoot must not be empty" }
if (-not (Test-Path $DevRoot)) { Write-Host "note: $DevRoot does not exist yet -- dev will say so until it does." }

# WSL remote for -Code: only meaningful where wsl.exe exists. -WslDistro /
# -WslRoot win; otherwise ask, Enter meaning none. Both are needed for the
# remote, so a half answer is dropped rather than written.
$wslGiven = $PSBoundParameters.ContainsKey('WslDistro') -or $PSBoundParameters.ContainsKey('WslRoot')
$hasWsl   = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
if (-not $wslGiven -and $hasWsl) {
    $WslDistro = Read-Answer "WSL distro for -Code (Enter for none)" $global:DevWslDistro
    if ($WslDistro) { $WslRoot = Read-Answer "Projects directory inside $WslDistro" $global:DevWslRoot }
}
if (($WslDistro -and -not $WslRoot) -or ($WslRoot -and -not $WslDistro)) {
    Write-Host "note: -Code uses the WSL remote only when both the distro and the path inside it are set -- leaving them out."
    $WslDistro = ""
    $WslRoot   = ""
}

$profileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null }
if (-not (Test-Path $PROFILE))    { New-Item -ItemType File -Path $PROFILE | Out-Null }

Copy-Item $PROFILE "$PROFILE.dev-shell-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"

$block = @($start, "`$DevRoot = `"$DevRoot`"")
if ($WslDistro) { $block += "`$DevWslDistro = `"$WslDistro`"" }
if ($WslRoot)   { $block += "`$DevWslRoot = `"$WslRoot`"" }
$block += ". `"$module`""
$block += $end

$lines = @(Get-Content $PROFILE)
$s = [array]::IndexOf($lines, $start)
$e = [array]::IndexOf($lines, $end)
if ($s -ge 0) {
    if ($e -lt $s) { throw "$PROFILE has '$start' but no '$end' after it; fix the block by hand" }
    # Swap the old block for the new one in place, so re-running changes settings.
    $before = @($lines | Select-Object -First $s)
    $after  = @($lines | Select-Object -Skip ($e + 1))
    Set-Content -Path $PROFILE -Value ($before + $block + $after) -Encoding UTF8
    Write-Host "updated dev-shell block in $PROFILE"
}
else {
    Add-Content -Path $PROFILE -Value (@("") + $block) -Encoding UTF8
    Write-Host "added dev-shell block to $PROFILE"
}

Write-Host "done -- dev will use $DevRoot. Open a new PowerShell session to load it."
