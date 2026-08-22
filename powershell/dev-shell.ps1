# dev-shell — project navigation and PSReadLine polish for PowerShell.
#
# Dot-source this from your $PROFILE:
#     . C:\path\to\dev-shell\powershell\dev-shell.ps1
#
# Optional configuration, set BEFORE dot-sourcing:
#   $DevRoot      projects directory              (default: $HOME\dev)
#   $DevWslDistro WSL distro name, e.g. "Ubuntu"  (default: none)
#   $DevWslRoot   projects path INSIDE that distro, e.g. "/home/you/dev"
#   $DevShellUx   $false to skip the PSReadLine styling
#
# When $DevWslDistro and $DevWslRoot are both set, -Code opens the project
# through the VS Code WSL remote so the editor runs inside Linux. Otherwise it
# opens the Windows path directly.

if (-not $DevRoot)   { $DevRoot = Join-Path $HOME "dev" }
if ($null -eq $DevShellUx) { $DevShellUx = $true }

function dev {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Project,
        [switch]$Explorer,
        [switch]$Code
    )

    if (-not (Test-Path $DevRoot)) {
        Write-Error "DevRoot does not exist: $DevRoot"
        return
    }

    $target = if ($Project) { Join-Path $DevRoot $Project } else { $DevRoot }
    if (-not (Test-Path $target)) {
        Write-Error "No such project: $Project"
        return
    }

    if ($Explorer) {
        Start-Process explorer.exe $target
        return
    }

    if ($Code) {
        if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
            Write-Error "'code' is not on PATH"
            return
        }
        $useRemote = $DevWslDistro -and $DevWslRoot
        if ($useRemote) {
            $wslPath = if ($Project) { "$DevWslRoot/$Project" } else { $DevWslRoot }
            code --remote "wsl+$DevWslDistro" $wslPath
        }
        else {
            code $target
        }
        return
    }

    Set-Location $target
}

# Read the current branch straight from .git, without spawning git. Faster on
# every Tab (no process per project), and it sidesteps git's safe.directory
# refusal when a Windows git inspects a repo living inside WSL.
function Get-DevBranch {
    param([string]$Path)

    $gitdir = Join-Path $Path ".git"
    if (Test-Path $gitdir -PathType Leaf) {
        # Worktrees and submodules store "gitdir: <path>" in a file.
        $line = Get-Content $gitdir -First 1 -ErrorAction SilentlyContinue
        if ($line -notmatch '^gitdir:\s*(.+)$') { return $null }
        $gitdir = $Matches[1].Trim()
        if (-not [System.IO.Path]::IsPathRooted($gitdir)) { $gitdir = Join-Path $Path $gitdir }
    }

    $head = Join-Path $gitdir "HEAD"
    if (-not (Test-Path $head)) { return $null }

    $line = Get-Content $head -First 1 -ErrorAction SilentlyContinue
    if (-not $line) { return $null }
    if ($line -match '^ref:\s*refs/heads/(.+)$') { return $Matches[1] }
    return $line.Substring(0, [Math]::Min(7, $line.Length))
}
# Complete project names, annotated with the current git branch. The fourth
# CompletionResult argument is the tooltip, which MenuComplete shows when
# ShowToolTips is enabled.
Register-ArgumentCompleter -CommandName dev -ParameterName Project -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if (-not (Test-Path $DevRoot)) { return }

    Get-ChildItem $DevRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$wordToComplete*" } |
        ForEach-Object {
            $branch = Get-DevBranch $_.FullName
            $desc = if ($branch) { "on $branch" } else { "no git repo" }
            [System.Management.Automation.CompletionResult]::new(
                $_.Name, $_.Name, 'ParameterValue', $desc)
        }
}

# --- Shell UX ---------------------------------------------------------------
if ($DevShellUx -and (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue)) {
    # Tab shows a navigable menu rather than cycling through matches silently.
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineOption -ShowToolTips

    # MenuComplete paints the whole column cell (widest item plus padding), so a
    # filled selection box always abuts the next column. Recolour the text
    # instead so the highlight cannot bleed into the neighbouring item.
    Set-PSReadLineOption -Colors @{ Selection = "`e[1;38;5;214m" }

    # Match the prompt chevron instead of the default ">>".
    Set-PSReadLineOption -ContinuationPrompt "❯❯ "

    # The matched portion of a history suggestion. The default is bright cyan,
    # which reads as unrelated to the amber selection colour.
    Set-PSReadLineOption -Colors @{ Emphasis = "`e[1;38;5;214m" }

    # A multi-line prompt (oh-my-posh, starship, ...) leaves PSReadLine
    # miscounting where to redraw, so a tall completion menu scrolls and lands
    # ABOVE the input line. Tell it how many EXTRA lines the prompt occupies.
    # Set $DevPromptExtraLines yourself if invoking prompt has side effects.
    if ($null -eq $DevPromptExtraLines) {
        try { $DevPromptExtraLines = @((prompt) -split "`n").Count - 1 }
        catch { $DevPromptExtraLines = 0 }
    }
    if ($DevPromptExtraLines -gt 0) {
        Set-PSReadLineOption -ExtraPromptLineCount $DevPromptExtraLines
    }
    # Predictions need a real VT console and throw when output is redirected,
    # which $Host.UI.SupportsVirtualTerminal does not reliably detect.
    # Note: the colour keys drop the "Color" suffix that the read-only
    # properties carry -- "ListPredictionSelected", not "...SelectedColor".
    try {
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView -ErrorAction Stop
        Set-PSReadLineOption -Colors @{
            ListPrediction         = "`e[38;5;244m"
            ListPredictionSelected = "`e[1;38;5;214m"
        }
    }
    catch {
        # No VT support (redirected or legacy console) -- predictions stay off.
    }
}