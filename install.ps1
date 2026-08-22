<#
.SYNOPSIS
    dev-shell installer for PowerShell.
.DESCRIPTION
    Writes a dev-shell block to your $PROFILE. Run it with no arguments and it
    asks where your projects live, where WSL is present which distro and path
    inside it -Code should open, and whether to customize the look -- with a
    preview on sample projects. Re-running replaces the block, so this is also
    how you change the settings later; every question defaults to the current
    setting. Without a terminal to ask on (-NonInteractive, redirected input,
    CI) -DevRoot must be given unless a block already has it, and the look
    keeps its current values. Anything given as a parameter is not asked for.
.PARAMETER DevRoot
    Projects directory.
.PARAMETER WslDistro
    WSL distro -Code should open projects in (together with -WslRoot).
.PARAMETER WslRoot
    Projects directory inside that distro.
.PARAMETER ShellUx
    $true or $false: PSReadLine styling (menu, colours, predictions).
.PARAMETER ContinuationPrompt
    Continuation prompt (default: two chevrons and a space).
.PARAMETER Accent
    256-colour index for the selected item (default: 214).
.PARAMETER Uninstall
    Remove the block again (the profile is backed up first).
.EXAMPLE
    ./install.ps1
.EXAMPLE
    ./install.ps1 -Uninstall
.EXAMPLE
    ./install.ps1 -DevRoot C:\code -Accent 39
.EXAMPLE
    ./install.ps1 -DevRoot $HOME\dev -WslDistro Ubuntu -WslRoot /home/you/dev
#>
[CmdletBinding()]
param(
    [string]$DevRoot,
    [string]$WslDistro,
    [string]$WslRoot,
    [bool]$ShellUx,
    [string]$ContinuationPrompt,
    [ValidateRange(0, 255)][int]$Accent,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$repo   = Split-Path -Parent $MyInvocation.MyCommand.Path
$module = Join-Path $repo "powershell\dev-shell.ps1"
$start  = "# >>> dev-shell >>>"
$end    = "# <<< dev-shell <<<"
$esc    = [char]27
$defaultContinuation = [string][char]0x276F * 2 + " "   # the chevrons, kept out of this ASCII file

if (-not (Test-Path $module)) { throw "module not found: $module" }

# Read-Host has no default, so show it in brackets and take Enter as "keep it".
# Returns $null when there is no terminal to ask on (redirected input, or
# -NonInteractive, where Read-Host throws).
function Read-Answer([string]$Prompt, [string]$Default) {
    if ([Console]::IsInputRedirected) { return $null }
    $shown = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    try { $answer = Read-Host $shown } catch { return $null }
    if ($answer) { return $answer }
    return $Default
}

# y/n with a default; $null when there is no terminal to ask on.
function Read-YesNo([string]$Prompt, [bool]$Default) {
    $hint = if ($Default) { "Y/n" } else { "y/N" }
    while ($true) {
        $answer = Read-Answer "$Prompt [$hint]" ""
        if ($null -eq $answer) { return $null }
        $answer = $answer.Trim()
        if ($answer -eq "") { return $Default }
        if ($answer -match '^(y|yes)$') { return $true }
        if ($answer -match '^(n|no)$') { return $false }
        Write-Host "  please answer y or n"
    }
}

# The value a variable is assigned in the existing block, read off the parsed
# syntax tree rather than by running the profile. $null when absent.
function Get-BlockSetting([string[]]$BlockLines, [string]$Name) {
    if (-not $BlockLines) { return $null }
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(($BlockLines -join "`n"), [ref]$tokens, [ref]$errors)
    $assignment = $ast.Find({ param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.Left.VariablePath.UserPath -eq $Name }.GetNewClosure(), $false)
    if (-not $assignment) { return $null }
    $rhs = $assignment.Right
    if ($rhs -is [System.Management.Automation.Language.PipelineAst]) { $rhs = $rhs.GetPureExpression() }
    elseif ($rhs -is [System.Management.Automation.Language.CommandExpressionAst]) { $rhs = $rhs.Expression }
    try { return $rhs.SafeGetValue() } catch { return $null }
}

# Double-quote a value for the block (PowerShell double-quote escaping).
function Format-Quoted([string]$Value) { '"' + ($Value -replace '([`"$])', '`$1') + '"' }

# How the menu, predictions and continuation prompt will look with the given
# settings, on sample projects, so the choice can be made by eye.
function Show-Preview([bool]$Ux, [int]$AccentIndex, [string]$Continuation) {
    $off = "${esc}[0m"; $sel = "${esc}[1;38;5;${AccentIndex}m"; $dim = "${esc}[38;5;244m"
    Write-Host ""
    if (-not $Ux) {
        Write-Host "  (styling off: plain Tab cycling, default colours, no predictions)"
        Write-Host "  > dev api"
        Write-Host ""
        return
    }
    Write-Host "  > dev <Tab>"
    Write-Host "  api        ${sel}website${off}    notes                  <- selected item, in the accent"
    Write-Host "  on feat/dark-mode                                <- its branch, as the tooltip"
    Write-Host ""
    Write-Host "  > dev web"
    Write-Host "  ${sel}> dev website -Code${off}                             <- selected prediction"
    Write-Host "  ${dim}  dev website${off}"
    Write-Host "  > echo `"multi"
    Write-Host "  ${Continuation}line`"                                      <- continuation prompt"
    Write-Host ""
}

# The existing block, if any, supplies the defaults. A start marker without an
# end marker is left for a human rather than guessed at.
$lines = @()
if (Test-Path $PROFILE) { $lines = @(Get-Content $PROFILE) }
$s = [array]::IndexOf($lines, $start)
$e = [array]::IndexOf($lines, $end)
if ($s -ge 0 -and $e -lt $s) {
    throw "$PROFILE has '$start' but no '$end' after it. Remove or fix the block by hand: delete from '$start' down to the line that dot-sources dev-shell.ps1, or restore a $PROFILE.dev-shell-backup-* file."
}
$blockLines = if ($s -ge 0) { $lines[$s..$e] } else { @() }

if ($Uninstall) {
    if ($s -lt 0) { Write-Host "no dev-shell block in $PROFILE -- nothing to remove."; return }
    Copy-Item $PROFILE "$PROFILE.dev-shell-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    # Drop the block and the blank line the installer put above it; keep
    # everything else as it was.
    $before = @($lines | Select-Object -First $s)
    if ($before.Count -gt 0 -and $before[-1] -eq "") { $before = @($before | Select-Object -First ($before.Count - 1)) }
    $after = @($lines | Select-Object -Skip ($e + 1))
    $rest = @($before + $after)
    if ($rest.Count) { Set-Content -Path $PROFILE -Value $rest -Encoding UTF8 } else { Clear-Content -Path $PROFILE }
    Write-Host "removed the dev-shell block from $PROFILE (backup beside it). Open a new PowerShell session."
    return
}

# Projects directory: -DevRoot wins; otherwise ask, defaulting to the current
# setting (block, then a profile that already loaded dev-shell, then ~\dev).
# With no terminal to ask on, take the block or insist on being told.
$curRoot = Get-BlockSetting $blockLines 'DevRoot'
if (-not $PSBoundParameters.ContainsKey('DevRoot')) {
    $default = if ($curRoot) { $curRoot } elseif ($global:DevRoot) { $global:DevRoot } else { Join-Path $HOME "dev" }
    # Loop on an untyped local: $DevRoot is a [string] parameter, so assigning
    # $null to it would silently become "" and hide the no-terminal case.
    while ($true) {
        $answer = Read-Answer "Projects directory" $default
        if ($null -eq $answer) {
            if ($curRoot) { $answer = $curRoot; break }
            throw "no terminal to ask on. Pass the projects directory: ./install.ps1 -DevRoot C:\path\to\projects"
        }
        $answer = $answer.Trim() -replace '^~', $HOME
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
    $curDistro = Get-BlockSetting $blockLines 'DevWslDistro'
    $curWslRoot = Get-BlockSetting $blockLines 'DevWslRoot'
    $distroDefault = if ($curDistro) { $curDistro } else { $global:DevWslDistro }
    $wslRootDefault = if ($curWslRoot) { $curWslRoot } else { $global:DevWslRoot }
    $WslDistro = (Read-Answer "WSL distro for -Code (Enter for none)" $distroDefault) -replace '^\s+|\s+$', ''
    if ($WslDistro) { $WslRoot = (Read-Answer "Projects directory inside $WslDistro" $wslRootDefault) -replace '^\s+|\s+$', '' }
}
if (($WslDistro -and -not $WslRoot) -or ($WslRoot -and -not $WslDistro)) {
    Write-Host "note: -Code uses the WSL remote only when both the distro and the path inside it are set -- leaving them out."
    $WslDistro = ""
    $WslRoot   = ""
}

# The look: current settings, then a gated round of questions (skipped when
# any look parameter was given), then the parameters on top.
$curUx     = Get-BlockSetting $blockLines 'DevShellUx'
$curCont   = Get-BlockSetting $blockLines 'DevContinuationPrompt'
$curAccent = Get-BlockSetting $blockLines 'DevAccent'
$ux     = if ($null -ne $curUx)     { [bool]$curUx }      else { $true }
$cont   = if ($null -ne $curCont)   { [string]$curCont }  else { $defaultContinuation }
# Named apart from the -Accent parameter: variable names are case-insensitive.
$accentIndex = if ($null -ne $curAccent) { [int]$curAccent } else { 214 }
$lookGiven = @('ShellUx', 'ContinuationPrompt', 'Accent') | Where-Object { $PSBoundParameters.ContainsKey($_) }
if (-not $lookGiven -and -not [Console]::IsInputRedirected) {
    Write-Host "This is how it looks now:"
    Show-Preview $ux $accentIndex $cont
    if (Read-YesNo "Customize the look (styling, continuation prompt, accent colour)?" $false) {
        while ($true) {
            $ux = Read-YesNo "PSReadLine styling (menu, colours, predictions) on?" $ux
            if ($ux) {
                $cont = Read-Answer "Continuation prompt" $cont
                while ($true) {
                    $answer = (Read-Answer "Accent colour, 0-255" $accentIndex).Trim()
                    if ($answer -match '^\d+$' -and [int]$answer -le 255) { $accentIndex = [int]$answer; break }
                    Write-Host "  please give a number 0-255"
                }
            }
            Write-Host "With those settings:"
            Show-Preview $ux $accentIndex $cont
            if (Read-YesNo "Keep these?" $true) { break }
        }
    }
}
if ($PSBoundParameters.ContainsKey('ShellUx'))            { $ux = $ShellUx }
if ($PSBoundParameters.ContainsKey('ContinuationPrompt')) { $cont = $ContinuationPrompt }
if ($PSBoundParameters.ContainsKey('Accent'))             { $accentIndex = $Accent }

$profileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null }
if (-not (Test-Path $PROFILE))    { New-Item -ItemType File -Path $PROFILE | Out-Null }

Copy-Item $PROFILE "$PROFILE.dev-shell-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"

$uxLiteral = if ($ux) { '$true' } else { '$false' }
$block = @($start, "`$DevRoot = $(Format-Quoted $DevRoot)")
if ($WslDistro) { $block += "`$DevWslDistro = $(Format-Quoted $WslDistro)" }
if ($WslRoot)   { $block += "`$DevWslRoot = $(Format-Quoted $WslRoot)" }
$block += "`$DevShellUx = $uxLiteral"
$block += "`$DevContinuationPrompt = $(Format-Quoted $cont)"
$block += "`$DevAccent = $accentIndex"
$block += ". $(Format-Quoted $module)"
$block += $end

if ($s -ge 0) {
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
