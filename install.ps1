<#
.SYNOPSIS
    dev-shell installer for PowerShell.
.EXAMPLE
    ./install.ps1
.EXAMPLE
    ./install.ps1 -DevRoot C:\code -WslDistro Ubuntu -WslRoot /home/you/dev
.NOTES
    Adds a block to your $PROFILE. Re-running is safe; it will not duplicate.
#>
[CmdletBinding()]
param(
    [string]$DevRoot   = (Join-Path $HOME "dev"),
    [string]$WslDistro,
    [string]$WslRoot
)

$ErrorActionPreference = "Stop"

$repo   = Split-Path -Parent $MyInvocation.MyCommand.Path
$module = Join-Path $repo "powershell\dev-shell.ps1"
$marker = "# >>> dev-shell >>>"

if (-not (Test-Path $module)) { throw "module not found: $module" }

$profileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null }
if (-not (Test-Path $PROFILE))    { New-Item -ItemType File -Path $PROFILE | Out-Null }

Copy-Item $PROFILE "$PROFILE.dev-shell-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"

if ((Get-Content $PROFILE -Raw) -match [regex]::Escape($marker)) {
    Write-Host "dev-shell block already present in $PROFILE -- leaving it alone."
}
else {
    $lines = @("", $marker, "`$DevRoot = `"$DevRoot`"")
    if ($WslDistro) { $lines += "`$DevWslDistro = `"$WslDistro`"" }
    if ($WslRoot)   { $lines += "`$DevWslRoot = `"$WslRoot`"" }
    $lines += ". `"$module`""
    $lines += "# <<< dev-shell <<<"
    Add-Content -Path $PROFILE -Value $lines -Encoding UTF8
    Write-Host "added dev-shell block to $PROFILE"
}

Write-Host "done. Open a new PowerShell session to load it."